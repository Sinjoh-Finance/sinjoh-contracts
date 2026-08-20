// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

interface IStakingSnapshot {
    function currentVotes(address account) external view returns (uint256);
    function currentTotalVotes() external view returns (uint256);
    function getPastVotes(address account, uint256 blockNumber) external view returns (uint256);
    function getPastTotalSupply(uint256 blockNumber) external view returns (uint256);
    function getPastRewardWeight(address account, uint256 blockNumber)
        external
        view
        returns (uint256);
    function getPastTotalRewardWeight(uint256 blockNumber) external view returns (uint256);
    function getPastUnlockTime(address account, uint256 blockNumber) external view returns (uint256);
}
