import { type Address, type Hex } from "viem";
import type { HolderTransferEvent } from "./airdrop-worker.js";
import { type BuiltRaffleRound, type RaffleSnapshotArtifact } from "./raffle.js";
export interface RaffleKeeperCall {
    kind: "commit" | "claim" | "retry" | "retry-stock" | "claim-owed" | "claim-stock-owed" | "expire" | "abandon";
    to: Address;
    value: 0n;
    data: Hex;
}
/** Replays complete ERC-20 history and computes snapshot or window-minimum holder weights. */
export declare function reconstructRaffleSnapshot(parameters: {
    snapshotBlock: bigint;
    snapshotBlockHash: Hex;
    totalSupply: bigint;
    basis: "snapshot" | "min-balance";
    weightWindowBlocks: bigint;
    transfers: readonly HolderTransferEvent[];
    exclusions: readonly Address[];
}): RaffleSnapshotArtifact;
/** Encodes the only attestor transaction after two-provider artifact reconciliation. */
export declare function encodeRaffleCommitCall(parameters: {
    round: BuiltRaffleRound;
}): RaffleKeeperCall;
/** Locates every winning ticket interval and encodes permissionless direct/stock claim attempts. */
export declare function encodeRaffleClaimCalls(parameters: {
    round: BuiltRaffleRound;
    seed: bigint;
    slotsPaidMask?: number;
}): readonly RaffleKeeperCall[];
export declare function encodeRaffleRetryCall(parameters: {
    raffle: Address;
    holder: Address;
    stockAsset?: Address;
}): RaffleKeeperCall;
/** Encodes the winner's own redirect of a deferred direct or stock prize. */
export declare function encodeRaffleClaimOwedToCall(parameters: {
    raffle: Address;
    payoutRecipient: Address;
    stockAsset?: Address;
}): RaffleKeeperCall;
export declare function encodeRaffleCloseCall(parameters: {
    raffle: Address;
    roundId: bigint;
    mode: "expire" | "abandon";
}): RaffleKeeperCall;
//# sourceMappingURL=raffle-worker.d.ts.map