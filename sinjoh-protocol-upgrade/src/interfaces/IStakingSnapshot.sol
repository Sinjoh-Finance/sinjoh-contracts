// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

interface IStakingSnapshot {
    function balanceOf(address account) external view returns (uint256);
    function totalStaked() external view returns (uint256);
    function getPastBalance(address account, uint256 timepoint) external view returns (uint256);
    function getPastTotalStaked(uint256 timepoint) external view returns (uint256);
}
