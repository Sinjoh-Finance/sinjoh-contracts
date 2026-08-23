// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { FundingBandObservation } from "./FundingBandTypes.sol";
import { IFundingBandMarketCapGuard } from "../interfaces/IFundingBandMarketCapGuard.sol";
import { IFundingBandQuoteUsdOracle } from "../interfaces/IFundingBandQuoteUsdOracle.sol";

/// @notice Project-bound Uniswap V3 TWAP market-cap source for Funding Bands.
/// @dev The live quote/USD source determines current FDV. Frozen reference quote/USD pricing
/// determines position ticks, keeping funded NFT ranges stable when the quote asset itself moves.
contract UniswapV3FundingBandMarketCapGuard is IFundingBandMarketCapGuard {
    uint32 public constant MAX_TWAP_WINDOW = 1 days;
    uint8 public constant MAX_QUOTE_DECIMALS = 38;

    address public override bandsContract;
    address public override subject;
    address public quoteAsset;
    address public override canonicalPool;
    address public factory;
    uint256 public override referenceSupply;
    uint32 public override minimumTwapWindow;
    address public quoteUsdOracle;
    uint256 public tickReferenceQuoteUsdE8;
    uint48 public maximumOracleAge;
    uint256 public quoteUnit;
    int24 public tickSpacing;

    error InvalidAddress(address candidate);
    error InvalidConfiguration();
    error InvalidPool();
    error OracleNotReady();
    error StaleQuoteUsdObservation(uint48 observedAt, uint48 currentTime);
    error InvalidQuoteUsdObservation();
    error InvalidObservationData();
    error InvalidMarketCapBounds(uint128 lower, uint128 upper);
    error EffectiveTicksCollapsed(int24 lower, int24 upper);
    error PriceOutsideTickRange(uint256 marketCapUsdE8);

    constructor(
        address bandsContract_,
        address subject_,
        address quoteAsset_,
        address canonicalPool_,
        address factory_,
        uint256 referenceSupply_,
        uint32 twapWindow_,
        address quoteUsdOracle_,
        uint256 tickReferenceQuoteUsdE8_,
        uint48 maximumOracleAge_
    ) {
        if (bandsContract_ == address(0)) {
            revert InvalidAddress(bandsContract_);
        }
        if (subject_.code.length == 0) revert InvalidAddress(subject_);
        if (quoteAsset_.code.length == 0 || quoteAsset_ == subject_) {
            revert InvalidAddress(quoteAsset_);
        }
        if (canonicalPool_.code.length == 0) revert InvalidAddress(canonicalPool_);
        if (factory_.code.length == 0) revert InvalidAddress(factory_);
        if (
            referenceSupply_ == 0 || twapWindow_ == 0 || twapWindow_ > MAX_TWAP_WINDOW
                || tickReferenceQuoteUsdE8_ == 0 || maximumOracleAge_ == 0
        ) revert InvalidConfiguration();
        uint8 quoteDecimals = IERC20Metadata(quoteAsset_).decimals();
        if (quoteDecimals > MAX_QUOTE_DECIMALS) revert InvalidConfiguration();
        if (
            quoteUsdOracle_ != address(0)
                && (quoteUsdOracle_.code.length == 0
                    || IFundingBandQuoteUsdOracle(quoteUsdOracle_).quoteAsset() != quoteAsset_)
        ) revert InvalidAddress(quoteUsdOracle_);

        IUniswapV3Pool pool = IUniswapV3Pool(canonicalPool_);
        address token0 = subject_ < quoteAsset_ ? subject_ : quoteAsset_;
        address token1 = subject_ < quoteAsset_ ? quoteAsset_ : subject_;
        uint24 fee = pool.fee();
        int24 spacing = pool.tickSpacing();
        if (
            fee == 0 || spacing <= 0 || pool.factory() != factory_ || pool.token0() != token0
                || pool.token1() != token1
                || IUniswapV3Factory(factory_).getPool(token0, token1, fee) != canonicalPool_
        ) revert InvalidPool();

        bandsContract = bandsContract_;
        subject = subject_;
        quoteAsset = quoteAsset_;
        canonicalPool = canonicalPool_;
        factory = factory_;
        referenceSupply = referenceSupply_;
        minimumTwapWindow = twapWindow_;
        quoteUsdOracle = quoteUsdOracle_;
        tickReferenceQuoteUsdE8 = tickReferenceQuoteUsdE8_;
        maximumOracleAge = maximumOracleAge_;
        quoteUnit = 10 ** quoteDecimals;
        tickSpacing = spacing;
    }

    /// @notice Permissionlessly requests the minimum V3 observation capacity needed by the guard.
    function preparePoolOracle() external {
        IUniswapV3Pool(canonicalPool).increaseObservationCardinalityNext(2);
    }

    function observe(uint128 lowerMarketCapUsdE8, uint128 upperMarketCapUsdE8, bytes calldata data)
        external
        view
        returns (FundingBandObservation memory observation)
    {
        if (data.length != 0) revert InvalidObservationData();
        if (lowerMarketCapUsdE8 == 0 || lowerMarketCapUsdE8 >= upperMarketCapUsdE8) {
            revert InvalidMarketCapBounds(lowerMarketCapUsdE8, upperMarketCapUsdE8);
        }
        (int24 twapTick, int56 olderCumulative, int56 currentCumulative) = _twapTick();
        (uint256 liveQuoteUsdE8, uint48 quoteObservedAt, bytes32 quoteObservationId) =
            _quoteUsdObservation();
        uint256 marketCapUsdE8 = _marketCapAtTick(twapTick, liveQuoteUsdE8);
        if (marketCapUsdE8 == 0) revert InvalidQuoteUsdObservation();
        (int24 effectiveLowerTick, int24 effectiveUpperTick) =
            _effectiveTicks(lowerMarketCapUsdE8, upperMarketCapUsdE8);
        uint48 currentTime = uint48(block.timestamp);
        observation = FundingBandObservation({
            marketCapUsdE8: marketCapUsdE8,
            observedAt: quoteObservedAt < currentTime ? quoteObservedAt : currentTime,
            observationId: keccak256(
                abi.encode(
                    block.chainid,
                    address(this),
                    canonicalPool,
                    minimumTwapWindow,
                    olderCumulative,
                    currentCumulative,
                    twapTick,
                    liveQuoteUsdE8,
                    quoteObservationId
                )
            ),
            effectiveLowerTick: effectiveLowerTick,
            effectiveUpperTick: effectiveUpperTick
        });
    }

    function marketCapAtTick(int24 tick, uint256 quoteUsdPriceE8) external view returns (uint256) {
        if (quoteUsdPriceE8 == 0) revert InvalidQuoteUsdObservation();
        return _marketCapAtTick(tick, quoteUsdPriceE8);
    }

    function effectiveTicks(uint128 lowerMarketCapUsdE8, uint128 upperMarketCapUsdE8)
        external
        view
        returns (int24 lower, int24 upper)
    {
        if (lowerMarketCapUsdE8 == 0 || lowerMarketCapUsdE8 >= upperMarketCapUsdE8) {
            revert InvalidMarketCapBounds(lowerMarketCapUsdE8, upperMarketCapUsdE8);
        }
        return _effectiveTicks(lowerMarketCapUsdE8, upperMarketCapUsdE8);
    }

    function _twapTick()
        private
        view
        returns (int24 arithmeticMeanTick, int56 olderCumulative, int56 currentCumulative)
    {
        (,, uint16 observationIndex, uint16 cardinality,,, bool unlocked) =
            IUniswapV3Pool(canonicalPool).slot0();
        observationIndex;
        if (!unlocked || cardinality < 2) revert OracleNotReady();
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = minimumTwapWindow;
        try IUniswapV3Pool(canonicalPool).observe(secondsAgos) returns (
            int56[] memory tickCumulatives, uint160[] memory
        ) {
            if (tickCumulatives.length != 2) revert OracleNotReady();
            olderCumulative = tickCumulatives[0];
            currentCumulative = tickCumulatives[1];
        } catch {
            revert OracleNotReady();
        }
        int56 delta = currentCumulative - olderCumulative;
        int56 window = int56(uint56(minimumTwapWindow));
        // A time-weighted mean of valid V3 int24 ticks remains within the int24 tick domain.
        // forge-lint: disable-next-line(unsafe-typecast)
        arithmeticMeanTick = int24(delta / window);
        if (delta < 0 && delta % window != 0) --arithmeticMeanTick;
    }

    function _quoteUsdObservation()
        private
        view
        returns (uint256 priceUsdE8, uint48 observedAt, bytes32 observationId)
    {
        uint48 currentTime = uint48(block.timestamp);
        if (quoteUsdOracle == address(0)) {
            return (
                tickReferenceQuoteUsdE8,
                currentTime,
                keccak256(abi.encode("FIXED_QUOTE_USD", quoteAsset, tickReferenceQuoteUsdE8))
            );
        }
        (priceUsdE8, observedAt, observationId) =
            IFundingBandQuoteUsdOracle(quoteUsdOracle).latestPriceUsdE8();
        if (priceUsdE8 == 0 || observationId == bytes32(0) || observedAt > currentTime) {
            revert InvalidQuoteUsdObservation();
        }
        if (currentTime - observedAt > maximumOracleAge) {
            revert StaleQuoteUsdObservation(observedAt, currentTime);
        }
    }

    function _marketCapAtTick(int24 tick, uint256 quoteUsdPriceE8) private view returns (uint256) {
        uint256 totalQuoteRaw = _quoteAtTick(tick, referenceSupply, subject, quoteAsset);
        return FullMath.mulDiv(totalQuoteRaw, quoteUsdPriceE8, quoteUnit);
    }

    function _effectiveTicks(uint128 lowerMarketCapUsdE8, uint128 upperMarketCapUsdE8)
        private
        view
        returns (int24 lower, int24 upper)
    {
        int24 first = _tickForMarketCap(lowerMarketCapUsdE8);
        int24 second = _tickForMarketCap(upperMarketCapUsdE8);
        int24 numericLower = first < second ? first : second;
        int24 numericUpper = first < second ? second : first;
        lower = _ceilToSpacing(numericLower);
        upper = _floorToSpacing(numericUpper);
        if (lower >= upper) revert EffectiveTicksCollapsed(lower, upper);
    }

    function _tickForMarketCap(uint256 marketCapUsdE8) private view returns (int24 tick) {
        uint256 totalQuoteRaw = Math.mulDiv(marketCapUsdE8, quoteUnit, tickReferenceQuoteUsdE8);
        if (totalQuoteRaw == 0) revert PriceOutsideTickRange(marketCapUsdE8);
        uint256 amount0 = subject < quoteAsset ? referenceSupply : totalQuoteRaw;
        uint256 amount1 = subject < quoteAsset ? totalQuoteRaw : referenceSupply;
        uint256 ratioX128 = Math.mulDiv(amount1, uint256(1) << 128, amount0);
        if (ratioX128 == 0) revert PriceOutsideTickRange(marketCapUsdE8);
        uint256 sqrtPrice = Math.sqrt(ratioX128) << 32;
        if (
            sqrtPrice < TickMath.MIN_SQRT_PRICE || sqrtPrice >= TickMath.MAX_SQRT_PRICE
                || sqrtPrice > type(uint160).max
        ) revert PriceOutsideTickRange(marketCapUsdE8);
        // The explicit bound above proves this conversion cannot truncate.
        // forge-lint: disable-next-line(unsafe-typecast)
        tick = TickMath.getTickAtSqrtPrice(uint160(sqrtPrice));
    }

    function _floorToSpacing(int24 tick) private view returns (int24 result) {
        int24 compressed = tick / tickSpacing;
        if (tick < 0 && tick % tickSpacing != 0) --compressed;
        result = compressed * tickSpacing;
    }

    function _ceilToSpacing(int24 tick) private view returns (int24 result) {
        result = _floorToSpacing(tick);
        if (result < tick) result += tickSpacing;
    }

    function _quoteAtTick(int24 tick, uint256 baseAmount, address baseToken, address quoteToken)
        private
        pure
        returns (uint256 quoteAmount)
    {
        uint160 sqrtRatioX96 = TickMath.getSqrtPriceAtTick(tick);
        if (sqrtRatioX96 <= type(uint128).max) {
            uint256 ratioX192 = uint256(sqrtRatioX96) * sqrtRatioX96;
            quoteAmount = baseToken < quoteToken
                ? FullMath.mulDiv(ratioX192, baseAmount, uint256(1) << 192)
                : FullMath.mulDiv(uint256(1) << 192, baseAmount, ratioX192);
        } else {
            uint256 ratioX128 = FullMath.mulDiv(sqrtRatioX96, sqrtRatioX96, uint256(1) << 64);
            quoteAmount = baseToken < quoteToken
                ? FullMath.mulDiv(ratioX128, baseAmount, uint256(1) << 128)
                : FullMath.mulDiv(uint256(1) << 128, baseAmount, ratioX128);
        }
    }
}
