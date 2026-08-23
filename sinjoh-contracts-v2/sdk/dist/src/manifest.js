import { getAddress, isAddress, isHex, keccak256, stringToHex, } from "viem";
/**
 * Produces a JSON-safe project provenance artifact after launch. The caller supplies the exact
 * preflight result and Registry readback; any address, identity, mode, supply, or module mismatch
 * fails before an artifact can be published.
 */
export function buildProjectLaunchManifest(parameters) {
    const { config, preview, record, release } = parameters;
    if (parameters.chainId <= 0n)
        throw new RangeError("Chain ID must be greater than zero");
    if (parameters.blockNumber < 0n)
        throw new RangeError("Block number cannot be negative");
    assertBytes32(parameters.transactionHash, "Transaction hash");
    assertBytes32(parameters.registeredLaunchConfigHash, "Registered launch config hash");
    assertReleaseReference(release);
    if (preview.launchConfigHash.toLowerCase() !== parameters.registeredLaunchConfigHash.toLowerCase()) {
        throw new Error("Registry launch config hash does not match the validated preflight");
    }
    if (preview.projectId.toLowerCase() !== record.projectId.toLowerCase()) {
        throw new Error("Registry project ID does not match the validated preflight");
    }
    assertSameAddress(preview.addresses.subject, record.subject, "subject");
    assertSameAddress(preview.addresses.controller, record.controller, "controller");
    assertSameAddress(config.creator, record.creator, "creator");
    if (BigInt(preview.enabledModules) !== BigInt(record.enabledModules)) {
        throw new Error("Registry enabled modules do not match the validated preflight");
    }
    if (BigInt(config.totalSupply) !== BigInt(record.referenceSupply)) {
        throw new Error("Registry reference supply does not match the launch configuration");
    }
    if (Number(config.governanceMode) !== Number(record.governanceMode)) {
        throw new Error("Registry governance mode does not match the launch configuration");
    }
    const addressPairs = [
        [preview.addresses.multisigAccount, record.multisigAccount, "Multisig Account"],
        [preview.addresses.tokenGovernor, record.tokenGovernor, "Token Governor"],
        [preview.addresses.tokenTimelock, record.tokenTimelock, "Token Timelock"],
        [preview.addresses.voteSource, record.voteSource, "vote source"],
        [preview.addresses.treasury, record.treasury, "Treasury"],
        [preview.addresses.router, record.router, "Router"],
        [preview.addresses.stakingPool, record.stakingPool, "Staking Pool"],
        [preview.addresses.posNft, record.posNft, "PoS NFT"],
        [preview.addresses.airdrop, record.airdrop, "Airdrop"],
        [preview.addresses.raffle, record.raffle, "Raffle"],
        [preview.addresses.liquidityManager, record.liquidityManager, "Liquidity Manager"],
        [preview.addresses.fundingBands, record.fundingBands, "Funding Bands"],
        [preview.addresses.basketManager, record.basketManager, "Basket Manager"],
    ];
    for (const [predicted, registered, label] of addressPairs) {
        assertSameAddress(predicted, registered, label);
    }
    if (BigInt(preview.addresses.primaryBasketId) !== BigInt(record.primaryBasketId)) {
        throw new Error("Registry primary Basket ID does not match the validated preflight");
    }
    assertSameAddress(config.launchProfile.canonicalPool, record.canonicalPool, "canonical pool");
    return {
        schemaVersion: "1.0",
        chainId: parameters.chainId.toString(),
        transactionHash: parameters.transactionHash,
        blockNumber: parameters.blockNumber.toString(),
        release: {
            ...release,
            launcher: getAddress(release.launcher),
            registry: getAddress(release.registry),
        },
        launchConfigHash: parameters.registeredLaunchConfigHash,
        projectId: record.projectId,
        subject: getAddress(record.subject),
        creator: getAddress(record.creator),
        controller: getAddress(record.controller),
        enabledModules: BigInt(record.enabledModules).toString(),
        configuration: jsonValue(config),
        predictedAddresses: jsonValue(preview.addresses),
        registryRecord: jsonValue(record),
    };
}
/** Stable serialization for storage, signing, or hashing. Object keys are sorted recursively. */
export function serializeProjectLaunchManifest(manifest) {
    return JSON.stringify(sortJson(manifest));
}
export function projectLaunchManifestHash(manifest) {
    return keccak256(stringToHex(serializeProjectLaunchManifest(manifest)));
}
function jsonValue(value) {
    if (typeof value === "bigint")
        return value.toString();
    if (value === null || typeof value === "boolean" || typeof value === "number" || typeof value === "string") {
        return value;
    }
    if (Array.isArray(value))
        return value.map(jsonValue);
    if (typeof value === "object") {
        return Object.fromEntries(Object.entries(value).map(([key, child]) => [key, jsonValue(child)]));
    }
    throw new TypeError(`Launch manifest cannot encode ${typeof value}`);
}
function sortJson(value) {
    if (Array.isArray(value))
        return value.map(sortJson);
    if (value !== null && typeof value === "object") {
        const record = value;
        return Object.fromEntries(Object.keys(record).sort().map((key) => [key, sortJson(record[key])]));
    }
    return value;
}
function assertReleaseReference(release) {
    if (!/^(0x)?(?:[0-9a-fA-F]{40}|[0-9a-fA-F]{64})$/.test(release.gitCommit)) {
        throw new RangeError("Release git commit must be a 20-byte or 32-byte commit hash");
    }
    if (!/^(0x)?[0-9a-fA-F]{64}$/.test(release.buildHash)) {
        throw new RangeError("Release build hash must be 32 bytes");
    }
    assertAddress(release.launcher, "Release Launcher");
    assertAddress(release.registry, "Release Registry");
}
function assertSameAddress(left, right, label) {
    if (left.toLowerCase() !== right.toLowerCase()) {
        throw new Error(`Registry ${label} does not match the validated preflight`);
    }
}
function assertAddress(value, label) {
    if (!isAddress(value) || /^0x0{40}$/i.test(value)) {
        throw new RangeError(`${label} must be a valid nonzero address`);
    }
}
function assertBytes32(value, label) {
    if (!isHex(value) || value.length !== 66)
        throw new RangeError(`${label} must be exactly 32 bytes`);
}
//# sourceMappingURL=manifest.js.map