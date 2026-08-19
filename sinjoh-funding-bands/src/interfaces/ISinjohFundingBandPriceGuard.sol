// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ISinjohLaunchVerifier } from "./ISinjohLaunchVerifier.sol";

interface ISinjohFundingBandPriceGuard {
    /// @notice Reverts unless the guard's configured price evidence is below the
    /// economic boundary represented by `boundaryTick`.
    function validateBelow(
        ISinjohLaunchVerifier.VerifiedLaunch calldata launch,
        int24 boundaryTick,
        bool subjectIsToken0,
        bytes calldata guardData
    ) external view;

    /// @notice Reverts unless the guard's configured price evidence has crossed the
    /// economic boundary represented by `boundaryTick`.
    function validateAbove(
        ISinjohLaunchVerifier.VerifiedLaunch calldata launch,
        int24 boundaryTick,
        bool subjectIsToken0,
        bytes calldata guardData
    ) external view;
}
