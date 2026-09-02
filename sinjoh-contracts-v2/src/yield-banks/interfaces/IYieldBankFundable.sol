// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

interface IYieldBankFundable {
    function fund(
        bytes32 collectionId,
        address sourceAsset,
        uint256 amount,
        bytes32 sourceType,
        bytes calldata sourceData
    ) external returns (uint256 received);
}
