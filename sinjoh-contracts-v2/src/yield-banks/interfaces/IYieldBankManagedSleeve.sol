// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

struct YieldBankAdapterRedemptionCall {
    address adapter;
    uint16 maxLossBps;
    bytes data;
}

interface IYieldBankManagedSleeve {
    function inventoryAssets() external view returns (address[] memory);

    function depositToAdapter(
        address adapter,
        uint256 assets,
        uint256 minPositionUnits,
        bytes calldata data
    ) external returns (uint256 positionUnits);

    function withdrawFromAdapter(
        address adapter,
        uint256 assets,
        uint16 maxLossBps,
        bytes calldata data
    ) external returns (uint256 assetsReturned);

    function collectAdapter(address adapter, bytes calldata data)
        external
        returns (address[] memory assets, uint256[] memory amounts);

    function exitAdapter(address adapter, uint16 maxLossBps, bytes calldata data)
        external
        returns (address[] memory assets, uint256[] memory amounts);

    function redeemManaged(
        uint256 shares,
        address receiver,
        address owner,
        uint256[] calldata minimumOutputs,
        YieldBankAdapterRedemptionCall[] calldata adapterCalls
    ) external returns (address[] memory assets, uint256[] memory amounts);
}
