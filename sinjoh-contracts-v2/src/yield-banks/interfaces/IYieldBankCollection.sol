// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

interface IYieldBankCollection {
    function collectionId() external view returns (bytes32);
    function liveSupply() external view returns (uint256);
    function accountOf(uint256 tokenId) external view returns (address);
    function distributor() external view returns (address);
    function proceedsVault() external view returns (address);
    function accrueDistribution(address asset, uint256 amount) external;
}
