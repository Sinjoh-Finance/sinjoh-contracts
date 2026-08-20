// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

interface IStakingSnapshot {
    function currentVotes(address account) external view returns (uint256);
    function currentTotalVotes() external view returns (uint256);
    function getPastVotes(address account, uint256 timepoint) external view returns (uint256);
    function getPastTotalSupply(uint256 timepoint) external view returns (uint256);
    function getPastRewardWeight(address account, uint256 timepoint) external view returns (uint256);
    function getPastTotalRewardWeight(uint256 timepoint) external view returns (uint256);
    function getPastEligibleRewardWeight(
        address account,
        uint256 checkpointTimepoint,
        uint256 eligibilityTimepoint
    ) external view returns (uint256);
    function getPastEligibleTotalRewardWeight(
        uint256 checkpointTimepoint,
        uint256 eligibilityTimepoint
    ) external view returns (uint256);
    function getPastUnlockTime(address account, uint256 timepoint) external view returns (uint256);
}
