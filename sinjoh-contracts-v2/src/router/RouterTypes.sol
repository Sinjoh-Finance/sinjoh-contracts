// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

enum RouterActionType {
    SEND,
    SWAP_AND_SEND,
    BURN_PROJECT_TOKEN,
    ADD_LIQUIDITY,
    FUND_AIRDROP,
    FUND_RAFFLE,
    FUND_TREASURY,
    FUND_PROJECT_SINK,
    SWAP_AND_FUND_TREASURY,
    SWAP_AND_FUND_AIRDROP,
    SWAP_AND_FUND_RAFFLE,
    NORMALIZE_TO_ROUTE
}

struct RouterAction {
    RouterActionType actionType;
    uint16 allocationBps;
    address recipient;
    address adapter;
    address priceGuard;
    bytes actionConfig;
}

struct RouterRouteInput {
    address inputAsset;
    RouterAction[] actions;
}

struct RouterSwapConfig {
    address outputAsset;
    uint128 maxAmountInPerCall;
    bytes routeData;
    bytes32[] approvalProof;
}

struct RouterSwapAndFundConfig {
    address outputAsset;
    uint128 maxAmountInPerCall;
    bytes routeData;
    bytes32[] approvalProof;
    bytes fundingConfig;
}
