// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { PoolId } from "@uniswap/v4-core/src/types/PoolId.sol";

import { IV4StateView } from "../SinjohFundingBands.sol";
import { ISinjohFundingBandPriceGuard } from "../interfaces/ISinjohFundingBandPriceGuard.sol";
import { ISinjohLaunchVerifier } from "../interfaces/ISinjohLaunchVerifier.sol";

/// @notice Autonomous Pons v2/v4 crossing guard.
/// @dev This contract reads only the canonical v4 StateView. The manager supplies
/// manipulation resistance by requiring two above-boundary observations separated
/// by its immutable settlement delay. No signer, publisher, or mutable administrator
/// participates in validation.
contract SinjohV4DelayedBandPriceGuard is ISinjohFundingBandPriceGuard {
    error InvalidAddress();
    error InvalidLaunch();
    error InvalidGuardData();
    error DependencyChanged();
    error PoolNotInitialized();
    error BoundaryNotCrossed();

    IV4StateView public immutable stateView;
    address public immutable poolManager;
    bytes32 public immutable stateViewCodehash;
    bytes32 public immutable poolManagerCodehash;

    constructor(address stateView_, bytes32 stateViewCodehash_, bytes32 poolManagerCodehash_) {
        if (stateView_.code.length == 0 || stateView_.codehash != stateViewCodehash_) {
            revert InvalidAddress();
        }
        address poolManager_ = IV4StateView(stateView_).poolManager();
        if (
            poolManager_.code.length == 0 || poolManager_.codehash != poolManagerCodehash_
                || poolManager_ == stateView_
        ) revert InvalidAddress();
        stateView = IV4StateView(stateView_);
        poolManager = poolManager_;
        stateViewCodehash = stateViewCodehash_;
        poolManagerCodehash = poolManagerCodehash_;
    }

    function validateBelow(
        ISinjohLaunchVerifier.VerifiedLaunch calldata launch,
        int24 boundaryTick,
        bool subjectIsToken0,
        bytes calldata guardData
    ) public view virtual {
        int24 spotTick = _spotTick(launch, guardData);
        bool below = subjectIsToken0 ? spotTick < boundaryTick : spotTick > boundaryTick;
        if (!below) revert BoundaryNotCrossed();
    }

    function validateAbove(
        ISinjohLaunchVerifier.VerifiedLaunch calldata launch,
        int24 boundaryTick,
        bool subjectIsToken0,
        bytes calldata guardData
    ) public view virtual {
        int24 spotTick = _spotTick(launch, guardData);
        bool above = subjectIsToken0 ? spotTick >= boundaryTick : spotTick <= boundaryTick;
        if (!above) revert BoundaryNotCrossed();
    }

    /// @notice Validates the live crossing used to start the manager's hold timer.
    /// @dev Confirmation-aware guards override `validateAbove` for final settlement
    /// while retaining this canonical spot check for the initial arm operation.
    function validateArm(
        ISinjohLaunchVerifier.VerifiedLaunch calldata launch,
        int24 boundaryTick,
        bool subjectIsToken0,
        bytes calldata guardData
    ) external view virtual {
        int24 spotTick = _spotTick(launch, guardData);
        bool above = subjectIsToken0 ? spotTick >= boundaryTick : spotTick <= boundaryTick;
        if (!above) revert BoundaryNotCrossed();
    }

    function _spotTick(
        ISinjohLaunchVerifier.VerifiedLaunch calldata launch,
        bytes calldata guardData
    ) internal view returns (int24 spotTick) {
        if (guardData.length != 0) revert InvalidGuardData();
        if (
            launch.venue != ISinjohLaunchVerifier.Venue.UNISWAP_V4 || launch.poolId == bytes32(0)
                || launch.pool != address(0)
        ) revert InvalidLaunch();
        if (
            address(stateView).codehash != stateViewCodehash
                || poolManager.codehash != poolManagerCodehash
                || stateView.poolManager() != poolManager
        ) revert DependencyChanged();
        uint160 sqrtPriceX96;
        (sqrtPriceX96, spotTick,,) = stateView.getSlot0(PoolId.wrap(launch.poolId));
        if (sqrtPriceX96 == 0) revert PoolNotInitialized();
    }
}
