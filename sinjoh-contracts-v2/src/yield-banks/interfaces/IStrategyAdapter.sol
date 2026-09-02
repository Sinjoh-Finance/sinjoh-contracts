// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

interface IStrategyAdapter {
    function sleeve() external view returns (address);
    function accountingAsset() external view returns (address);
    function positionAssets() external view returns (address[] memory);
    function totalManagedAssets() external view returns (uint256);
    function totalPositionUnits() external view returns (uint256);
    function deposit(uint256 assets, uint256 minPositionUnits, bytes calldata data)
        external
        returns (uint256 positionUnits);
    function withdraw(uint256 assets, address receiver, uint16 maxLossBps, bytes calldata data)
        external
        returns (uint256 assetsReturned);
    function collect(address receiver, bytes calldata data)
        external
        returns (address[] memory assets, uint256[] memory amounts);
    function exitAll(address receiver, uint16 maxLossBps, bytes calldata data)
        external
        returns (address[] memory assets, uint256[] memory amounts);
}
