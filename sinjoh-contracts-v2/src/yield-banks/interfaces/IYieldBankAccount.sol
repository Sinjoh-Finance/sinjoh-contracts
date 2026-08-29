// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

interface IYieldBankAccount {
    function collection() external view returns (address);
    function nft() external view returns (address);
    function tokenId() external view returns (uint256);
    function trackedAssets() external view returns (address[] memory);
    function trackAsset(address asset) external;
}
