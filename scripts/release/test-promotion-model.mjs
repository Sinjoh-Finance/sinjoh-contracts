#!/usr/bin/env node
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import {
  collectPromotionContracts,
  resolvePromotionConsumers
} from "./promotion-model.mjs";
import { projectV2DeploymentKeys } from "./project-v2-mainnet-entry.mjs";

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
assert.equal(
  mainnetManifest.letscashDependencies.factoryProxy.implementation,
  "0x8E0Ee024c2B547AaE91E6B9b1D3940449B3404F4"
);
assert.equal(
  mainnetManifest.letscashDependencies.factoryProxy.implementationRuntimeCodeHash,
  "0xf2e80731c9679b7869b99b8a3eb0428be9923d93abdce4c73de77e9b7fca0603"
);
assert.equal(
  mainnetManifest.letscashDependencies.factoryImplementation.address,
  mainnetManifest.letscashDependencies.factoryProxy.implementation
);
assert.deepEqual(
  Object.keys(mainnetManifest.letscashDependencies.factoryHistoricalImplementations),
  ["cash-cat-factory-vnext-pre-20260825"]
);
assert.equal(
  mainnetManifest.letscashDependencies.factoryHistoricalImplementations[
    "cash-cat-factory-vnext-pre-20260825"
  ].address,
  "0x3dFd73A63E15920aDd4B6c5C6a4b1b4B768b2c1A"
);
const projectRelease = JSON.parse(readFileSync(resolve(
  repoRoot,
  "sinjoh-contracts-v2/deployments/project-launcher-v2-4663-public-pons-dual-funding.json"
), "utf8"));
const fundingRelease = JSON.parse(readFileSync(resolve(
  repoRoot,
  "sinjoh-funding-bands/deployments/funding-bands-4663-public-pons-dual.json"
), "utf8"));
assert.equal(
  createHash("sha256")
    .update(readFileSync(resolve(
      repoRoot,
      "sinjoh-contracts-v2/deployments/project-launcher-v2-4663-public-pons-dual-funding.json"
    )))
    .digest("hex"),
  "07f6a52fccad5dba731e538548a88f96d1e6bbd03f90cdcd9e34d23e42034d41"
);
assert.equal(
  createHash("sha256")
    .update(readFileSync(resolve(
      repoRoot,
      "sinjoh-funding-bands/deployments/funding-bands-4663-public-pons-dual.json"
    )))
    .digest("hex"),
  "a1b57ef6a72d12cb82e6aac13dc3048d31811dd7d6810c002b40afb17614e0fc"
);
assert.equal(mainnetManifest.currentInfrastructure.projectV2.sourceCommit, projectRelease.gitCommit);
assert.equal(mainnetManifest.currentInfrastructure.projectV2.buildHash, projectRelease.buildHash);
for (const key of projectV2DeploymentKeys) {
  assert.equal(mainnetManifest.currentInfrastructure.projectV2[key].address, projectRelease[key]);
  assert.equal(
    mainnetManifest.currentInfrastructure.projectV2[key].runtimeCodeHash,
    projectRelease[`${key}RuntimeHash`].toLowerCase()
  );
}
assert.equal(
  mainnetManifest.currentInfrastructure.fundingBands.ponsV2Generation.adapterFactory.address,
  fundingRelease.ponsV2AdapterFactory
);
assert.equal(
  mainnetManifest.currentInfrastructure.fundingBands.ponsV2Generation.ordinaryAdapterImplementation.address,
  fundingRelease.ponsV2AdapterImplementation
);
assert.equal(
  mainnetManifest.currentInfrastructure.fundingBands.ponsV2Generation.projectAdapterImplementation.address,
  fundingRelease.ponsV2ProjectAdapterImplementation
);
assert.equal(
  mainnetManifest.currentInfrastructure.fundingBands.ponsV2Verifier.address,
  fundingRelease.verifier
);
assert.equal(
  mainnetManifest.currentInfrastructure.fundingBands.launchEscrow.address,
  fundingRelease.escrow
);
assert.equal(
  mainnetManifest.currentInfrastructure.fundingBands.manager.address,
  fundingRelease.manager
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
  "0xfAB57a5fE409B4503A1a09fD7DC80e6ffB85Abb8"
);
assert.equal(
  generatedConsumers.ui.contracts.ponsV2PairBuybackPriceGuard.address,
  "0x69768f0b41A5A51aB23b23ccfbE9e3122Ac0DA8b"
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
assert.equal(
  releaseContracts[
    "contracts.ponsV2PairBuybackHistoricalGenerations.trustedForwarderFactory.adapter"
  ].address,
  "0x1BE0E8F04221329FDfea34f41a1832a80c2c147c"
);
assert.equal(
  releaseContracts[
    "contracts.ponsV2PairBuybackHistoricalGenerations.trustedForwarderFactory.priceGuard"
  ].address,
  "0x902A6Fa8Ca273aAB186633FF27879Cd3703F6AED"
);
assert.deepEqual(
  Object.keys(mainnetManifest.currentInfrastructure.projectV2Generations).sort(),
  [
    "project-v2-gascap-20260825-3d6dd81",
    "project-v2-public-pons-wrong-locker-20260825-1925510",
    "project-v2-routing-complete-20260825-3b5dc15"
  ]
);
assert.equal(
  createHash("sha256")
    .update(JSON.stringify(
      mainnetManifest.currentInfrastructure.projectV2Generations[
        "project-v2-routing-complete-20260825-3b5dc15"
      ]
    ))
    .digest("hex"),
  "50e4ba8d6de68d17109e940adeb300c7769a0a5ecb2220272470884f7474241b"
);
assert.equal(
  createHash("sha256")
    .update(JSON.stringify(
      mainnetManifest.currentInfrastructure.projectV2Generations[
        "project-v2-gascap-20260825-3d6dd81"
      ]
    ))
    .digest("hex"),
  "7a0f243fb43e29e3f140a8fde7a100e5498b6c1347447ee187f940b275842d95"
);
assert.equal(
  mainnetManifest.currentInfrastructure.projectV2.launcher.address,
  "0x6b5e99b344C0671f77BAC00c5ADbE453Ffa39100"
);
assert.equal(
  mainnetManifest.currentInfrastructure.projectV2.ponsProjectAdapterFactory.address,
  "0xa16389c14c9299A4317D50aEfd5e4cC442F2dF0d"
);
assert.equal(
  mainnetManifest.currentInfrastructure.ponsV2AdapterImplementation.address,
  "0xAf3D6710621697d25096E01367A3D0490Fd11e2b"
);
assert.equal(
  mainnetManifest.currentInfrastructure.fundingBands.ponsV2Verifier.address,
  "0x9d93036656C51dd9Fe2164f9325FeF850fC282D9"
);
assert.equal(
  mainnetManifest.currentInfrastructure.fundingBands.launchEscrow.address,
  "0xf8F28826d4837e10fc9eD0d7787F763725F10378"
);
assert.equal(
  mainnetManifest.dependencies.ponsV2LaunchFactory.address,
  "0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e"
);
assert.equal(
  mainnetManifest.dependencies.ponsV2LaunchLocker.address,
  "0x267444D099b10fB5Ed7c3Cc7B7c767AdcA574952"
);

console.log("promotion model tests passed");
