// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

/// @notice Common discovery surface for a project module with immutable control.
interface IProjectControlled {
    function projectId() external view returns (bytes32);
    function controller() external view returns (address);
}
