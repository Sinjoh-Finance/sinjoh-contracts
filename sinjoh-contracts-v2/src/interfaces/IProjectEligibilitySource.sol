// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

/// @notice Timestamp-checkpoint surface shared by liquid-token and staking eligibility sources.
interface IProjectEligibilitySource {
    function CLOCK_MODE() external view returns (string memory);
    function clock() external view returns (uint48);
    function getPastVotes(address account, uint256 timepoint) external view returns (uint256);
    function getPastTotalSupply(uint256 timepoint) external view returns (uint256);
}
