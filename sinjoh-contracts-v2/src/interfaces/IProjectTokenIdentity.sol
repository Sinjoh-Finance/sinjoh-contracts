// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

/// @notice Immutable identity surface required from a v2 project token.
interface IProjectTokenIdentity {
    function registry() external view returns (address);
    function projectId() external view returns (bytes32);
}
