// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

import { ISinjohPriceGuard } from "./interfaces/ISinjohPriceGuard.sol";

/// @notice Anchors one immutable, one-directional route to Uniswap v3 TWAPs.
/// @dev Differs from {SinjohV3TwapPriceGuard} in two ways that a fee router
/// bound to a launchpad subject needs:
///
/// 1. The router always passes its own bound subject to the guard, even when
///    that subject is on neither side of the conversion. This guard therefore
///    binds the subject separately from the traded pair.
/// 2. A route may traverse two pools, so both legs are quoted and both are
///    independently checked for spot-versus-TWAP dislocation.
///
/// It owns no strategy. Every pool, fee, asset, bound, and window is fixed at
/// deployment, and a caller can only make the resulting minimum stricter.
contract SinjohV3RouteTwapPriceGuard is ISinjohPriceGuard {
    uint16 public constant BPS = 10_000;
    uint16 public constant MAX_BOUND_BPS = 2_000;
    uint32 public constant MAX_TWAP_WINDOW = 1 days;
    uint48 public constant MAX_VALIDITY_PERIOD = 5 minutes;

    error InvalidAddress();
    error InvalidConfiguration();
    error InvalidRoute();
    error InvalidAmount();
    error NotActive();
    error AlreadyActive();
    error OracleNotReady();
    error PriceUnavailable();
    error ExcessivePriceDeviation(uint256 allowedBps, uint256 actualBps);

    event Activated(address indexed firstPool, address indexed secondPool, address indexed subject);

    /// @param midAsset Intermediate asset, or the zero address for a direct route.
    /// @param secondPool Second pool, or the zero address for a direct route.
    struct RouteGuard {
        address factory;
        address subject;
        address assetIn;
        address midAsset;
        address assetOut;
        address firstPool;
        address secondPool;
        uint24 firstPoolFee;
        uint24 secondPoolFee;
        bytes32 routeHash;
        uint32 twapWindow;
        uint16 maxSpotDeviationBps;
        uint16 maxOutputSlippageBps;
        uint48 validityPeriod;
        uint128 maxAmountIn;
        uint128 comparisonAmount;
    }

    address public immutable factory;
    address public immutable subject;
    address public immutable assetIn;
    address public immutable midAsset;
    address public immutable assetOut;
    address public immutable firstPool;
    address public immutable secondPool;
    uint24 public immutable firstPoolFee;
    uint24 public immutable secondPoolFee;
    bytes32 public immutable routeHash;
    uint32 public immutable twapWindow;
    uint16 public immutable maxSpotDeviationBps;
    uint16 public immutable maxOutputSlippageBps;
    uint48 public immutable validityPeriod;
    uint128 public immutable maxAmountIn;
    uint128 public immutable comparisonAmount;
    bool public active;

    constructor(RouteGuard memory config) {
        bool twoHop = config.midAsset != address(0);

        if (
            config.factory.code.length == 0 || config.subject == address(0)
                || config.assetIn == address(0) || config.assetOut == address(0)
                || config.firstPool == address(0) || config.assetIn == config.assetOut
                || config.firstPoolFee == 0
        ) revert InvalidAddress();

        if (twoHop) {
            if (
                config.secondPool == address(0) || config.secondPool == config.firstPool
                    || config.secondPoolFee == 0 || config.midAsset == config.assetIn
                    || config.midAsset == config.assetOut
            ) revert InvalidAddress();
        } else {
            if (config.secondPool != address(0) || config.secondPoolFee != 0) {
                revert InvalidAddress();
            }
        }

        if (
            config.routeHash == bytes32(0) || config.twapWindow == 0
                || config.twapWindow > MAX_TWAP_WINDOW || config.maxSpotDeviationBps == 0
                || config.maxSpotDeviationBps > MAX_BOUND_BPS || config.maxOutputSlippageBps == 0
                || config.maxOutputSlippageBps > MAX_BOUND_BPS || config.validityPeriod == 0
                || config.validityPeriod > MAX_VALIDITY_PERIOD || config.maxAmountIn == 0
                || config.comparisonAmount == 0
        ) revert InvalidConfiguration();

        factory = config.factory;
        subject = config.subject;
        assetIn = config.assetIn;
        midAsset = config.midAsset;
        assetOut = config.assetOut;
        firstPool = config.firstPool;
        secondPool = config.secondPool;
        firstPoolFee = config.firstPoolFee;
        secondPoolFee = config.secondPoolFee;
        routeHash = config.routeHash;
        twapWindow = config.twapWindow;
        maxSpotDeviationBps = config.maxSpotDeviationBps;
        maxOutputSlippageBps = config.maxOutputSlippageBps;
        validityPeriod = config.validityPeriod;
        maxAmountIn = config.maxAmountIn;
        comparisonAmount = config.comparisonAmount;
    }

    /// @notice Enables the oracle once the predicted subject and pools exist.
    /// @dev Permissionless because every checked address was fixed at deployment.
    function activate() external {
        if (active) revert AlreadyActive();
        if (
            firstPool.code.length == 0 || assetIn.code.length == 0 || assetOut.code.length == 0
                || subject.code.length == 0
        ) revert InvalidAddress();

        if (midAsset == address(0)) {
            _validatePool(firstPool, assetIn, assetOut, firstPoolFee);
        } else {
            if (secondPool.code.length == 0 || midAsset.code.length == 0) {
                revert InvalidAddress();
            }
            _validatePool(firstPool, assetIn, midAsset, firstPoolFee);
            _validatePool(secondPool, midAsset, assetOut, secondPoolFee);
        }

        // Fresh V3 pools start with one observation slot, which cannot support
        // a historical TWAP. Growing the ring buffer is permissionless; the
        // next pool write populates the second slot and the guard remains
        // fail-closed until the full window has elapsed.
        IUniswapV3Pool(firstPool).increaseObservationCardinalityNext(2);
        if (midAsset != address(0)) {
            IUniswapV3Pool(secondPool).increaseObservationCardinalityNext(2);
        }

        active = true;
        emit Activated(firstPool, secondPool, subject);
    }

    /// @inheritdoc ISinjohPriceGuard
    /// @dev Anchoring an external venue's spot price is only meaningful for a
    /// direct route. A two-hop guard has no single pool price to compare, so it
    /// fails closed rather than returning a bound it cannot justify.
    function validatePoolPrice(
        address subject_,
        address assetIn_,
        address assetOut_,
        uint160 venueSqrtPriceX96
    ) external view {
        if (!active) revert NotActive();
        if (midAsset != address(0)) revert InvalidRoute();
        _validateRoute(subject_, assetIn_, assetOut_);

        int24 twapTick = _twapTickAndValidateAnchor(firstPool, assetIn, assetOut);
        // TickMath accepts MIN_SQRT_PRICE <= x < MAX_SQRT_PRICE.
        if (
            venueSqrtPriceX96 < TickMath.MIN_SQRT_PRICE
                || venueSqrtPriceX96 >= TickMath.MAX_SQRT_PRICE
        ) revert PriceUnavailable();
        int24 venueTick = TickMath.getTickAtSqrtPrice(venueSqrtPriceX96);
        _validateDeviation(assetIn, assetOut, twapTick, venueTick);
    }

    /// @inheritdoc ISinjohPriceGuard
    function minimumOutput(
        address subject_,
        address assetIn_,
        address assetOut_,
        uint256 amountIn,
        bytes32 routeHash_,
        bytes calldata guardData
    ) external view returns (uint256 minOut, uint48 validUntil) {
        if (!active) revert NotActive();
        _validateRoute(subject_, assetIn_, assetOut_);
        if (
            routeHash_ != routeHash || guardData.length != 0 || amountIn == 0
                || amountIn > maxAmountIn
        ) revert InvalidAmount();

        uint256 expectedOut = _quoteRoute(uint128(amountIn));
        if (expectedOut == 0) revert PriceUnavailable();
        // One bound covers the whole route. It has to absorb every hop's pool
        // fee as well as price impact, so a two-hop route needs a wider
        // configured slippage than a direct one to stay executable.
        minOut = FullMath.mulDiv(expectedOut, BPS - maxOutputSlippageBps, BPS);
        if (minOut == 0) revert PriceUnavailable();
        validUntil = uint48(block.timestamp) + validityPeriod;
    }

    /// @notice The route's TWAP output for `amountIn`, before the slippage bound.
    function quoteAtTwap(uint128 amountIn) external view returns (uint256 amountOut) {
        if (!active) revert NotActive();
        if (amountIn == 0 || amountIn > maxAmountIn) revert InvalidAmount();
        amountOut = _quoteRoute(amountIn);
    }

    function _quoteRoute(uint128 amountIn) private view returns (uint256 amountOut) {
        if (midAsset == address(0)) {
            int24 directTick = _twapTickAndValidateAnchor(firstPool, assetIn, assetOut);
            return _quoteAtTick(directTick, amountIn, assetIn, assetOut);
        }

        int24 firstTick = _twapTickAndValidateAnchor(firstPool, assetIn, midAsset);
        uint256 intermediate = _quoteAtTick(firstTick, amountIn, assetIn, midAsset);
        if (intermediate == 0 || intermediate > type(uint128).max) revert PriceUnavailable();
        int24 secondTick = _twapTickAndValidateAnchor(secondPool, midAsset, assetOut);
        amountOut = _quoteAtTick(secondTick, uint128(intermediate), midAsset, assetOut);
    }

    function _validateRoute(address subject_, address assetIn_, address assetOut_) private view {
        if (subject_ != subject || assetIn_ != assetIn || assetOut_ != assetOut) {
            revert InvalidRoute();
        }
    }

    function _validatePool(address pool, address tokenA, address tokenB, uint24 fee) private view {
        IUniswapV3Pool candidate = IUniswapV3Pool(pool);
        address token0 = tokenA < tokenB ? tokenA : tokenB;
        address token1 = tokenA < tokenB ? tokenB : tokenA;
        if (
            candidate.factory() != factory || candidate.token0() != token0
                || candidate.token1() != token1 || candidate.fee() != fee
                || IUniswapV3Factory(factory).getPool(token0, token1, fee) != pool
        ) revert InvalidRoute();
    }

    function _twapTickAndValidateAnchor(address pool, address tokenA, address tokenB)
        private
        view
        returns (int24 twapTick)
    {
        uint32 window = twapWindow;
        (, int24 spotTick,, uint16 cardinality,,, bool unlocked) = IUniswapV3Pool(pool).slot0();
        if (!unlocked || cardinality < 2) revert OracleNotReady();
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = window;
        secondsAgos[1] = 0;
        try IUniswapV3Pool(pool).observe(secondsAgos) returns (
            int56[] memory tickCumulatives, uint160[] memory
        ) {
            if (tickCumulatives.length != 2) revert OracleNotReady();
            int56 delta = tickCumulatives[1] - tickCumulatives[0];
            int56 windowSeconds = int56(uint56(window));
            twapTick = int24(delta / windowSeconds);
            if (delta < 0 && delta % windowSeconds != 0) twapTick--;
        } catch {
            revert OracleNotReady();
        }
        _validateDeviation(tokenA, tokenB, twapTick, spotTick);
    }

    /// @dev Compares the two ticks as a price ratio in the pool's own token
    /// order, so the check is independent of either token's decimals. The pair
    /// is passed in from immutables that {activate} already proved match the
    /// pool, which keeps the hot path free of extra external calls.
    function _validateDeviation(
        address tokenA,
        address tokenB,
        int24 referenceTick,
        int24 observedTick
    ) private view {
        address token0 = tokenA < tokenB ? tokenA : tokenB;
        address token1 = tokenA < tokenB ? tokenB : tokenA;
        uint256 referenceQuote = _quoteAtTick(referenceTick, comparisonAmount, token0, token1);
        uint256 observed = _quoteAtTick(observedTick, comparisonAmount, token0, token1);
        if (referenceQuote == 0 || observed == 0) revert PriceUnavailable();
        uint256 difference =
            referenceQuote > observed ? referenceQuote - observed : observed - referenceQuote;
        uint256 deviationBps = FullMath.mulDiv(difference, BPS, referenceQuote);
        if (deviationBps > maxSpotDeviationBps) {
            revert ExcessivePriceDeviation(maxSpotDeviationBps, deviationBps);
        }
    }

    function _quoteAtTick(int24 tick, uint128 baseAmount, address baseToken, address quoteToken)
        private
        pure
        returns (uint256 quoteAmount)
    {
        uint160 sqrtRatioX96 = TickMath.getSqrtPriceAtTick(tick);
        if (sqrtRatioX96 <= type(uint128).max) {
            uint256 ratioX192 = uint256(sqrtRatioX96) * sqrtRatioX96;
            quoteAmount = baseToken < quoteToken
                ? FullMath.mulDiv(ratioX192, baseAmount, 1 << 192)
                : FullMath.mulDiv(1 << 192, baseAmount, ratioX192);
        } else {
            uint256 ratioX128 = FullMath.mulDiv(sqrtRatioX96, sqrtRatioX96, 1 << 64);
            quoteAmount = baseToken < quoteToken
                ? FullMath.mulDiv(ratioX128, baseAmount, 1 << 128)
                : FullMath.mulDiv(1 << 128, baseAmount, ratioX128);
        }
    }
}
