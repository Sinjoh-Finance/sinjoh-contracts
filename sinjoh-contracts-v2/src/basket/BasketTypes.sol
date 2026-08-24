// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

enum BasketState {
    ACTIVE,
    REBALANCING,
    BURNING,
    BURNED
}

enum BasketHarvestCadence {
    ONE_DAY,
    SEVEN_DAYS
}

enum BasketEligibilityMode {
    HOLDERS,
    STAKERS
}

enum BasketBurnTaxDestination {
    CREATOR,
    TREASURY,
    ROUTER,
    AIRDROP
}

struct BasketTarget {
    address depositAsset;
    address yieldAdapter;
    uint16 targetWeightBps;
    address[] rewardAssets;
    bytes32[] yieldApprovalProof;
}

struct BasketSwapLeg {
    address inputAsset;
    uint8 targetIndex;
    address swapAdapter;
    address priceGuard;
    uint16 maxSlippageBps;
    bytes routeData;
    bytes32[] approvalProof;
}

struct BasketAllocationConfig {
    address[] inputAssets;
    BasketTarget[] targets;
    BasketSwapLeg[] swapLegs;
}

struct BasketConfig {
    BasketHarvestCadence cadence;
    BasketEligibilityMode eligibilityMode;
    bool governanceUpdatesEnabled;
    uint16 burnTaxBps;
    BasketBurnTaxDestination burnTaxDestination;
    uint256 burnPriceSubject;
    bytes airdropAccountConfig;
    BasketAllocationConfig allocation;
}
