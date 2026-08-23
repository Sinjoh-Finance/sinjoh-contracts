// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

/// @notice Fixed launch-supply surface used by project protocols for immutable calculations.
interface IProjectReferenceSupply {
    function initialSupply() external view returns (uint256);
}
