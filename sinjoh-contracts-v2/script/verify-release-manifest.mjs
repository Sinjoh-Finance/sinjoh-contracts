import { readFile } from "node:fs/promises";

const manifestPath = process.argv[2];
if (!manifestPath) throw new Error("usage: node script/verify-release-manifest.mjs <manifest.json>");
const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
const zeroAddress = `0x${"0".repeat(40)}`;
const zeroBytes32 = `0x${"0".repeat(64)}`;

const required = [
  "chainId", "protocolVersion", "gitCommit", "sourceTreeHash", "buildHash", "compiler",
  "evmVersion", "optimizerEnabled", "optimizerRuns", "viaIr", "auditReportVersion",
  "auditEvidence", "auditEvidenceHash", "forkEvidence", "forkEvidenceHash", "testnetEvidence",
  "testnetEvidenceHash", "roleEvidence", "roleEvidenceHash", "assetFlowEvidence",
  "assetFlowEvidenceHash",
  "broadcaster", "protocolFeeRecipient",
  "registry", "deploymentEngine", "launcher", "raffleImplementation",
  "raffleImplementationRuntimeHash",
  "randomnessAdapter", "randomnessAdapterRuntimeHash",
  "basketEnabled",
  "basketVaultImplementation", "basketVaultImplementationRuntimeHash",
  "erc4626YieldAdapterFactory", "erc4626YieldAdapterFactoryRuntimeHash",
  "erc4626YieldAdapterRuntimeHash",
  "fundingBandV3IntegrationFactory", "fundingBandV3IntegrationFactoryRuntimeHash",
  "fundingBandMarketCapGuardRuntimeHash", "fundingBandPositionAdapterRuntimeHash",
  "v3Factory", "v3FactoryRuntimeHash", "v3PositionManager", "v3PositionManagerRuntimeHash",
  "v4PositionManager", "v4PositionManagerRuntimeHash", "v4StateView",
  "v4StateViewRuntimeHash", "permit2", "permit2RuntimeHash", "integrationApprovalRoot",
  "registryRuntimeHash", "deploymentEngineRuntimeHash", "launcherRuntimeHash",
  "tokenCreationCodeHash", "multisigCreationCodeHash", "timelockCreationCodeHash",
  "stakingCreationCodeHash", "treasuryCreationCodeHash", "airdropCreationCodeHash",
  "routerCreationCodeHash", "basketCreationCodeHash", "bandsCreationCodeHash",
  "liquidityCreationCodeHash",
];
for (const key of required) {
  if (!(key in manifest)) throw new Error(`release manifest is missing '${key}'`);
}

const expected = {
  chainId: Number(process.env.EXPECTED_CHAIN_ID),
  protocolVersion: 2,
  gitCommit: process.env.RELEASE_GIT_COMMIT,
  sourceTreeHash: process.env.RELEASE_SOURCE_TREE_HASH,
  buildHash: process.env.RELEASE_BUILD_HASH,
  compiler: "solc-0.8.28",
  evmVersion: "cancun",
  optimizerEnabled: true,
  optimizerRuns: 1000,
  viaIr: true,
  basketEnabled: false,
  basketVaultImplementation: zeroAddress,
  basketVaultImplementationRuntimeHash: zeroBytes32,
  erc4626YieldAdapterFactory: zeroAddress,
  erc4626YieldAdapterFactoryRuntimeHash: zeroBytes32,
  erc4626YieldAdapterRuntimeHash: zeroBytes32,
  basketCreationCodeHash: zeroBytes32,
  auditReportVersion: process.env.AUDIT_REPORT_VERSION,
  auditEvidence: process.env.AUDIT_EVIDENCE_PATH,
  auditEvidenceHash: process.env.AUDIT_EVIDENCE_HASH,
  forkEvidence: process.env.FORK_EVIDENCE_PATH,
  forkEvidenceHash: process.env.FORK_EVIDENCE_HASH,
  testnetEvidence: process.env.TESTNET_EVIDENCE_PATH,
  testnetEvidenceHash: process.env.TESTNET_EVIDENCE_HASH,
  roleEvidence: process.env.ROLE_EVIDENCE_PATH,
  roleEvidenceHash: process.env.ROLE_EVIDENCE_HASH,
  assetFlowEvidence: process.env.ASSET_FLOW_EVIDENCE_PATH,
  assetFlowEvidenceHash: process.env.ASSET_FLOW_EVIDENCE_HASH,
};
for (const [key, value] of Object.entries(expected)) {
  if (manifest[key] !== value) {
    throw new Error(`release manifest '${key}' is ${manifest[key]}, expected ${value}`);
  }
}

const approvedReleaseValues = {
  protocolFeeRecipient: "PROTOCOL_FEE_RECIPIENT",
  integrationApprovalRoot: "INTEGRATION_APPROVAL_ROOT",
  randomnessAdapter: "RANDOMNESS_ADAPTER",
  randomnessAdapterRuntimeHash: "RANDOMNESS_ADAPTER_RUNTIME_HASH",
  v3Factory: "V3_FACTORY",
  v3FactoryRuntimeHash: "V3_FACTORY_RUNTIME_HASH",
  v3PositionManager: "V3_POSITION_MANAGER",
  v3PositionManagerRuntimeHash: "V3_POSITION_MANAGER_RUNTIME_HASH",
  v4PositionManager: "V4_POSITION_MANAGER",
  v4PositionManagerRuntimeHash: "V4_POSITION_MANAGER_RUNTIME_HASH",
  v4StateView: "V4_STATE_VIEW",
  v4StateViewRuntimeHash: "V4_STATE_VIEW_RUNTIME_HASH",
  permit2: "PERMIT2",
  permit2RuntimeHash: "PERMIT2_RUNTIME_HASH",
};
for (const [key, environmentKey] of Object.entries(approvedReleaseValues)) {
  if (manifest[key].toLowerCase() !== process.env[environmentKey].toLowerCase()) {
    throw new Error(`release manifest '${key}' does not match the approved release value`);
  }
}

const addressPattern = /^0x[0-9a-fA-F]{40}$/;
const bytes32Pattern = /^0x[0-9a-fA-F]{64}$/;
for (const [key, value] of Object.entries(manifest)) {
  if (key.endsWith("RuntimeHash") || key.endsWith("CodeHash") || key === "integrationApprovalRoot") {
    if (!bytes32Pattern.test(value)) throw new Error(`release manifest '${key}' is not bytes32`);
  }
  if (key.endsWith("EvidenceHash") && !/^[0-9a-fA-F]{64}$/.test(value)) {
    throw new Error(`release manifest '${key}' is not a SHA-256 hash`);
  }
  if (
    key.endsWith("Factory") || key.endsWith("Manager") || key.endsWith("Implementation")
      || ["broadcaster", "protocolFeeRecipient", "registry", "deploymentEngine", "launcher",
        "randomnessAdapter", "v3Factory", "v4StateView", "permit2"].includes(key)
  ) {
    if (
      !manifest.basketEnabled
        && ["basketVaultImplementation", "erc4626YieldAdapterFactory"].includes(key)
        && /^0x0{40}$/i.test(value)
    ) continue;
    if (!addressPattern.test(value) || /^0x0{40}$/i.test(value)) {
      throw new Error(`release manifest '${key}' is not a nonzero address`);
    }
  }
}

console.log(`verified release manifest ${manifestPath}`);
