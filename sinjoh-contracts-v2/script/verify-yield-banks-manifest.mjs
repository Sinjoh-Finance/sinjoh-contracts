import { readFile } from "node:fs/promises";
import { createRequire } from "node:module";

const requireFromSdk = createRequire(new URL("../sdk/package.json", import.meta.url));
const { createPublicClient, encodeAbiParameters, getAddress, http, keccak256, stringToHex } = requireFromSdk("viem");

const manifestPath = process.argv[2];
const rpcUrl = process.argv[3] ?? process.env.YIELD_BANK_RPC_URL;
if (!manifestPath || !rpcUrl) {
  throw new Error("usage: node script/verify-yield-banks-manifest.mjs <manifest.json> <rpc-url>");
}
const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
const client = createPublicClient({ transport: http(rpcUrl) });
const bytes32 = /^0x[0-9a-fA-F]{64}$/;
const zeroBytes32 = `0x${"0".repeat(64)}`;
const EIP1967_IMPLEMENTATION_SLOT =
  "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";
const EIP1967_BEACON_SLOT =
  "0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50";
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
assert(manifest.chainId === 4663, "Yield Banks release manifests require Robinhood mainnet chain 4663");
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
assert(manifest.equityModel.custody !== "onchain-tokenized-equity"
  || manifest.equityModel.income === "balance-appreciation",
"Robinhood Stock Token income must use the multiplier-aware balance-appreciation model");
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
const canonicalAddresses = (addresses) => [...new Set(addresses.map((address) => getAddress(address)))]
  .sort((left, right) => left.toLowerCase().localeCompare(right.toLowerCase()));
const publicDrop = manifest.openSea.publicDrop;
assert(publicDrop && /^\d+$/.test(publicDrop.mintPrice)
  && BigInt(publicDrop.mintPrice) > 0n && BigInt(publicDrop.mintPrice) < (1n << 80n)
  && Number.isSafeInteger(publicDrop.startTime) && publicDrop.startTime >= 0
  && Number.isSafeInteger(publicDrop.endTime) && publicDrop.endTime > publicDrop.startTime
  && Number.isInteger(publicDrop.maxTotalMintableByWallet)
  && publicDrop.maxTotalMintableByWallet >= 1 && publicDrop.maxTotalMintableByWallet <= 65_535
  && isBps(publicDrop.feeBps) && publicDrop.feeBps < 10_000
  && typeof publicDrop.restrictFeeRecipients === "boolean",
"OpenSea public drop configuration is invalid");
const allowedFeeRecipients = canonicalAddresses(manifest.openSea.allowedFeeRecipients);
assert(allowedFeeRecipients.length === manifest.openSea.allowedFeeRecipients.length,
  "OpenSea allowed fee recipients must be unique");
assert(!publicDrop.restrictFeeRecipients || allowedFeeRecipients.length > 0,
  "restricted SeaDrop stages require an allowed fee recipient");
assert(manifest.openSea.allowListMerkleRoot === zeroBytes32,
  "YieldBankNFT rejects nonempty SeaDrop allowlists because their price and fee are not callback-bound");
const allowedPayers = canonicalAddresses(manifest.openSea.allowedPayers);
assert(allowedPayers.length === manifest.openSea.allowedPayers.length,
  "OpenSea allowed payers must be unique");
const tokenGatedDrops = [...manifest.openSea.tokenGatedDrops]
  .map((stage) => ({ ...stage, allowedNftToken: getAddress(stage.allowedNftToken) }))
  .sort((left, right) => left.allowedNftToken.toLowerCase()
    .localeCompare(right.allowedNftToken.toLowerCase()));
assert(new Set(tokenGatedDrops.map((stage) => stage.allowedNftToken)).size
  === tokenGatedDrops.length, "SeaDrop token-gated assets must be unique");
for (const stage of tokenGatedDrops) {
  assert(/^\d+$/.test(stage.mintPrice) && BigInt(stage.mintPrice) > 0n
    && BigInt(stage.mintPrice) < (1n << 80n)
    && Number.isInteger(stage.maxTotalMintableByWallet)
    && stage.maxTotalMintableByWallet >= 1 && stage.maxTotalMintableByWallet <= 65_535
    && Number.isSafeInteger(stage.startTime) && stage.startTime >= 0
    && Number.isSafeInteger(stage.endTime) && stage.endTime > stage.startTime
    && Number.isInteger(stage.dropStageIndex) && stage.dropStageIndex >= 0
    && stage.dropStageIndex <= 255 && Number.isInteger(stage.maxTokenSupplyForStage)
    && stage.maxTokenSupplyForStage >= 1 && stage.maxTokenSupplyForStage <= 4_294_967_295
    && isBps(stage.feeBps) && stage.feeBps < 10_000
    && typeof stage.restrictFeeRecipients === "boolean",
  `invalid SeaDrop token-gated stage for ${stage.allowedNftToken}`);
  assert(!stage.restrictFeeRecipients || allowedFeeRecipients.length > 0,
    `restricted token-gated stage ${stage.allowedNftToken} requires an allowed fee recipient`);
}
const signedMintValidations = [...manifest.openSea.signedMintValidations]
  .map((params) => ({ ...params, signer: getAddress(params.signer) }))
  .sort((left, right) => left.signer.toLowerCase().localeCompare(right.signer.toLowerCase()));
assert(new Set(signedMintValidations.map((params) => params.signer)).size
  === signedMintValidations.length, "SeaDrop signed-mint signers must be unique");
for (const params of signedMintValidations) {
  assert(/^\d+$/.test(params.minMintPrice) && BigInt(params.minMintPrice) > 0n
    && BigInt(params.minMintPrice) < (1n << 80n)
    && Number.isInteger(params.maxMaxTotalMintableByWallet)
    && params.maxMaxTotalMintableByWallet >= 1
    && params.maxMaxTotalMintableByWallet <= 16_777_215
    && Number.isSafeInteger(params.minStartTime) && params.minStartTime >= 0
    && Number.isSafeInteger(params.maxEndTime) && params.maxEndTime > params.minStartTime
    && Number.isSafeInteger(params.maxMaxTokenSupplyForStage)
    && params.maxMaxTokenSupplyForStage >= 1
    && params.maxMaxTokenSupplyForStage <= 1_099_511_627_775
    && isBps(params.minFeeBps) && isBps(params.maxFeeBps)
    && params.minFeeBps <= params.maxFeeBps && params.maxFeeBps < 10_000,
  `invalid SeaDrop signed-mint validation for ${params.signer}`);
}
const mintStagesHash = keccak256(encodeAbiParameters(
  [
    { type: "tuple", components: [
    { name: "mintPrice", type: "uint80" }, { name: "startTime", type: "uint48" },
    { name: "endTime", type: "uint48" },
    { name: "maxTotalMintableByWallet", type: "uint16" },
    { name: "feeBps", type: "uint16" },
    { name: "restrictFeeRecipients", type: "bool" },
    ] },
    { type: "bytes32" }, { type: "address[]" }, { type: "address[]" },
    { type: "tuple[]", components: [
      { name: "allowedNftToken", type: "address" }, { name: "mintPrice", type: "uint80" },
      { name: "maxTotalMintableByWallet", type: "uint16" },
      { name: "startTime", type: "uint48" }, { name: "endTime", type: "uint48" },
      { name: "dropStageIndex", type: "uint8" },
      { name: "maxTokenSupplyForStage", type: "uint32" },
      { name: "feeBps", type: "uint16" },
      { name: "restrictFeeRecipients", type: "bool" },
    ] },
    { type: "tuple[]", components: [
      { name: "signer", type: "address" }, { name: "minMintPrice", type: "uint80" },
      { name: "maxMaxTotalMintableByWallet", type: "uint24" },
      { name: "minStartTime", type: "uint40" }, { name: "maxEndTime", type: "uint40" },
      { name: "maxMaxTokenSupplyForStage", type: "uint40" },
      { name: "minFeeBps", type: "uint16" }, { name: "maxFeeBps", type: "uint16" },
    ] },
  ],
  [
    { ...publicDrop, mintPrice: BigInt(publicDrop.mintPrice) },
    manifest.openSea.allowListMerkleRoot,
    allowedFeeRecipients,
    allowedPayers,
    tokenGatedDrops.map((stage) => ({ ...stage, mintPrice: BigInt(stage.mintPrice) })),
    signedMintValidations.map((params) => ({
      ...params, minMintPrice: BigInt(params.minMintPrice),
    })),
  ],
));
assert(mintStagesHash.toLowerCase() === manifest.openSea.mintStagesHash.toLowerCase(),
  "OpenSea mintStagesHash does not bind every recorded SeaDrop mint path");
assert(manifest.openSea.observedPrimaryPlatformFeeBps === publicDrop.feeBps,
  "observed primary fee must match the onchain public drop fee");
assert(sameAddress(manifest.openSea.creatorPayoutAddress, manifest.contracts.proceedsVault.address),
  "OpenSea creator payout must be the proceeds vault");
assert(manifest.openSea.observedSecondaryRoyaltyBps === manifest.economics.secondaryRoyaltyBps,
  "OpenSea secondary royalty rate must match the immutable collection rate");
assert(sameAddress(
  manifest.openSea.observedSecondaryRoyaltyRecipient,
  manifest.contracts.revenueRouter.address,
), "OpenSea secondary royalty recipient must be the collection revenue router");
assert(manifest.dependencies.eligibilityPolicy, "dependencies.eligibilityPolicy missing");

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
const validateImplementationBinding = async (path, entry, required) => {
  const binding = entry.implementationBinding;
  assert(binding || !required, `${path}.implementationBinding is required`);
  if (!binding || binding.kind === "immutable") return;
  assert(binding.kind === "eip1967" || binding.kind === "beacon",
    `${path}.implementationBinding kind is invalid`);
  getAddress(binding.implementation);
  assert(bytes32.test(binding.implementationRuntimeCodeHash),
    `${path} implementation code hash must be bytes32`);
  const wordToAddress = (word) => getAddress(`0x${word.slice(-40)}`);
  let implementation;
  if (binding.kind === "eip1967") {
    implementation = wordToAddress(await client.getStorageAt({
      address: entry.address, slot: EIP1967_IMPLEMENTATION_SLOT,
    }));
    assert(sameAddress(implementation, binding.implementation),
      `${path} active EIP-1967 implementation mismatch`);
  } else {
    getAddress(binding.beacon);
    assert(bytes32.test(binding.beaconRuntimeCodeHash),
      `${path} beacon code hash must be bytes32`);
    const beacon = wordToAddress(await client.getStorageAt({
      address: entry.address, slot: EIP1967_BEACON_SLOT,
    }));
    assert(sameAddress(beacon, binding.beacon), `${path} active beacon mismatch`);
    const beaconCode = await client.getCode({ address: beacon });
    assert(beaconCode && keccak256(beaconCode).toLowerCase()
      === binding.beaconRuntimeCodeHash.toLowerCase(), `${path} beacon code hash mismatch`);
    implementation = await client.readContract({
      address: beacon,
      abi: [{ type: "function", name: "implementation", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] }],
      functionName: "implementation",
    });
    assert(sameAddress(implementation, binding.implementation),
      `${path} active beacon implementation mismatch`);
  }
  const implementationCode = await client.getCode({ address: implementation });
  assert(implementationCode && keccak256(implementationCode).toLowerCase()
    === binding.implementationRuntimeCodeHash.toLowerCase(),
  `${path} implementation code hash mismatch`);
};
await validateImplementationBinding("dependencies.USDG", manifest.dependencies.USDG, true);
assert(manifest.dependencies.USDG.implementationBinding.kind === "eip1967",
  "dependencies.USDG must bind its active EIP-1967 implementation");
for (let index = 0; index < manifest.equityAssets.length; ++index) {
  await validateImplementationBinding(`equityAssets.${index}`, manifest.equityAssets[index], true);
  if (manifest.equityModel.custody === "onchain-tokenized-equity") {
    assert(manifest.equityAssets[index].implementationBinding.kind === "beacon",
      `equityAssets.${index} must bind its Stock Token beacon implementation`);
  }
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
  { type: "function", name: "eligibilityPolicy", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  ...[
    "creator", "openSeaManager", "sinjohFeeRecipient", "operationsReserve", "revenueRouter",
    "portfolioAllocator", "collectionTimelock", "guardian",
  ].map((name) => ({ type: "function", name, stateMutability: "view", inputs: [], outputs: [{ type: "address" }] })),
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
  { type: "function", name: "owner", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
];
const vaultAbi = [
  { type: "function", name: "allocationOperator", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
];
const sleeveAbi = [
  { type: "function", name: "maximumStrategies", stateMutability: "view", inputs: [], outputs: [{ type: "uint8" }] },
  { type: "function", name: "maximumAdapterCapBps", stateMutability: "view", inputs: [], outputs: [{ type: "uint16" }] },
  { type: "function", name: "maximumOperatorLossBps", stateMutability: "view", inputs: [], outputs: [{ type: "uint16" }] },
  { type: "function", name: "eligibilityPolicy", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
];
const seaDropAbi = [
  { type: "function", name: "getCreatorPayoutAddress", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "address" }] },
  { type: "function", name: "getAllowListMerkleRoot", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "bytes32" }] },
  { type: "function", name: "getAllowedFeeRecipients", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "address[]" }] },
  { type: "function", name: "getPayers", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "address[]" }] },
  { type: "function", name: "getSigners", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "address[]" }] },
  { type: "function", name: "getTokenGatedAllowedTokens", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "address[]" }] },
  { type: "function", name: "getTokenGatedDrop", stateMutability: "view", inputs: [{ type: "address" }, { type: "address" }], outputs: [{ type: "tuple", components: [
    { name: "mintPrice", type: "uint80" },
    { name: "maxTotalMintableByWallet", type: "uint16" },
    { name: "startTime", type: "uint48" }, { name: "endTime", type: "uint48" },
    { name: "dropStageIndex", type: "uint8" },
    { name: "maxTokenSupplyForStage", type: "uint32" },
    { name: "feeBps", type: "uint16" },
    { name: "restrictFeeRecipients", type: "bool" },
  ] }] },
  { type: "function", name: "getSignedMintValidationParams", stateMutability: "view", inputs: [{ type: "address" }, { type: "address" }], outputs: [{ type: "tuple", components: [
    { name: "minMintPrice", type: "uint80" },
    { name: "maxMaxTotalMintableByWallet", type: "uint24" },
    { name: "minStartTime", type: "uint40" }, { name: "maxEndTime", type: "uint40" },
    { name: "maxMaxTokenSupplyForStage", type: "uint40" },
    { name: "minFeeBps", type: "uint16" }, { name: "maxFeeBps", type: "uint16" },
  ] }] },
  { type: "function", name: "getPublicDrop", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "tuple", components: [
    { name: "mintPrice", type: "uint80" }, { name: "startTime", type: "uint48" },
    { name: "endTime", type: "uint48" }, { name: "maxTotalMintableByWallet", type: "uint16" },
    { name: "feeBps", type: "uint16" }, { name: "restrictFeeRecipients", type: "bool" },
  ] }] },
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
  collectionProceedsVault, collectionAccountImplementation, collectionEligibilityPolicy,
  collectionCreator, collectionOpenSeaManager, collectionSinjohFeeRecipient,
  collectionOperationsReserve, collectionRevenueRouter, collectionPortfolioAllocator,
  collectionTimelock, collectionGuardian,
  collectionSecondaryRoyaltyBps, nftMaxSupply, nftSeaDrop, nftCollection, nftRoyaltyReceiver,
  nftRoyaltyBps, nftOwner, allocationOperator, collectionRecord, seaDropCreatorPayout,
  seaDropPublicDrop, seaDropAllowListMerkleRoot, seaDropFeeRecipients, seaDropPayers,
  seaDropSigners, seaDropTokenGatedTokens, ...onchainEconomicValues] = await Promise.all([
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
  read(manifest.contracts.collection.address, collectionAbi, "eligibilityPolicy"),
  read(manifest.contracts.collection.address, collectionAbi, "creator"),
  read(manifest.contracts.collection.address, collectionAbi, "openSeaManager"),
  read(manifest.contracts.collection.address, collectionAbi, "sinjohFeeRecipient"),
  read(manifest.contracts.collection.address, collectionAbi, "operationsReserve"),
  read(manifest.contracts.collection.address, collectionAbi, "revenueRouter"),
  read(manifest.contracts.collection.address, collectionAbi, "portfolioAllocator"),
  read(manifest.contracts.collection.address, collectionAbi, "collectionTimelock"),
  read(manifest.contracts.collection.address, collectionAbi, "guardian"),
  read(manifest.contracts.collection.address, collectionAbi, "secondaryRoyaltyBps"),
  read(manifest.contracts.nft.address, nftAbi, "maxSupply"),
  read(manifest.contracts.nft.address, nftAbi, "seaDrop"),
  read(manifest.contracts.nft.address, nftAbi, "collection"),
  read(manifest.contracts.nft.address, nftAbi, "royaltyReceiver"),
  read(manifest.contracts.nft.address, nftAbi, "royaltyBps"),
  read(manifest.contracts.nft.address, nftAbi, "owner"),
  read(manifest.contracts.proceedsVault.address, vaultAbi, "allocationOperator"),
  read(manifest.contracts.registry.address, registryAbi, "collections", [manifest.contracts.collection.address]),
  read(manifest.dependencies.seaDrop.address, seaDropAbi, "getCreatorPayoutAddress", [manifest.contracts.nft.address]),
  read(manifest.dependencies.seaDrop.address, seaDropAbi, "getPublicDrop", [manifest.contracts.nft.address]),
  read(manifest.dependencies.seaDrop.address, seaDropAbi, "getAllowListMerkleRoot", [manifest.contracts.nft.address]),
  read(manifest.dependencies.seaDrop.address, seaDropAbi, "getAllowedFeeRecipients", [manifest.contracts.nft.address]),
  read(manifest.dependencies.seaDrop.address, seaDropAbi, "getPayers", [manifest.contracts.nft.address]),
  read(manifest.dependencies.seaDrop.address, seaDropAbi, "getSigners", [manifest.contracts.nft.address]),
  read(manifest.dependencies.seaDrop.address, seaDropAbi, "getTokenGatedAllowedTokens", [manifest.contracts.nft.address]),
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
assert(sameAddress(collectionEligibilityPolicy, manifest.dependencies.eligibilityPolicy.address),
  "collection eligibility policy mismatch");
for (const [name, actual, expected] of [
  ["creator", collectionCreator, manifest.roles.creator],
  ["openSeaManager", collectionOpenSeaManager, manifest.roles.openSeaManager],
  ["sinjohFeeRecipient", collectionSinjohFeeRecipient, manifest.roles.sinjoh],
  ["operationsReserve", collectionOperationsReserve, manifest.roles.operations],
  ["revenueRouter", collectionRevenueRouter, manifest.contracts.revenueRouter.address],
  ["portfolioAllocator", collectionPortfolioAllocator, manifest.contracts.allocator.address],
  ["collectionTimelock", collectionTimelock, manifest.roles.timelock],
  ["guardian", collectionGuardian, manifest.roles.guardian],
]) assert(sameAddress(actual, expected), `collection ${name} mismatch`);
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
assert(sameAddress(nftOwner, manifest.roles.timelock),
  "NFT ownership has not been accepted by the collection timelock");
assert(sameAddress(seaDropCreatorPayout, manifest.contracts.proceedsVault.address),
  "SeaDrop creator payout address mismatch");
assert(BigInt(publicDrop.mintPrice) === seaDropPublicDrop.mintPrice
  && publicDrop.startTime === Number(seaDropPublicDrop.startTime)
  && publicDrop.endTime === Number(seaDropPublicDrop.endTime)
  && publicDrop.maxTotalMintableByWallet === Number(seaDropPublicDrop.maxTotalMintableByWallet)
  && publicDrop.feeBps === Number(seaDropPublicDrop.feeBps)
  && publicDrop.restrictFeeRecipients === seaDropPublicDrop.restrictFeeRecipients,
"SeaDrop public drop configuration mismatch");
assert(seaDropAllowListMerkleRoot.toLowerCase()
  === manifest.openSea.allowListMerkleRoot.toLowerCase(), "SeaDrop allowlist root mismatch");
assert(JSON.stringify(allowedFeeRecipients)
  === JSON.stringify(canonicalAddresses(seaDropFeeRecipients)),
"SeaDrop allowed fee recipients mismatch");
assert(JSON.stringify(allowedPayers) === JSON.stringify(canonicalAddresses(seaDropPayers)),
  "SeaDrop allowed payers mismatch");
assert(JSON.stringify(signedMintValidations.map((params) => params.signer))
  === JSON.stringify(canonicalAddresses(seaDropSigners)), "SeaDrop signer set mismatch");
assert(JSON.stringify(tokenGatedDrops.map((stage) => stage.allowedNftToken))
  === JSON.stringify(canonicalAddresses(seaDropTokenGatedTokens)),
"SeaDrop token-gated asset set mismatch");
const [onchainTokenGatedDrops, onchainSignedMintValidations] = await Promise.all([
  Promise.all(tokenGatedDrops.map((stage) => read(
    manifest.dependencies.seaDrop.address, seaDropAbi, "getTokenGatedDrop",
    [manifest.contracts.nft.address, stage.allowedNftToken],
  ))),
  Promise.all(signedMintValidations.map((params) => read(
    manifest.dependencies.seaDrop.address, seaDropAbi, "getSignedMintValidationParams",
    [manifest.contracts.nft.address, params.signer],
  ))),
]);
for (let index = 0; index < tokenGatedDrops.length; ++index) {
  const expected = tokenGatedDrops[index];
  const actual = onchainTokenGatedDrops[index];
  assert(BigInt(expected.mintPrice) === actual.mintPrice
    && expected.maxTotalMintableByWallet === Number(actual.maxTotalMintableByWallet)
    && expected.startTime === Number(actual.startTime) && expected.endTime === Number(actual.endTime)
    && expected.dropStageIndex === Number(actual.dropStageIndex)
    && expected.maxTokenSupplyForStage === Number(actual.maxTokenSupplyForStage)
    && expected.feeBps === Number(actual.feeBps)
    && expected.restrictFeeRecipients === actual.restrictFeeRecipients,
  `SeaDrop token-gated stage mismatch for ${expected.allowedNftToken}`);
}
for (let index = 0; index < signedMintValidations.length; ++index) {
  const expected = signedMintValidations[index];
  const actual = onchainSignedMintValidations[index];
  assert(BigInt(expected.minMintPrice) === actual.minMintPrice
    && expected.maxMaxTotalMintableByWallet === Number(actual.maxMaxTotalMintableByWallet)
    && expected.minStartTime === Number(actual.minStartTime)
    && expected.maxEndTime === Number(actual.maxEndTime)
    && expected.maxMaxTokenSupplyForStage === Number(actual.maxMaxTokenSupplyForStage)
    && expected.minFeeBps === Number(actual.minFeeBps)
    && expected.maxFeeBps === Number(actual.maxFeeBps),
  `SeaDrop signed-mint validation mismatch for ${expected.signer}`);
}
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
  const [maximumStrategies, maximumAdapterCapBps, maximumOperatorLossBps,
    sleeveEligibilityPolicy] = await Promise.all([
    read(sleeve, sleeveAbi, "maximumStrategies"),
    read(sleeve, sleeveAbi, "maximumAdapterCapBps"),
    read(sleeve, sleeveAbi, "maximumOperatorLossBps"),
    read(sleeve, sleeveAbi, "eligibilityPolicy"),
  ]);
  assert(Number(maximumStrategies) === policy.maximumStrategies,
    `${key} maximumStrategies mismatch`);
  assert(Number(maximumAdapterCapBps) === policy.maximumAdapterCapBps,
    `${key} maximumAdapterCapBps mismatch`);
  assert(Number(maximumOperatorLossBps) === policy.maximumOperatorLossBps,
    `${key} maximumOperatorLossBps mismatch`);
  assert(sameAddress(sleeveEligibilityPolicy, manifest.dependencies.eligibilityPolicy.address),
    `${key} eligibility policy mismatch`);
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
