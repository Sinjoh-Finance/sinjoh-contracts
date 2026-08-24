import {
  encodeAbiParameters,
  getAddress,
  isAddress,
  keccak256,
  parseAbiParameters,
  toBytes,
  type Address,
  type Hex,
} from "viem";

const LEAF_DOMAIN = keccak256(toBytes("SINJOH_RAFFLE_LEAF_V1"));
const NODE_DOMAIN = keccak256(toBytes("SINJOH_RAFFLE_NODE_V1"));
const EMPTY_DOMAIN = keccak256(toBytes("SINJOH_RAFFLE_EMPTY_V1"));
const SLOT_DOMAIN = keccak256(toBytes("SINJOH_RAFFLE_SLOT_V1"));
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
const BURN_ADDRESS = "0x000000000000000000000000000000000000dead";
const MAX_UINT64 = 2n ** 64n - 1n;
const MAX_UINT256 = 2n ** 256n - 1n;
const leafParameters = parseAbiParameters("bytes32,uint256,address,uint64,uint64,address,uint256");
const nodeParameters = parseAbiParameters("bytes32,bytes32,uint256,bytes32,uint256");
const emptyParameters = parseAbiParameters("bytes32,uint64");
const slotParameters = parseAbiParameters("bytes32,uint256,address,uint64,uint8,uint256");

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

interface TreeNode {
  hash: Hex;
  sum: bigint;
  members: number[];
}

/** Reconciles two independently acquired snapshots before an attestor builds a round. */
export function reconcileRaffleSnapshots(parameters: {
  primary: RaffleSnapshotArtifact;
  secondary: RaffleSnapshotArtifact;
  exclusions?: readonly Address[];
}): RaffleSnapshotArtifact {
  const { primary, secondary } = parameters;
  assertBytes32(primary.snapshotBlockHash, "Primary snapshot block hash");
  assertBytes32(secondary.snapshotBlockHash, "Secondary snapshot block hash");
  if (
    primary.snapshotBlock !== secondary.snapshotBlock
      || primary.snapshotBlockHash.toLowerCase() !== secondary.snapshotBlockHash.toLowerCase()
      || primary.basis !== secondary.basis
      || primary.weightWindowBlocks !== secondary.weightWindowBlocks
      || primary.totalSupply !== secondary.totalSupply
  ) throw new RangeError("RPC providers disagree on the Raffle snapshot; do not commit this round");
  const primaryWeights = canonicalWeights(primary.weights, parameters.exclusions);
  const secondaryWeights = canonicalWeights(secondary.weights, parameters.exclusions);
  if (
    primaryWeights.length !== secondaryWeights.length
      || primaryWeights.some((entry, index) => {
        const other = secondaryWeights[index];
        return other === undefined || entry.holder !== other.holder || entry.weight !== other.weight;
      })
  ) throw new RangeError("RPC providers disagree on Raffle holder weights; do not commit this round");
  return { ...primary, weights: primaryWeights };
}

/** Recommended attestor path: reconcile two providers, then build the deterministic sum tree. */
export function buildVerifiedRaffleRound(parameters: {
  chainId: bigint;
  raffle: Address;
  roundId: bigint;
  tokensPerTicket: bigint;
  maxTicketsPerHolder: bigint;
  winnersPerRound: number;
  primarySnapshot: RaffleSnapshotArtifact;
  secondarySnapshot: RaffleSnapshotArtifact;
  exclusions?: readonly Address[];
}): BuiltRaffleRound {
  const snapshot = reconcileRaffleSnapshots({
    primary: parameters.primarySnapshot,
    secondary: parameters.secondarySnapshot,
    ...(parameters.exclusions === undefined ? {} : { exclusions: parameters.exclusions }),
  });
  return buildRaffleRound({
    ...parameters,
    snapshotBlock: snapshot.snapshotBlock,
    snapshotBlockHash: snapshot.snapshotBlockHash,
    basis: snapshot.basis,
    weightWindowBlocks: snapshot.weightWindowBlocks,
    weights: snapshot.weights,
  });
}

/** Builds the padded, direction-aware ticket-interval Merkle-sum artifact. */
export function buildRaffleRound(parameters: {
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
}): BuiltRaffleRound {
  assertAddress(parameters.raffle, "Raffle contract");
  assertBytes32(parameters.snapshotBlockHash, "Snapshot block hash");
  assertUnsigned(parameters.chainId, MAX_UINT256, "Chain ID");
  assertUnsigned(parameters.roundId, MAX_UINT64, "Round ID");
  assertUnsigned(parameters.snapshotBlock, MAX_UINT64, "Snapshot block");
  if (parameters.roundId === 0n) throw new RangeError("Round ID must be greater than zero");
  if (parameters.tokensPerTicket <= 0n) throw new RangeError("Tokens per ticket must be positive");
  if (parameters.maxTicketsPerHolder < 0n) throw new RangeError("Ticket cap cannot be negative");
  if (!Number.isInteger(parameters.winnersPerRound) || parameters.winnersPerRound < 1 || parameters.winnersPerRound > 16) {
    throw new RangeError("Winner count must be between 1 and 16");
  }
  if (
    (parameters.basis === "snapshot" && parameters.weightWindowBlocks !== 0n)
      || (parameters.basis === "min-balance" && parameters.weightWindowBlocks <= 0n)
  ) throw new RangeError("Raffle weight window does not match the selected basis");

  const weighted = canonicalWeights(parameters.weights, parameters.exclusions);
  let offset = 0n;
  const leaves: RaffleLeafArtifact[] = [];
  for (const entry of weighted) {
    let tickets = entry.weight / parameters.tokensPerTicket;
    if (parameters.maxTicketsPerHolder !== 0n && tickets > parameters.maxTicketsPerHolder) {
      tickets = parameters.maxTicketsPerHolder;
    }
    if (tickets === 0n) continue;
    if (offset + tickets > MAX_UINT256) throw new RangeError("Total Raffle tickets exceed uint256");
    const leafHash = raffleLeafHash({ ...parameters, holder: entry.holder, tickets });
    leaves.push({ ...entry, tickets, offset, leafHash });
    offset += tickets;
  }
  if (leaves.length === 0) throw new RangeError("No eligible Raffle tickets; skip this round");

  let width = 1;
  while (width < leaves.length) width *= 2;
  const emptyLeafHash = raffleEmptyLeafHash(parameters.roundId);
  const proofs: RaffleProofElementArtifact[][] = leaves.map(() => []);
  let level: TreeNode[] = Array.from({ length: width }, (_, index) => {
    const leaf = leaves[index];
    return leaf === undefined
      ? { hash: emptyLeafHash, sum: 0n, members: [] }
      : { hash: leaf.leafHash, sum: leaf.tickets, members: [index] };
  });
  while (level.length > 1) {
    const next: TreeNode[] = [];
    for (let index = 0; index < level.length; index += 2) {
      const left = level[index];
      const right = level[index + 1];
      if (left === undefined || right === undefined) throw new Error("Invalid Raffle tree state");
      for (const member of left.members) proofs[member]?.push({
        siblingHash: right.hash, siblingSum: right.sum, siblingIsLeft: false,
      });
      for (const member of right.members) proofs[member]?.push({
        siblingHash: left.hash, siblingSum: left.sum, siblingIsLeft: true,
      });
      next.push({
        hash: raffleNodeHash(left.hash, left.sum, right.hash, right.sum),
        sum: left.sum + right.sum,
        members: [...left.members, ...right.members],
      });
    }
    level = next;
  }
  const root = level[0];
  if (root === undefined || root.sum !== offset) throw new Error("Invalid Raffle root sum");
  const artifactHash = keccak256(toBytes(JSON.stringify({
    version: "sinjoh-raffle-artifact-v1",
    chainId: parameters.chainId.toString(),
    raffle: getAddress(parameters.raffle),
    roundId: parameters.roundId.toString(),
    snapshotBlock: parameters.snapshotBlock.toString(),
    snapshotBlockHash: parameters.snapshotBlockHash.toLowerCase(),
    basis: parameters.basis,
    weightWindowBlocks: parameters.weightWindowBlocks.toString(),
    tokensPerTicket: parameters.tokensPerTicket.toString(),
    maxTicketsPerHolder: parameters.maxTicketsPerHolder.toString(),
    winnersPerRound: parameters.winnersPerRound,
    rootHash: root.hash,
    totalTickets: root.sum.toString(),
    leaves: leaves.map((leaf) => ({
      holder: leaf.holder, weight: leaf.weight.toString(), tickets: leaf.tickets.toString(), offset: leaf.offset.toString(),
    })),
  })));
  return {
    chainId: parameters.chainId,
    raffle: getAddress(parameters.raffle),
    winnersPerRound: parameters.winnersPerRound,
    commitment: {
      roundId: parameters.roundId,
      snapshotBlock: parameters.snapshotBlock,
      snapshotBlockHash: parameters.snapshotBlockHash,
      rootHash: root.hash,
      totalTickets: root.sum,
      artifactHash,
    },
    emptyLeafHash,
    leaves,
    proofs,
  };
}

export function raffleWinningIndex(parameters: {
  chainId: bigint;
  raffle: Address;
  roundId: bigint;
  slot: number;
  seed: bigint;
  totalTickets: bigint;
}): bigint {
  assertAddress(parameters.raffle, "Raffle contract");
  if (!Number.isInteger(parameters.slot) || parameters.slot < 0 || parameters.slot > 15) {
    throw new RangeError("Raffle slot must be between 0 and 15");
  }
  if (parameters.seed <= 0n || parameters.totalTickets <= 0n) {
    throw new RangeError("Raffle seed and total tickets must be positive");
  }
  const digest = keccak256(encodeAbiParameters(slotParameters, [
    SLOT_DOMAIN,
    parameters.chainId,
    getAddress(parameters.raffle),
    parameters.roundId,
    parameters.slot,
    parameters.seed,
  ]));
  return BigInt(digest) % parameters.totalTickets;
}

function raffleLeafHash(parameters: {
  chainId: bigint;
  raffle: Address;
  roundId: bigint;
  snapshotBlock: bigint;
  holder: Address;
  tickets: bigint;
}): Hex {
  return keccak256(encodeAbiParameters(leafParameters, [
    LEAF_DOMAIN,
    parameters.chainId,
    getAddress(parameters.raffle),
    parameters.roundId,
    parameters.snapshotBlock,
    getAddress(parameters.holder),
    parameters.tickets,
  ]));
}

function raffleNodeHash(leftHash: Hex, leftSum: bigint, rightHash: Hex, rightSum: bigint): Hex {
  return keccak256(encodeAbiParameters(nodeParameters, [NODE_DOMAIN, leftHash, leftSum, rightHash, rightSum]));
}

function raffleEmptyLeafHash(roundId: bigint): Hex {
  return keccak256(encodeAbiParameters(emptyParameters, [EMPTY_DOMAIN, roundId]));
}

function canonicalWeights(weights: readonly RaffleWeight[], exclusions?: readonly Address[]): RaffleWeight[] {
  const excluded = new Set([ZERO_ADDRESS, BURN_ADDRESS]);
  for (const address of exclusions ?? []) {
    assertAddress(address, "Excluded holder");
    excluded.add(address.toLowerCase());
  }
  const seen = new Set<string>();
  return weights.map((entry) => {
    assertAddress(entry.holder, "Raffle holder");
    if (entry.weight < 0n || entry.weight > MAX_UINT256) throw new RangeError("Raffle weight must fit uint256");
    const holder = entry.holder.toLowerCase();
    if (excluded.has(holder)) throw new RangeError(`Excluded holder ${entry.holder} cannot receive tickets`);
    if (seen.has(holder)) throw new RangeError(`Duplicate Raffle holder ${entry.holder}`);
    seen.add(holder);
    return { holder: getAddress(entry.holder), weight: entry.weight };
  }).sort((left, right) => BigInt(left.holder) < BigInt(right.holder) ? -1 : 1);
}

function assertAddress(value: Address, label: string): void {
  if (!isAddress(value)) throw new RangeError(`${label} must be a valid address`);
}

function assertBytes32(value: Hex, label: string): void {
  if (!/^0x[0-9a-fA-F]{64}$/.test(value)) throw new RangeError(`${label} must be exactly 32 bytes`);
}

function assertUnsigned(value: bigint, maximum: bigint, label: string): void {
  if (value < 0n || value > maximum) throw new RangeError(`${label} is out of range`);
}
