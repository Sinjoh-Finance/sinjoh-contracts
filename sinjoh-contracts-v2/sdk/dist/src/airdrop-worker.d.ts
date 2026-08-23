import { type Address, type Hex } from "viem";
import type { AirdropLeafArtifact, AirdropProofArtifact, AirdropSnapshotArtifact, BuiltAirdropEpoch } from "./airdrop.js";
export interface OrderedChainEvent {
    blockNumber: bigint;
    transactionIndex: number;
    logIndex: number;
    removed?: boolean;
}
export interface HolderTransferEvent extends OrderedChainEvent {
    from: Address;
    to: Address;
    value: bigint;
}
export type StakingPositionEvent = (OrderedChainEvent & {
    eventName: "PositionCreated";
    tokenId: bigint;
    owner: Address;
    amount: bigint;
}) | (OrderedChainEvent & {
    eventName: "PositionTransferred";
    tokenId: bigint;
    from: Address;
    to: Address;
    amount: bigint;
}) | (OrderedChainEvent & {
    eventName: "PositionRedeemed";
    tokenId: bigint;
    owner: Address;
    amount: bigint;
});
export interface AirdropPushBatch {
    indices: readonly number[];
    leaves: readonly AirdropLeafArtifact[];
    proofs: readonly AirdropProofArtifact[];
}
export interface AirdropKeeperCall {
    kind: "push" | "retry-credit" | "finalize";
    to: Address;
    value: 0n;
    data: Hex;
}
/** Reconstructs holder balances from the complete ordered ERC-20 Transfer history. */
export declare function reconstructHolderAirdropSnapshot(parameters: {
    snapshotBlock: bigint;
    snapshotBlockHash: Hex;
    snapshotTime: bigint;
    totalSupply: bigint;
    totalEligibleWeight: bigint;
    transfers: readonly HolderTransferEvent[];
    exclusions: readonly Address[];
}): AirdropSnapshotArtifact;
/** Reconstructs aggregate active stake by replaying the staking pool's canonical position events. */
export declare function reconstructStakerAirdropSnapshot(parameters: {
    snapshotBlock: bigint;
    snapshotBlockHash: Hex;
    snapshotTime: bigint;
    totalStakedSupply: bigint;
    totalEligibleWeight: bigint;
    events: readonly StakingPositionEvent[];
    exclusions: readonly Address[];
}): AirdropSnapshotArtifact;
/** Builds bounded permissionless push calls while retaining zero-entitlement leaves for settlement. */
export declare function planAirdropPushBatches(parameters: {
    epoch: BuiltAirdropEpoch;
    processedHolders?: readonly Address[];
    maxPushBatchSize: number;
}): readonly AirdropPushBatch[];
/** Encodes permissionless push transactions in the same bounded order as the published artifact. */
export declare function encodeAirdropPushCalls(parameters: {
    airdrop: Address;
    accountId: Hex;
    epochId: bigint;
    batches: readonly AirdropPushBatch[];
}): readonly AirdropKeeperCall[];
/** Encodes a permissionless retry whose recipient and asset cannot be redirected by the caller. */
export declare function encodeAirdropRetryCreditCall(parameters: {
    airdrop: Address;
    recipient: Address;
    asset: Address;
    maxAmount: bigint;
}): AirdropKeeperCall;
/** Encodes finalization after on-chain status confirms every committed leaf is settled. */
export declare function encodeAirdropFinalizeCall(parameters: {
    airdrop: Address;
    accountId: Hex;
    epochId: bigint;
}): AirdropKeeperCall;
//# sourceMappingURL=airdrop-worker.d.ts.map