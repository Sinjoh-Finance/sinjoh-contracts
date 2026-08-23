import { readFile } from "node:fs/promises";

const manifestPath = process.argv[2];
if (!manifestPath) throw new Error("usage: node script/verify-release-manifest.mjs <manifest.json>");
const manifest = JSON.parse(await readFile(manifestPath, "utf8"));

const required = [
  "chainId", "protocolVersion", "gitCommit", "sourceTreeHash", "buildHash", "compiler",
  "evmVersion", "optimizerEnabled", "optimizerRuns", "viaIr", "auditReportVersion",
  "auditEvidence", "forkEvidence", "testnetEvidence", "roleEvidence", "assetFlowEvidence",
  "broadcaster", "protocolFeeRecipient",
  "registry", "deploymentEngine", "launcher", "raffleImplementation",
  "basketVaultImplementation", "erc4626YieldAdapterFactory", "erc4626YieldAdapterRuntimeHash",
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
  auditReportVersion: process.env.AUDIT_REPORT_VERSION,
  auditEvidence: process.env.AUDIT_EVIDENCE_PATH,
  forkEvidence: process.env.FORK_EVIDENCE_PATH,
  testnetEvidence: process.env.TESTNET_EVIDENCE_PATH,
  roleEvidence: process.env.ROLE_EVIDENCE_PATH,
  assetFlowEvidence: process.env.ASSET_FLOW_EVIDENCE_PATH,
};
for (const [key, value] of Object.entries(expected)) {
  if (manifest[key] !== value) {
    throw new Error(`release manifest '${key}' is ${manifest[key]}, expected ${value}`);
  }
}

const addressPattern = /^0x[0-9a-fA-F]{40}$/;
const bytes32Pattern = /^0x[0-9a-fA-F]{64}$/;
for (const [key, value] of Object.entries(manifest)) {
  if (key.endsWith("RuntimeHash") || key.endsWith("CodeHash") || key === "integrationApprovalRoot") {
    if (!bytes32Pattern.test(value)) throw new Error(`release manifest '${key}' is not bytes32`);
  }
  if (
    key.endsWith("Factory") || key.endsWith("Manager") || key.endsWith("Implementation")
      || ["broadcaster", "protocolFeeRecipient", "registry", "deploymentEngine", "launcher",
        "v3Factory", "v4StateView", "permit2"].includes(key)
  ) {
    if (!addressPattern.test(value) || /^0x0{40}$/i.test(value)) {
      throw new Error(`release manifest '${key}' is not a nonzero address`);
    }
  }
}

console.log(`verified release manifest ${manifestPath}`);
