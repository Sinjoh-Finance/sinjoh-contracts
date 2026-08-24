// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

/// @notice Identity exposed by an approved per-launch launchpad adapter.
interface IProjectLaunchAdapter {
    function adapterFactory() external view returns (address);
    function creator() external view returns (address);
    function subject() external view returns (address);
}

/// @notice Factory registry used to prove that an adapter was created by an approved generation.
interface IProjectLaunchAdapterFactory {
    function isAdapter(address adapter) external view returns (bool);
}
