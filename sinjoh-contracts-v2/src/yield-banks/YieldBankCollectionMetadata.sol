// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IYieldBankCollectionMetadata } from "./interfaces/IYieldBankCollectionMetadata.sol";

/// @notice Immutable name and symbol storage for one Yield Bank NFT collection.
/// @dev Token metadata and artwork remain collection-controlled through the NFT's base URI.
contract YieldBankCollectionMetadata is IYieldBankCollectionMetadata {
    string public collectionName;
    string public collectionSymbol;

    error InvalidConfiguration();

    constructor(string memory collectionName_, string memory collectionSymbol_) {
        bytes memory nameBytes = bytes(collectionName_);
        bytes memory symbolBytes = bytes(collectionSymbol_);
        if (
            nameBytes.length == 0 || nameBytes.length > 128 || symbolBytes.length == 0
                || symbolBytes.length > 32
        ) revert InvalidConfiguration();
        collectionName = collectionName_;
        collectionSymbol = collectionSymbol_;
    }
}
