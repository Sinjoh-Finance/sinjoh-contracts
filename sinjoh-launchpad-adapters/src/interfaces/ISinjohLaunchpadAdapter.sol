// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

/// @notice The seam between `SinjohFeeRouter` and any launchpad.
///
/// One instance per launch. The adapter is the launchpad-side identity: it is
/// the launch deployer and the creator-fee recipient, and it forwards what it
/// receives to exactly one immutable router.
///
/// Launch is deliberately absent. Launch parameters are irreducibly
/// launchpad-specific, and funnelling them through a common `bytes` blob would
/// recreate the arbitrary-calldata surface these adapters exist to avoid. Each
/// adapter exposes its own typed `launch`.
interface ISinjohLaunchpadAdapter {
    /// @notice The router that receives everything this adapter forwards.
    function router() external view returns (address);

    /// @notice The launched token, or zero before launch.
    function subject() external view returns (address);

    /// @notice Assets this adapter is permitted to forward. Fixed at launch.
    function intakeAssets() external view returns (address[] memory);

    /// @notice Pulls whatever the launchpad currently owes into this adapter.
    /// Permissionless. An upstream "nothing accrued" condition is a no-op, not
    /// a revert, so keeper polling on an idle launch is not an error.
    ///
    /// @dev Returns one amount per entry of `intakeAssets()`, in that order.
    /// Deliberately not a fixed pair: pons v2 pays a single quote asset, pons
    /// v1 pays both the subject token and WETH from its v3 position, and a
    /// third launchpad may do something else again. A fixed arity would encode
    /// one launchpad's asset model into the interface every other launchpad has
    /// to satisfy.
    function collect() external returns (uint256[] memory amounts);

    /// @notice Forwards this adapter's full balance of `asset` to the router.
    /// Permissionless. Returns zero without an external call on a zero balance.
    function forward(address asset) external returns (uint256 amount);
}
