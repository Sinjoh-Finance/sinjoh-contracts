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
const operationsAttestor = "0xbd5323053ca81c4fD208874Db73e1484819214d7";
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
      NEXT_PUBLIC_PROJECT_V2_AIRDROP_ATTESTOR: {
        manifestPath: "currentInfrastructure.raffleOperations.attestor",
        format: "nonzero-address"
      },
      NEXT_PUBLIC_PROJECT_V2_RAFFLE_ATTESTOR: {
        manifestPath: "currentInfrastructure.raffleOperations.attestor",
        format: "nonzero-address"
      },
      NEXT_PUBLIC_CHAIN_ID: { value: 1 }
    }
  }
}, contracts, 4663, {
  currentInfrastructure: { raffleOperations: { attestor: operationsAttestor } }
});

assert.deepEqual(consumers.ui.environment, {
  NEXT_PUBLIC_PROJECT_V2_LAUNCHER: launcher,
  NEXT_PUBLIC_PROJECT_V2_GIT_COMMIT: sourceCommit,
  NEXT_PUBLIC_PROJECT_V2_PONS_APPROVAL_PROOF_2: approvalProof2,
  NEXT_PUBLIC_PROJECT_V2_AIRDROP_ATTESTOR: operationsAttestor,
  NEXT_PUBLIC_PROJECT_V2_RAFFLE_ATTESTOR: operationsAttestor,
  NEXT_PUBLIC_CHAIN_ID: 4663
});

const manifestAttestorBindings = {
  schemaVersion: 1,
  ui: {
    environment: {
      NEXT_PUBLIC_PROJECT_V2_AIRDROP_ATTESTOR: {
        manifestPath: "currentInfrastructure.raffleOperations.attestor",
        format: "nonzero-address"
      }
    }
  }
};

assert.throws(
  () => resolvePromotionConsumers(manifestAttestorBindings, contracts, 4663, {
    currentInfrastructure: { raffleOperations: { attestor: "0x1234" } }
  }),
  /complete non-zero address/
);
assert.throws(
  () => resolvePromotionConsumers(manifestAttestorBindings, contracts, 4663, {
    currentInfrastructure: {
      raffleOperations: { attestor: "0x0000000000000000000000000000000000000000" }
    }
  }),
  /complete non-zero address/
);
assert.throws(
  () => resolvePromotionConsumers(manifestAttestorBindings, contracts, 4663, {}),
  /references missing currentInfrastructure\.raffleOperations\.attestor/
);

const repoRoot = resolve(import.meta.dirname, "../..");
const mainnetManifest = JSON.parse(
  readFileSync(resolve(repoRoot, "mainnet-deployments.json"), "utf8")
);
const releaseBindings = JSON.parse(
  readFileSync(resolve(repoRoot, "deployments/consumers/bindings.json"), "utf8")
);
const releaseContracts = {};
collectPromotionContracts(mainnetManifest.currentInfrastructure ?? {}, "contracts", releaseContracts);
collectPromotionContracts(mainnetManifest.dependencies ?? {}, "dependencies", releaseContracts);
collectPromotionContracts(
  mainnetManifest.letscashDependencies ?? {},
  "dependencies.letscash",
  releaseContracts
);
const generatedConsumers = resolvePromotionConsumers(
  releaseBindings,
  releaseContracts,
  mainnetManifest.chainId,
  mainnetManifest
);
assert.equal(
  generatedConsumers.ui.environment.NEXT_PUBLIC_PROJECT_V2_AIRDROP_ATTESTOR,
  mainnetManifest.currentInfrastructure.raffleOperations.attestor
);
assert.equal(
  generatedConsumers.ui.environment.NEXT_PUBLIC_PROJECT_V2_RAFFLE_ATTESTOR,
  mainnetManifest.currentInfrastructure.raffleOperations.attestor
);
assert.equal(
  generatedConsumers.ui.contracts.ponsV2PairBuybackAdapter.address,
  "0x1BE0E8F04221329FDfea34f41a1832a80c2c147c"
);
assert.equal(
  generatedConsumers.ui.contracts.ponsV2PairBuybackPriceGuard.address,
  "0x902A6Fa8Ca273aAB186633FF27879Cd3703F6AED"
);
assert.equal(
  releaseContracts[
    "contracts.ponsV2PairBuybackHistoricalGenerations.indexedLegacyFactory.adapter"
  ].address,
  "0xfAB57a5fE409B4503A1a09fD7DC80e6ffB85Abb8"
);
assert.equal(
  releaseContracts[
    "contracts.ponsV2PairBuybackHistoricalGenerations.indexedLegacyFactory.priceGuard"
  ].address,
  "0x69768f0b41A5A51aB23b23ccfbE9e3122Ac0DA8b"
);

console.log("promotion model tests passed");
