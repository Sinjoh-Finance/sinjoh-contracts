// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

import { IChainlinkAggregatorV3 } from "./interfaces/IChainlinkAggregatorV3.sol";

library FundingBandMath {
    uint256 private constant Q128 = 1 << 128;
    uint256 private constant Q192 = 1 << 192;
    uint256 private constant WETH_SCALE = 1e18;

    error InvalidMathInput();
    error PriceOutOfRange();
    error CollapsedRange();
    error InvalidOracleRound();
    error StaleOracleRound();

    struct ConvertedRange {
        int24 tickLower;
        int24 tickUpper;
        uint160 lowerSqrtPriceX96;
        uint160 upperSqrtPriceX96;
        uint256 lowerWethPerSubjectX128;
        uint256 upperWethPerSubjectX128;
    }

    /// @dev `launchSupply` is the raw ERC-20 supply. Token decimals cancel when converting
    /// raw subject units into raw WETH units, but are still snapshotted by the caller for
    /// disclosure and fixed-supply validation.
    function convertRange(
        uint128 lowerMarketCapUsdE8,
        uint128 upperMarketCapUsdE8,
        uint256 launchSupply,
        uint256 ethUsdE8,
        int24 tickSpacing,
        bool subjectIsToken0
    ) external pure returns (ConvertedRange memory converted) {
        if (
            lowerMarketCapUsdE8 == 0 || lowerMarketCapUsdE8 >= upperMarketCapUsdE8
                || launchSupply == 0 || ethUsdE8 == 0 || tickSpacing <= 0
        ) revert InvalidMathInput();

        converted.lowerWethPerSubjectX128 =
            _wethPerSubjectX128(lowerMarketCapUsdE8, launchSupply, ethUsdE8);
        converted.upperWethPerSubjectX128 =
            _wethPerSubjectX128(upperMarketCapUsdE8, launchSupply, ethUsdE8);
        if (
            converted.lowerWethPerSubjectX128 == 0
                || converted.lowerWethPerSubjectX128 >= converted.upperWethPerSubjectX128
        ) revert PriceOutOfRange();

        uint160 lowerEconomicSqrt =
            _sqrtPriceX96(converted.lowerWethPerSubjectX128, subjectIsToken0);
        uint160 upperEconomicSqrt =
            _sqrtPriceX96(converted.upperWethPerSubjectX128, subjectIsToken0);
        int24 lowerEconomicTick = TickMath.getTickAtSqrtPrice(lowerEconomicSqrt);
        int24 upperEconomicTick = TickMath.getTickAtSqrtPrice(upperEconomicSqrt);

        if (subjectIsToken0) {
            converted.tickLower = _ceilToSpacing(lowerEconomicTick, tickSpacing);
            converted.tickUpper = _ceilToSpacing(upperEconomicTick, tickSpacing);
        } else {
            converted.tickLower = _floorToSpacing(upperEconomicTick, tickSpacing);
            converted.tickUpper = _floorToSpacing(lowerEconomicTick, tickSpacing);
        }
        if (
            converted.tickLower < TickMath.minUsableTick(tickSpacing)
                || converted.tickUpper > TickMath.maxUsableTick(tickSpacing)
        ) revert PriceOutOfRange();
        if (converted.tickLower >= converted.tickUpper) revert CollapsedRange();

        converted.lowerSqrtPriceX96 = TickMath.getSqrtPriceAtTick(
            subjectIsToken0 ? converted.tickLower : converted.tickUpper
        );
        converted.upperSqrtPriceX96 = TickMath.getSqrtPriceAtTick(
            subjectIsToken0 ? converted.tickUpper : converted.tickLower
        );

        // Publish the executable, tick-rounded prices rather than the pre-rounding requests.
        // This keeps events and UI reads consistent with the actual liquidity position.
        converted.lowerWethPerSubjectX128 =
            _wethPerSubjectX128AtSqrt(converted.lowerSqrtPriceX96, subjectIsToken0);
        converted.upperWethPerSubjectX128 =
            _wethPerSubjectX128AtSqrt(converted.upperSqrtPriceX96, subjectIsToken0);
    }

    function snapshotEthUsd(IChainlinkAggregatorV3 oracle, uint48 maxOracleAge)
        external
        view
        returns (uint256 answerE8, uint48 updatedAt48)
    {
        (uint80 roundId, int256 answer,, uint256 updatedAt, uint80 answeredInRound) =
            oracle.latestRoundData();
        if (
            answer <= 0 || updatedAt == 0
                // Timestamp comparison intentionally rejects future-dated oracle rounds.
                // forge-lint: disable-next-line(block-timestamp)
                || updatedAt > block.timestamp || answeredInRound < roundId
        ) revert InvalidOracleRound();
        // Timestamp comparison is the intended oracle staleness bound.
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp - updatedAt > maxOracleAge) revert StaleOracleRound();
        uint8 decimals = oracle.decimals();
        if (decimals > 36 || updatedAt > type(uint48).max) revert InvalidOracleRound();
        // The negative and zero cases were rejected above.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 unsignedAnswer = uint256(answer);
        if (decimals < 8) {
            answerE8 = unsignedAnswer * (10 ** (8 - decimals));
        } else if (decimals > 8) {
            answerE8 = unsignedAnswer / (10 ** (decimals - 8));
        } else {
            answerE8 = unsignedAnswer;
        }
        if (answerE8 == 0) revert InvalidOracleRound();
        // `updatedAt` was bounded to uint48 above.
        // forge-lint: disable-next-line(unsafe-typecast)
        updatedAt48 = uint48(updatedAt);
    }

    function _wethPerSubjectX128(uint256 marketCapUsdE8, uint256 supply, uint256 ethUsdE8)
        private
        pure
        returns (uint256)
    {
        uint256 usdScaled = FullMath.mulDiv(marketCapUsdE8, WETH_SCALE * Q128, supply);
        return usdScaled / ethUsdE8;
    }

    function _sqrtPriceX96(uint256 wethPerSubjectX128, bool subjectIsToken0)
        private
        pure
        returns (uint160 sqrtPriceX96)
    {
        uint256 direct = Math.sqrt(wethPerSubjectX128) << 32;
        if (direct < TickMath.MIN_SQRT_PRICE || direct >= TickMath.MAX_SQRT_PRICE) {
            revert PriceOutOfRange();
        }
        uint256 oriented = subjectIsToken0 ? direct : Q192 / direct;
        if (oriented < TickMath.MIN_SQRT_PRICE || oriented >= TickMath.MAX_SQRT_PRICE) {
            revert PriceOutOfRange();
        }
        // TickMath.MAX_SQRT_PRICE is strictly below uint160's maximum.
        // forge-lint: disable-next-line(unsafe-typecast)
        sqrtPriceX96 = uint160(oriented);
    }

    function _wethPerSubjectX128AtSqrt(uint160 sqrtPriceX96, bool subjectIsToken0)
        private
        pure
        returns (uint256)
    {
        uint256 orientedPriceX128 =
            FullMath.mulDiv(uint256(sqrtPriceX96), uint256(sqrtPriceX96), 1 << 64);
        if (orientedPriceX128 == 0) revert PriceOutOfRange();
        return subjectIsToken0 ? orientedPriceX128 : FullMath.mulDiv(Q128, Q128, orientedPriceX128);
    }

    function _floorToSpacing(int24 tick, int24 spacing) private pure returns (int24) {
        int24 compressed = tick / spacing;
        if (tick < 0 && tick % spacing != 0) compressed--;
        return compressed * spacing;
    }

    function _ceilToSpacing(int24 tick, int24 spacing) private pure returns (int24) {
        int24 floorTick = _floorToSpacing(tick, spacing);
        return floorTick == tick ? tick : floorTick + spacing;
    }
}
