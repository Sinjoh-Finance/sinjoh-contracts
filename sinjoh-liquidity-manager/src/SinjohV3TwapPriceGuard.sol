// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

import { ISinjohPriceGuard } from "./interfaces/ISinjohPriceGuard.sol";

/// @notice Anchors swap output and LP venue spot to one immutable Uniswap v3 TWAP.
contract SinjohV3TwapPriceGuard is ISinjohPriceGuard {
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

    event Activated(
        address indexed oraclePool, address indexed subject, address indexed quoteAsset
    );

    IUniswapV3Pool public immutable oraclePool;
    address public immutable factory;
    address public immutable subject;
    address public immutable quoteAsset;
    uint24 public immutable poolFee;
    bytes32 public immutable routeHash;
    uint32 public immutable twapWindow;
    uint16 public immutable maxSpotDeviationBps;
    uint16 public immutable maxOutputSlippageBps;
    uint48 public immutable validityPeriod;
    uint128 public immutable maxAmountIn;
    uint128 public immutable comparisonAmount;
    bool public active;

    constructor(
        address oraclePool_,
        address factory_,
        address subject_,
        address quoteAsset_,
        uint24 poolFee_,
        bytes32 routeHash_,
        uint32 twapWindow_,
        uint16 maxSpotDeviationBps_,
        uint16 maxOutputSlippageBps_,
        uint48 validityPeriod_,
        uint128 maxAmountIn_,
        uint128 comparisonAmount_
    ) {
        if (
            oraclePool_ == address(0) || factory_.code.length == 0 || subject_ == address(0)
                || quoteAsset_.code.length == 0 || subject_ == quoteAsset_ || poolFee_ == 0
        ) revert InvalidAddress();
        if (
            routeHash_ == bytes32(0) || twapWindow_ == 0 || twapWindow_ > MAX_TWAP_WINDOW
                || maxSpotDeviationBps_ == 0 || maxSpotDeviationBps_ > MAX_BOUND_BPS
                || maxOutputSlippageBps_ == 0 || maxOutputSlippageBps_ > MAX_BOUND_BPS
                || validityPeriod_ == 0 || validityPeriod_ > MAX_VALIDITY_PERIOD
                || maxAmountIn_ == 0 || comparisonAmount_ == 0
        ) revert InvalidConfiguration();

        oraclePool = IUniswapV3Pool(oraclePool_);
        factory = factory_;
        subject = subject_;
        quoteAsset = quoteAsset_;
        poolFee = poolFee_;
        routeHash = routeHash_;
        twapWindow = twapWindow_;
        maxSpotDeviationBps = maxSpotDeviationBps_;
        maxOutputSlippageBps = maxOutputSlippageBps_;
        validityPeriod = validityPeriod_;
        maxAmountIn = maxAmountIn_;
        comparisonAmount = comparisonAmount_;
    }

    /// @notice Enables the immutable oracle once the predicted subject and pool exist.
    /// @dev Permissionless because the pool and pair were fixed at deployment.
    function activate() external {
        if (active) revert AlreadyActive();
        if (address(oraclePool).code.length == 0 || subject.code.length == 0) {
            revert InvalidAddress();
        }
        address token0 = subject < quoteAsset ? subject : quoteAsset;
        address token1 = subject < quoteAsset ? quoteAsset : subject;
        if (
            oraclePool.factory() != factory || oraclePool.token0() != token0
                || oraclePool.token1() != token1 || oraclePool.fee() != poolFee
                || IUniswapV3Factory(factory).getPool(token0, token1, poolFee)
                    != address(oraclePool)
        ) {
            revert InvalidRoute();
        }
        // Fresh V3 pools start with one observation slot, which cannot support
        // a historical TWAP. Growing the ring buffer is permissionless; the
        // next pool write populates the second slot and the guard remains
        // fail-closed until the full window has elapsed.
        oraclePool.increaseObservationCardinalityNext(2);
        active = true;
        emit Activated(address(oraclePool), subject, quoteAsset);
    }

    function validatePoolPrice(
        address subject_,
        address assetIn_,
        address assetOut_,
        uint160 venueSqrtPriceX96
    ) external view {
        if (!active) revert NotActive();
        _validatePair(subject_, assetIn_, assetOut_);
        int24 twapTick = _twapTickAndValidateAnchor();
        int24 venueTick;
        // TickMath accepts MIN_SQRT_PRICE <= x < MAX_SQRT_PRICE.
        if (
            venueSqrtPriceX96 < TickMath.MIN_SQRT_PRICE
                || venueSqrtPriceX96 >= TickMath.MAX_SQRT_PRICE
        ) revert PriceUnavailable();
        venueTick = TickMath.getTickAtSqrtPrice(venueSqrtPriceX96);
        _validateDeviation(twapTick, venueTick, comparisonAmount);
    }

    function minimumOutput(
        address subject_,
        address assetIn_,
        address assetOut_,
        uint256 amountIn,
        bytes32 routeHash_,
        bytes calldata guardData
    ) external view returns (uint256 minOut, uint48 validUntil) {
        if (!active) revert NotActive();
        _validatePair(subject_, assetIn_, assetOut_);
        if (
            routeHash_ != routeHash || guardData.length != 0 || amountIn == 0
                || amountIn > maxAmountIn
        ) revert InvalidAmount();
        int24 twapTick = _twapTickAndValidateAnchor();
        uint256 expectedOut = _quoteAtTick(twapTick, uint128(amountIn), assetIn_, assetOut_);
        if (expectedOut == 0) revert PriceUnavailable();
        minOut = FullMath.mulDiv(expectedOut, BPS - maxOutputSlippageBps, BPS);
        if (minOut == 0) revert PriceUnavailable();
        validUntil = uint48(block.timestamp) + validityPeriod;
    }

    function quoteAtTwap(uint128 amountIn) external view returns (uint256 amountOut) {
        if (!active) revert NotActive();
        int24 twapTick = _twapTickAndValidateAnchor();
        amountOut = _quoteAtTick(twapTick, amountIn, quoteAsset, subject);
    }

    function _validatePair(address subject_, address assetIn_, address assetOut_) private view {
        bool forward = assetIn_ == quoteAsset && assetOut_ == subject;
        bool reverse = assetIn_ == subject && assetOut_ == quoteAsset;
        if (subject_ != subject || (!forward && !reverse)) {
            revert InvalidRoute();
        }
    }

    function _twapTickAndValidateAnchor() private view returns (int24 twapTick) {
        (, int24 spotTick,, uint16 cardinality,,, bool unlocked) = oraclePool.slot0();
        if (!unlocked || cardinality < 2) revert OracleNotReady();
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = twapWindow;
        secondsAgos[1] = 0;
        try oraclePool.observe(secondsAgos) returns (
            int56[] memory tickCumulatives, uint160[] memory
        ) {
            if (tickCumulatives.length != 2) revert OracleNotReady();
            int56 delta = tickCumulatives[1] - tickCumulatives[0];
            int56 window = int56(uint56(twapWindow));
            twapTick = int24(delta / window);
            if (delta < 0 && delta % window != 0) twapTick--;
        } catch {
            revert OracleNotReady();
        }
        _validateDeviation(twapTick, spotTick, comparisonAmount);
    }

    function _validateDeviation(int24 referenceTick, int24 observedTick, uint128 amount)
        private
        view
    {
        uint256 referenceQuote = _quoteAtTick(referenceTick, amount, quoteAsset, subject);
        uint256 observed = _quoteAtTick(observedTick, amount, quoteAsset, subject);
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
