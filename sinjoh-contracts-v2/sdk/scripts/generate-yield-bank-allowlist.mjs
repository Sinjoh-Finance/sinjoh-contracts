#!/usr/bin/env node

import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import {
  concatHex,
  encodeAbiParameters,
  getAddress,
  keccak256,
} from "viem";

const MINT_PARAMS = {
  type: "tuple",
  components: [
    { name: "mintPrice", type: "uint256" },
    { name: "maxTotalMintableByWallet", type: "uint256" },
    { name: "startTime", type: "uint256" },
    { name: "endTime", type: "uint256" },
    { name: "dropStageIndex", type: "uint256" },
    { name: "maxTokenSupplyForStage", type: "uint256" },
    { name: "feeBps", type: "uint256" },
    { name: "restrictFeeRecipients", type: "bool" },
  ],
};

function invariant(value, message) {
  if (!value) throw new Error(message);
}

function wholeTokens(balance) {
  return BigInt(String(balance).split(".")[0]);
}

function asBigInt(value, field) {
  invariant(value !== null && value !== undefined && value !== "", `${field} is required`);
  const parsed = BigInt(value);
  invariant(parsed >= 0n, `${field} must be nonnegative`);
  return parsed;
}

export function seaDropLeaf(address, mintParams) {
  return keccak256(
    encodeAbiParameters(
      [{ type: "address" }, MINT_PARAMS],
      [getAddress(address), mintParams],
    ),
  );
}

function hashPair(a, b) {
  return keccak256(a.toLowerCase() < b.toLowerCase() ? concatHex([a, b]) : concatHex([b, a]));
}

export function buildMerkleTree(inputLeaves) {
  invariant(inputLeaves.length > 0, "allowlist has no leaves");
  const leaves = [...inputLeaves].sort((a, b) => a.toLowerCase().localeCompare(b.toLowerCase()));
  const levels = [leaves];
  while (levels.at(-1).length > 1) {
    const previous = levels.at(-1);
    const next = [];
    for (let i = 0; i < previous.length; i += 2) {
      next.push(i + 1 === previous.length ? previous[i] : hashPair(previous[i], previous[i + 1]));
    }
    levels.push(next);
  }
  return { leaves, levels, root: levels.at(-1)[0] };
}

function proofFor(tree, leaf) {
  let index = tree.leaves.indexOf(leaf);
  invariant(index !== -1, "leaf missing from tree");
  const proof = [];
  for (let levelIndex = 0; levelIndex < tree.levels.length - 1; levelIndex += 1) {
    const level = tree.levels[levelIndex];
    const sibling = index % 2 === 0 ? index + 1 : index - 1;
    if (sibling < level.length) proof.push(level[sibling]);
    index = Math.floor(index / 2);
  }
  return proof;
}

export function verifyProof(leaf, proof, root) {
  return proof.reduce((hash, sibling) => hashPair(hash, sibling), leaf) === root;
}

export function buildAllowlist(snapshot, plan) {
  invariant(Array.isArray(snapshot.holders), "snapshot.holders must be an array");
  invariant(Array.isArray(plan.stages) && plan.stages.length > 0, "plan.stages is required");

  const stages = [];
  plan.stages.forEach((stage, index) => {
    const normalized = {
      name: String(stage.name),
      minimumBalance: asBigInt(stage.minimumBalance, `stages[${index}].minimumBalance`),
      mintPrice: asBigInt(stage.mintPrice, `stages[${index}].mintPrice`),
      maxTotalMintableByWallet: asBigInt(
        stage.maxTotalMintableByWallet,
        `stages[${index}].maxTotalMintableByWallet`,
      ),
      startTime: asBigInt(stage.startTime, `stages[${index}].startTime`),
      endTime: asBigInt(stage.endTime, `stages[${index}].endTime`),
      dropStageIndex: asBigInt(stage.dropStageIndex, `stages[${index}].dropStageIndex`),
      maxTokenSupplyForStage: asBigInt(
        stage.maxTokenSupplyForStage,
        `stages[${index}].maxTokenSupplyForStage`,
      ),
      feeBps: asBigInt(stage.feeBps, `stages[${index}].feeBps`),
      restrictFeeRecipients: stage.restrictFeeRecipients,
    };
    invariant(normalized.name.length > 0, `stages[${index}].name is required`);
    invariant(normalized.minimumBalance > 0n, `stages[${index}].minimumBalance must be positive`);
    invariant(normalized.mintPrice > 0n, `stages[${index}].mintPrice must be positive`);
    invariant(normalized.maxTotalMintableByWallet > 0n, `stages[${index}] wallet limit must be positive`);
    invariant(normalized.startTime < normalized.endTime, `stages[${index}] time range is invalid`);
    invariant(normalized.feeBps < 10_000n, `stages[${index}].feeBps must be below 10000`);
    invariant(normalized.dropStageIndex <= 255n, `stages[${index}].dropStageIndex is too large`);
    invariant(
      normalized.maxTokenSupplyForStage <= 4_294_967_295n,
      `stages[${index}].maxTokenSupplyForStage is too large`,
    );
    invariant(
      typeof normalized.restrictFeeRecipients === "boolean",
      `stages[${index}].restrictFeeRecipients must be boolean`,
    );
    if (index > 0) {
      invariant(
        normalized.minimumBalance < stages[index - 1].minimumBalance,
        "stage minimum balances must be strictly descending",
      );
      invariant(
        normalized.maxTokenSupplyForStage > stages[index - 1].maxTokenSupplyForStage,
        "stage supply boundaries must be strictly increasing",
      );
    }
    stages.push(normalized);
  });

  const entries = [];
  for (const holder of snapshot.holders) {
    if (holder.classification !== "Holder") continue;
    const balance = wholeTokens(holder.balance);
    for (const stage of stages) {
      if (balance < stage.minimumBalance) continue;
      const mintParams = {
        mintPrice: stage.mintPrice,
        maxTotalMintableByWallet: stage.maxTotalMintableByWallet,
        startTime: stage.startTime,
        endTime: stage.endTime,
        dropStageIndex: stage.dropStageIndex,
        maxTokenSupplyForStage: stage.maxTokenSupplyForStage,
        feeBps: stage.feeBps,
        restrictFeeRecipients: stage.restrictFeeRecipients,
      };
      entries.push({
        address: getAddress(holder.address),
        stage: stage.name,
        minimumBalance: stage.minimumBalance,
        ...mintParams,
        leaf: seaDropLeaf(holder.address, mintParams),
      });
    }
  }

  entries.sort((a, b) =>
    a.address.toLowerCase().localeCompare(b.address.toLowerCase()) ||
    Number(a.dropStageIndex - b.dropStageIndex),
  );
  const uniqueLeaves = new Set(entries.map((entry) => entry.leaf));
  invariant(uniqueLeaves.size === entries.length, "duplicate SeaDrop leaf generated");
  const tree = buildMerkleTree(entries.map((entry) => entry.leaf));
  for (const entry of entries) {
    entry.proof = proofFor(tree, entry.leaf);
    invariant(verifyProof(entry.leaf, entry.proof, tree.root), `invalid proof for ${entry.address}`);
  }
  return { entries, root: tree.root, stages };
}

function stringify(value) {
  return `${JSON.stringify(value, (_, item) => typeof item === "bigint" ? item.toString() : item, 2)}\n`;
}

async function main() {
  const [snapshotPath, planPath, outputPath] = process.argv.slice(2);
  invariant(snapshotPath && planPath && outputPath, "usage: generate-yield-bank-allowlist <snapshot.json> <mint-plan.json> <output.json>");
  const snapshot = JSON.parse(await readFile(resolve(snapshotPath), "utf8"));
  const plan = JSON.parse(await readFile(resolve(planPath), "utf8"));
  const artifact = buildAllowlist(snapshot, plan);
  const output = {
    schemaVersion: "1.0",
    token: snapshot.token,
    snapshotBlock: snapshot.snapshotBlock,
    snapshotBlockHash: snapshot.snapshotBlockHash,
    merkleRoot: artifact.root,
    eligibleWallets: new Set(artifact.entries.map((entry) => entry.address)).size,
    leafCount: artifact.entries.length,
    tiers: artifact.stages.map((stage) => ({
      name: stage.name,
      minimumBalance: stage.minimumBalance,
      eligibleWallets: artifact.entries.filter((entry) => entry.stage === stage.name).length,
    })),
    entries: artifact.entries,
  };
  await mkdir(dirname(resolve(outputPath)), { recursive: true });
  await writeFile(resolve(outputPath), stringify(output));
  process.stdout.write(`${artifact.root}\n`);
}

if (process.argv[1] && import.meta.url === new URL(`file://${resolve(process.argv[1])}`).href) {
  main().catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
}
