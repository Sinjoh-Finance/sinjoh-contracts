#!/usr/bin/env node
import assert from "node:assert/strict";
import {
  buildProjectV2MainnetEntry,
  projectV2DeploymentKeys
} from "./project-v2-mainnet-entry.mjs";

const manifest = {
  chainId: 4663,
  protocolVersion: 2,
  gitCommit: "1".repeat(40),
  buildHash: "2".repeat(64),
  ponsLaunchpadApprovalProof: [
    `0x${"33".repeat(32)}`,
    `0x${"44".repeat(32)}`,
    `0x${"55".repeat(32)}`
  ]
};
const transactions = [];
const receipts = [];
let block = 100;
for (const [index, key] of projectV2DeploymentKeys.entries()) {
  const address = `0x${(index + 1).toString(16).padStart(40, "0")}`;
  manifest[key] = address;
  manifest[`${key}RuntimeHash`] = `0x${(index + 1).toString(16).padStart(64, "0")}`;
  if (key === "ponsProjectAdapterImplementation") continue;
  const hash = `0x${(index + 101).toString(16).padStart(64, "0")}`;
  transactions.push({ hash, contractAddress: address });
  receipts.push({ transactionHash: hash, blockNumber: `0x${block.toString(16)}`, status: "0x1" });
  block += 1;
}

const entry = buildProjectV2MainnetEntry(manifest, [{ chain: 4663, transactions, receipts }]);
assert.equal(entry.sourceCommit, manifest.gitCommit);
assert.equal(entry.approvalProof2, manifest.ponsLaunchpadApprovalProof[2]);
assert.equal(entry.launcher.address, manifest.launcher);
assert.equal(entry.launcher.deploymentBlock, block - 1);
assert.equal(
  entry.ponsProjectAdapterImplementation.deploymentTransaction,
  entry.ponsProjectAdapterFactory.deploymentTransaction
);
assert.throws(
  () => buildProjectV2MainnetEntry(manifest, [{ chain: 4663, transactions, receipts: [] }]),
  /missing a successful receipt/
);

console.log("Project V2 mainnet entry tests passed");
