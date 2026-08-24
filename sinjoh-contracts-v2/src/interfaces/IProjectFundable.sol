// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

/// @notice Common attributed-funding interface for routeable Sinjoh v2 value sinks.
interface IProjectFundable {
    function fund(
        bytes32 projectId,
        address subject,
        address asset,
        uint256 amount,
        bytes calldata config
    ) external payable returns (uint256 received);
}
