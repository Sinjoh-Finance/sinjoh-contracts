// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import { ISinjohFundingBandPriceGuard } from "../interfaces/ISinjohFundingBandPriceGuard.sol";
import { ISinjohLaunchVerifier } from "../interfaces/ISinjohLaunchVerifier.sol";

contract SinjohV3TwapBandPriceGuard is ISinjohFundingBandPriceGuard {
    uint32 public constant MAX_TWAP_WINDOW = 1 days;
    int24 public constant MAX_TICK_DEVIATION = 50_000;

    error InvalidConfiguration();
    error InvalidLaunch();
    error OracleNotReady();
    error ExcessiveDeviation(int24 spotTick, int24 twapTick);
    error BoundaryNotCrossed();

    uint32 public immutable twapWindow;
    int24 public immutable maxSpotTwapDeviation;

    constructor(uint32 twapWindow_, int24 maxSpotTwapDeviation_) {
        if (
            twapWindow_ == 0 || twapWindow_ > MAX_TWAP_WINDOW || maxSpotTwapDeviation_ <= 0
                || maxSpotTwapDeviation_ > MAX_TICK_DEVIATION
        ) revert InvalidConfiguration();
        twapWindow = twapWindow_;
        maxSpotTwapDeviation = maxSpotTwapDeviation_;
    }

    function validateBelow(
        ISinjohLaunchVerifier.VerifiedLaunch calldata launch,
        int24 boundaryTick,
        bool subjectIsToken0,
        bytes calldata guardData
    ) external view {
        (int24 spotTick, int24 twapTick) = _validatedTicks(launch, guardData);
        bool below = subjectIsToken0
            ? spotTick < boundaryTick && twapTick < boundaryTick
            : spotTick > boundaryTick && twapTick > boundaryTick;
        if (!below) revert BoundaryNotCrossed();
    }

    function validateAbove(
        ISinjohLaunchVerifier.VerifiedLaunch calldata launch,
        int24 boundaryTick,
        bool subjectIsToken0,
        bytes calldata guardData
    ) external view {
        (int24 spotTick, int24 twapTick) = _validatedTicks(launch, guardData);
        bool above = subjectIsToken0
            ? spotTick >= boundaryTick && twapTick >= boundaryTick
            : spotTick <= boundaryTick && twapTick <= boundaryTick;
        if (!above) revert BoundaryNotCrossed();
    }

    function _validatedTicks(
        ISinjohLaunchVerifier.VerifiedLaunch calldata launch,
        bytes calldata guardData
    ) private view returns (int24 spotTick, int24 twapTick) {
        if (
            launch.venue != ISinjohLaunchVerifier.Venue.UNISWAP_V3 || launch.pool.code.length == 0
                || guardData.length != 0
        ) revert InvalidLaunch();
        uint16 observationCardinality;
        bool unlocked;
        (, spotTick,, observationCardinality,,, unlocked) = IUniswapV3Pool(launch.pool).slot0();
        if (!unlocked || observationCardinality < 2) revert OracleNotReady();

        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = twapWindow;
        secondsAgos[1] = 0;
        try IUniswapV3Pool(launch.pool).observe(secondsAgos) returns (
            int56[] memory tickCumulatives, uint160[] memory
        ) {
            if (tickCumulatives.length != 2) revert OracleNotReady();
            int56 delta = tickCumulatives[1] - tickCumulatives[0];
            int56 window = int56(uint56(twapWindow));
            // A time-weighted average of valid Uniswap int24 ticks remains in int24 range.
            // forge-lint: disable-next-line(unsafe-typecast)
            twapTick = int24(delta / window);
            if (delta < 0 && delta % window != 0) twapTick--;
        } catch {
            revert OracleNotReady();
        }
        int256 difference = int256(spotTick) - int256(twapTick);
        if (difference < 0) difference = -difference;
        if (difference > int256(maxSpotTwapDeviation)) {
            revert ExcessiveDeviation(spotTick, twapTick);
        }
    }
}
