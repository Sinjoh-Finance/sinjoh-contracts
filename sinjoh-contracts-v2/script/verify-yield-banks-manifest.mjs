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
  "proceedsVault", "distributor", "revenueRouter", "timelock",
  "allocator", "priceHub", "strategyRegistry", "renderer", "coreSleeve",
  "marketMakingSleeve", "usdgSleeve",
  "rebalanceValueGuard",
];
const assert = (condition, message) => { if (!condition) throw new Error(message); };
const hashText = (value) => keccak256(stringToHex(value));
const sameAddress = (left, right) => getAddress(left) === getAddress(right);

assert(manifest.schemaVersion === "1.0", "unsupported Yield Banks manifest schema");
assert(manifest.chainId === 4663, "Yield Banks release manifests require Robinhood mainnet chain 4663");
assert(bytes32.test(manifest.collectionId), "collectionId must be bytes32");
assert(Number(await client.getChainId()) === manifest.chainId, "RPC chain does not match manifest");
const verificationBlock = await client.getBlock();
const chainNow = verificationBlock.timestamp;
assert(Number.isSafeInteger(manifest.economics.maxSupply) && manifest.economics.maxSupply > 0,
  "maxSupply must be a positive safe integer");
const isBps = (value) => Number.isInteger(value) && value >= 0 && value <= 10_000;
for (const key of [
  "secondaryRoyaltyBps",
  "primaryBackingBps", "primaryCreatorBps", "primarySinjohBps",
  "royaltyBackingBps", "royaltyCreatorBps", "royaltySinjohBps",
  "coreWeightBps", "marketMakingWeightBps", "usdgWeightBps",
]) assert(isBps(manifest.economics[key]), `economics.${key} must be integer basis points`);
assert(manifest.economics.primaryBackingBps > 0
  && manifest.economics.primaryBackingBps + manifest.economics.primaryCreatorBps
    + manifest.economics.primarySinjohBps === 10_000,
"primary economics must sum to 10000 basis points with positive backing");
assert(manifest.economics.royaltyBackingBps > 0
  && manifest.economics.royaltyBackingBps + manifest.economics.royaltyCreatorBps
    + manifest.economics.royaltySinjohBps === 10_000,
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
  && ["robinhood-stock-token", "offchain-custody-receipt"].includes(manifest.equityModel.custody)
  && ["balance-appreciation", "cash-distribution", "mixed"].includes(manifest.equityModel.income),
"equityModel must explicitly describe custody and income behavior");
assert(manifest.equityModel.custody !== "robinhood-stock-token"
  || manifest.equityModel.income === "balance-appreciation",
"Robinhood Stock Token income must use the multiplier-aware balance-appreciation model");
assert(new URL(manifest.equityModel.disclosureUri).protocol === "https:",
  "equityModel.disclosureUri must be HTTPS");
assert(manifest.equityAssets.length >= 1, "at least one reviewed equity asset is required");
assert(Array.isArray(manifest.feeds) && manifest.feeds.length >= 1,
  "at least one reviewed feed binding is required");
assert(Array.isArray(manifest.deltaPools), "deltaPools must be an array");
const containsAddress = (records, address) => Object.values(records)
  .some((entry) => sameAddress(entry.address, address));
const allManifestEntries = [
  ...Object.values(manifest.contracts), ...Object.values(manifest.dependencies),
  ...manifest.equityAssets, ...Object.values(manifest.adapters),
  ...manifest.feeds.map((binding) => binding.feed), ...Object.values(manifest.pools),
];
const manifestEntryFor = (address) => allManifestEntries
  .find((entry) => sameAddress(entry.address, address));
const seenDeltaPools = new Set();
const seenDeltaSleeves = new Set();
const seenDeltaAdapters = new Set();
for (const delta of manifest.deltaPools) {
  assert(Number.isInteger(delta.maximumPositions) && delta.maximumPositions >= 1
    && delta.maximumPositions <= 64, "Delta maximumPositions must be an integer from 1 through 64");
  assert(delta.maximumStrategies === 1,
    `Delta sleeve ${delta.sleeve} must have exactly one strategy slot`);
  assert(isBps(delta.adapterCapBps) && delta.adapterCapBps > 0
    && delta.adapterCapBps <= manifest.policyCaps.marketMaking.maximumAdapterCapBps,
  `Delta adapter cap exceeds the market-making policy for ${delta.adapter}`);
  for (const [field, records] of [
    ["adapter", manifest.adapters], ["entryRoute", manifest.adapters],
    ["exitRoute", manifest.adapters], ["pool", manifest.pools],
    ["pairedAsset", manifest.dependencies], ["positionBuilder", manifest.dependencies],
    ["factory", manifest.dependencies], ["positionManager", manifest.dependencies],
  ]) assert(containsAddress(records, delta[field]),
    `Delta ${field} ${delta[field]} is not bound to its manifest group`);
  assert(manifestEntryFor(delta.sleeve), `Delta sleeve ${delta.sleeve} is not in the manifest`);
  assert(!sameAddress(delta.pairedAsset, manifest.dependencies.WETH.address),
    `Delta paired asset must differ from WETH for ${delta.pool}`);
  const poolKey = getAddress(delta.pool);
  const sleeveKey = getAddress(delta.sleeve);
  const adapterKey = getAddress(delta.adapter);
  assert(!seenDeltaPools.has(poolKey), `duplicate Delta pool ${poolKey}`);
  assert(!seenDeltaSleeves.has(sleeveKey), `Delta sleeve reused across pools ${sleeveKey}`);
  assert(!seenDeltaAdapters.has(adapterKey), `Delta adapter reused across pools ${adapterKey}`);
  seenDeltaPools.add(poolKey);
  seenDeltaSleeves.add(sleeveKey);
  seenDeltaAdapters.add(adapterKey);
}
const equityAssetKeys = new Set(manifest.equityAssets.map((entry) => getAddress(entry.address)));
assert(Array.isArray(manifest.coreConstituents)
  && manifest.coreConstituents.length === manifest.equityAssets.length,
"every reviewed Stock Token must be an exact Core sleeve constituent");
const constituentAssetKeys = new Set();
let constituentWeightTotal = 0;
for (const constituent of manifest.coreConstituents) {
  const asset = getAddress(constituent.asset);
  assert(equityAssetKeys.has(asset), `Core constituent is not a reviewed Stock Token: ${asset}`);
  assert(!constituentAssetKeys.has(asset), `duplicate Core constituent ${asset}`);
  const routeEntry = manifestEntryFor(constituent.route);
  assert(routeEntry
    && routeEntry.runtimeCodeHash.toLowerCase()
      === constituent.routeRuntimeCodeHash.toLowerCase(),
  `Core constituent route is not codehash-bound in the manifest: ${constituent.route}`);
  assert(isBps(constituent.weightBps) && constituent.weightBps > 0,
    `invalid Core constituent weight for ${asset}`);
  constituentWeightTotal += constituent.weightBps;
  constituentAssetKeys.add(asset);
}
assert(constituentWeightTotal === 10_000, "Core constituent weights must sum to 10000 basis points");
for (const asset of equityAssetKeys) {
  assert(constituentAssetKeys.has(asset), `reviewed Stock Token is absent from Core sleeve: ${asset}`);
}
const requiredPricedAssets = new Set([
  getAddress(manifest.dependencies.WETH.address),
  getAddress(manifest.dependencies.USDG.address),
  ...equityAssetKeys,
  ...manifest.deltaPools.map((delta) => getAddress(delta.pairedAsset)),
]);
const feedAssetKeys = new Set();
const feedAddressKeys = new Set();
const feedBindingsByAsset = new Map();
for (const binding of manifest.feeds) {
  const asset = getAddress(binding.asset);
  const feed = getAddress(binding.feed.address);
  assert(requiredPricedAssets.has(asset), `feed binds an unused asset ${asset}`);
  assert(!feedAssetKeys.has(asset), `duplicate feed binding for ${asset}`);
  assert(!feedAddressKeys.has(feed), `feed proxy reused for multiple assets ${feed}`);
  assert(Number.isInteger(binding.heartbeat) && binding.heartbeat > 0,
    `invalid feed heartbeat for ${asset}`);
  assert(Number.isInteger(binding.gracePeriod) && binding.gracePeriod >= 0,
    `invalid feed grace period for ${asset}`);
  assert(isBps(binding.maxDeviationBps), `invalid feed deviation limit for ${asset}`);
  assert(Number.isInteger(binding.decimals) && binding.decimals >= 0 && binding.decimals <= 18,
    `invalid feed decimals for ${asset}`);
  assert(typeof binding.description === "string" && binding.description.length > 0,
    `missing feed description for ${asset}`);
  const feedSource = new URL(binding.sourceUrl);
  assert(feedSource.protocol === "https:", `feed source must use HTTPS for ${asset}`);
  if (binding.kind === "chainlink") {
    assert(feedSource.hostname === "docs.chain.link",
      `Chainlink feed source must be official Chainlink documentation for ${asset}`);
    assert(sameAddress(binding.wethUsdFeed, "0x0000000000000000000000000000000000000000")
      && binding.twapWindow === 0 && binding.maxSpotDeviationBps === 0
      && binding.comparisonAmount === "0" && binding.minimumLiquidity === "0",
    `Chainlink feed must not contain derived-price settings for ${asset}`);
  } else {
    assert(binding.kind === "delta-v3-twap"
      && feedSource.hostname === "robinhoodchain.blockscout.com"
      && feedSource.pathname.toLowerCase().includes(binding.feed.address.toLowerCase())
      && !sameAddress(binding.referenceSource, "0x0000000000000000000000000000000000000000")
      && manifestEntryFor(binding.referenceSource)
      && !sameAddress(binding.wethUsdFeed, "0x0000000000000000000000000000000000000000")
      && manifestEntryFor(binding.wethUsdFeed)
      && Number.isInteger(binding.twapWindow) && binding.twapWindow > 0
      && binding.twapWindow <= 86_400
      && isBps(binding.maxSpotDeviationBps) && binding.maxSpotDeviationBps > 0
      && binding.maxSpotDeviationBps <= 2_000
      && /^\d+$/.test(binding.comparisonAmount) && BigInt(binding.comparisonAmount) > 0n
      && BigInt(binding.comparisonAmount) < (1n << 128n)
      && /^\d+$/.test(binding.minimumLiquidity) && BigInt(binding.minimumLiquidity) > 0n
      && BigInt(binding.minimumLiquidity) < (1n << 128n),
    `invalid Delta V3 TWAP feed provenance or controls for ${asset}`);
  }
  assert(Number.isFinite(Date.parse(binding.observedAt)),
    `feed observation time is invalid for ${asset}`);
  assert(equityAssetKeys.has(asset) ? binding.checkAssetOraclePause === true
    : binding.checkAssetOraclePause === false,
  `feed oracle-pause policy does not match asset type for ${asset}`);
  assert(binding.weekdaysOnly === equityAssetKeys.has(asset),
    `feed weekday policy does not match the documented asset availability for ${asset}`);
  if (!sameAddress(binding.referenceSource, "0x0000000000000000000000000000000000000000")) {
    assert(manifestEntryFor(binding.referenceSource),
      `feed reference source ${binding.referenceSource} is not in the manifest`);
  }
  feedAssetKeys.add(asset);
  feedAddressKeys.add(feed);
  feedBindingsByAsset.set(asset, binding);
}
for (const asset of requiredPricedAssets) {
  assert(feedAssetKeys.has(asset), `missing exact PriceHub feed binding for ${asset}`);
}
for (const asset of [
  manifest.dependencies.WETH.address,
  manifest.dependencies.USDG.address,
  ...manifest.equityAssets.map((entry) => entry.address),
]) {
  assert(feedBindingsByAsset.get(getAddress(asset)).kind === "chainlink",
    `externally priced release asset must use a direct Chainlink feed: ${asset}`);
}
assert(manifest.routeBindings && Array.isArray(manifest.routeBindings.allocations)
  && Array.isArray(manifest.routeBindings.rebalances), "routeBindings are required");
const allowedSleeveKeys = new Set([
  getAddress(manifest.contracts.coreSleeve.address),
  getAddress(manifest.contracts.marketMakingSleeve.address),
  getAddress(manifest.contracts.usdgSleeve.address),
  ...manifest.deltaPools.map((delta) => getAddress(delta.sleeve)),
]);
const allocationKeys = new Set();
for (const binding of manifest.routeBindings.allocations) {
  const key = `${getAddress(binding.inputAsset)}:${getAddress(binding.sleeve)}`;
  assert(!allocationKeys.has(key), `duplicate allocation route ${key}`);
  allocationKeys.add(key);
  assert(allowedSleeveKeys.has(getAddress(binding.sleeve)),
    `allocation route targets an unreviewed sleeve ${binding.sleeve}`);
  assert(manifestEntryFor(binding.inputAsset),
    `allocation route input is not a manifest dependency ${binding.inputAsset}`);
  const entry = manifestEntryFor(binding.route);
  assert(entry && entry.runtimeCodeHash.toLowerCase() === binding.runtimeCodeHash.toLowerCase(),
    `allocation route ${binding.route} is not a matching manifest dependency`);
}
assert(allocationKeys.has(
  `${getAddress(manifest.dependencies.WETH.address)}:${getAddress(manifest.contracts.usdgSleeve.address)}`,
), `missing WETH allocation route for USDG sleeve ${manifest.contracts.usdgSleeve.address}`);
const rebalanceAssets = [
  manifest.dependencies.USDG.address,
  ...manifest.deltaPools.map((delta) => delta.pairedAsset),
  ...manifest.equityAssets.map((entry) => entry.address),
];
const rebalanceKeys = new Set();
for (const binding of manifest.routeBindings.rebalances) {
  const key = getAddress(binding.inputAsset);
  assert(!rebalanceKeys.has(key), `duplicate rebalance route ${key}`);
  rebalanceKeys.add(key);
  assert(manifestEntryFor(binding.inputAsset),
    `rebalance route input is not a manifest dependency ${binding.inputAsset}`);
  const entry = manifestEntryFor(binding.route);
  assert(entry && entry.runtimeCodeHash.toLowerCase() === binding.runtimeCodeHash.toLowerCase(),
    `rebalance route ${binding.route} is not a matching manifest dependency`);
}
for (const asset of new Set(rebalanceAssets.map((address) => getAddress(address)))) {
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
  pools: manifest.pools,
})) for (const [key, entry] of Object.entries(records)) entries.push([`${group}.${key}`, entry]);
manifest.equityAssets.forEach((entry, index) => entries.push([`equityAssets.${index}`, entry]));
manifest.feeds.forEach((binding, index) => entries.push([`feeds.${index}.feed`, binding.feed]));
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
await validateImplementationBinding("dependencies.WETH", manifest.dependencies.WETH, true);
assert(manifest.dependencies.WETH.implementationBinding.kind === "eip1967",
  "dependencies.WETH must bind its active EIP-1967 implementation");
await validateImplementationBinding("dependencies.USDG", manifest.dependencies.USDG, true);
assert(manifest.dependencies.USDG.implementationBinding.kind === "eip1967",
  "dependencies.USDG must bind its active EIP-1967 implementation");
for (let index = 0; index < manifest.equityAssets.length; ++index) {
  await validateImplementationBinding(`equityAssets.${index}`, manifest.equityAssets[index], true);
  if (manifest.equityModel.custody === "robinhood-stock-token") {
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
  { type: "function", name: "redemptionToken", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "redemptionTokenAmount", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "redemptionTokenCodeHash", stateMutability: "view", inputs: [], outputs: [{ type: "bytes32" }] },
  ...[
    "creator", "openSeaManager", "sinjohFeeRecipient", "revenueRouter",
    "portfolioAllocator", "collectionTimelock", "guardian",
  ].map((name) => ({ type: "function", name, stateMutability: "view", inputs: [], outputs: [{ type: "address" }] })),
  { type: "function", name: "secondaryRoyaltyBps", stateMutability: "view", inputs: [], outputs: [{ type: "uint96" }] },
  ...[
    "primaryBackingBps", "primaryCreatorBps", "primarySinjohBps",
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
    "royaltyBackingBps", "royaltyCreatorBps", "royaltySinjohBps",
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
    "sleeve", "accountingAsset", "pairedAsset", "priceHub", "pool", "factory",
    "positionManager", "positionBuilder", "entryRoute", "exitRoute",
  ].map((name) => ({ type: "function", name, stateMutability: "view", inputs: [], outputs: [{ type: "address" }] })),
  ...[
    "poolCodeHash", "factoryCodeHash", "positionManagerCodeHash",
    "positionBuilderCodeHash", "entryRouteCodeHash", "exitRouteCodeHash",
  ].map((name) => ({ type: "function", name, stateMutability: "view", inputs: [], outputs: [{ type: "bytes32" }] })),
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
  { type: "function", name: "rebalanceValueGuard", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "routeBinding", stateMutability: "view", inputs: [
    { type: "address" }, { type: "address" },
  ], outputs: [{ type: "address" }, { type: "bytes32" }] },
  { type: "function", name: "rebalanceRoute", stateMutability: "view", inputs: [
    { type: "address" },
  ], outputs: [{ type: "address" }, { type: "bytes32" }] },
  { type: "function", name: "deltaPoolBinding", stateMutability: "view", inputs: [
    { type: "address" },
  ], outputs: [
    { type: "address" }, { type: "address" }, { type: "bytes32" },
    { type: "bytes32" }, { type: "bytes32" },
  ] },
  { type: "function", name: "deltaPoolOfSleeve", stateMutability: "view", inputs: [
    { type: "address" },
  ], outputs: [{ type: "address" }] },
];
const sleeveAdapterAbi = [
  { type: "function", name: "adapterState", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "uint8" }] },
  { type: "function", name: "adapterCapBps", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "uint16" }] },
  { type: "function", name: "maximumStrategies", stateMutability: "view", inputs: [], outputs: [{ type: "uint8" }] },
  { type: "function", name: "adapters", stateMutability: "view", inputs: [], outputs: [{ type: "address[]" }] },
  { type: "function", name: "category", stateMutability: "view", inputs: [], outputs: [{ type: "bytes32" }] },
  { type: "function", name: "accountingAsset", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "allocator", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "timelock", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "guardian", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "priceHub", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "strategyRegistry", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "inventoryAssets", stateMutability: "view", inputs: [], outputs: [{ type: "address[]" }] },
];
const coreSleeveAbi = [
  { type: "function", name: "constituentWeightTotal", stateMutability: "view", inputs: [], outputs: [{ type: "uint16" }] },
  { type: "function", name: "constituents", stateMutability: "view", inputs: [], outputs: [{
    type: "tuple[]", components: [
      { name: "asset", type: "address" }, { name: "route", type: "address" },
      { name: "routeRuntimeCodeHash", type: "bytes32" }, { name: "weightBps", type: "uint16" },
    ],
  }] },
];
const priceHubAbi = [
  { type: "function", name: "chainHealthy", stateMutability: "view", inputs: [], outputs: [{ type: "bool" }] },
  { type: "function", name: "guardianPaused", stateMutability: "view", inputs: [], outputs: [{ type: "bool" }] },
  { type: "function", name: "feedConfig", stateMutability: "view", inputs: [{ type: "address" }], outputs: [
    { type: "address" }, { type: "address" }, { type: "uint32" }, { type: "uint32" },
    { type: "uint16" }, { type: "uint8" }, { type: "bytes32" }, { type: "bytes32" },
    { type: "bytes32" }, { type: "bool" }, { type: "bool" }, { type: "bool" },
    { type: "bool" },
  ] },
];
const aggregatorAbi = [
  { type: "function", name: "decimals", stateMutability: "view", inputs: [], outputs: [{ type: "uint8" }] },
  { type: "function", name: "description", stateMutability: "view", inputs: [], outputs: [{ type: "string" }] },
  { type: "function", name: "latestRoundData", stateMutability: "view", inputs: [], outputs: [
    { type: "uint80" }, { type: "int256" }, { type: "uint256" }, { type: "uint256" },
    { type: "uint80" },
  ] },
];
const oraclePauseAbi = [
  { type: "function", name: "oraclePaused", stateMutability: "view", inputs: [], outputs: [{ type: "bool" }] },
];
const v3PoolAbi = [
  ...["factory", "token0", "token1"].map((name) => ({
    type: "function", name, stateMutability: "view", inputs: [], outputs: [{ type: "address" }],
  })),
  { type: "function", name: "fee", stateMutability: "view", inputs: [], outputs: [{ type: "uint24" }] },
  { type: "function", name: "tickSpacing", stateMutability: "view", inputs: [], outputs: [{ type: "int24" }] },
  { type: "function", name: "liquidity", stateMutability: "view", inputs: [], outputs: [{ type: "uint128" }] },
  { type: "function", name: "slot0", stateMutability: "view", inputs: [], outputs: [
    { type: "uint160" }, { type: "int24" }, { type: "uint16" }, { type: "uint16" },
    { type: "uint16" }, { type: "uint8" }, { type: "bool" },
  ] },
];
const v3FactoryAbi = [
  { type: "function", name: "getPool", stateMutability: "view", inputs: [
    { type: "address" }, { type: "address" }, { type: "uint24" },
  ], outputs: [{ type: "address" }] },
];
const positionBuilderAbi = [
  ...["uniFactory", "positionManager", "weth"].map((name) => ({
    type: "function", name, stateMutability: "view", inputs: [], outputs: [{ type: "address" }],
  })),
];
const positionManagerAbi = [
  ...["factory", "WETH9"].map((name) => ({
    type: "function", name, stateMutability: "view", inputs: [], outputs: [{ type: "address" }],
  })),
];
const singlePoolRouteAbi = [
  ...["inputAsset", "outputAsset", "pool", "factory"].map((name) => ({
    type: "function", name, stateMutability: "view", inputs: [], outputs: [{ type: "address" }],
  })),
  ...["poolCodeHash", "factoryCodeHash"].map((name) => ({
    type: "function", name, stateMutability: "view", inputs: [], outputs: [{ type: "bytes32" }],
  })),
];
const collectionSleeveAbi = [
  { type: "function", name: "isSleeveAsset", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "bool" }] },
];
const deltaTwapFeedAbi = [
  ...["pairedAsset", "weth", "pool", "factory", "wethUsdFeed"].map((name) => ({
    type: "function", name, stateMutability: "view", inputs: [], outputs: [{ type: "address" }],
  })),
  ...[
    "pairedAssetCodeHash", "wethCodeHash", "poolCodeHash", "factoryCodeHash",
    "wethUsdFeedCodeHash", "wethUsdFeedDescriptionHash",
  ].map((name) => ({
    type: "function", name, stateMutability: "view", inputs: [], outputs: [{ type: "bytes32" }],
  })),
  { type: "function", name: "twapWindow", stateMutability: "view", inputs: [], outputs: [{ type: "uint32" }] },
  { type: "function", name: "maxSpotDeviationBps", stateMutability: "view", inputs: [], outputs: [{ type: "uint16" }] },
  { type: "function", name: "comparisonAmount", stateMutability: "view", inputs: [], outputs: [{ type: "uint128" }] },
  { type: "function", name: "minimumLiquidity", stateMutability: "view", inputs: [], outputs: [{ type: "uint128" }] },
];
const read = (address, abi, functionName, args = []) => client.readContract({
  address, abi, functionName, args,
});
const factory = manifest.contracts.factory.address;
const [predictedFactory, factoryVersion, collectionCodeHash, systemPlanHash,
  collectionId, collectionMaxSupply, collectionNft, collectionDistributor,
  collectionProceedsVault, collectionAccountImplementation, collectionEligibilityPolicy,
  collectionRedemptionToken, collectionRedemptionTokenAmount, collectionRedemptionTokenCodeHash,
  collectionCreator, collectionOpenSeaManager, collectionSinjohFeeRecipient,
  collectionRevenueRouter, collectionPortfolioAllocator,
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
  read(manifest.contracts.collection.address, collectionAbi, "redemptionToken"),
  read(manifest.contracts.collection.address, collectionAbi, "redemptionTokenAmount"),
  read(manifest.contracts.collection.address, collectionAbi, "redemptionTokenCodeHash"),
  read(manifest.contracts.collection.address, collectionAbi, "creator"),
  read(manifest.contracts.collection.address, collectionAbi, "openSeaManager"),
  read(manifest.contracts.collection.address, collectionAbi, "sinjohFeeRecipient"),
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
    "primaryBackingBps", "primaryCreatorBps", "primarySinjohBps",
    "coreWeightBps", "marketMakingWeightBps", "usdgWeightBps",
  ].map((name) => read(manifest.contracts.collection.address, collectionAbi, name)),
  ...[
    "royaltyBackingBps", "royaltyCreatorBps", "royaltySinjohBps",
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
assert(sameAddress(collectionRedemptionToken, manifest.redemption.token)
  && collectionRedemptionTokenAmount === BigInt(manifest.redemption.amount)
  && collectionRedemptionTokenCodeHash.toLowerCase()
    === manifest.redemption.tokenRuntimeCodeHash.toLowerCase(),
"collection redemption-token configuration mismatch");
const redemptionDisabled = sameAddress(
  manifest.redemption.token, "0x0000000000000000000000000000000000000000",
);
assert(redemptionDisabled
  ? manifest.redemption.amount === 0 && manifest.redemption.tokenRuntimeCodeHash === zeroBytes32
  : manifest.redemption.amount > 0 && manifest.redemption.tokenRuntimeCodeHash !== zeroBytes32
    && manifestEntryFor(manifest.redemption.token),
"redemption token, amount, runtime hash, and manifest entry are inconsistent");
for (const [name, actual, expected] of [
  ["creator", collectionCreator, manifest.roles.creator],
  ["openSeaManager", collectionOpenSeaManager, manifest.roles.openSeaManager],
  ["sinjohFeeRecipient", collectionSinjohFeeRecipient, manifest.roles.sinjoh],
  ["revenueRouter", collectionRevenueRouter, manifest.contracts.revenueRouter.address],
  ["portfolioAllocator", collectionPortfolioAllocator, manifest.contracts.allocator.address],
  ["collectionTimelock", collectionTimelock, manifest.roles.timelock],
  ["guardian", collectionGuardian, manifest.roles.guardian],
]) assert(sameAddress(actual, expected), `collection ${name} mismatch`);
assert(sameAddress(
  await read(manifest.contracts.collection.address, collectionAbi, "portfolioAllocator"),
  manifest.contracts.allocator.address,
), "collection portfolio allocator mismatch");
assert(sameAddress(
  await read(manifest.contracts.allocator.address, allocatorAbi, "rebalanceValueGuard"),
  manifest.contracts.rebalanceValueGuard.address,
), "allocator rebalance value guard mismatch");
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
  "primaryBackingBps", "primaryCreatorBps", "primarySinjohBps",
  "coreWeightBps", "marketMakingWeightBps", "usdgWeightBps",
];
const royaltyEconomicKeys = [
  "royaltyBackingBps", "royaltyCreatorBps", "royaltySinjohBps",
];
collectionEconomicKeys.forEach((key, index) => assert(
  onchainEconomicValues[index] === BigInt(manifest.economics[key]), `onchain ${key} mismatch`,
));
royaltyEconomicKeys.forEach((key, index) => assert(
  onchainEconomicValues[collectionEconomicKeys.length + index]
    === BigInt(manifest.economics[key]), `onchain ${key} mismatch`,
));
for (const [key, contractKey, categoryLabel, accountingAsset] of [
  ["core", "coreSleeve", "YIELD_BANK_CORE", manifest.dependencies.WETH.address],
  ["marketMaking", "marketMakingSleeve", "YIELD_BANK_MARKET_MAKING", manifest.dependencies.WETH.address],
  ["usdg", "usdgSleeve", "YIELD_BANK_USDG", manifest.dependencies.USDG.address],
]) {
  const policy = manifest.policyCaps[key];
  const sleeve = manifest.contracts[contractKey].address;
  const [maximumStrategies, maximumAdapterCapBps, maximumOperatorLossBps,
    sleeveEligibilityPolicy, category, actualAccountingAsset, allocator, timelock,
    guardian, configuredPriceHub, configuredRegistry, configuredAdapters,
    inventoryAssets] = await Promise.all([
    read(sleeve, sleeveAbi, "maximumStrategies"),
    read(sleeve, sleeveAbi, "maximumAdapterCapBps"),
    read(sleeve, sleeveAbi, "maximumOperatorLossBps"),
    read(sleeve, sleeveAbi, "eligibilityPolicy"),
    read(sleeve, sleeveAdapterAbi, "category"),
    read(sleeve, sleeveAdapterAbi, "accountingAsset"),
    read(sleeve, sleeveAdapterAbi, "allocator"),
    read(sleeve, sleeveAdapterAbi, "timelock"),
    read(sleeve, sleeveAdapterAbi, "guardian"),
    read(sleeve, sleeveAdapterAbi, "priceHub"),
    read(sleeve, sleeveAdapterAbi, "strategyRegistry"),
    read(sleeve, sleeveAdapterAbi, "adapters"),
    read(sleeve, sleeveAdapterAbi, "inventoryAssets"),
  ]);
  assert(Number(maximumStrategies) === policy.maximumStrategies,
    `${key} maximumStrategies mismatch`);
  assert(Number(maximumAdapterCapBps) === policy.maximumAdapterCapBps,
    `${key} maximumAdapterCapBps mismatch`);
  assert(Number(maximumOperatorLossBps) === policy.maximumOperatorLossBps,
    `${key} maximumOperatorLossBps mismatch`);
  assert(sameAddress(sleeveEligibilityPolicy, manifest.dependencies.eligibilityPolicy.address),
    `${key} eligibility policy mismatch`);
  assert(category.toLowerCase() === keccak256(stringToHex(categoryLabel)).toLowerCase()
    && sameAddress(actualAccountingAsset, accountingAsset)
    && sameAddress(allocator, manifest.contracts.allocator.address)
    && sameAddress(timelock, manifest.roles.timelock)
    && sameAddress(guardian, manifest.roles.guardian)
    && sameAddress(configuredPriceHub, manifest.contracts.priceHub.address)
    && sameAddress(configuredRegistry, manifest.contracts.strategyRegistry.address),
  `${key} sleeve immutable identity mismatch`);
  assert(configuredAdapters.length === 0,
    `${key} base sleeve contains an adapter not covered by this release`);
  const expectedInventory = key === "core"
    ? canonicalAddresses([
      manifest.dependencies.WETH.address,
      ...manifest.coreConstituents.map((constituent) => constituent.asset),
    ])
    : canonicalAddresses([accountingAsset]);
  assert(JSON.stringify(canonicalAddresses(inventoryAssets)) === JSON.stringify(expectedInventory),
    `${key} sleeve inventory does not match the reviewed release assets`);
}

const [onchainConstituents, onchainConstituentWeight] = await Promise.all([
  read(manifest.contracts.coreSleeve.address, coreSleeveAbi, "constituents"),
  read(manifest.contracts.coreSleeve.address, coreSleeveAbi, "constituentWeightTotal"),
]);
assert(Number(onchainConstituentWeight) === 10_000
  && onchainConstituents.length === manifest.coreConstituents.length,
"Core sleeve constituent count or weight total mismatch");
for (let index = 0; index < manifest.coreConstituents.length; ++index) {
  const expected = manifest.coreConstituents[index];
  const actual = onchainConstituents[index];
  assert(sameAddress(actual.asset, expected.asset) && sameAddress(actual.route, expected.route)
    && actual.routeRuntimeCodeHash.toLowerCase() === expected.routeRuntimeCodeHash.toLowerCase()
    && Number(actual.weightBps) === expected.weightBps,
  `Core sleeve constituent mismatch at index ${index}`);
  const [routeInput, routeOutput] = await Promise.all([
    read(expected.route, singlePoolRouteAbi, "inputAsset"),
    read(expected.route, singlePoolRouteAbi, "outputAsset"),
  ]);
  assert(sameAddress(routeInput, manifest.dependencies.WETH.address)
    && sameAddress(routeOutput, expected.asset),
  `Core constituent route direction mismatch for ${expected.route}`);
}

const [chainHealthy, guardianPaused] = await Promise.all([
  read(manifest.contracts.priceHub.address, priceHubAbi, "chainHealthy"),
  read(manifest.contracts.priceHub.address, priceHubAbi, "guardianPaused"),
]);
assert(chainHealthy === true, "PriceHub chain-health gate is not healthy");
assert(guardianPaused === false, "PriceHub guardian pause is active");
for (const binding of manifest.feeds) {
  const [config, feedDecimals, feedDescription, latestRound] = await Promise.all([
    read(manifest.contracts.priceHub.address, priceHubAbi, "feedConfig", [binding.asset]),
    read(binding.feed.address, aggregatorAbi, "decimals"),
    read(binding.feed.address, aggregatorAbi, "description"),
    read(binding.feed.address, aggregatorAbi, "latestRoundData"),
  ]);
  assert(sameAddress(config[0], binding.feed.address)
    && sameAddress(config[1], binding.referenceSource)
    && Number(config[2]) === binding.heartbeat
    && Number(config[3]) === binding.gracePeriod
    && Number(config[4]) === binding.maxDeviationBps
    && Number(config[5]) === binding.decimals
    && config[6].toLowerCase() === binding.feed.runtimeCodeHash.toLowerCase()
    && config[7].toLowerCase() === (sameAddress(
      binding.referenceSource, "0x0000000000000000000000000000000000000000",
    ) ? zeroBytes32 : manifestEntryFor(binding.referenceSource).runtimeCodeHash).toLowerCase()
    && config[8].toLowerCase() === hashText(binding.description).toLowerCase()
    && config[9] === true
    && config[10] === false
    && config[11] === binding.weekdaysOnly
    && config[12] === binding.checkAssetOraclePause,
  `PriceHub feed configuration mismatch for ${binding.asset}`);
  assert(Number(feedDecimals) === binding.decimals,
    `live feed decimals mismatch for ${binding.asset}`);
  assert(feedDescription === binding.description,
    `live feed description mismatch for ${binding.asset}`);
  const now = chainNow;
  assert(latestRound[0] > 0n && latestRound[1] > 0n && latestRound[2] > 0n
    && latestRound[3] >= latestRound[2] && latestRound[3] <= now,
  `live feed has invalid round data for ${binding.asset}`);
  if (!binding.weekdaysOnly) {
    assert(now - latestRound[3] <= BigInt(binding.heartbeat + binding.gracePeriod),
      `live feed is stale for ${binding.asset}`);
  }
  if (binding.checkAssetOraclePause) {
    const oraclePaused = await read(binding.asset, oraclePauseAbi, "oraclePaused");
    assert(oraclePaused === false, `asset oracle is paused for ${binding.asset}`);
  }
  if (binding.kind === "delta-v3-twap") {
    const matchingPools = manifest.deltaPools.filter((delta) =>
      sameAddress(delta.pairedAsset, binding.asset));
    assert(matchingPools.length === 1,
      `derived feed must bind exactly one reviewed Delta pool for ${binding.asset}`);
    const delta = matchingPools[0];
    const wethFeedBinding = feedBindingsByAsset.get(getAddress(manifest.dependencies.WETH.address));
    const state = await Promise.all([
      read(binding.feed.address, deltaTwapFeedAbi, "pairedAsset"),
      read(binding.feed.address, deltaTwapFeedAbi, "weth"),
      read(binding.feed.address, deltaTwapFeedAbi, "pool"),
      read(binding.feed.address, deltaTwapFeedAbi, "factory"),
      read(binding.feed.address, deltaTwapFeedAbi, "wethUsdFeed"),
      read(binding.feed.address, deltaTwapFeedAbi, "pairedAssetCodeHash"),
      read(binding.feed.address, deltaTwapFeedAbi, "wethCodeHash"),
      read(binding.feed.address, deltaTwapFeedAbi, "poolCodeHash"),
      read(binding.feed.address, deltaTwapFeedAbi, "factoryCodeHash"),
      read(binding.feed.address, deltaTwapFeedAbi, "wethUsdFeedCodeHash"),
      read(binding.feed.address, deltaTwapFeedAbi, "wethUsdFeedDescriptionHash"),
      read(binding.feed.address, deltaTwapFeedAbi, "twapWindow"),
      read(binding.feed.address, deltaTwapFeedAbi, "maxSpotDeviationBps"),
      read(binding.feed.address, deltaTwapFeedAbi, "comparisonAmount"),
      read(binding.feed.address, deltaTwapFeedAbi, "minimumLiquidity"),
    ]);
    assert(sameAddress(state[0], binding.asset)
      && sameAddress(state[1], manifest.dependencies.WETH.address)
      && sameAddress(state[2], delta.pool) && sameAddress(state[3], delta.factory)
      && sameAddress(state[4], wethFeedBinding.feed.address)
      && state[5].toLowerCase() === manifestEntryFor(binding.asset).runtimeCodeHash.toLowerCase()
      && state[6].toLowerCase() === manifest.dependencies.WETH.runtimeCodeHash.toLowerCase()
      && state[7].toLowerCase() === manifestEntryFor(delta.pool).runtimeCodeHash.toLowerCase()
      && state[8].toLowerCase() === manifestEntryFor(delta.factory).runtimeCodeHash.toLowerCase()
      && state[9].toLowerCase() === wethFeedBinding.feed.runtimeCodeHash.toLowerCase()
      && state[10].toLowerCase() === hashText(wethFeedBinding.description).toLowerCase()
      && Number(state[11]) === binding.twapWindow
      && Number(state[12]) === binding.maxSpotDeviationBps
      && state[13] === BigInt(binding.comparisonAmount)
      && state[14] === BigInt(binding.minimumLiquidity),
    `derived Delta V3 TWAP feed binding mismatch for ${binding.asset}`);
  }
}

const marketMakingCategory = keccak256(stringToHex("YIELD_BANK_MARKET_MAKING"));
for (const delta of manifest.deltaPools) {
  const adapterEntry = manifestEntryFor(delta.adapter);
  const sleeveEntry = manifestEntryFor(delta.sleeve);
  const poolEntry = manifestEntryFor(delta.pool);
  const builderEntry = manifestEntryFor(delta.positionBuilder);
  const managerEntry = manifestEntryFor(delta.positionManager);
  const factoryEntry = manifestEntryFor(delta.factory);
  const entryRouteEntry = manifestEntryFor(delta.entryRoute);
  const exitRouteEntry = manifestEntryFor(delta.exitRoute);
  assert(adapterEntry && sleeveEntry && poolEntry && builderEntry && managerEntry && factoryEntry
    && entryRouteEntry && exitRouteEntry, `Delta manifest entry missing for pool ${delta.pool}`);

  const deltaAddressFields = [
    ["sleeve", delta.sleeve],
    ["accountingAsset", manifest.dependencies.WETH.address],
    ["pairedAsset", delta.pairedAsset],
    ["priceHub", manifest.contracts.priceHub.address],
    ["pool", delta.pool],
    ["factory", delta.factory],
    ["positionManager", delta.positionManager],
    ["positionBuilder", delta.positionBuilder],
    ["entryRoute", delta.entryRoute],
    ["exitRoute", delta.exitRoute],
  ];
  const deltaHashFields = [
    ["poolCodeHash", poolEntry.runtimeCodeHash],
    ["factoryCodeHash", factoryEntry.runtimeCodeHash],
    ["positionManagerCodeHash", managerEntry.runtimeCodeHash],
    ["positionBuilderCodeHash", builderEntry.runtimeCodeHash],
    ["entryRouteCodeHash", entryRouteEntry.runtimeCodeHash],
    ["exitRouteCodeHash", exitRouteEntry.runtimeCodeHash],
  ];
  const [deltaAddresses, deltaHashes, maximumPositions, strategyRecord,
    sleeveAdapterState, sleeveAdapterCap, sleeveMaximumStrategies, configuredAdapters,
    sleeveCategory, sleeveAccountingAsset, sleeveAllocator, registeredSleeveAsset,
    allocatorPoolBinding, reversePoolBinding, poolFactory, token0, token1, poolFee,
    poolTickSpacing, poolLiquidity, poolSlot0, factoryPool, builderFactory,
    builderManager, builderWeth, managerFactory, managerWeth] = await Promise.all([
    Promise.all(deltaAddressFields.map(([field]) => read(delta.adapter, deltaAdapterAbi, field))),
    Promise.all(deltaHashFields.map(([field]) => read(delta.adapter, deltaAdapterAbi, field))),
    read(delta.adapter, deltaAdapterAbi, "maximumPositions"),
    read(manifest.contracts.strategyRegistry.address, strategyRegistryAbi, "recordOf", [delta.adapter]),
    read(delta.sleeve, sleeveAdapterAbi, "adapterState", [delta.adapter]),
    read(delta.sleeve, sleeveAdapterAbi, "adapterCapBps", [delta.adapter]),
    read(delta.sleeve, sleeveAdapterAbi, "maximumStrategies"),
    read(delta.sleeve, sleeveAdapterAbi, "adapters"),
    read(delta.sleeve, sleeveAdapterAbi, "category"),
    read(delta.sleeve, sleeveAdapterAbi, "accountingAsset"),
    read(delta.sleeve, sleeveAdapterAbi, "allocator"),
    read(manifest.contracts.collection.address, collectionSleeveAbi, "isSleeveAsset", [delta.sleeve]),
    read(manifest.contracts.allocator.address, allocatorAbi, "deltaPoolBinding", [delta.pool]),
    read(manifest.contracts.allocator.address, allocatorAbi, "deltaPoolOfSleeve", [delta.sleeve]),
    read(delta.pool, v3PoolAbi, "factory"),
    read(delta.pool, v3PoolAbi, "token0"),
    read(delta.pool, v3PoolAbi, "token1"),
    read(delta.pool, v3PoolAbi, "fee"),
    read(delta.pool, v3PoolAbi, "tickSpacing"),
    read(delta.pool, v3PoolAbi, "liquidity"),
    read(delta.pool, v3PoolAbi, "slot0"),
    read(delta.factory, v3FactoryAbi, "getPool", [
      manifest.dependencies.WETH.address, delta.pairedAsset, delta.fee,
    ]),
    read(delta.positionBuilder, positionBuilderAbi, "uniFactory"),
    read(delta.positionBuilder, positionBuilderAbi, "positionManager"),
    read(delta.positionBuilder, positionBuilderAbi, "weth"),
    read(delta.positionManager, positionManagerAbi, "factory"),
    read(delta.positionManager, positionManagerAbi, "WETH9"),
  ]);
  deltaAddressFields.forEach(([field, expected], index) => assert(
    sameAddress(deltaAddresses[index], expected),
    `Delta adapter ${delta.adapter} ${field} mismatch`,
  ));
  deltaHashFields.forEach(([field, expected], index) => assert(
    deltaHashes[index].toLowerCase() === expected.toLowerCase(),
    `Delta adapter ${delta.adapter} ${field} mismatch`,
  ));
  assert(Number(maximumPositions) === delta.maximumPositions,
    `Delta adapter maximumPositions mismatch for ${delta.adapter}`);
  assert(sameAddress(strategyRecord.implementation, delta.adapter)
    && strategyRecord.runtimeCodeHash.toLowerCase() === adapterEntry.runtimeCodeHash.toLowerCase()
    && strategyRecord.sleeveCategory.toLowerCase() === marketMakingCategory.toLowerCase()
    && sameAddress(strategyRecord.accountingAsset, manifest.dependencies.WETH.address)
    && Number(strategyRecord.state) === 1,
  `Delta adapter registry record mismatch for ${delta.adapter}`);
  assert(Number(sleeveAdapterState) === 3,
    `Delta adapter is not ACTIVE for ${delta.adapter}`);
  assert(Number(sleeveAdapterCap) === delta.adapterCapBps,
    `Delta adapter cap mismatch for ${delta.adapter}`);
  assert(Number(sleeveMaximumStrategies) === 1 && configuredAdapters.length === 1
    && sameAddress(configuredAdapters[0], delta.adapter),
  `Delta sleeve is not isolated to its one adapter for ${delta.sleeve}`);
  assert(sleeveCategory.toLowerCase() === marketMakingCategory.toLowerCase()
    && sameAddress(sleeveAccountingAsset, manifest.dependencies.WETH.address)
    && sameAddress(sleeveAllocator, manifest.contracts.allocator.address)
    && registeredSleeveAsset === true
    && !sameAddress(delta.sleeve, manifest.contracts.marketMakingSleeve.address),
  `Delta sleeve identity mismatch for ${delta.sleeve}`);
  assert(sameAddress(allocatorPoolBinding[0], delta.sleeve)
    && sameAddress(allocatorPoolBinding[1], delta.adapter)
    && allocatorPoolBinding[2].toLowerCase() === poolEntry.runtimeCodeHash.toLowerCase()
    && allocatorPoolBinding[3].toLowerCase() === sleeveEntry.runtimeCodeHash.toLowerCase()
    && allocatorPoolBinding[4].toLowerCase() === adapterEntry.runtimeCodeHash.toLowerCase()
    && sameAddress(reversePoolBinding, delta.pool),
  `allocator Delta pool binding mismatch for ${delta.pool}`);
  assert(sameAddress(poolFactory, delta.factory)
    && ((sameAddress(token0, manifest.dependencies.WETH.address)
      && sameAddress(token1, delta.pairedAsset))
      || (sameAddress(token0, delta.pairedAsset)
        && sameAddress(token1, manifest.dependencies.WETH.address)))
    && Number(poolFee) === delta.fee
    && Number(poolTickSpacing) === delta.tickSpacing
    && poolLiquidity > 0n && poolSlot0[6] === true
    && sameAddress(factoryPool, delta.pool),
  `live Delta pool identity or liquidity mismatch for ${delta.pool}`);
  assert(sameAddress(builderFactory, delta.factory)
    && sameAddress(builderManager, delta.positionManager)
    && sameAddress(builderWeth, manifest.dependencies.WETH.address)
    && sameAddress(managerFactory, delta.factory)
    && sameAddress(managerWeth, manifest.dependencies.WETH.address),
  `Delta builder/manager dependency graph mismatch for ${delta.adapter}`);

  for (const [route, inputAsset, outputAsset, routeEntry] of [
    [delta.entryRoute, manifest.dependencies.WETH.address, delta.pairedAsset, entryRouteEntry],
    [delta.exitRoute, delta.pairedAsset, manifest.dependencies.WETH.address, exitRouteEntry],
  ]) {
    const routeState = await Promise.all([
      read(route, singlePoolRouteAbi, "inputAsset"),
      read(route, singlePoolRouteAbi, "outputAsset"),
      read(route, singlePoolRouteAbi, "pool"),
      read(route, singlePoolRouteAbi, "factory"),
      read(route, singlePoolRouteAbi, "poolCodeHash"),
      read(route, singlePoolRouteAbi, "factoryCodeHash"),
    ]);
    assert(sameAddress(routeState[0], inputAsset) && sameAddress(routeState[1], outputAsset)
      && sameAddress(routeState[2], delta.pool) && sameAddress(routeState[3], delta.factory)
      && routeState[4].toLowerCase() === poolEntry.runtimeCodeHash.toLowerCase()
      && routeState[5].toLowerCase() === factoryEntry.runtimeCodeHash.toLowerCase()
      && routeEntry.runtimeCodeHash.toLowerCase()
        === manifestEntryFor(route).runtimeCodeHash.toLowerCase(),
    `Delta route direction or dependency binding mismatch for ${route}`);
  }
}
for (const binding of manifest.routeBindings.allocations) {
  const actual = await read(manifest.contracts.allocator.address, allocatorAbi, "routeBinding", [
    binding.inputAsset, binding.sleeve,
  ]);
  const [routeInput, routeOutput, sleeveAccounting] = await Promise.all([
    read(binding.route, singlePoolRouteAbi, "inputAsset"),
    read(binding.route, singlePoolRouteAbi, "outputAsset"),
    read(binding.sleeve, sleeveAdapterAbi, "accountingAsset"),
  ]);
  assert(sameAddress(actual[0], binding.route)
    && actual[1].toLowerCase() === binding.runtimeCodeHash.toLowerCase(),
  `allocation route binding mismatch for ${binding.inputAsset} -> ${binding.sleeve}`);
  assert(sameAddress(routeInput, binding.inputAsset)
    && sameAddress(routeOutput, sleeveAccounting)
    && !sameAddress(binding.inputAsset, sleeveAccounting),
  `allocation route direction is wrong or redundant for ${binding.route}`);
}
for (const binding of manifest.routeBindings.rebalances) {
  const actual = await read(manifest.contracts.allocator.address, allocatorAbi, "rebalanceRoute", [
    binding.inputAsset,
  ]);
  const [routeInput, routeOutput] = await Promise.all([
    read(binding.route, singlePoolRouteAbi, "inputAsset"),
    read(binding.route, singlePoolRouteAbi, "outputAsset"),
  ]);
  assert(sameAddress(actual[0], binding.route)
    && actual[1].toLowerCase() === binding.runtimeCodeHash.toLowerCase(),
  `rebalance route binding mismatch for ${binding.inputAsset}`);
  assert(sameAddress(routeInput, binding.inputAsset)
    && sameAddress(routeOutput, manifest.dependencies.WETH.address),
  `rebalance route direction mismatch for ${binding.route}`);
}

console.log(JSON.stringify({
  status: "verified",
  manifest: manifestPath,
  chainId: manifest.chainId,
  collection: manifest.contracts.collection.address,
  nft: manifest.contracts.nft.address,
  proceedsVault: manifest.contracts.proceedsVault.address,
  deltaPools: manifest.deltaPools.map(({ pool, sleeve, adapter }) => ({ pool, sleeve, adapter })),
  contractsVerified: entries.length,
}, null, 2));
