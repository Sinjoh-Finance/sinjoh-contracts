// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ISinjohLaunchVerifier } from "./ISinjohLaunchVerifier.sol";

interface ISinjohFundingBandPriceGuard {
    /// @notice Reverts unless spot and the manipulation-resistant reference are below
    /// the economic boundary represented by `boundaryTick`.
    function validateBelow(
        ISinjohLaunchVerifier.VerifiedLaunch calldata launch,
        int24 boundaryTick,
        bool subjectIsToken0,
        bytes calldata guardData
    ) external view;

    /// @notice Reverts unless spot and the manipulation-resistant reference have crossed
    /// the economic boundary represented by `boundaryTick`.
    function validateAbove(
        ISinjohLaunchVerifier.VerifiedLaunch calldata launch,
        int24 boundaryTick,
        bool subjectIsToken0,
        bytes calldata guardData
    ) external view;
}
