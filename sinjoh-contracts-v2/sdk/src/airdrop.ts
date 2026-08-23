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

const LEAF_DOMAIN = keccak256(toBytes("SINJOH_V2_AIRDROP_LEAF"));
const NODE_DOMAIN = keccak256(toBytes("SINJOH_V2_AIRDROP_NODE"));
const MAX_UINT32 = 2n ** 32n - 1n;
const MAX_UINT48 = 2n ** 48n - 1n;
const MAX_UINT64 = 2n ** 64n - 1n;
const MAX_UINT256 = 2n ** 256n - 1n;

const leafParameters = parseAbiParameters(
  "bytes32,uint256,address,bytes32,uint64,uint64,uint48,address,uint256,uint256",
);
const nodeParameters = parseAbiParameters(
  "bytes32,bytes32,uint256,uint256,uint32,bytes32,uint256,uint256,uint32",
);

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

interface TreeNode {
  hash: Hex;
  weightSum: bigint;
  amountSum: bigint;
  leafCount: number;
  members: number[];
}

/**
 * Requires two independently acquired provider snapshots to identify the same canonical epoch.
 * The returned weights are normalized and sorted so downstream signing cannot depend on RPC order.
 */
export function reconcileAirdropSnapshots(parameters: {
  primary: AirdropSnapshotArtifact;
  secondary: AirdropSnapshotArtifact;
  exclusions?: readonly Address[];
}): AirdropSnapshotArtifact {
  const { primary, secondary } = parameters;
  assertBytes32(primary.snapshotBlockHash, "Primary snapshot block hash");
  assertBytes32(secondary.snapshotBlockHash, "Secondary snapshot block hash");
  assertUnsigned(primary.snapshotBlock, 64n, "Primary snapshot block");
  assertUnsigned(secondary.snapshotBlock, 64n, "Secondary snapshot block");
  assertUnsigned(primary.snapshotTime, 48n, "Primary snapshot time");
  assertUnsigned(secondary.snapshotTime, 48n, "Secondary snapshot time");
  if (
    primary.snapshotBlock !== secondary.snapshotBlock
      || primary.snapshotBlockHash.toLowerCase() !== secondary.snapshotBlockHash.toLowerCase()
      || primary.snapshotTime !== secondary.snapshotTime
  ) {
    throw new RangeError("RPC providers disagree on the Airdrop snapshot; do not sign this epoch");
  }

  const primaryWeights = canonicalWeights(primary.weights, parameters.exclusions);
  const secondaryWeights = canonicalWeights(secondary.weights, parameters.exclusions);
  const primaryTotal = primaryWeights.reduce((total, entry) => total + entry.weight, 0n);
  const secondaryTotal = secondaryWeights.reduce((total, entry) => total + entry.weight, 0n);
  if (
    primary.totalEligibleWeight !== primaryTotal
      || secondary.totalEligibleWeight !== secondaryTotal
  ) {
    throw new RangeError("Airdrop snapshot weights do not match the on-chain eligible supply");
  }
  if (
    primaryTotal !== secondaryTotal
      || primaryWeights.length !== secondaryWeights.length
      || primaryWeights.some((entry, index) => {
        const other = secondaryWeights[index];
        return other === undefined || entry.holder !== other.holder || entry.weight !== other.weight;
      })
  ) {
    throw new RangeError("RPC providers disagree on eligible Airdrop holders; do not sign this epoch");
  }

  return {
    snapshotBlock: primary.snapshotBlock,
    snapshotBlockHash: primary.snapshotBlockHash,
    snapshotTime: primary.snapshotTime,
    totalEligibleWeight: primaryTotal,
    weights: primaryWeights,
  };
}

/** Recommended attestor entrypoint: reconcile two RPC snapshots before building a signable epoch. */
export function buildVerifiedAirdropEpoch(parameters: {
  chainId: bigint;
  airdrop: Address;
  accountId: Hex;
  epochId: bigint;
  epochAmount: bigint;
  primarySnapshot: AirdropSnapshotArtifact;
  secondarySnapshot: AirdropSnapshotArtifact;
  exclusions?: readonly Address[];
}): BuiltAirdropEpoch {
  const snapshot = reconcileAirdropSnapshots({
    primary: parameters.primarySnapshot,
    secondary: parameters.secondarySnapshot,
    ...(parameters.exclusions === undefined ? {} : { exclusions: parameters.exclusions }),
  });
  return buildAirdropEpoch({
    chainId: parameters.chainId,
    airdrop: parameters.airdrop,
    accountId: parameters.accountId,
    epochId: parameters.epochId,
    snapshotBlock: snapshot.snapshotBlock,
    snapshotBlockHash: snapshot.snapshotBlockHash,
    snapshotTime: snapshot.snapshotTime,
    epochAmount: parameters.epochAmount,
    weights: snapshot.weights,
    ...(parameters.exclusions === undefined ? {} : { exclusions: parameters.exclusions }),
    expectedTotalEligibleWeight: snapshot.totalEligibleWeight,
  });
}

/**
 * Builds the complete deterministic Merkle-sum artifact consumed by `ProjectAirdropV2`.
 * Positive-weight holders are address-sorted; zero-entitlement leaves are retained.
 */
export function buildAirdropEpoch(parameters: {
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
}): BuiltAirdropEpoch {
  assertAddress(parameters.airdrop, "Airdrop contract");
  assertBytes32(parameters.accountId, "Account ID");
  assertBytes32(parameters.snapshotBlockHash, "Snapshot block hash");
  assertUnsigned(parameters.chainId, 256n, "Chain ID");
  assertUnsigned(parameters.epochId, 64n, "Epoch ID");
  assertUnsigned(parameters.snapshotBlock, 64n, "Snapshot block");
  assertUnsigned(parameters.snapshotTime, 48n, "Snapshot time");
  if (parameters.epochAmount <= 0n || parameters.epochAmount > MAX_UINT256) {
    throw new RangeError("Epoch amount must fit uint256 and be greater than zero");
  }
  if (parameters.weights.length === 0 || BigInt(parameters.weights.length) > MAX_UINT32) {
    throw new RangeError("Airdrop artifact must contain at least one holder");
  }

  const weights = canonicalWeights(parameters.weights, parameters.exclusions);

  const totalEligibleWeight = weights.reduce((total, entry) => total + entry.weight, 0n);
  if (totalEligibleWeight > MAX_UINT256) {
    throw new RangeError("Total eligible Airdrop weight exceeds uint256");
  }
  if (
    parameters.expectedTotalEligibleWeight !== undefined
      && totalEligibleWeight !== parameters.expectedTotalEligibleWeight
  ) {
    throw new RangeError("Holder weights do not match the on-chain eligible supply");
  }
  const leaves = weights.map(({ holder, weight }) => ({
    holder,
    weight,
    amount: parameters.epochAmount * weight / totalEligibleWeight,
  }));
  const proofs: AirdropProofNodeArtifact[][] = leaves.map(() => []);
  let level: TreeNode[] = leaves.map((leaf, index) => ({
    hash: airdropLeafHash({ ...parameters, leaf }),
    weightSum: leaf.weight,
    amountSum: leaf.amount,
    leafCount: 1,
    members: [index],
  }));

  while (level.length > 1) {
    const next: TreeNode[] = [];
    for (let index = 0; index < level.length; index += 2) {
      const left = level[index];
      if (left === undefined) throw new Error("Invalid Airdrop tree state");
      const right = level[index + 1];
      if (right === undefined) {
        next.push(left);
        continue;
      }
      for (const member of left.members) proofs[member]?.push(proofNode(right, false));
      for (const member of right.members) proofs[member]?.push(proofNode(left, true));
      next.push({
        hash: airdropNodeHash(left, right),
        weightSum: left.weightSum + right.weightSum,
        amountSum: left.amountSum + right.amountSum,
        leafCount: left.leafCount + right.leafCount,
        members: [...left.members, ...right.members],
      });
    }
    level = next;
  }

  const root = level[0];
  if (root === undefined || root.amountSum === 0n) {
    throw new RangeError("Epoch amount is too small to produce a nonzero entitlement");
  }
  const artifactMaterial = {
    version: "sinjoh-airdrop-artifact-v2",
    chainId: parameters.chainId.toString(),
    airdrop: getAddress(parameters.airdrop),
    accountId: parameters.accountId.toLowerCase(),
    epochId: parameters.epochId.toString(),
    snapshotBlock: parameters.snapshotBlock.toString(),
    snapshotBlockHash: parameters.snapshotBlockHash.toLowerCase(),
    snapshotTime: parameters.snapshotTime.toString(),
    epochAmount: parameters.epochAmount.toString(),
    totalEligibleWeight: totalEligibleWeight.toString(),
    rootHash: root.hash,
    rootSum: root.amountSum.toString(),
    leaves: leaves.map((leaf) => ({
      holder: leaf.holder,
      weight: leaf.weight.toString(),
      amount: leaf.amount.toString(),
    })),
  };
  const artifactHash = keccak256(toBytes(JSON.stringify(artifactMaterial)));
  return {
    commitment: {
      accountId: parameters.accountId,
      epochId: parameters.epochId,
      snapshotBlock: parameters.snapshotBlock,
      snapshotBlockHash: parameters.snapshotBlockHash,
      snapshotTime: parameters.snapshotTime,
      rootHash: root.hash,
      rootSum: root.amountSum,
      epochAmount: parameters.epochAmount,
      totalEligibleWeight,
      leafCount: leaves.length,
      artifactHash,
    },
    leaves,
    proofs: proofs.map((nodes) => ({ nodes })),
  };
}

function canonicalWeights(
  supplied: readonly AirdropWeight[],
  suppliedExclusions?: readonly Address[],
): AirdropWeight[] {
  if (supplied.length === 0 || BigInt(supplied.length) > MAX_UINT32) {
    throw new RangeError("Airdrop artifact must contain at least one holder");
  }
  const exclusions = new Set(
    (suppliedExclusions ?? []).map((address) => {
      assertAddress(address, "Excluded holder");
      return address.toLowerCase();
    }),
  );
  const seen = new Set<string>();
  return supplied.map(({ holder, weight }) => {
    assertAddress(holder, "Holder");
    if (weight <= 0n || weight > MAX_UINT256) {
      throw new RangeError("Every Airdrop holder weight must fit uint256 and be positive");
    }
    const normalized = holder.toLowerCase();
    if (exclusions.has(normalized)) throw new RangeError(`Excluded holder ${holder} cannot receive`);
    if (seen.has(normalized)) throw new RangeError(`Duplicate Airdrop holder ${holder}`);
    seen.add(normalized);
    return { holder: getAddress(holder), weight };
  }).sort((left, right) => {
    const a = BigInt(left.holder);
    const b = BigInt(right.holder);
    return a < b ? -1 : a > b ? 1 : 0;
  });
}

/** EIP-712 payload for the immutable Airdrop attestor key. */
export function airdropCommitmentTypedData(
  chainId: number,
  airdrop: Address,
  commitment: AirdropEpochCommitmentArtifact,
) {
  return {
    domain: {
      name: "Sinjoh Project Airdrop",
      version: "2",
      chainId,
      verifyingContract: airdrop,
    },
    primaryType: "AirdropEpochCommitment" as const,
    types: {
      AirdropEpochCommitment: [
        { name: "accountId", type: "bytes32" },
        { name: "epochId", type: "uint64" },
        { name: "snapshotBlock", type: "uint64" },
        { name: "snapshotBlockHash", type: "bytes32" },
        { name: "snapshotTime", type: "uint48" },
        { name: "rootHash", type: "bytes32" },
        { name: "rootSum", type: "uint256" },
        { name: "epochAmount", type: "uint256" },
        { name: "totalEligibleWeight", type: "uint256" },
        { name: "leafCount", type: "uint32" },
        { name: "artifactHash", type: "bytes32" },
      ],
    },
    message: { ...commitment, snapshotTime: Number(commitment.snapshotTime) },
  } as const;
}

function airdropLeafHash(parameters: {
  chainId: bigint;
  airdrop: Address;
  accountId: Hex;
  epochId: bigint;
  snapshotBlock: bigint;
  snapshotTime: bigint;
  leaf: AirdropLeafArtifact;
}): Hex {
  const inner = keccak256(encodeAbiParameters(leafParameters, [
    LEAF_DOMAIN,
    parameters.chainId,
    parameters.airdrop,
    parameters.accountId,
    parameters.epochId,
    parameters.snapshotBlock,
    Number(parameters.snapshotTime),
    parameters.leaf.holder,
    parameters.leaf.weight,
    parameters.leaf.amount,
  ]));
  return keccak256(inner);
}

function airdropNodeHash(left: TreeNode, right: TreeNode): Hex {
  return keccak256(encodeAbiParameters(nodeParameters, [
    NODE_DOMAIN,
    left.hash,
    left.weightSum,
    left.amountSum,
    left.leafCount,
    right.hash,
    right.weightSum,
    right.amountSum,
    right.leafCount,
  ]));
}

function proofNode(node: TreeNode, siblingOnLeft: boolean): AirdropProofNodeArtifact {
  return {
    siblingHash: node.hash,
    siblingWeightSum: node.weightSum,
    siblingAmountSum: node.amountSum,
    siblingLeafCount: node.leafCount,
    siblingOnLeft,
  };
}

function assertAddress(value: Address, label: string): void {
  if (!isAddress(value)) throw new RangeError(`${label} must be a valid address`);
}

function assertBytes32(value: Hex, label: string): void {
  if (!/^0x[0-9a-fA-F]{64}$/.test(value)) throw new RangeError(`${label} must be exactly 32 bytes`);
}

function assertUnsigned(value: bigint, bits: bigint, label: string): void {
  const maximum = bits === 256n
    ? MAX_UINT256
    : bits === 64n
      ? MAX_UINT64
      : bits === 48n
        ? MAX_UINT48
        : 2n ** bits - 1n;
  if (value < 0n || value > maximum) throw new RangeError(`${label} exceeds uint${bits}`);
}
