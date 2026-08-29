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
assert(Number(await client.getChainId()) === manifest.chainId, "RPC chain does not match manifest");
assert(Number.isSafeInteger(manifest.economics.maxSupply) && manifest.economics.maxSupply > 0,
  "maxSupply must be a positive safe integer");
const isBps = (value) => Number.isInteger(value) && value >= 0 && value <= 10_000;
for (const key of [
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
assert(manifest.stockTokens.length >= 1, "at least one reviewed Stock Token is required");
assert(Object.keys(manifest.feeds).length >= 1, "at least one reviewed feed is required");
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

const entries = [];
for (const [group, records] of Object.entries({
  contracts: manifest.contracts,
  dependencies: manifest.dependencies,
  adapters: manifest.adapters,
  feeds: manifest.feeds,
  pools: manifest.pools,
})) for (const [key, entry] of Object.entries(records)) entries.push([`${group}.${key}`, entry]);
manifest.stockTokens.forEach((entry, index) => entries.push([`stockTokens.${index}`, entry]));
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
  { type: "function", name: "maxSupply", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "proceedsVault", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  ...[
    "primaryBackingBps", "primaryCreatorBps", "primarySinjohBps", "primaryOperationsBps",
    "coreWeightBps", "marketMakingWeightBps", "usdgWeightBps",
  ].map((name) => ({ type: "function", name, stateMutability: "view", inputs: [], outputs: [{ type: "uint16" }] })),
];
const nftAbi = [
  { type: "function", name: "maxSupply", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "seaDrop", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
];
const vaultAbi = [
  { type: "function", name: "allocationOperator", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
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
const read = (address, abi, functionName, args = []) => client.readContract({
  address, abi, functionName, args,
});
const factory = manifest.contracts.factory.address;
const [predictedFactory, factoryVersion, collectionCodeHash, systemPlanHash,
  collectionMaxSupply, collectionProceedsVault, nftMaxSupply, nftSeaDrop,
  allocationOperator, collectionRecord, ...onchainEconomicValues] = await Promise.all([
  read(manifest.contracts.factoryDeployer.address, deployerAbi, "predict", [manifest.deployment.factorySalt]),
  read(factory, factoryAbi, "factoryVersion"),
  read(factory, factoryAbi, "collectionCreationCodeHash"),
  read(factory, factoryAbi, "systemPlanHash"),
  read(manifest.contracts.collection.address, collectionAbi, "maxSupply"),
  read(manifest.contracts.collection.address, collectionAbi, "proceedsVault"),
  read(manifest.contracts.nft.address, nftAbi, "maxSupply"),
  read(manifest.contracts.nft.address, nftAbi, "seaDrop"),
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
assert(collectionRecord[5] === true, "collection is not registered");
assert(collectionMaxSupply === BigInt(manifest.economics.maxSupply)
  && nftMaxSupply === BigInt(manifest.economics.maxSupply), "onchain maxSupply mismatch");
assert(sameAddress(collectionProceedsVault, manifest.contracts.proceedsVault.address),
  "collection proceeds vault mismatch");
assert(sameAddress(nftSeaDrop, manifest.dependencies.seaDrop.address), "NFT SeaDrop mismatch");
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

console.log(JSON.stringify({
  status: "verified",
  manifest: manifestPath,
  chainId: manifest.chainId,
  collection: manifest.contracts.collection.address,
  nft: manifest.contracts.nft.address,
  proceedsVault: manifest.contracts.proceedsVault.address,
  contractsVerified: entries.length,
}, null, 2));
