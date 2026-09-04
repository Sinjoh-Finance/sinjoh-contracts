// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

enum YieldBankCollectionState {
    DEPLOYED,
    ACTIVE,
    INVESTMENT_PAUSED,
    CLOSED
}
enum YieldBankTokenState {
    UNMINTED,
    ACTIVE,
    BURNING,
    BURNED
}
enum YieldBankAdapterState {
    UNREGISTERED,
    REGISTERED,
    REJECTED,
    ACTIVE,
    DEPOSIT_PAUSED,
    EXIT_ONLY,
    RETIRED
}
enum YieldBankRedemptionMode {
    IN_KIND
}

/// @notice An inclusive token-id boundary and its relative collection-fee weight.
/// @dev Ranges are contiguous from token id 1. An empty schedule means every token has weight 1.
struct YieldBankFeeWeightRange {
    uint64 endTokenId;
    uint96 feeWeight;
}

/// @notice One independently mintable, fixed-price token-id tier for a collection.
/// @dev Tiers are ordered by their inclusive `endTokenId`; a tier starts one token after the prior
///      tier. Initial allowlist windows are nonoverlapping and later public windows select a tier
///      by matching its immutable economic terms. Prices and fees are denominated in the chain's
///      native token and basis points. An empty schedule preserves unrestricted SeaDrop behavior.
struct YieldBankMintStage {
    uint64 endTokenId;
    uint80 mintPrice;
    uint48 startTime;
    uint48 endTime;
    uint16 maxMintsPerWallet;
    uint16 feeBps;
    uint8 dropStageIndex;
    bool restrictFeeRecipients;
}

struct YieldBankConfig {
    bytes32 collectionId;
    uint256 maxSupply;
    YieldBankFeeWeightRange[] feeWeightRanges;
    uint96 secondaryRoyaltyBps;
    uint16 primaryBackingBps;
    uint16 primaryCreatorBps;
    uint16 primarySinjohBps;
    uint16 royaltyBackingBps;
    uint16 royaltyCreatorBps;
    uint16 royaltySinjohBps;
    uint16 exitTaxBps;
    uint16 coreWeightBps;
    uint16 marketMakingWeightBps;
    uint16 usdgWeightBps;
    address creator;
    address openSeaManager;
    address sinjohFeeRecipient;
    address redemptionToken;
    uint256 redemptionTokenAmount;
    bytes32 redemptionTokenCodeHash;
    address revenueRouter;
    address eligibilityPolicy;
    address portfolioAllocator;
    address allocationOperator;
    address collectionTimelock;
    address guardian;
    address metadata;
    address weth;
    address seaDrop;
    address coreSleeve;
    address marketMakingSleeve;
    address usdgSleeve;
    address accountImplementation;
    bytes32[10] integrationCodeHashes;
}
