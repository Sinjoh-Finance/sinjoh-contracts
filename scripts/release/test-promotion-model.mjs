#!/usr/bin/env node
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import {
  collectPromotionContracts,
  resolvePromotionConsumers
} from "./promotion-model.mjs";

const sourceCommit = "1".repeat(40);
const buildHash = "2".repeat(64);
const approvalProof0 = `0x${"33".repeat(32)}`;
const approvalProof1 = `0x${"44".repeat(32)}`;
const approvalProof2 = `0x${"55".repeat(32)}`;
const launcher = "0x1111111111111111111111111111111111111111";
const launcherRuntimeCodeHash = `0x${"AA".repeat(32)}`;
const contracts = {};

collectPromotionContracts({
  projectV2: {
    sourceCommit,
    buildHash,
    approvalProof0,
    approvalProof1,
    approvalProof2,
    launcher: {
      address: launcher,
      runtimeCodeHash: launcherRuntimeCodeHash
    }
  }
}, "contracts", contracts);

assert.deepEqual(contracts["contracts.projectV2.launcher"], {
  sourceCommit,
  buildHash,
  approvalProof0,
  approvalProof1,
  approvalProof2,
  address: launcher,
  runtimeCodeHash: launcherRuntimeCodeHash
});

const consumers = resolvePromotionConsumers({
  schemaVersion: 1,
  ui: {
    environment: {
      NEXT_PUBLIC_PROJECT_V2_LAUNCHER: {
        path: "contracts.projectV2.launcher",
        field: "address"
      },
      NEXT_PUBLIC_PROJECT_V2_GIT_COMMIT: {
        path: "contracts.projectV2.launcher",
        field: "sourceCommit"
      },
      NEXT_PUBLIC_PROJECT_V2_PONS_APPROVAL_PROOF_2: {
        path: "contracts.projectV2.launcher",
        field: "approvalProof2"
      },
      NEXT_PUBLIC_CHAIN_ID: { value: 1 }
    }
  }
}, contracts, 4663);

assert.deepEqual(consumers.ui.environment, {
  NEXT_PUBLIC_PROJECT_V2_LAUNCHER: launcher,
  NEXT_PUBLIC_PROJECT_V2_GIT_COMMIT: sourceCommit,
  NEXT_PUBLIC_PROJECT_V2_PONS_APPROVAL_PROOF_2: approvalProof2,
  NEXT_PUBLIC_CHAIN_ID: 4663
});

const repoRoot = resolve(import.meta.dirname, "../..");
const productionBindings = JSON.parse(
  readFileSync(resolve(repoRoot, "deployments/consumers/bindings.json"), "utf8")
);
const mainnet = JSON.parse(
  readFileSync(resolve(repoRoot, "mainnet-deployments.json"), "utf8")
);
const operationalAttestor = mainnet.currentInfrastructure?.raffleOperations?.attestor;
assert.match(operationalAttestor, /^0x[0-9a-fA-F]{40}$/);
assert.equal(
  productionBindings.ui.environment.NEXT_PUBLIC_PROJECT_V2_AIRDROP_ATTESTOR.value,
  operationalAttestor
);
assert.equal(
  productionBindings.ui.environment.NEXT_PUBLIC_PROJECT_V2_RAFFLE_ATTESTOR.value,
  operationalAttestor
);

console.log("promotion model tests passed");
