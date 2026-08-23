import { type Address, type Hex } from "viem";
export interface AirdropWeight {
    holder: Address;
    weight: bigint;
}
export interface AirdropSnapshotArtifact {
    snapshotBlock: bigint;
    snapshotBlockHash: Hex;
    snapshotTime: bigint;
    totalEligibleWeight: bigint;
    weights: readonly AirdropWeight[];
}
export interface AirdropLeafArtifact extends AirdropWeight {
    amount: bigint;
}
export interface AirdropProofNodeArtifact {
    siblingHash: Hex;
    siblingWeightSum: bigint;
    siblingAmountSum: bigint;
    siblingLeafCount: number;
    siblingOnLeft: boolean;
}
export interface AirdropProofArtifact {
    nodes: readonly AirdropProofNodeArtifact[];
}
export interface AirdropEpochCommitmentArtifact {
    accountId: Hex;
    epochId: bigint;
    snapshotBlock: bigint;
    snapshotBlockHash: Hex;
    snapshotTime: bigint;
    rootHash: Hex;
    rootSum: bigint;
    epochAmount: bigint;
    totalEligibleWeight: bigint;
    leafCount: number;
    artifactHash: Hex;
}
export interface BuiltAirdropEpoch {
    commitment: AirdropEpochCommitmentArtifact;
    leaves: readonly AirdropLeafArtifact[];
    proofs: readonly AirdropProofArtifact[];
}
/**
 * Requires two independently acquired provider snapshots to identify the same canonical epoch.
 * The returned weights are normalized and sorted so downstream signing cannot depend on RPC order.
 */
export declare function reconcileAirdropSnapshots(parameters: {
    primary: AirdropSnapshotArtifact;
    secondary: AirdropSnapshotArtifact;
    exclusions?: readonly Address[];
}): AirdropSnapshotArtifact;
/** Recommended attestor entrypoint: reconcile two RPC snapshots before building a signable epoch. */
export declare function buildVerifiedAirdropEpoch(parameters: {
    chainId: bigint;
    airdrop: Address;
    accountId: Hex;
    epochId: bigint;
    epochAmount: bigint;
    primarySnapshot: AirdropSnapshotArtifact;
    secondarySnapshot: AirdropSnapshotArtifact;
    exclusions?: readonly Address[];
}): BuiltAirdropEpoch;
/**
 * Builds the complete deterministic Merkle-sum artifact consumed by `ProjectAirdropV2`.
 * Positive-weight holders are address-sorted; zero-entitlement leaves are retained.
 */
export declare function buildAirdropEpoch(parameters: {
    chainId: bigint;
    airdrop: Address;
    accountId: Hex;
    epochId: bigint;
    snapshotBlock: bigint;
    snapshotBlockHash: Hex;
    snapshotTime: bigint;
    epochAmount: bigint;
    weights: readonly AirdropWeight[];
    exclusions?: readonly Address[];
    expectedTotalEligibleWeight?: bigint;
}): BuiltAirdropEpoch;
/** EIP-712 payload for the immutable Airdrop attestor key. */
export declare function airdropCommitmentTypedData(chainId: number, airdrop: Address, commitment: AirdropEpochCommitmentArtifact): {
    readonly domain: {
        readonly name: "Sinjoh Project Airdrop";
        readonly version: "2";
        readonly chainId: number;
        readonly verifyingContract: `0x${string}`;
    };
    readonly primaryType: "AirdropEpochCommitment";
    readonly types: {
        readonly AirdropEpochCommitment: readonly [{
            readonly name: "accountId";
            readonly type: "bytes32";
        }, {
            readonly name: "epochId";
            readonly type: "uint64";
        }, {
            readonly name: "snapshotBlock";
            readonly type: "uint64";
        }, {
            readonly name: "snapshotBlockHash";
            readonly type: "bytes32";
        }, {
            readonly name: "snapshotTime";
            readonly type: "uint48";
        }, {
            readonly name: "rootHash";
            readonly type: "bytes32";
        }, {
            readonly name: "rootSum";
            readonly type: "uint256";
        }, {
            readonly name: "epochAmount";
            readonly type: "uint256";
        }, {
            readonly name: "totalEligibleWeight";
            readonly type: "uint256";
        }, {
            readonly name: "leafCount";
            readonly type: "uint32";
        }, {
            readonly name: "artifactHash";
            readonly type: "bytes32";
        }];
    };
    readonly message: AirdropEpochCommitmentArtifact;
};
//# sourceMappingURL=airdrop.d.ts.map