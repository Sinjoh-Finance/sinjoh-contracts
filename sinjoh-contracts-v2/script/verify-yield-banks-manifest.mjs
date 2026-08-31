import { readFile } from "node:fs/promises";
import { createRequire } from "node:module";

const requireFromSdk = createRequire(new URL("../sdk/package.json", import.meta.url));
const { createPublicClient, getAddress, http, keccak256, stringToHex } = requireFromSdk("viem");

const manifestPath = process.argv[2];
const rpcUrl = process.argv[3] ?? process.env.YIELD_BANK_RPC_URL;
if (!manifestPath || !rpcUrl) {
  throw new Error("usage: node script/verify-yield-banks-manifest.mjs <manifest.json> <rpc-url>");
}
const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
const client = createPublicClient({ transport: http(rpcUrl) });
const bytes32 = /^0x[0-9a-fA-F]{64}$/;
const zeroBytes32 = `0x${"0".repeat(64)}`;
const expectedDependencies = {
  WETH: "0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73",
  USDG: "0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168",
  seaDrop: "0x00005EA00Ac477B1030CE78506496e8C2dE24bf5",
  seaport: "0x0000000000000068F116a894984e2DB1123eB395",
};
const requiredContracts = [
  "registry", "factoryDeployer", "factory", "collection", "nft", "accountImplementation",
  "proceedsVault", "distributor", "revenueRouter", "operationsReserve", "timelock",
  "allocator", "priceHub", "strategyRegistry", "renderer", "coreSleeve",
  "marketMakingSleeve", "usdgSleeve",
];
const assert = (condition, message) => { if (!condition) throw new Error(message); };
const hashText = (value) => keccak256(stringToHex(value));
const sameAddress = (left, right) => getAddress(left) === getAddress(right);

assert(manifest.schemaVersion === "1.0", "unsupported Yield Banks manifest schema");
assert(manifest.chainId === 4663 || manifest.chainId === 46630, "unsupported chainId");
assert(bytes32.test(manifest.collectionId), "collectionId must be bytes32");
assert(Number(await client.getChainId()) === manifest.chainId, "RPC chain does not match manifest");
assert(Number.isSafeInteger(manifest.economics.maxSupply) && manifest.economics.maxSupply > 0,
  "maxSupply must be a positive safe integer");
const isBps = (value) => Number.isInteger(value) && value >= 0 && value <= 10_000;
for (const key of [
  "secondaryRoyaltyBps",
  "primaryBackingBps", "primaryCreatorBps", "primarySinjohBps", "primaryOperationsBps",
  "royaltyBackingBps", "royaltyCreatorBps", "royaltySinjohBps", "royaltyOperationsBps",
  "coreWeightBps", "marketMakingWeightBps", "usdgWeightBps",
]) assert(isBps(manifest.economics[key]), `economics.${key} must be integer basis points`);
assert(manifest.economics.primaryBackingBps > 0
  && manifest.economics.primaryBackingBps + manifest.economics.primaryCreatorBps
    + manifest.economics.primarySinjohBps + manifest.economics.primaryOperationsBps === 10_000,
"primary economics must sum to 10000 basis points with positive backing");
assert(manifest.economics.royaltyBackingBps > 0
  && manifest.economics.royaltyBackingBps + manifest.economics.royaltyCreatorBps
    + manifest.economics.royaltySinjohBps + manifest.economics.royaltyOperationsBps === 10_000,
"royalty economics must sum to 10000 basis points with positive backing");
assert(manifest.economics.coreWeightBps > 0 && manifest.economics.marketMakingWeightBps > 0
  && manifest.economics.usdgWeightBps > 0
  && manifest.economics.coreWeightBps + manifest.economics.marketMakingWeightBps
    + manifest.economics.usdgWeightBps === 10_000,
"portfolio weights must be positive and sum to 10000 basis points");
assert(manifest.economics.exitTaxBps === 500, "exit tax mismatch");
for (const key of requiredContracts) assert(manifest.contracts[key], `contracts.${key} missing`);
for (const [key, address] of Object.entries(expectedDependencies)) {
  assert(manifest.dependencies[key], `dependencies.${key} missing`);
  assert(sameAddress(manifest.dependencies[key].address, address), `dependencies.${key} mismatch`);
}
assert(manifest.equityModel
  && ["onchain-tokenized-equity", "offchain-custody-receipt"].includes(manifest.equityModel.custody)
  && ["balance-appreciation", "cash-distribution", "mixed"].includes(manifest.equityModel.income),
"equityModel must explicitly describe custody and income behavior");
assert(new URL(manifest.equityModel.disclosureUri).protocol === "https:",
  "equityModel.disclosureUri must be HTTPS");
assert(manifest.equityAssets.length >= 1, "at least one reviewed equity asset is required");
assert(Object.keys(manifest.feeds).length >= 1, "at least one reviewed feed is required");
assert(manifest.delta && Number.isInteger(manifest.delta.maximumPositions)
  && manifest.delta.maximumPositions >= 1 && manifest.delta.maximumPositions <= 64,
"delta.maximumPositions must be an integer from 1 through 64");
assert(isBps(manifest.delta.adapterCapBps) && manifest.delta.adapterCapBps > 0
  && manifest.delta.adapterCapBps <= manifest.policyCaps.marketMaking.maximumAdapterCapBps,
"delta.adapterCapBps exceeds the market-making sleeve policy");
assert(manifest.policyCaps.marketMaking.maximumStrategies >= 1,
  "Delta requires at least one market-making strategy slot");
const containsAddress = (records, address) => Object.values(records)
  .some((entry) => sameAddress(entry.address, address));
for (const [field, records] of [
  ["adapter", manifest.adapters], ["entryRoute", manifest.adapters],
  ["exitRoute", manifest.adapters], ["pool", manifest.pools],
  ["injoh", manifest.dependencies], ["positionBuilder", manifest.dependencies],
  ["factory", manifest.dependencies], ["positionManager", manifest.dependencies],
]) assert(containsAddress(records, manifest.delta[field]),
  `delta.${field} is not bound to its manifest group`);
assert(!sameAddress(manifest.delta.injoh, manifest.dependencies.WETH.address),
  "delta.injoh must differ from WETH");
assert(manifest.routeBindings && Array.isArray(manifest.routeBindings.allocations)
  && Array.isArray(manifest.routeBindings.rebalances), "routeBindings are required");
const allManifestEntries = [
  ...Object.values(manifest.dependencies), ...manifest.equityAssets,
  ...Object.values(manifest.adapters), ...Object.values(manifest.pools),
];
const manifestEntryFor = (address) => allManifestEntries.find((entry) => sameAddress(entry.address, address));
const allocationKeys = new Set();
for (const binding of manifest.routeBindings.allocations) {
  const key = `${getAddress(binding.inputAsset)}:${getAddress(binding.sleeve)}`;
  assert(!allocationKeys.has(key), `duplicate allocation route ${key}`);
  allocationKeys.add(key);
  const entry = manifestEntryFor(binding.route);
  assert(entry && entry.runtimeCodeHash.toLowerCase() === binding.runtimeCodeHash.toLowerCase(),
    `allocation route ${binding.route} is not a matching manifest dependency`);
}
for (const sleeve of [manifest.contracts.coreSleeve.address, manifest.contracts.usdgSleeve.address]) {
  assert(allocationKeys.has(`${getAddress(manifest.dependencies.WETH.address)}:${getAddress(sleeve)}`),
    `missing WETH allocation route for sleeve ${sleeve}`);
}
const rebalanceAssets = [
  manifest.dependencies.USDG.address, manifest.delta.injoh,
  ...manifest.equityAssets.map((entry) => entry.address),
];
const rebalanceKeys = new Set();
for (const binding of manifest.routeBindings.rebalances) {
  const key = getAddress(binding.inputAsset);
  assert(!rebalanceKeys.has(key), `duplicate rebalance route ${key}`);
  rebalanceKeys.add(key);
  const entry = manifestEntryFor(binding.route);
  assert(entry && entry.runtimeCodeHash.toLowerCase() === binding.runtimeCodeHash.toLowerCase(),
    `rebalance route ${binding.route} is not a matching manifest dependency`);
}
for (const asset of rebalanceAssets) {
  assert(rebalanceKeys.has(getAddress(asset)), `missing WETH rebalance route for ${asset}`);
}
for (const sleeve of ["core", "marketMaking", "usdg"]) {
  const policy = manifest.policyCaps[sleeve];
  assert(policy && Number.isInteger(policy.maximumStrategies)
    && policy.maximumStrategies >= 0 && policy.maximumStrategies <= 8,
  `policyCaps.${sleeve}.maximumStrategies must be an integer from 0 through 8`);
  assert(isBps(policy.maximumAdapterCapBps),
    `policyCaps.${sleeve}.maximumAdapterCapBps must be integer basis points`);
  assert(isBps(policy.maximumOperatorLossBps),
    `policyCaps.${sleeve}.maximumOperatorLossBps must be integer basis points`);
  assert(policy.maximumStrategies === 0 || policy.maximumAdapterCapBps > 0,
    `policyCaps.${sleeve} must permit a positive adapter cap when strategies are enabled`);
}
for (const key of [
  "factorySalt", "collectionSalt", "collectionConfigurationHash", "systemPlanHash",
  "collectionCreationCodeHash", "metadataBaseUriHash", "contractUriHash",
]) assert(bytes32.test(manifest.deployment[key]), `deployment.${key} must be bytes32`);
assert(manifest.deployment.factorySalt !== zeroBytes32
  && manifest.deployment.collectionSalt !== zeroBytes32, "deployment salts must be nonzero");
assert(hashText(manifest.deployment.metadataBaseUri).toLowerCase()
  === manifest.deployment.metadataBaseUriHash.toLowerCase(), "metadataBaseUri hash mismatch");
assert(hashText(manifest.deployment.contractUri).toLowerCase()
  === manifest.deployment.contractUriHash.toLowerCase(), "contractUri hash mismatch");
assert(manifest.openSea.collectionUrl
  === `https://opensea.io/collection/${manifest.openSea.collectionSlug}/overview`,
"OpenSea collection URL mismatch");
assert(sameAddress(manifest.openSea.creatorPayoutAddress, manifest.contracts.proceedsVault.address),
  "OpenSea creator payout must be the proceeds vault");
assert(manifest.openSea.observedSecondaryRoyaltyBps === manifest.economics.secondaryRoyaltyBps,
  "OpenSea secondary royalty rate must match the immutable collection rate");
assert(sameAddress(
  manifest.openSea.observedSecondaryRoyaltyRecipient,
  manifest.contracts.revenueRouter.address,
), "OpenSea secondary royalty recipient must be the collection revenue router");

const entries = [];
for (const [group, records] of Object.entries({
  contracts: manifest.contracts,
  dependencies: manifest.dependencies,
  adapters: manifest.adapters,
  feeds: manifest.feeds,
  pools: manifest.pools,
})) for (const [key, entry] of Object.entries(records)) entries.push([`${group}.${key}`, entry]);
manifest.equityAssets.forEach((entry, index) => entries.push([`equityAssets.${index}`, entry]));
for (const [path, entry] of entries) {
  getAddress(entry.address);
  assert(bytes32.test(entry.runtimeCodeHash), `${path}.runtimeCodeHash must be bytes32`);
  assert(entry.version && entry.provenance, `${path} version/provenance missing`);
  assert(bytes32.test(entry.deploymentTransaction), `${path}.deploymentTransaction must be bytes32`);
  assert(bytes32.test(entry.verificationTransaction), `${path}.verificationTransaction must be bytes32`);
  const code = await client.getCode({ address: entry.address });
  assert(code && code !== "0x", `${path} has no runtime code`);
  assert(keccak256(code).toLowerCase() === entry.runtimeCodeHash.toLowerCase(),
    `${path} runtime code hash mismatch`);
}

const factoryAbi = [
  { type: "function", name: "factoryVersion", stateMutability: "view", inputs: [], outputs: [{ type: "bytes32" }] },
  { type: "function", name: "collectionCreationCodeHash", stateMutability: "view", inputs: [], outputs: [{ type: "bytes32" }] },
  { type: "function", name: "systemPlanHash", stateMutability: "view", inputs: [], outputs: [{ type: "bytes32" }] },
];
const deployerAbi = [
  { type: "function", name: "predict", stateMutability: "view", inputs: [{ type: "bytes32" }], outputs: [{ type: "address" }] },
];
const collectionAbi = [
  { type: "function", name: "collectionId", stateMutability: "view", inputs: [], outputs: [{ type: "bytes32" }] },
  { type: "function", name: "maxSupply", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "nft", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "distributor", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "proceedsVault", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "portfolioAllocator", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "accountImplementation", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "secondaryRoyaltyBps", stateMutability: "view", inputs: [], outputs: [{ type: "uint96" }] },
  ...[
    "primaryBackingBps", "primaryCreatorBps", "primarySinjohBps", "primaryOperationsBps",
    "coreWeightBps", "marketMakingWeightBps", "usdgWeightBps",
  ].map((name) => ({ type: "function", name, stateMutability: "view", inputs: [], outputs: [{ type: "uint16" }] })),
];
const nftAbi = [
  { type: "function", name: "maxSupply", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "seaDrop", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "collection", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "royaltyReceiver", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "royaltyBps", stateMutability: "view", inputs: [], outputs: [{ type: "uint96" }] },
];
const vaultAbi = [
  { type: "function", name: "allocationOperator", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
];
const sleeveAbi = [
  { type: "function", name: "maximumStrategies", stateMutability: "view", inputs: [], outputs: [{ type: "uint8" }] },
  { type: "function", name: "maximumAdapterCapBps", stateMutability: "view", inputs: [], outputs: [{ type: "uint16" }] },
  { type: "function", name: "maximumOperatorLossBps", stateMutability: "view", inputs: [], outputs: [{ type: "uint16" }] },
];
const revenueRouterAbi = [
  ...[
    "royaltyBackingBps", "royaltyCreatorBps", "royaltySinjohBps", "royaltyOperationsBps",
  ].map((name) => ({ type: "function", name, stateMutability: "view", inputs: [], outputs: [{ type: "uint16" }] })),
];
const registryAbi = [
  { type: "function", name: "collections", stateMutability: "view", inputs: [{ type: "address" }], outputs: [
    { type: "address" }, { type: "bytes32" }, { type: "bytes32" }, { type: "bytes32" },
    { type: "uint48" }, { type: "bool" },
  ] },
];
const deltaAdapterAbi = [
  ...[
    "sleeve", "accountingAsset", "injoh", "priceHub", "pool", "factory",
    "positionManager", "positionBuilder", "entryRoute", "exitRoute",
  ].map((name) => ({ type: "function", name, stateMutability: "view", inputs: [], outputs: [{ type: "address" }] })),
  { type: "function", name: "maximumPositions", stateMutability: "view", inputs: [], outputs: [{ type: "uint8" }] },
];
const strategyRegistryAbi = [
  { type: "function", name: "recordOf", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "tuple", components: [
    { name: "implementation", type: "address" }, { name: "runtimeCodeHash", type: "bytes32" },
    { name: "sleeveCategory", type: "bytes32" }, { name: "accountingAsset", type: "address" },
    { name: "state", type: "uint8" }, { name: "registeredAt", type: "uint48" },
  ] }] },
];
const allocatorAbi = [
  { type: "function", name: "routeBinding", stateMutability: "view", inputs: [
    { type: "address" }, { type: "address" },
  ], outputs: [{ type: "address" }, { type: "bytes32" }] },
  { type: "function", name: "rebalanceRoute", stateMutability: "view", inputs: [
    { type: "address" },
  ], outputs: [{ type: "address" }, { type: "bytes32" }] },
];
const sleeveAdapterAbi = [
  { type: "function", name: "adapterState", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "uint8" }] },
  { type: "function", name: "adapterCapBps", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "uint16" }] },
];
const read = (address, abi, functionName, args = []) => client.readContract({
  address, abi, functionName, args,
});
const factory = manifest.contracts.factory.address;
const [predictedFactory, factoryVersion, collectionCodeHash, systemPlanHash,
  collectionId, collectionMaxSupply, collectionNft, collectionDistributor,
  collectionProceedsVault, collectionAccountImplementation, collectionSecondaryRoyaltyBps, nftMaxSupply, nftSeaDrop, nftCollection, nftRoyaltyReceiver,
  nftRoyaltyBps, allocationOperator, collectionRecord, ...onchainEconomicValues] = await Promise.all([
  read(manifest.contracts.factoryDeployer.address, deployerAbi, "predict", [manifest.deployment.factorySalt]),
  read(factory, factoryAbi, "factoryVersion"),
  read(factory, factoryAbi, "collectionCreationCodeHash"),
  read(factory, factoryAbi, "systemPlanHash"),
  read(manifest.contracts.collection.address, collectionAbi, "collectionId"),
  read(manifest.contracts.collection.address, collectionAbi, "maxSupply"),
  read(manifest.contracts.collection.address, collectionAbi, "nft"),
  read(manifest.contracts.collection.address, collectionAbi, "distributor"),
  read(manifest.contracts.collection.address, collectionAbi, "proceedsVault"),
  read(manifest.contracts.collection.address, collectionAbi, "accountImplementation"),
  read(manifest.contracts.collection.address, collectionAbi, "secondaryRoyaltyBps"),
  read(manifest.contracts.nft.address, nftAbi, "maxSupply"),
  read(manifest.contracts.nft.address, nftAbi, "seaDrop"),
  read(manifest.contracts.nft.address, nftAbi, "collection"),
  read(manifest.contracts.nft.address, nftAbi, "royaltyReceiver"),
  read(manifest.contracts.nft.address, nftAbi, "royaltyBps"),
  read(manifest.contracts.proceedsVault.address, vaultAbi, "allocationOperator"),
  read(manifest.contracts.registry.address, registryAbi, "collections", [manifest.contracts.collection.address]),
  ...[
    "primaryBackingBps", "primaryCreatorBps", "primarySinjohBps", "primaryOperationsBps",
    "coreWeightBps", "marketMakingWeightBps", "usdgWeightBps",
  ].map((name) => read(manifest.contracts.collection.address, collectionAbi, name)),
  ...[
    "royaltyBackingBps", "royaltyCreatorBps", "royaltySinjohBps", "royaltyOperationsBps",
  ].map((name) => read(manifest.contracts.revenueRouter.address, revenueRouterAbi, name)),
]);
assert(sameAddress(predictedFactory, factory), "factory salt does not predict manifest factory");
assert(factoryVersion.toLowerCase() === manifest.factoryVersion.toLowerCase(), "factory version mismatch");
assert(collectionCodeHash.toLowerCase() === manifest.deployment.collectionCreationCodeHash.toLowerCase(),
  "collection creation code hash mismatch");
assert(systemPlanHash.toLowerCase() === manifest.deployment.systemPlanHash.toLowerCase(),
  "system plan hash mismatch");
assert(collectionRecord[2].toLowerCase() === manifest.deployment.collectionConfigurationHash.toLowerCase(),
  "collection configuration hash mismatch");
assert(sameAddress(collectionRecord[0], factory)
  && collectionRecord[1].toLowerCase() === manifest.factoryVersion.toLowerCase()
  && collectionRecord[3].toLowerCase() === manifest.contracts.collection.runtimeCodeHash.toLowerCase()
  && collectionRecord[5] === true, "collection registry record mismatch");
assert(collectionId.toLowerCase() === manifest.collectionId.toLowerCase(), "collectionId mismatch");
assert(collectionMaxSupply === BigInt(manifest.economics.maxSupply)
  && nftMaxSupply === BigInt(manifest.economics.maxSupply), "onchain maxSupply mismatch");
assert(collectionSecondaryRoyaltyBps === BigInt(manifest.economics.secondaryRoyaltyBps),
  "collection secondary royalty mismatch");
assert(sameAddress(collectionProceedsVault, manifest.contracts.proceedsVault.address),
  "collection proceeds vault mismatch");
assert(sameAddress(collectionAccountImplementation, manifest.contracts.accountImplementation.address),
  "collection account implementation mismatch");
assert(sameAddress(
  await read(manifest.contracts.collection.address, collectionAbi, "portfolioAllocator"),
  manifest.contracts.allocator.address,
), "collection portfolio allocator mismatch");
assert(sameAddress(collectionNft, manifest.contracts.nft.address), "collection NFT mismatch");
assert(sameAddress(collectionDistributor, manifest.contracts.distributor.address),
  "collection distributor mismatch");
assert(sameAddress(nftSeaDrop, manifest.dependencies.seaDrop.address), "NFT SeaDrop mismatch");
assert(sameAddress(nftCollection, manifest.contracts.collection.address), "NFT collection mismatch");
assert(sameAddress(nftRoyaltyReceiver, manifest.contracts.revenueRouter.address)
  && Number(nftRoyaltyBps) === manifest.economics.secondaryRoyaltyBps,
"NFT royalty receiver or rate mismatch");
assert(sameAddress(allocationOperator, manifest.roles.allocationOperator),
  "allocation operator mismatch");
const collectionEconomicKeys = [
  "primaryBackingBps", "primaryCreatorBps", "primarySinjohBps", "primaryOperationsBps",
  "coreWeightBps", "marketMakingWeightBps", "usdgWeightBps",
];
const royaltyEconomicKeys = [
  "royaltyBackingBps", "royaltyCreatorBps", "royaltySinjohBps", "royaltyOperationsBps",
];
collectionEconomicKeys.forEach((key, index) => assert(
  onchainEconomicValues[index] === BigInt(manifest.economics[key]), `onchain ${key} mismatch`,
));
royaltyEconomicKeys.forEach((key, index) => assert(
  onchainEconomicValues[collectionEconomicKeys.length + index]
    === BigInt(manifest.economics[key]), `onchain ${key} mismatch`,
));
for (const [key, contractKey] of [
  ["core", "coreSleeve"],
  ["marketMaking", "marketMakingSleeve"],
  ["usdg", "usdgSleeve"],
]) {
  const policy = manifest.policyCaps[key];
  const sleeve = manifest.contracts[contractKey].address;
  const [maximumStrategies, maximumAdapterCapBps, maximumOperatorLossBps] = await Promise.all([
    read(sleeve, sleeveAbi, "maximumStrategies"),
    read(sleeve, sleeveAbi, "maximumAdapterCapBps"),
    read(sleeve, sleeveAbi, "maximumOperatorLossBps"),
  ]);
  assert(Number(maximumStrategies) === policy.maximumStrategies,
    `${key} maximumStrategies mismatch`);
  assert(Number(maximumAdapterCapBps) === policy.maximumAdapterCapBps,
    `${key} maximumAdapterCapBps mismatch`);
  assert(Number(maximumOperatorLossBps) === policy.maximumOperatorLossBps,
    `${key} maximumOperatorLossBps mismatch`);
}

const deltaAddressFields = [
  ["sleeve", manifest.contracts.marketMakingSleeve.address],
  ["accountingAsset", manifest.dependencies.WETH.address],
  ["injoh", manifest.delta.injoh],
  ["priceHub", manifest.contracts.priceHub.address],
  ["pool", manifest.delta.pool],
  ["factory", manifest.delta.factory],
  ["positionManager", manifest.delta.positionManager],
  ["positionBuilder", manifest.delta.positionBuilder],
  ["entryRoute", manifest.delta.entryRoute],
  ["exitRoute", manifest.delta.exitRoute],
];
const [deltaAddresses, maximumPositions, strategyRecord, sleeveAdapterState, sleeveAdapterCap] =
  await Promise.all([
    Promise.all(deltaAddressFields.map(([field]) =>
      read(manifest.delta.adapter, deltaAdapterAbi, field))),
    read(manifest.delta.adapter, deltaAdapterAbi, "maximumPositions"),
    read(manifest.contracts.strategyRegistry.address, strategyRegistryAbi, "recordOf", [manifest.delta.adapter]),
    read(manifest.contracts.marketMakingSleeve.address, sleeveAdapterAbi, "adapterState", [manifest.delta.adapter]),
    read(manifest.contracts.marketMakingSleeve.address, sleeveAdapterAbi, "adapterCapBps", [manifest.delta.adapter]),
  ]);
deltaAddressFields.forEach(([field, expected], index) => assert(
  sameAddress(deltaAddresses[index], expected), `Delta adapter ${field} mismatch`,
));
assert(Number(maximumPositions) === manifest.delta.maximumPositions,
  "Delta adapter maximumPositions mismatch");
assert(sameAddress(strategyRecord[0], manifest.delta.adapter)
  && sameAddress(strategyRecord[3], manifest.dependencies.WETH.address)
  && strategyRecord[1].toLowerCase()
    === manifest.adapters[Object.keys(manifest.adapters).find((key) =>
      sameAddress(manifest.adapters[key].address, manifest.delta.adapter))].runtimeCodeHash.toLowerCase()
  && strategyRecord[2].toLowerCase()
    === keccak256(stringToHex("YIELD_BANK_MARKET_MAKING")).toLowerCase()
  && Number(strategyRecord[4]) === 1,
"Delta adapter is not registered with the expected category, asset, and runtime");
assert(Number(sleeveAdapterState) === 3, "Delta adapter is not ACTIVE in the market-making sleeve");
assert(Number(sleeveAdapterCap) === manifest.delta.adapterCapBps,
  "Delta adapter cap does not match the manifest");
for (const binding of manifest.routeBindings.allocations) {
  const actual = await read(manifest.contracts.allocator.address, allocatorAbi, "routeBinding", [
    binding.inputAsset, binding.sleeve,
  ]);
  assert(sameAddress(actual[0], binding.route)
    && actual[1].toLowerCase() === binding.runtimeCodeHash.toLowerCase(),
  `allocation route binding mismatch for ${binding.inputAsset} -> ${binding.sleeve}`);
}
for (const binding of manifest.routeBindings.rebalances) {
  const actual = await read(manifest.contracts.allocator.address, allocatorAbi, "rebalanceRoute", [
    binding.inputAsset,
  ]);
  assert(sameAddress(actual[0], binding.route)
    && actual[1].toLowerCase() === binding.runtimeCodeHash.toLowerCase(),
  `rebalance route binding mismatch for ${binding.inputAsset}`);
}

console.log(JSON.stringify({
  status: "verified",
  manifest: manifestPath,
  chainId: manifest.chainId,
  collection: manifest.contracts.collection.address,
  nft: manifest.contracts.nft.address,
  proceedsVault: manifest.contracts.proceedsVault.address,
  deltaAdapter: manifest.delta.adapter,
  contractsVerified: entries.length,
}, null, 2));
