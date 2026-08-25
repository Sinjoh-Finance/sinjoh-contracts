// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { IProjectPriceGuard } from "../interfaces/IProjectPriceGuard.sol";

/// @notice Release-approved, route-bound V3 TWAP guard for project custody swaps.
/// @dev The concrete pair is resolved from the canonical factory. The fixed route hash binds the
/// companion direct-V3 adapter to this guard's fee tier, while every quote rejects insufficient
/// history and excessive spot/TWAP deviation.
contract ProjectV3TwapPriceGuard is IProjectPriceGuard {
    uint16 public constant BPS = 10_000;
    uint16 public constant MAX_BOUND_BPS = 2_000;
    uint32 public constant MAX_TWAP_WINDOW = 1 days;
    uint48 public constant MAX_VALIDITY_PERIOD = 5 minutes;
    uint16 public constant MIN_OBSERVATION_CARDINALITY = 2;

    address public immutable factory;
    bytes32 public immutable factoryCodehash;
    uint24 public immutable poolFee;
    bytes32 public immutable routeHash;
    uint32 public immutable twapWindow;
    uint16 public immutable maxSpotDeviationBps;
    uint16 public immutable maxOutputSlippageBps;
    uint48 public immutable validityPeriod;
    uint128 public immutable comparisonAmount;

    error InvalidDependency(address candidate);
    error DependencyChanged(address candidate);
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

    constructor(
        address factory_,
        uint24 poolFee_,
        uint32 twapWindow_,
        uint16 maxSpotDeviationBps_,
        uint16 maxOutputSlippageBps_,
        uint48 validityPeriod_,
        uint128 comparisonAmount_
    ) {
        if (factory_.code.length == 0) revert InvalidDependency(factory_);
        if (
            poolFee_ == 0 || IUniswapV3Factory(factory_).feeAmountTickSpacing(poolFee_) == 0
                || twapWindow_ == 0 || twapWindow_ > MAX_TWAP_WINDOW || maxSpotDeviationBps_ == 0
                || maxSpotDeviationBps_ > MAX_BOUND_BPS || maxOutputSlippageBps_ == 0
                || maxOutputSlippageBps_ > MAX_BOUND_BPS || validityPeriod_ == 0
                || validityPeriod_ > MAX_VALIDITY_PERIOD || comparisonAmount_ == 0
        ) revert InvalidConfiguration();
        factory = factory_;
        factoryCodehash = factory_.codehash;
        poolFee = poolFee_;
        routeHash = keccak256(abi.encode(poolFee_));
        twapWindow = twapWindow_;
        maxSpotDeviationBps = maxSpotDeviationBps_;
        maxOutputSlippageBps = maxOutputSlippageBps_;
        validityPeriod = validityPeriod_;
        comparisonAmount = comparisonAmount_;
    }

    function prime(address tokenA, address tokenB, uint16 cardinality)
        external
        returns (address pool)
    {
        if (cardinality < MIN_OBSERVATION_CARDINALITY) revert InvalidConfiguration();
        pool = _pool(tokenA, tokenB);
        IUniswapV3Pool(pool).increaseObservationCardinalityNext(cardinality);
        emit Primed(pool, tokenA, tokenB, cardinality);
    }

    function poolFor(address tokenA, address tokenB) external view returns (address) {
        return _pool(tokenA, tokenB);
    }

    function minimumOutput(
        address assetIn,
        address assetOut,
        uint256 amountIn,
        bytes32 suppliedRouteHash,
        bytes calldata guardData
    ) external view returns (uint256 minimumOut, uint48 validUntil) {
        return _minimumOutput(assetIn, assetOut, amountIn, suppliedRouteHash, guardData);
    }

    /// @notice Subject-aware ABI used by permanent Project integrations.
    /// @dev The subject authenticates the project context at the caller. Router payouts may
    /// intentionally exchange two non-subject assets, so this generic V3 guard must not require
    /// either side of the approved pair to equal the subject.
    function minimumOutput(
        address subject,
        address assetIn,
        address assetOut,
        uint256 amountIn,
        bytes32 suppliedRouteHash,
        bytes calldata guardData
    ) external view returns (uint256 minimumOut, uint48 validUntil) {
        if (subject == address(0)) revert InvalidRoute();
        return _minimumOutput(assetIn, assetOut, amountIn, suppliedRouteHash, guardData);
    }

    function validatePoolPrice(
        address subject,
        address assetIn,
        address assetOut,
        uint160 venueSqrtPriceX96
    ) external view {
        _validateSubjectPair(subject, assetIn, assetOut);
        int24 twapTick = _twapTickAndValidateAnchor(_pool(assetIn, assetOut), assetIn, assetOut);
        if (
            venueSqrtPriceX96 < TickMath.MIN_SQRT_PRICE
                || venueSqrtPriceX96 >= TickMath.MAX_SQRT_PRICE
        ) revert PriceUnavailable();
        _validateDeviation(
            twapTick, TickMath.getTickAtSqrtPrice(venueSqrtPriceX96), assetIn, assetOut
        );
    }

    function _minimumOutput(
        address assetIn,
        address assetOut,
        uint256 amountIn,
        bytes32 suppliedRouteHash,
        bytes calldata guardData
    ) private view returns (uint256 minimumOut, uint48 validUntil) {
        if (
            assetIn == address(0) || assetOut == address(0) || assetIn == assetOut
                || suppliedRouteHash != routeHash || guardData.length != 0 || amountIn == 0
                || amountIn > type(uint128).max
        ) revert InvalidRoute();
        int24 twapTick = _twapTickAndValidateAnchor(_pool(assetIn, assetOut), assetIn, assetOut);
        // `amountIn` was bounded to uint128 above.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 expectedOut = _quoteAtTick(twapTick, uint128(amountIn), assetIn, assetOut);
        if (expectedOut == 0) revert PriceUnavailable();
        minimumOut = FullMath.mulDiv(expectedOut, BPS - maxOutputSlippageBps, BPS);
        if (minimumOut == 0) revert PriceUnavailable();
        validUntil = uint48(block.timestamp) + validityPeriod;
    }

    function quoteAtTwap(address assetIn, address assetOut, uint128 amountIn)
        external
        view
        returns (uint256 amountOut)
    {
        if (amountIn == 0 || assetIn == assetOut) revert InvalidAmount();
        int24 twapTick = _twapTickAndValidateAnchor(_pool(assetIn, assetOut), assetIn, assetOut);
        amountOut = _quoteAtTick(twapTick, amountIn, assetIn, assetOut);
    }

    function _pool(address tokenA, address tokenB) private view returns (address pool) {
        if (factory.codehash != factoryCodehash) revert DependencyChanged(factory);
        pool = IUniswapV3Factory(factory).getPool(tokenA, tokenB, poolFee);
        if (pool.code.length == 0) revert PoolNotFound(tokenA, tokenB);
        IUniswapV3Pool candidate = IUniswapV3Pool(pool);
        address token0 = tokenA < tokenB ? tokenA : tokenB;
        address token1 = tokenA < tokenB ? tokenB : tokenA;
        if (
            candidate.factory() != factory || candidate.token0() != token0
                || candidate.token1() != token1 || candidate.fee() != poolFee
        ) revert InvalidRoute();
    }

    function _twapTickAndValidateAnchor(address pool, address tokenA, address tokenB)
        private
        view
        returns (int24 twapTick)
    {
        (, int24 spotTick,, uint16 cardinality,,, bool unlocked) = IUniswapV3Pool(pool).slot0();
        if (!unlocked || cardinality < MIN_OBSERVATION_CARDINALITY) revert OracleNotReady();
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = twapWindow;
        try IUniswapV3Pool(pool).observe(secondsAgos) returns (
            int56[] memory tickCumulatives, uint160[] memory
        ) {
            if (tickCumulatives.length != 2) revert OracleNotReady();
            int56 delta = tickCumulatives[1] - tickCumulatives[0];
            int56 window = int56(uint56(twapWindow));
            // A mean of int24 ticks remains inside the int24 tick domain.
            // forge-lint: disable-next-line(unsafe-typecast)
            twapTick = int24(delta / window);
            if (delta < 0 && delta % window != 0) --twapTick;
        } catch {
            revert OracleNotReady();
        }
        _validateDeviation(twapTick, spotTick, tokenA, tokenB);
    }

    function _validateSubjectPair(address subject, address assetIn, address assetOut) private pure {
        if (subject == address(0) || (subject != assetIn && subject != assetOut)) {
            revert InvalidRoute();
        }
    }

    function _validateDeviation(
        int24 referenceTick,
        int24 observedTick,
        address tokenA,
        address tokenB
    ) private view {
        uint256 twapQuote = _quoteAtTick(referenceTick, comparisonAmount, tokenA, tokenB);
        uint256 spotQuote = _quoteAtTick(observedTick, comparisonAmount, tokenA, tokenB);
        if (twapQuote == 0 || spotQuote == 0) revert PriceUnavailable();
        uint256 difference = twapQuote > spotQuote ? twapQuote - spotQuote : spotQuote - twapQuote;
        uint256 deviationBps = FullMath.mulDiv(difference, BPS, twapQuote);
        if (deviationBps > maxSpotDeviationBps) {
            revert ExcessivePriceDeviation(maxSpotDeviationBps, deviationBps);
        }
    }

    function _quoteAtTick(int24 tick, uint128 amount, address base, address quote)
        private
        pure
        returns (uint256 output)
    {
        uint160 sqrtRatioX96 = TickMath.getSqrtPriceAtTick(tick);
        if (sqrtRatioX96 <= type(uint128).max) {
            uint256 ratioX192 = uint256(sqrtRatioX96) * sqrtRatioX96;
            return base < quote
                ? FullMath.mulDiv(ratioX192, amount, 1 << 192)
                : FullMath.mulDiv(1 << 192, amount, ratioX192);
        }
        uint256 ratioX128 = FullMath.mulDiv(sqrtRatioX96, sqrtRatioX96, 1 << 64);
        return base < quote
            ? FullMath.mulDiv(ratioX128, amount, 1 << 128)
            : FullMath.mulDiv(1 << 128, amount, ratioX128);
    }
}
