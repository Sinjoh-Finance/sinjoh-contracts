// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

/// @notice Identity readbacks required from every Sinjoh v2 project module.
interface IProjectModule {
    function projectId() external view returns (bytes32);
    function registry() external view returns (address);
    function subject() external view returns (address);
}
