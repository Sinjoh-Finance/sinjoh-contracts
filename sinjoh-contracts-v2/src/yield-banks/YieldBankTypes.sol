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

struct YieldBankConfig {
    bytes32 collectionId;
    uint256 maxSupply;
    YieldBankFeeWeightRange[] feeWeightRanges;
    uint96 secondaryRoyaltyBps;
    uint16 primaryBackingBps;
    uint16 primaryCreatorBps;
    uint16 primarySinjohBps;
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
    address renderer;
    address weth;
    address seaDrop;
    address coreSleeve;
    address marketMakingSleeve;
    address usdgSleeve;
    address accountImplementation;
    bytes32[10] integrationCodeHashes;
}
