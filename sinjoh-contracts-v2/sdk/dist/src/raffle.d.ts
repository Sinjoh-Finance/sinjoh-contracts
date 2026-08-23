import { type Address, type Hex } from "viem";
export interface RaffleWeight {
    holder: Address;
    weight: bigint;
}
export interface RaffleSnapshotArtifact {
    snapshotBlock: bigint;
    snapshotBlockHash: Hex;
    basis: "snapshot" | "min-balance";
    weightWindowBlocks: bigint;
    totalSupply: bigint;
    weights: readonly RaffleWeight[];
}
export interface RaffleLeafArtifact extends RaffleWeight {
    tickets: bigint;
    offset: bigint;
    leafHash: Hex;
}
export interface RaffleProofElementArtifact {
    siblingHash: Hex;
    siblingSum: bigint;
    siblingIsLeft: boolean;
}
export interface BuiltRaffleRound {
    chainId: bigint;
    raffle: Address;
    winnersPerRound: number;
    commitment: {
        roundId: bigint;
        snapshotBlock: bigint;
        snapshotBlockHash: Hex;
        rootHash: Hex;
        totalTickets: bigint;
        artifactHash: Hex;
    };
    emptyLeafHash: Hex;
    leaves: readonly RaffleLeafArtifact[];
    proofs: readonly (readonly RaffleProofElementArtifact[])[];
}
/** Reconciles two independently acquired snapshots before an attestor builds a round. */
export declare function reconcileRaffleSnapshots(parameters: {
    primary: RaffleSnapshotArtifact;
    secondary: RaffleSnapshotArtifact;
    exclusions?: readonly Address[];
}): RaffleSnapshotArtifact;
/** Recommended attestor path: reconcile two providers, then build the deterministic sum tree. */
export declare function buildVerifiedRaffleRound(parameters: {
    chainId: bigint;
    raffle: Address;
    roundId: bigint;
    tokensPerTicket: bigint;
    maxTicketsPerHolder: bigint;
    winnersPerRound: number;
    primarySnapshot: RaffleSnapshotArtifact;
    secondarySnapshot: RaffleSnapshotArtifact;
    exclusions?: readonly Address[];
}): BuiltRaffleRound;
/** Builds the padded, direction-aware ticket-interval Merkle-sum artifact. */
export declare function buildRaffleRound(parameters: {
    chainId: bigint;
    raffle: Address;
    roundId: bigint;
    snapshotBlock: bigint;
    snapshotBlockHash: Hex;
    basis: "snapshot" | "min-balance";
    weightWindowBlocks: bigint;
    tokensPerTicket: bigint;
    maxTicketsPerHolder: bigint;
    winnersPerRound: number;
    weights: readonly RaffleWeight[];
    exclusions?: readonly Address[];
}): BuiltRaffleRound;
export declare function raffleWinningIndex(parameters: {
    chainId: bigint;
    raffle: Address;
    roundId: bigint;
    slot: number;
    seed: bigint;
    totalTickets: bigint;
}): bigint;
//# sourceMappingURL=raffle.d.ts.map