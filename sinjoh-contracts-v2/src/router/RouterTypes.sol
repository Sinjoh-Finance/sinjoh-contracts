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
    FUND_PROJECT_SINK
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
    bytes routeData;
    bytes32[] approvalProof;
}
