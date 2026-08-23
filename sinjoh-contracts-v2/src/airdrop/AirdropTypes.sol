// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

enum AirdropEligibilityMode {
    HOLDERS,
    STAKERS
}

enum AirdropCadence {
    ON_DEMAND,
    DAILY,
    WEEKLY
}

enum AirdropDustDestination {
    TREASURY,
    NEXT_EPOCH,
    FUNDER
}

struct AirdropAccountConfig {
    uint16 maxPushBatchSize;
    uint16 minimumSnapshotConfirmations;
    AirdropCadence cadence;
    AirdropDustDestination dustDestination;
}

struct AirdropEpochCommitment {
    bytes32 accountId;
    uint64 epochId;
    uint64 snapshotBlock;
    bytes32 snapshotBlockHash;
    uint48 snapshotTime;
    bytes32 rootHash;
    uint256 rootSum;
    uint256 epochAmount;
    uint256 totalEligibleWeight;
    uint32 leafCount;
    bytes32 artifactHash;
}

struct AirdropLeaf {
    address holder;
    uint256 weight;
    uint256 amount;
}

struct AirdropProofNode {
    bytes32 siblingHash;
    uint256 siblingWeightSum;
    uint256 siblingAmountSum;
    uint32 siblingLeafCount;
    bool siblingOnLeft;
}

struct AirdropProof {
    AirdropProofNode[] nodes;
}
