// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

import { ISinjohPriceGuard } from "./interfaces/ISinjohPriceGuard.sol";

/// @notice One guard serving every launch, anchoring swap output and LP venue
/// spot price to the canonical Uniswap v3 pool's TWAP.
/// @dev {SinjohV3TwapPriceGuard} pins a single pool at deployment. That is the
/// stronger guarantee, but it needs one guard per launch. This contract instead
/// resolves the pool from the canonical factory on every call, so one
/// deployment covers every launch and no per-launch wiring is required.
///
/// The pair being priced always comes from the liquidity manager's own
/// immutable account configuration, never from the caller, and the pool is
/// derived from the factory rather than accepted as an argument. A caller
/// therefore cannot point this guard at a pool it did not derive itself.
///
/// The guard holds no mutable state and owns no strategy: every bound is fixed
/// at deployment and applies uniformly. Because each liquidity-manager account
/// stores its guard address immutably, redeploying with different bounds only
/// affects launches configured afterwards; existing launches keep the guard
/// they were configured with.
contract SinjohSharedV3TwapPriceGuard is ISinjohPriceGuard {
    uint16 public constant BPS = 10_000;
    uint16 public constant MAX_BOUND_BPS = 2_000;
    uint32 public constant MAX_TWAP_WINDOW = 1 days;
    uint48 public constant MAX_VALIDITY_PERIOD = 5 minutes;
    uint16 public constant MIN_OBSERVATION_CARDINALITY = 2;

    error InvalidAddress();
    error InvalidConfiguration();
    error InvalidRoute();
    error InvalidAmount();
    error PoolNotFound(address tokenA, address tokenB);
    error OracleNotReady();
    error PriceUnavailable();
    error ExcessivePriceDeviation(uint256 allowedBps, uint256 actualBps);

    event Primed(
        address indexed pool, address indexed tokenA, address indexed tokenB, uint16 cardinality
    );

    address public immutable factory;
    uint24 public immutable poolFee;
    uint32 public immutable twapWindow;
    uint16 public immutable maxSpotDeviationBps;
    uint16 public immutable maxOutputSlippageBps;
    uint48 public immutable validityPeriod;
    uint128 public immutable comparisonAmount;

    constructor(
        address factory_,
        uint24 poolFee_,
        uint32 twapWindow_,
        uint16 maxSpotDeviationBps_,
        uint16 maxOutputSlippageBps_,
        uint48 validityPeriod_,
        uint128 comparisonAmount_
    ) {
        if (factory_.code.length == 0) revert InvalidAddress();
        if (
            poolFee_ == 0 || IUniswapV3Factory(factory_).feeAmountTickSpacing(poolFee_) == 0
                || twapWindow_ == 0 || twapWindow_ > MAX_TWAP_WINDOW || maxSpotDeviationBps_ == 0
                || maxSpotDeviationBps_ > MAX_BOUND_BPS || maxOutputSlippageBps_ == 0
                || maxOutputSlippageBps_ > MAX_BOUND_BPS || validityPeriod_ == 0
                || validityPeriod_ > MAX_VALIDITY_PERIOD || comparisonAmount_ == 0
        ) revert InvalidConfiguration();

        factory = factory_;
        poolFee = poolFee_;
        twapWindow = twapWindow_;
        maxSpotDeviationBps = maxSpotDeviationBps_;
        maxOutputSlippageBps = maxOutputSlippageBps_;
        validityPeriod = validityPeriod_;
        comparisonAmount = comparisonAmount_;
    }

    /// @notice Grows a pool's observation buffer so it can answer this guard's TWAP.
    /// @dev Permissionless: the pool is derived from the canonical factory and
    /// Uniswap only ever raises the target, so this cannot shrink history or
    /// touch an unrelated pool. A pool that records an observation every block
    /// needs roughly `twapWindow / blockTime` slots before the full window is
    /// retrievable, so size `cardinality` for how actively the pair trades
    /// rather than assuming the two-slot minimum is enough.
    function prime(address tokenA, address tokenB, uint16 cardinality)
        external
        returns (address pool)
    {
        if (cardinality < MIN_OBSERVATION_CARDINALITY) revert InvalidConfiguration();
        pool = _pool(tokenA, tokenB);
        IUniswapV3Pool(pool).increaseObservationCardinalityNext(cardinality);
        emit Primed(pool, tokenA, tokenB, cardinality);
    }

    /// @notice The canonical pool this guard prices `tokenA`/`tokenB` against.
    function poolFor(address tokenA, address tokenB) external view returns (address) {
        return _pool(tokenA, tokenB);
    }

    /// @inheritdoc ISinjohPriceGuard
    function validatePoolPrice(
        address subject_,
        address assetIn_,
        address assetOut_,
        uint160 venueSqrtPriceX96
    ) external view {
        _validatePair(subject_, assetIn_, assetOut_);
        int24 twapTick = _twapTickAndValidateAnchor(_pool(assetIn_, assetOut_), assetIn_, assetOut_);
        // TickMath accepts MIN_SQRT_PRICE <= x < MAX_SQRT_PRICE.
        if (
            venueSqrtPriceX96 < TickMath.MIN_SQRT_PRICE
                || venueSqrtPriceX96 >= TickMath.MAX_SQRT_PRICE
        ) revert PriceUnavailable();
        int24 venueTick = TickMath.getTickAtSqrtPrice(venueSqrtPriceX96);
        _validateDeviation(assetIn_, assetOut_, twapTick, venueTick);
    }

    /// @inheritdoc ISinjohPriceGuard
    /// @dev The route hash is not pinned. A per-launch guard can bind one route
    /// because it is deployed for one launch; a shared guard serves every route
    /// and has no single hash to compare against. Nothing is lost to a caller:
    /// the assets come from the manager's immutable configuration and the pool
    /// is derived here, so the quote does not depend on the route bytes.
    function minimumOutput(
        address subject_,
        address assetIn_,
        address assetOut_,
        uint256 amountIn,
        bytes32,
        bytes calldata guardData
    ) external view returns (uint256 minOut, uint48 validUntil) {
        _validatePair(subject_, assetIn_, assetOut_);
        if (guardData.length != 0 || amountIn == 0 || amountIn > type(uint128).max) {
            revert InvalidAmount();
        }
        int24 twapTick = _twapTickAndValidateAnchor(_pool(assetIn_, assetOut_), assetIn_, assetOut_);
        uint256 expectedOut = _quoteAtTick(twapTick, uint128(amountIn), assetIn_, assetOut_);
        if (expectedOut == 0) revert PriceUnavailable();
        minOut = FullMath.mulDiv(expectedOut, BPS - maxOutputSlippageBps, BPS);
        if (minOut == 0) revert PriceUnavailable();
        validUntil = uint48(block.timestamp) + validityPeriod;
    }

    /// @notice The pair's TWAP output for `amountIn`, before the slippage bound.
    function quoteAtTwap(address assetIn_, address assetOut_, uint128 amountIn)
        external
        view
        returns (uint256 amountOut)
    {
        if (amountIn == 0 || assetIn_ == assetOut_) revert InvalidAmount();
        int24 twapTick = _twapTickAndValidateAnchor(_pool(assetIn_, assetOut_), assetIn_, assetOut_);
        amountOut = _quoteAtTick(twapTick, amountIn, assetIn_, assetOut_);
    }

    /// @dev The subject must be one side of the traded pair. The liquidity
    /// manager always swaps between its account's quote asset and its subject,
    /// so anything else is a route this guard was never meant to price.
    function _validatePair(address subject_, address assetIn_, address assetOut_) private pure {
        if (
            subject_ == address(0) || assetIn_ == address(0) || assetOut_ == address(0)
                || assetIn_ == assetOut_ || (subject_ != assetIn_ && subject_ != assetOut_)
        ) revert InvalidRoute();
    }

    function _pool(address tokenA, address tokenB) private view returns (address pool) {
        pool = IUniswapV3Factory(factory).getPool(tokenA, tokenB, poolFee);
        if (pool == address(0) || pool.code.length == 0) revert PoolNotFound(tokenA, tokenB);
    }

    function _twapTickAndValidateAnchor(address pool, address tokenA, address tokenB)
        private
        view
        returns (int24 twapTick)
    {
        uint32 window = twapWindow;
        (, int24 spotTick,, uint16 cardinality,,, bool unlocked) = IUniswapV3Pool(pool).slot0();
        if (!unlocked || cardinality < MIN_OBSERVATION_CARDINALITY) revert OracleNotReady();
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = window;
        secondsAgos[1] = 0;
        // Uniswap reverts when the buffer does not reach back a full window, so
        // a pool without enough history fails closed rather than quoting a
        // shorter, cheaper-to-move average.
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
    /// order, so the check is independent of either token's decimals.
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
