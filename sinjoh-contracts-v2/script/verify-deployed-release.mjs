import { readFile } from "node:fs/promises";
import { createRequire } from "node:module";

const requireFromSdk = createRequire(new URL("../sdk/package.json", import.meta.url));
const {
  createPublicClient,
  encodeAbiParameters,
  getAddress,
  http,
  keccak256,
  parseAbi,
  stringToHex,
} = requireFromSdk("viem");

const manifestPath = process.argv[2];
const rpcUrl = process.env.RPC_URL;
if (!manifestPath || !rpcUrl) {
  throw new Error("usage: RPC_URL=<url> node script/verify-deployed-release.mjs <manifest.json>");
}

const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
const client = createPublicClient({ transport: http(rpcUrl) });
const zeroAddress = `0x${"0".repeat(40)}`;
const zeroBytes32 = `0x${"0".repeat(64)}`;

const fail = (message) => {
  throw new Error(message);
};
const normalize = (value) => typeof value === "string" && value.startsWith("0x")
  ? value.toLowerCase()
  : value;
const assertEqual = (label, actual, expected) => {
  if (normalize(actual) !== normalize(expected)) {
    fail(`${label} is ${actual}, expected ${expected}`);
  }
};
const read = (address, abi, functionName, args = []) => client.readContract({
  address: getAddress(address),
  abi,
  functionName,
  args,
});
const verifyCodeHash = async (label, address, expectedHash) => {
  const code = await client.getBytecode({ address: getAddress(address) });
  if (!code || code === "0x") fail(`${label} has no runtime bytecode at ${address}`);
  assertEqual(`${label} runtime hash`, keccak256(code), expectedHash);
};

const launcherAbi = parseAbi([
  "function PROTOCOL_VERSION() view returns (uint32)",
  "function registry() view returns (address)",
  "function deployer() view returns (address)",
  "function validator() view returns (address)",
]);
const validatorAbi = parseAbi([
  "function registry() view returns (address)",
  "function deployer() view returns (address)",
]);
const registryAbi = parseAbi([
  "function PROTOCOL_VERSION() view returns (uint32)",
  "function launcher() view returns (address)",
  "function projectCount() view returns (uint256)",
]);
const deployerAbi = parseAbi([
  "function launcher() view returns (address)",
  "function registry() view returns (address)",
  "function protocolFeeRecipient() view returns (address)",
  "function integrationApprovalRoot() view returns (bytes32)",
  "function raffleImplementation() view returns (address)",
  "function randomnessAdapter() view returns (address)",
  "function basketEnabled() view returns (bool)",
  "function basketVaultImplementation() view returns (address)",
  "function erc4626YieldAdapterFactory() view returns (address)",
  "function fundingBandV3IntegrationFactory() view returns (address)",
  "function v3Factory() view returns (address)",
  "function v3PositionManager() view returns (address)",
  "function v4PositionManager() view returns (address)",
  "function v4StateView() view returns (address)",
  "function permit2() view returns (address)",
  "function creationCodeStore(bytes32) view returns (address)",
  "function creationCodeHash(bytes32) view returns (bytes32)",
]);
const bandFactoryAbi = parseAbi([
  "function v3Factory() view returns (address)",
  "function v3PositionManager() view returns (address)",
]);
const quoteOracleAbi = parseAbi([
  "function quoteAsset() view returns (address)",
  "function aggregator() view returns (address)",
  "function quoteAssetCodehash() view returns (bytes32)",
  "function aggregatorCodehash() view returns (bytes32)",
  "function latestPriceUsdE8() view returns (uint256 priceUsdE8, uint48 observedAt, bytes32 observationId)",
  "error OracleNotReady()",
]);
const underlyingOracleAbi = parseAbi([
  "function pool() view returns (address)",
  "function minimumLiquidity() view returns (uint128)",
]);
const v3PoolAbi = parseAbi(["function liquidity() view returns (uint128)"]);
const guardAbi = parseAbi([
  "function factory() view returns (address)",
  "function factoryCodehash() view returns (bytes32)",
  "function poolFee() view returns (uint24)",
  "function routeHash() view returns (bytes32)",
  "function twapWindow() view returns (uint32)",
  "function maxSpotDeviationBps() view returns (uint16)",
  "function maxOutputSlippageBps() view returns (uint16)",
  "function validityPeriod() view returns (uint48)",
  "function comparisonAmount() view returns (uint128)",
]);
const codeStoreAbi = parseAbi([
  "function creationCodeHash() view returns (bytes32)",
  "function creationCodeLength() view returns (uint256)",
  "function chunkCount() view returns (uint256)",
  "function chunkAt(uint256) view returns (address)",
]);
const raffleAbi = parseAbi(["function initialized() view returns (bool)"]);
const ponsProjectFactoryAbi = parseAbi([
  "function launchFactory() view returns (address)",
  "function projectLauncher() view returns (address)",
  "function projectRegistry() view returns (address)",
  "function projectTokenFactory() view returns (address)",
  "function projectImplementation() view returns (address)",
]);
const ponsLaunchFactoryAbi = parseAbi(["function launchForwarder() view returns (address)"]);
const poolsProjectFactoryAbi = parseAbi([
  "function projectLauncher() view returns (address)",
  "function projectRegistry() view returns (address)",
  "function projectTokenFactory() view returns (address)",
]);
const poolsLbpProjectFactoryAbi = parseAbi([
  "function projectLauncher() view returns (address)",
  "function projectRegistry() view returns (address)",
  "function projectTokenFactory() view returns (address)",
  "function projectRegistrationHelper() view returns (address)",
]);

assertEqual("chain id", await client.getChainId(), manifest.chainId);

const runtimeBindings = [
  ["registry", "registry", "registryRuntimeHash"],
  ["deployment engine", "deploymentEngine", "deploymentEngineRuntimeHash"],
  ["launch validator", "launchValidator", "launchValidatorRuntimeHash"],
  ["launcher", "launcher", "launcherRuntimeHash"],
  ["Pons project token factory", "ponsProjectTokenFactory", "ponsProjectTokenFactoryRuntimeHash"],
  ["launchpad project token factory", "launchpadProjectTokenFactory", "launchpadProjectTokenFactoryRuntimeHash"],
  ["Pons project adapter factory", "ponsProjectAdapterFactory", "ponsProjectAdapterFactoryRuntimeHash"],
  ["Pools Instant project adapter factory", "poolsInstantProjectAdapterFactory", "poolsInstantProjectAdapterFactoryRuntimeHash"],
  ["Pools LBP project adapter factory", "poolsLbpProjectAdapterFactory", "poolsLbpProjectAdapterFactoryRuntimeHash"],
  ["Pons project adapter implementation", "ponsProjectAdapterImplementation", "ponsProjectAdapterImplementationRuntimeHash"],
  ["Pools project registration helper", "poolsProjectRegistrationHelper", "poolsProjectRegistrationHelperRuntimeHash"],
  ["Pons launch factory", "ponsLaunchFactory", "ponsLaunchFactoryRuntimeHash"],
  ["raffle implementation", "raffleImplementation", "raffleImplementationRuntimeHash"],
  ["randomness adapter", "randomnessAdapter", "randomnessAdapterRuntimeHash"],
  ["project swap adapter", "projectSwapAdapter", "projectSwapAdapterRuntimeHash"],
  ["funding band integration factory", "fundingBandV3IntegrationFactory", "fundingBandV3IntegrationFactoryRuntimeHash"],
  ["funding band quote oracle", "fundingBandQuoteUsdOracle", "fundingBandQuoteUsdOracleRuntimeHash"],
  ["funding band quote asset", "fundingBandQuoteAsset", "fundingBandQuoteAssetRuntimeHash"],
  ["funding band USD aggregator", "fundingBandQuoteUsdAggregator", "fundingBandQuoteUsdAggregatorRuntimeHash"],
  ["V3 guard 500", "projectV3PriceGuard500", "projectV3PriceGuard500RuntimeHash"],
  ["V3 guard 3000", "projectV3PriceGuard3000", "projectV3PriceGuard3000RuntimeHash"],
  ["V3 guard 10000", "projectV3PriceGuard10000", "projectV3PriceGuard10000RuntimeHash"],
  ["V3 factory", "v3Factory", "v3FactoryRuntimeHash"],
  ["V3 position manager", "v3PositionManager", "v3PositionManagerRuntimeHash"],
  ["V4 position manager", "v4PositionManager", "v4PositionManagerRuntimeHash"],
  ["V4 state view", "v4StateView", "v4StateViewRuntimeHash"],
  ["Permit2", "permit2", "permit2RuntimeHash"],
];
await Promise.all(runtimeBindings.map(([label, addressKey, hashKey]) =>
  verifyCodeHash(label, manifest[addressKey], manifest[hashKey])));

assertEqual("launcher protocol version", await read(manifest.launcher, launcherAbi, "PROTOCOL_VERSION"), manifest.protocolVersion);
assertEqual("launcher registry", await read(manifest.launcher, launcherAbi, "registry"), manifest.registry);
assertEqual("launcher deployment engine", await read(manifest.launcher, launcherAbi, "deployer"), manifest.deploymentEngine);
assertEqual("launcher validator", await read(manifest.launcher, launcherAbi, "validator"), manifest.launchValidator);
assertEqual("validator registry", await read(manifest.launchValidator, validatorAbi, "registry"), manifest.registry);
assertEqual("validator deployment engine", await read(manifest.launchValidator, validatorAbi, "deployer"), manifest.deploymentEngine);
assertEqual("registry protocol version", await read(manifest.registry, registryAbi, "PROTOCOL_VERSION"), manifest.protocolVersion);
assertEqual("registry launcher", await read(manifest.registry, registryAbi, "launcher"), manifest.launcher);

for (const [label, address, abi, expectedTokenFactory] of [
  ["Pons", manifest.ponsProjectAdapterFactory, ponsProjectFactoryAbi, manifest.ponsProjectTokenFactory],
  ["Pools Instant", manifest.poolsInstantProjectAdapterFactory, poolsProjectFactoryAbi, manifest.launchpadProjectTokenFactory],
  ["Pools LBP", manifest.poolsLbpProjectAdapterFactory, poolsLbpProjectFactoryAbi, manifest.launchpadProjectTokenFactory],
]) {
  assertEqual(`${label} project launcher binding`, await read(address, abi, "projectLauncher"), manifest.launcher);
  assertEqual(`${label} project registry binding`, await read(address, abi, "projectRegistry"), manifest.registry);
  assertEqual(`${label} project token factory binding`, await read(address, abi, "projectTokenFactory"), expectedTokenFactory);
}
assertEqual(
  "Pons project implementation binding",
  await read(manifest.ponsProjectAdapterFactory, ponsProjectFactoryAbi, "projectImplementation"),
  manifest.ponsProjectAdapterImplementation,
);
assertEqual(
  "Pons launch factory binding",
  await read(manifest.ponsProjectAdapterFactory, ponsProjectFactoryAbi, "launchFactory"),
  manifest.ponsLaunchFactory,
);
assertEqual(
  "Pons launch forwarder",
  await read(manifest.ponsLaunchFactory, ponsLaunchFactoryAbi, "launchForwarder"),
  manifest.ponsProjectAdapterFactory,
);
assertEqual(
  "Pools LBP registration helper binding",
  await read(manifest.poolsLbpProjectAdapterFactory, poolsLbpProjectFactoryAbi, "projectRegistrationHelper"),
  manifest.poolsProjectRegistrationHelper,
);

const engineChecks = [
  ["engine launcher", "launcher", manifest.launcher],
  ["engine registry", "registry", manifest.registry],
  ["protocol fee recipient", "protocolFeeRecipient", manifest.protocolFeeRecipient],
  ["integration approval root", "integrationApprovalRoot", manifest.integrationApprovalRoot],
  ["raffle implementation", "raffleImplementation", manifest.raffleImplementation],
  ["randomness adapter", "randomnessAdapter", manifest.randomnessAdapter],
  ["basket enabled", "basketEnabled", false],
  ["basket vault implementation", "basketVaultImplementation", zeroAddress],
  ["ERC-4626 adapter factory", "erc4626YieldAdapterFactory", zeroAddress],
  ["funding band integration factory", "fundingBandV3IntegrationFactory", manifest.fundingBandV3IntegrationFactory],
  ["V3 factory", "v3Factory", manifest.v3Factory],
  ["V3 position manager", "v3PositionManager", manifest.v3PositionManager],
  ["V4 position manager", "v4PositionManager", manifest.v4PositionManager],
  ["V4 state view", "v4StateView", manifest.v4StateView],
  ["Permit2", "permit2", manifest.permit2],
];
for (const [label, functionName, expected] of engineChecks) {
  assertEqual(label, await read(manifest.deploymentEngine, deployerAbi, functionName), expected);
}
if (normalize(manifest.integrationApprovalRoot) === zeroBytes32) {
  fail("integration approval root is zero");
}
assertEqual("raffle implementation initialization lock", await read(manifest.raffleImplementation, raffleAbi, "initialized"), true);

assertEqual(
  "funding band factory V3 factory",
  await read(manifest.fundingBandV3IntegrationFactory, bandFactoryAbi, "v3Factory"),
  manifest.v3Factory,
);
assertEqual(
  "funding band factory V3 position manager",
  await read(manifest.fundingBandV3IntegrationFactory, bandFactoryAbi, "v3PositionManager"),
  manifest.v3PositionManager,
);

assertEqual("quote oracle asset", await read(manifest.fundingBandQuoteUsdOracle, quoteOracleAbi, "quoteAsset"), manifest.fundingBandQuoteAsset);
assertEqual("quote oracle aggregator", await read(manifest.fundingBandQuoteUsdOracle, quoteOracleAbi, "aggregator"), manifest.fundingBandQuoteUsdAggregator);
assertEqual("quote oracle asset hash pin", await read(manifest.fundingBandQuoteUsdOracle, quoteOracleAbi, "quoteAssetCodehash"), manifest.fundingBandQuoteAssetRuntimeHash);
assertEqual("quote oracle aggregator hash pin", await read(manifest.fundingBandQuoteUsdOracle, quoteOracleAbi, "aggregatorCodehash"), manifest.fundingBandQuoteUsdAggregatorRuntimeHash);
let priceUsdE8;
let observedAt;
let oracleReadiness = "ready";
let oracleReadinessDetail = "";
try {
  const observation = await read(
    manifest.fundingBandQuoteUsdOracle,
    quoteOracleAbi,
    "latestPriceUsdE8",
  );
  [priceUsdE8, observedAt] = observation;
  const observationId = observation[2];
  if (priceUsdE8 <= 0n || observedAt <= 0n || observationId === zeroBytes32) {
    fail("funding band quote oracle returned an invalid live observation");
  }
} catch (error) {
  if (!String(error).includes("OracleNotReady") && !String(error).includes("0x6e155fc6")) {
    throw error;
  }
  oracleReadiness = "not-ready";
  const pool = await read(
    manifest.fundingBandQuoteUsdAggregator,
    underlyingOracleAbi,
    "pool",
  );
  const minimumLiquidity = await read(
    manifest.fundingBandQuoteUsdAggregator,
    underlyingOracleAbi,
    "minimumLiquidity",
  );
  const activeLiquidity = await read(pool, v3PoolAbi, "liquidity");
  if (activeLiquidity >= minimumLiquidity) {
    fail("funding band oracle is not ready even though active liquidity meets its floor");
  }
  oracleReadinessDetail = ` pool=${pool} activeLiquidity=${activeLiquidity} minimumLiquidity=${minimumLiquidity}`;
}

for (const [fee, addressKey] of [
  [500, "projectV3PriceGuard500"],
  [3000, "projectV3PriceGuard3000"],
  [10000, "projectV3PriceGuard10000"],
]) {
  const address = manifest[addressKey];
  assertEqual(`guard ${fee} factory`, await read(address, guardAbi, "factory"), manifest.v3Factory);
  assertEqual(`guard ${fee} factory hash pin`, await read(address, guardAbi, "factoryCodehash"), manifest.v3FactoryRuntimeHash);
  assertEqual(`guard ${fee} pool fee`, await read(address, guardAbi, "poolFee"), fee);
  assertEqual(
    `guard ${fee} route hash`,
    await read(address, guardAbi, "routeHash"),
    keccak256(encodeAbiParameters([{ type: "uint24" }], [fee])),
  );
  assertEqual(`guard ${fee} TWAP window`, await read(address, guardAbi, "twapWindow"), 900);
  assertEqual(`guard ${fee} max spot deviation`, await read(address, guardAbi, "maxSpotDeviationBps"), 1000);
  assertEqual(`guard ${fee} max output slippage`, await read(address, guardAbi, "maxOutputSlippageBps"), 750);
  assertEqual(`guard ${fee} validity period`, await read(address, guardAbi, "validityPeriod"), 300);
  assertEqual(`guard ${fee} comparison amount`, await read(address, guardAbi, "comparisonAmount"), 10n ** 18n);
}

const moduleBindings = [
  ["TOKEN", "tokenCreationCodeHash"],
  ["MULTISIG", "multisigCreationCodeHash"],
  ["TIMELOCK", "timelockCreationCodeHash"],
  ["STAKING", "stakingCreationCodeHash"],
  ["TREASURY", "treasuryCreationCodeHash"],
  ["AIRDROP", "airdropCreationCodeHash"],
  ["ROUTER", "routerCreationCodeHash"],
  ["BANDS", "bandsCreationCodeHash"],
  ["LIQUIDITY", "liquidityCreationCodeHash"],
];
for (const [moduleName, manifestHashKey] of moduleBindings) {
  const moduleKey = keccak256(stringToHex(moduleName));
  const expectedHash = manifest[manifestHashKey];
  const store = await read(manifest.deploymentEngine, deployerAbi, "creationCodeStore", [moduleKey]);
  if (normalize(store) === zeroAddress) fail(`${moduleName} creation-code store is zero`);
  assertEqual(
    `${moduleName} engine creation-code hash`,
    await read(manifest.deploymentEngine, deployerAbi, "creationCodeHash", [moduleKey]),
    expectedHash,
  );
  assertEqual(`${moduleName} store creation-code hash`, await read(store, codeStoreAbi, "creationCodeHash"), expectedHash);
  const length = await read(store, codeStoreAbi, "creationCodeLength");
  const chunkCount = await read(store, codeStoreAbi, "chunkCount");
  if (length <= 0n || chunkCount <= 0n) fail(`${moduleName} creation-code store is empty`);
  for (let index = 0n; index < chunkCount; index += 1n) {
    const chunk = await read(store, codeStoreAbi, "chunkAt", [index]);
    const chunkCode = await client.getBytecode({ address: chunk });
    if (!chunkCode || chunkCode === "0x" || !chunkCode.startsWith("0x00")) {
      fail(`${moduleName} creation-code chunk ${index} is missing or executable`);
    }
  }
}

const projectCount = await read(manifest.registry, registryAbi, "projectCount");
console.log(`verified deployed release ${manifestPath}`);
console.log(
  `chain=${manifest.chainId} registryProjects=${projectCount} fundingBandsOracle=${oracleReadiness}`
    + (oracleReadiness === "ready"
      ? ` liveQuoteUsdE8=${priceUsdE8} observedAt=${observedAt}`
      : oracleReadinessDetail),
);
