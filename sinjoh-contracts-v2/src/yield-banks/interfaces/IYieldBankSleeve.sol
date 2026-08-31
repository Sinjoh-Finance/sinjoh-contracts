// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { YieldBankRedemptionMode } from "../YieldBankTypes.sol";

interface IYieldBankSleeve {
    function category() external view returns (bytes32);
    function accountingAsset() external view returns (address);
    function totalAssetsUsd18() external view returns (uint256 value, uint48 pricedAt);
    function activeStrategyCount() external view returns (uint256);
    function deposit(uint256 assets, address receiver, uint256 minShares, bytes calldata data)
        external
        returns (uint256 shares);
    function redeem(
        uint256 shares,
        address receiver,
        address owner,
        YieldBankRedemptionMode mode,
        uint256[] calldata minimumOutputs,
        bytes calldata data
    ) external returns (address[] memory assets, uint256[] memory amounts);
}
