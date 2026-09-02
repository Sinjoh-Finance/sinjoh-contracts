// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

interface IYieldBankCollectionMetadata {
    function collectionName() external view returns (string memory);
    function collectionSymbol() external view returns (string memory);
}
