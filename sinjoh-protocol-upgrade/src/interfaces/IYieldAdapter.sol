// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

interface IYieldAdapter {
    function asset() external view returns (address);
    function deposit(uint256 amount) external returns (uint256 shares);
    function withdraw(uint256 shares) external returns (uint256 assets);
    function harvest() external returns (address[] memory rewardTokens, uint256[] memory amounts);
    function totalAssets() external view returns (uint256);
}
