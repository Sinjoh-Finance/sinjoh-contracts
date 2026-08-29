// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

struct PublicDrop {
    uint80 mintPrice;
    uint48 startTime;
    uint48 endTime;
    uint16 maxTotalMintableByWallet;
    uint16 feeBps;
    bool restrictFeeRecipients;
}

struct TokenGatedDropStage {
    uint80 mintPrice;
    uint16 maxTotalMintableByWallet;
    uint48 startTime;
    uint48 endTime;
    uint8 dropStageIndex;
    uint32 maxTokenSupplyForStage;
    uint16 feeBps;
    bool restrictFeeRecipients;
}

struct AllowListData {
    bytes32 merkleRoot;
    string[] publicKeyURIs;
    string allowListURI;
}

struct SignedMintValidationParams {
    uint80 minMintPrice;
    uint24 maxMaxTotalMintableByWallet;
    uint40 minStartTime;
    uint40 maxEndTime;
    uint40 maxMaxTokenSupplyForStage;
    uint16 minFeeBps;
    uint16 maxFeeBps;
}
