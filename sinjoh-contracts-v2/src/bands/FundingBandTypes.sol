// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

enum FundingBandState {
    NONE,
    ACTIVE,
    ARMED,
    SETTLED_PENDING_DELIVERY,
    DELIVERED
}

enum FundingBandDestination {
    CREATOR,
    TREASURY,
    BUYBACK_BURN,
    BUYBACK_AIRDROP,
    ROUTER,
    RAFFLE,
    BASKET_VIA_TREASURY
}

struct FundingBandConfig {
    uint128 lowerMarketCapUsdE8;
    uint128 upperMarketCapUsdE8;
    uint128 subjectAmount;
    FundingBandDestination destination;
    bytes destinationConfig;
}

struct FundingBandObservation {
    uint256 marketCapUsdE8;
    uint48 observedAt;
    bytes32 observationId;
    int24 effectiveLowerTick;
    int24 effectiveUpperTick;
}

struct FundingBandSwapConfig {
    address swapAdapter;
    address priceGuard;
    uint16 maxSlippageBps;
    bytes routeData;
    bytes guardData;
    bytes32[] approvalProof;
}

struct FundingBandDeliveryConfig {
    bytes fundConfig;
    FundingBandSwapConfig conversion;
}
