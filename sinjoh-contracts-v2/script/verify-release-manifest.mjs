import { readFile } from "node:fs/promises";
import { createRequire } from "node:module";

const requireFromSdk = createRequire(new URL("../sdk/package.json", import.meta.url));
const { concatHex, encodeAbiParameters, keccak256, stringToHex } = requireFromSdk("viem");

const manifestPath = process.argv[2];
if (!manifestPath) throw new Error("usage: node script/verify-release-manifest.mjs <manifest.json>");
const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
const zeroAddress = `0x${"0".repeat(40)}`;
const zeroBytes32 = `0x${"0".repeat(64)}`;
const addressPattern = /^0x[0-9a-fA-F]{40}$/;
const bytes32Pattern = /^0x[0-9a-fA-F]{64}$/;

const required = [
  "chainId", "protocolVersion", "gitCommit", "sourceTreeHash", "buildHash", "compiler",
  "evmVersion", "optimizerEnabled", "optimizerRuns", "viaIr",
  "broadcaster", "protocolFeeRecipient",
  "registry", "deploymentEngine", "launchValidator", "launcher",
  "ponsProjectTokenFactory", "launchpadProjectTokenFactory", "raffleImplementation",
  "launchValidatorRuntimeHash", "ponsProjectTokenFactoryRuntimeHash",
  "launchpadProjectTokenFactoryRuntimeHash",
  "raffleImplementationRuntimeHash",
  "randomnessAdapter", "randomnessAdapterRuntimeHash",
  "basketEnabled",
  "basketVaultImplementation", "basketVaultImplementationRuntimeHash",
  "erc4626YieldAdapterFactory", "erc4626YieldAdapterFactoryRuntimeHash",
  "erc4626YieldAdapterRuntimeHash",
  "fundingBandV3IntegrationFactory", "fundingBandV3IntegrationFactoryRuntimeHash",
  "fundingBandMarketCapGuardRuntimeTemplateHash",
  "fundingBandPositionAdapterRuntimeTemplateHash",
  "v3Factory", "v3FactoryRuntimeHash", "v3PositionManager", "v3PositionManagerRuntimeHash",
  "v4PositionManager", "v4PositionManagerRuntimeHash", "v4StateView",
  "v4StateViewRuntimeHash", "permit2", "permit2RuntimeHash", "integrationApprovalRoot",
  "projectSwapAdapter", "projectSwapAdapterRuntimeHash", "fundingBandQuoteUsdOracle",
  "fundingBandQuoteUsdOracleRuntimeHash", "fundingBandQuoteAsset",
  "fundingBandQuoteAssetRuntimeHash", "fundingBandQuoteUsdAggregator",
  "fundingBandQuoteUsdAggregatorRuntimeHash", "projectV3PriceGuard500",
  "projectV3PriceGuard500RuntimeHash", "projectV3PriceGuard3000",
  "projectV3PriceGuard3000RuntimeHash", "projectV3PriceGuard10000",
  "projectV3PriceGuard10000RuntimeHash", "swapApprovalLeaf500", "swapApprovalLeaf3000",
  "swapApprovalLeaf10000", "fundingBandIntegrationLeaf", "swapApprovalProof500",
  "swapApprovalProof3000", "swapApprovalProof10000", "fundingBandIntegrationProof",
  "ponsV2PairBuybackAdapter", "ponsV2PairBuybackAdapterRuntimeHash",
  "ponsV2PairBuybackPriceGuard", "ponsV2PairBuybackPriceGuardRuntimeHash",
  "flapBuybackAdapter", "flapBuybackAdapterRuntimeHash",
  "flapBuybackPriceGuard", "flapBuybackPriceGuardRuntimeHash",
  "flapPayoutPriceGuard", "flapPayoutPriceGuardRuntimeHash",
  "ponsV2PairBuybackApprovalLeaf", "flapBuybackApprovalLeaf", "flapPayoutApprovalLeaf",
  "ponsV2PairBuybackApprovalProof", "flapBuybackApprovalProof", "flapPayoutApprovalProof",
  "ponsProjectAdapterFactory", "ponsProjectAdapterFactoryRuntimeHash",
  "poolsInstantProjectAdapterFactory", "poolsInstantProjectAdapterFactoryRuntimeHash",
  "poolsInstantNoFeeProjectAdapterFactory", "poolsInstantNoFeeProjectAdapterFactoryRuntimeHash",
  "poolsLbpProjectAdapterFactory", "poolsLbpProjectAdapterFactoryRuntimeHash",
  "ponsProjectAdapterImplementation", "ponsProjectAdapterImplementationRuntimeHash",
  "poolsProjectRegistrationHelper", "poolsProjectRegistrationHelperRuntimeHash",
  "ponsLaunchFactory", "ponsLaunchFactoryRuntimeHash",
  "ponsLaunchpadApprovalLeaf", "poolsInstantLaunchpadApprovalLeaf",
  "poolsLbpLaunchpadApprovalLeaf", "ponsLaunchpadApprovalProof",
  "poolsInstantLaunchpadApprovalProof", "poolsInstantNoFeeLaunchpadApprovalLeaf",
  "poolsInstantNoFeeLaunchpadApprovalProof", "poolsLbpLaunchpadApprovalProof",
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
  optimizerRuns: 200,
  viaIr: true,
  basketEnabled: false,
  basketVaultImplementation: zeroAddress,
  basketVaultImplementationRuntimeHash: zeroBytes32,
  erc4626YieldAdapterFactory: zeroAddress,
  erc4626YieldAdapterFactoryRuntimeHash: zeroBytes32,
  erc4626YieldAdapterRuntimeHash: zeroBytes32,
  basketCreationCodeHash: zeroBytes32,
};
for (const [key, value] of Object.entries(expected)) {
  if (manifest[key] !== value) {
    throw new Error(`release manifest '${key}' is ${manifest[key]}, expected ${value}`);
  }
}

const approvedReleaseValues = {
  protocolFeeRecipient: "PROTOCOL_FEE_RECIPIENT",
  projectSwapAdapter: "PROJECT_SWAP_ADAPTER",
  projectSwapAdapterRuntimeHash: "PROJECT_SWAP_ADAPTER_RUNTIME_HASH",
  fundingBandQuoteAsset: "FUNDING_BAND_QUOTE_ASSET",
  fundingBandQuoteAssetRuntimeHash: "FUNDING_BAND_QUOTE_ASSET_RUNTIME_HASH",
  fundingBandQuoteUsdAggregator: "FUNDING_BAND_QUOTE_USD_AGGREGATOR",
  fundingBandQuoteUsdAggregatorRuntimeHash: "FUNDING_BAND_QUOTE_USD_AGGREGATOR_RUNTIME_HASH",
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
  ponsProjectAdapterFactory: "PONS_PROJECT_ADAPTER_FACTORY",
  ponsProjectAdapterFactoryRuntimeHash: "PONS_PROJECT_ADAPTER_FACTORY_RUNTIME_HASH",
  poolsInstantProjectAdapterFactory: "POOLS_INSTANT_PROJECT_ADAPTER_FACTORY",
  poolsInstantProjectAdapterFactoryRuntimeHash: "POOLS_INSTANT_PROJECT_ADAPTER_FACTORY_RUNTIME_HASH",
  poolsInstantNoFeeProjectAdapterFactory: "POOLS_INSTANT_NO_FEE_PROJECT_ADAPTER_FACTORY",
  poolsInstantNoFeeProjectAdapterFactoryRuntimeHash: "POOLS_INSTANT_NO_FEE_PROJECT_ADAPTER_FACTORY_RUNTIME_HASH",
  poolsLbpProjectAdapterFactory: "POOLS_LBP_PROJECT_ADAPTER_FACTORY",
  poolsLbpProjectAdapterFactoryRuntimeHash: "POOLS_LBP_PROJECT_ADAPTER_FACTORY_RUNTIME_HASH",
  ponsProjectAdapterImplementation: "PONS_PROJECT_ADAPTER_IMPLEMENTATION",
  ponsProjectAdapterImplementationRuntimeHash: "PONS_PROJECT_ADAPTER_IMPLEMENTATION_RUNTIME_HASH",
  poolsProjectRegistrationHelper: "POOLS_PROJECT_REGISTRATION_HELPER",
  poolsProjectRegistrationHelperRuntimeHash: "POOLS_PROJECT_REGISTRATION_HELPER_RUNTIME_HASH",
  ponsLaunchFactory: "PONS_LAUNCH_FACTORY",
  ponsLaunchFactoryRuntimeHash: "PONS_LAUNCH_FACTORY_RUNTIME_HASH",
  ponsV2PairBuybackAdapter: "PONS_V2_PAIR_BUYBACK_ADAPTER",
  ponsV2PairBuybackAdapterRuntimeHash: "PONS_V2_PAIR_BUYBACK_ADAPTER_RUNTIME_HASH",
  ponsV2PairBuybackPriceGuard: "PONS_V2_PAIR_BUYBACK_PRICE_GUARD",
  ponsV2PairBuybackPriceGuardRuntimeHash: "PONS_V2_PAIR_BUYBACK_PRICE_GUARD_RUNTIME_HASH",
  flapBuybackAdapter: "FLAP_BUYBACK_ADAPTER",
  flapBuybackAdapterRuntimeHash: "FLAP_BUYBACK_ADAPTER_RUNTIME_HASH",
  flapBuybackPriceGuard: "FLAP_BUYBACK_PRICE_GUARD",
  flapBuybackPriceGuardRuntimeHash: "FLAP_BUYBACK_PRICE_GUARD_RUNTIME_HASH",
  flapPayoutPriceGuard: "FLAP_PAYOUT_PRICE_GUARD",
  flapPayoutPriceGuardRuntimeHash: "FLAP_PAYOUT_PRICE_GUARD_RUNTIME_HASH",
};
for (const [key, environmentKey] of Object.entries(approvedReleaseValues)) {
  if (manifest[key].toLowerCase() !== process.env[environmentKey].toLowerCase()) {
    throw new Error(`release manifest '${key}' does not match the approved release value`);
  }
}
if (manifest.integrationApprovalRoot === zeroBytes32) {
  throw new Error("release manifest integrationApprovalRoot must be nonzero");
}
for (const [key, expectedLength] of [
  ["swapApprovalProof500", 4], ["swapApprovalProof3000", 4],
  ["swapApprovalProof10000", 4], ["fundingBandIntegrationProof", 4],
  ["ponsLaunchpadApprovalProof", 4], ["poolsInstantLaunchpadApprovalProof", 4],
  ["poolsInstantNoFeeLaunchpadApprovalProof", 4], ["poolsLbpLaunchpadApprovalProof", 4],
  ["ponsV2PairBuybackApprovalProof", 4], ["flapBuybackApprovalProof", 4],
  ["flapPayoutApprovalProof", 4],
]) {
  if (!Array.isArray(manifest[key]) || manifest[key].length !== expectedLength
      || manifest[key].some((value) => !bytes32Pattern.test(value))) {
    throw new Error(`release manifest '${key}' must contain exactly ${expectedLength} bytes32 nodes`);
  }
}

const bytes32Type = { type: "bytes32" };
const uint256Type = { type: "uint256" };
const addressType = { type: "address" };
const doubleHash = (types, values) => keccak256(keccak256(encodeAbiParameters(types, values)));
const swapDomain = keccak256(stringToHex("SINJOH_V2_SWAP_INTEGRATION_APPROVAL"));
const fundingBandFactoryDomain = keccak256(
  stringToHex("SINJOH_V2_FUNDING_BAND_FACTORY_INTEGRATION"),
);
const launchpadFactoryDomain = keccak256(
  stringToHex("SINJOH_V2_LAUNCHPAD_FACTORY_APPROVAL"),
);
const swapLeaf = (guard, guardRuntimeHash) => doubleHash(
  [bytes32Type, uint256Type, addressType, bytes32Type, addressType, bytes32Type],
  [
    swapDomain,
    BigInt(manifest.chainId),
    manifest.projectSwapAdapter,
    manifest.projectSwapAdapterRuntimeHash,
    guard,
    guardRuntimeHash,
  ],
);
const explicitSwapLeaf = (adapter, adapterRuntimeHash, guard, guardRuntimeHash) => doubleHash(
  [bytes32Type, uint256Type, addressType, bytes32Type, addressType, bytes32Type],
  [swapDomain, BigInt(manifest.chainId), adapter, adapterRuntimeHash, guard, guardRuntimeHash],
);
const computedLeaves = {
  swapApprovalLeaf500: swapLeaf(
    manifest.projectV3PriceGuard500,
    manifest.projectV3PriceGuard500RuntimeHash,
  ),
  swapApprovalLeaf3000: swapLeaf(
    manifest.projectV3PriceGuard3000,
    manifest.projectV3PriceGuard3000RuntimeHash,
  ),
  swapApprovalLeaf10000: swapLeaf(
    manifest.projectV3PriceGuard10000,
    manifest.projectV3PriceGuard10000RuntimeHash,
  ),
  fundingBandIntegrationLeaf: doubleHash(
    [
      bytes32Type, uint256Type, addressType, addressType, bytes32Type,
      addressType, addressType, bytes32Type, addressType, bytes32Type,
    ],
    [
      fundingBandFactoryDomain,
      BigInt(manifest.chainId),
      manifest.fundingBandV3IntegrationFactory,
      manifest.v3Factory,
      manifest.v3FactoryRuntimeHash,
      manifest.fundingBandQuoteAsset,
      manifest.v3PositionManager,
      manifest.v3PositionManagerRuntimeHash,
      manifest.fundingBandQuoteUsdOracle,
      manifest.fundingBandQuoteUsdOracleRuntimeHash,
    ],
  ),
  ponsLaunchpadApprovalLeaf: doubleHash(
    [bytes32Type, uint256Type, addressType, bytes32Type],
    [launchpadFactoryDomain, BigInt(manifest.chainId), manifest.ponsProjectAdapterFactory,
      manifest.ponsProjectAdapterFactoryRuntimeHash],
  ),
  poolsInstantLaunchpadApprovalLeaf: doubleHash(
    [bytes32Type, uint256Type, addressType, bytes32Type],
    [launchpadFactoryDomain, BigInt(manifest.chainId), manifest.poolsInstantProjectAdapterFactory,
      manifest.poolsInstantProjectAdapterFactoryRuntimeHash],
  ),
  poolsInstantNoFeeLaunchpadApprovalLeaf: doubleHash(
    [bytes32Type, uint256Type, addressType, bytes32Type],
    [launchpadFactoryDomain, BigInt(manifest.chainId), manifest.poolsInstantNoFeeProjectAdapterFactory,
      manifest.poolsInstantNoFeeProjectAdapterFactoryRuntimeHash],
  ),
  poolsLbpLaunchpadApprovalLeaf: doubleHash(
    [bytes32Type, uint256Type, addressType, bytes32Type],
    [launchpadFactoryDomain, BigInt(manifest.chainId), manifest.poolsLbpProjectAdapterFactory,
      manifest.poolsLbpProjectAdapterFactoryRuntimeHash],
  ),
  ponsV2PairBuybackApprovalLeaf: explicitSwapLeaf(
    manifest.ponsV2PairBuybackAdapter,
    manifest.ponsV2PairBuybackAdapterRuntimeHash,
    manifest.ponsV2PairBuybackPriceGuard,
    manifest.ponsV2PairBuybackPriceGuardRuntimeHash,
  ),
  flapBuybackApprovalLeaf: explicitSwapLeaf(
    manifest.flapBuybackAdapter,
    manifest.flapBuybackAdapterRuntimeHash,
    manifest.flapBuybackPriceGuard,
    manifest.flapBuybackPriceGuardRuntimeHash,
  ),
  flapPayoutApprovalLeaf: explicitSwapLeaf(
    manifest.flapBuybackAdapter,
    manifest.flapBuybackAdapterRuntimeHash,
    manifest.flapPayoutPriceGuard,
    manifest.flapPayoutPriceGuardRuntimeHash,
  ),
};
for (const [key, computed] of Object.entries(computedLeaves)) {
  if (manifest[key].toLowerCase() !== computed.toLowerCase()) {
    throw new Error(`release manifest '${key}' does not match its exact approved integration`);
  }
}
if (new Set(Object.values(computedLeaves).map((value) => value.toLowerCase())).size !== 11) {
  throw new Error("release manifest integration approval leaves must be unique");
}
const processProof = (leaf, proof) => proof.reduce((hash, sibling) => {
  const ordered = BigInt(hash) < BigInt(sibling) ? [hash, sibling] : [sibling, hash];
  return keccak256(concatHex(ordered));
}, leaf);
const proofFields = {
  swapApprovalLeaf500: "swapApprovalProof500",
  swapApprovalLeaf3000: "swapApprovalProof3000",
  swapApprovalLeaf10000: "swapApprovalProof10000",
  fundingBandIntegrationLeaf: "fundingBandIntegrationProof",
  ponsLaunchpadApprovalLeaf: "ponsLaunchpadApprovalProof",
  poolsInstantLaunchpadApprovalLeaf: "poolsInstantLaunchpadApprovalProof",
  poolsInstantNoFeeLaunchpadApprovalLeaf: "poolsInstantNoFeeLaunchpadApprovalProof",
  poolsLbpLaunchpadApprovalLeaf: "poolsLbpLaunchpadApprovalProof",
  ponsV2PairBuybackApprovalLeaf: "ponsV2PairBuybackApprovalProof",
  flapBuybackApprovalLeaf: "flapBuybackApprovalProof",
  flapPayoutApprovalLeaf: "flapPayoutApprovalProof",
};
for (const [leafField, proofField] of Object.entries(proofFields)) {
  const computedRoot = processProof(manifest[leafField], manifest[proofField]);
  if (computedRoot.toLowerCase() !== manifest.integrationApprovalRoot.toLowerCase()) {
    throw new Error(`release manifest '${proofField}' does not reconstruct integrationApprovalRoot`);
  }
}

for (const [key, value] of Object.entries(manifest)) {
  if (key.endsWith("RuntimeHash") || key.endsWith("CodeHash") || key === "integrationApprovalRoot") {
    if (!bytes32Pattern.test(value)) throw new Error(`release manifest '${key}' is not bytes32`);
  }
  if (
    key.endsWith("Factory") || key.endsWith("Manager") || key.endsWith("Implementation")
      || key.endsWith("Adapter") || key.endsWith("Guard") || key.endsWith("Oracle")
      || key.endsWith("Aggregator") || key.endsWith("Asset")
      || ["broadcaster", "protocolFeeRecipient", "registry", "deploymentEngine",
        "launchValidator", "launcher", "ponsProjectTokenFactory", "launchpadProjectTokenFactory",
        "ponsLaunchFactory", "poolsProjectRegistrationHelper",
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
