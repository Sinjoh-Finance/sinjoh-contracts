// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { YieldBankCollectionState } from "../YieldBankTypes.sol";

interface IYieldBankCollection {
    function state() external view returns (YieldBankCollectionState);
    function collectionId() external view returns (bytes32);
    function nft() external view returns (address);
    function portfolioAllocator() external view returns (address);
    function weth() external view returns (address);
    function coreWeightBps() external view returns (uint16);
    function marketMakingWeightBps() external view returns (uint16);
    function usdgWeightBps() external view returns (uint16);
    function liveSupply() external view returns (uint256);
    function totalLiveFeeWeight() external view returns (uint256);
    function maximumTotalFeeWeight() external view returns (uint256);
    function feeWeightRangeCount() external view returns (uint256);
    function feeWeightRange(uint256 index) external view returns (uint64 endTokenId, uint96 weight);
    function feeWeightOf(uint256 tokenId) external view returns (uint96);
    function accountOf(uint256 tokenId) external view returns (address);
    function distributor() external view returns (address);
    function proceedsVault() external view returns (address);
    function isSleeveAsset(address asset) external view returns (bool);
    function claimPrimary(uint256 tokenId) external;
    function settle(uint256 tokenId) external;
    function accrueDistribution(address asset, uint256 amount) external;
}
