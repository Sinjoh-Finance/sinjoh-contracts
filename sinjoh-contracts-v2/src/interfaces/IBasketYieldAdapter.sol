// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

/// @notice Narrow, vault-bound interface for one approved yield-bearing position.
interface IBasketYieldAdapter {
    function basketVault() external view returns (address);
    function depositAsset() external view returns (address);
    function deposit(uint256 assets) external returns (uint256 positionUnits);
    function totalAssets() external view returns (uint256 assets);
    function harvest(address recipient)
        external
        returns (address[] memory assets, uint256[] memory amounts);
    function exitAll(address recipient)
        external
        returns (address[] memory assets, uint256[] memory amounts);
}
