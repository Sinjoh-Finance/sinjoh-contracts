// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

interface IBasketMetadataSource {
    function isBasketTransferAllowed(uint256 basketId) external view returns (bool);
    function basketMetadata(uint256 basketId)
        external
        view
        returns (
            address subject,
            address vault,
            uint8 state,
            uint8 cadence,
            uint256 burnPrice,
            uint16 burnTaxBps
        );
}
