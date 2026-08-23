import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import test from "node:test";
import { decodeFunctionData, hashTypedData } from "viem";
import { airdropCommitmentTypedData, buildFundingBandCreationActions, buildAirdropEpoch, buildVerifiedAirdropEpoch, buildLaunchFromPreset, encodeGovernanceAction, encodeMultisigSubmission, encodeTokenGovernanceProposal, erc4626BasketYieldAdapterFactoryAbi, fundingBandDestination, marketCapUsdE8, projectFundingBandsV2Abi, projectGovernorV2Abi, projectLauncherV2Abi, projectMultisigAccountV2Abi, projectRegistryV2Abi, projectTreasuryVaultV2Abi, simpleFundingBandConfig, launchErrorMessage, } from "../src/index.js";
const fixture = JSON.parse(await readFile(resolve(process.cwd(), "fixtures/treasury-send.json"), "utf8"));
const airdropFixture = JSON.parse(await readFile(resolve(process.cwd(), "fixtures/airdrop-tree.json"), "utf8"));
test("exports the required project discovery and launch ABI", () => {
    assert.ok(projectLauncherV2Abi.some((item) => item.type === "function" && item.name === "predictLaunch"));
    assert.ok(projectLauncherV2Abi.some((item) => item.type === "function" && item.name === "validateLaunchConfig"));
    assert.ok(projectRegistryV2Abi.some((item) => item.type === "function" && item.name === "project"));
    assert.ok(erc4626BasketYieldAdapterFactoryAbi.some((item) => item.type === "function" && item.name === "predict"));
});
test("encodes the shared Treasury governance action fixture", () => {
    const action = encodeGovernanceAction({
        target: fixture.target,
        abi: projectTreasuryVaultV2Abi,
        functionName: "send",
        args: [fixture.asset, BigInt(fixture.amount), fixture.recipient],
        value: BigInt(fixture.value),
    });
    assert.deepEqual(action, {
        target: fixture.target,
        value: 0n,
        data: fixture.calldata,
    });
    assert.deepEqual(decodeFunctionData({ abi: projectTreasuryVaultV2Abi, data: action.data }), {
        functionName: "send",
        args: [fixture.asset, BigInt(fixture.amount), fixture.recipient],
    });
});
test("builds one atomic funding-band governance batch from product-level choices", () => {
    const treasury = "0x0000000000000000000000000000000000001000";
    const fundingBands = "0x0000000000000000000000000000000000002000";
    const subject = "0x0000000000000000000000000000000000003000";
    const config = simpleFundingBandConfig({
        lowerMarketCapUsd: "1000000",
        upperMarketCapUsd: "2000000",
        subjectAmount: 25000n,
        destination: fundingBandDestination.basketViaTreasury,
    });
    const actions = buildFundingBandCreationActions({ treasury, fundingBands, subject, config });
    assert.equal(config.lowerMarketCapUsdE8, marketCapUsdE8("1000000"));
    assert.deepEqual(decodeFunctionData({ abi: projectTreasuryVaultV2Abi, data: actions[0].data }), { functionName: "send", args: [subject, 25000n, fundingBands] });
    assert.deepEqual(decodeFunctionData({ abi: projectFundingBandsV2Abi, data: actions[1].data }), { functionName: "createBand", args: [config, "0x"] });
    assert.equal(decodeFunctionData({
        abi: projectMultisigAccountV2Abi,
        data: encodeMultisigSubmission(actions),
    }).functionName, "submit");
    assert.equal(decodeFunctionData({
        abi: projectGovernorV2Abi,
        data: encodeTokenGovernanceProposal(actions, "Create the $1M-$2M funding band"),
    }).functionName, "propose");
});
test("rejects invalid funding-band product inputs before wallet submission", () => {
    assert.throws(() => simpleFundingBandConfig({
        lowerMarketCapUsd: "2",
        upperMarketCapUsd: "1",
        subjectAmount: 1n,
        destination: fundingBandDestination.creator,
    }), /Upper market cap/);
    assert.throws(() => marketCapUsdE8("0"), /greater than zero/);
});
test("hydrates a reviewed launch preset from creator-owned fields only", () => {
    const curatedConfig = {
        governanceMode: 1,
        launchProfile: { canonicalPool: "0x0000000000000000000000000000000000009000" },
    };
    const config = buildLaunchFromPreset({ id: "base-all-modules", protocolVersion: "2.0.0", config: curatedConfig }, {
        creator: "0x0000000000000000000000000000000000001000",
        name: " Project ",
        symbol: " PRJ ",
        totalSupply: 1000n,
        salt: `0x${"11".repeat(32)}`,
        tokenAllocations: [
            { recipient: "0x0000000000000000000000000000000000002000", amount: 750n },
            { recipient: "0x0000000000000000000000000000000000003000", amount: 250n },
        ],
    });
    assert.equal(config.name, "Project");
    assert.equal(config.symbol, "PRJ");
    assert.equal(config.governanceMode, 1);
    assert.deepEqual(config.launchProfile, curatedConfig.launchProfile);
});
test("rejects creator mistakes locally and returns corrective launch copy", () => {
    const preset = {
        id: "reviewed",
        protocolVersion: "2.0.0",
        config: {},
    };
    assert.throws(() => buildLaunchFromPreset(preset, {
        creator: "0x0000000000000000000000000000000000001000",
        name: "Project",
        symbol: "PRJ",
        totalSupply: 10n,
        salt: `0x${"22".repeat(32)}`,
        tokenAllocations: [
            { recipient: "0x0000000000000000000000000000000000002000", amount: 9n },
        ],
    }), /add up to the total supply exactly/);
    assert.match(launchErrorMessage("InvalidModuleDependencies"), /requires another feature/);
});
test("builds sorted proportional Airdrop leaves and direction-aware proofs", () => {
    const epoch = buildAirdropEpoch({
        chainId: 8453n,
        airdrop: "0x0000000000000000000000000000000000001000",
        accountId: `0x${"aa".repeat(32)}`,
        epochId: 1n,
        snapshotBlock: 100n,
        snapshotBlockHash: `0x${"bb".repeat(32)}`,
        snapshotTime: 1000n,
        epochAmount: 10n,
        expectedTotalEligibleWeight: 100n,
        weights: [
            { holder: "0x0000000000000000000000000000000000000003", weight: 1n },
            { holder: "0x0000000000000000000000000000000000000001", weight: 49n },
            { holder: "0x0000000000000000000000000000000000000002", weight: 50n },
        ],
    });
    assert.deepEqual(epoch.leaves.map((leaf) => leaf.holder), [
        "0x0000000000000000000000000000000000000001",
        "0x0000000000000000000000000000000000000002",
        "0x0000000000000000000000000000000000000003",
    ]);
    assert.deepEqual(epoch.leaves.map((leaf) => leaf.amount), [4n, 5n, 0n]);
    assert.equal(epoch.commitment.rootSum, 9n);
    assert.equal(epoch.commitment.leafCount, 3);
    assert.equal(epoch.proofs.length, 3);
    assert.equal(epoch.proofs[0]?.nodes[0]?.siblingOnLeft, false);
    assert.equal(epoch.proofs[1]?.nodes[0]?.siblingOnLeft, true);
    assert.equal(epoch.proofs[2]?.nodes.length, 1);
});
test("rejects incomplete, duplicate, or excluded Airdrop snapshots before signing", () => {
    const base = {
        chainId: 8453n,
        airdrop: "0x0000000000000000000000000000000000001000",
        accountId: `0x${"aa".repeat(32)}`,
        epochId: 1n,
        snapshotBlock: 100n,
        snapshotBlockHash: `0x${"bb".repeat(32)}`,
        snapshotTime: 1000n,
        epochAmount: 10n,
    };
    assert.throws(() => buildAirdropEpoch({
        ...base,
        expectedTotalEligibleWeight: 2n,
        weights: [{ holder: "0x0000000000000000000000000000000000000001", weight: 1n }],
    }), /eligible supply/);
    assert.throws(() => buildAirdropEpoch({
        ...base,
        weights: [
            { holder: "0x0000000000000000000000000000000000000001", weight: 1n },
            { holder: "0x0000000000000000000000000000000000000001", weight: 1n },
        ],
    }), /Duplicate/);
    assert.throws(() => buildAirdropEpoch({
        ...base,
        exclusions: ["0x000000000000000000000000000000000000dEaD"],
        weights: [{ holder: "0x000000000000000000000000000000000000dEaD", weight: 1n }],
    }), /Excluded holder/);
});
test("matches the shared Solidity Airdrop tree fixture exactly", () => {
    const epoch = buildAirdropEpoch({
        chainId: BigInt(airdropFixture.chainId),
        airdrop: airdropFixture.airdrop,
        accountId: airdropFixture.accountId,
        epochId: BigInt(airdropFixture.epochId),
        snapshotBlock: BigInt(airdropFixture.snapshotBlock),
        snapshotBlockHash: airdropFixture.snapshotBlockHash,
        snapshotTime: BigInt(airdropFixture.snapshotTime),
        epochAmount: BigInt(airdropFixture.epochAmount),
        expectedTotalEligibleWeight: BigInt(airdropFixture.totalEligibleWeight),
        weights: [...airdropFixture.holders].reverse().map(({ holder, weight }) => ({
            holder,
            weight: BigInt(weight),
        })),
    });
    assert.deepEqual(epoch.leaves.map(({ holder, weight, amount }) => ({
        holder,
        weight: weight.toString(),
        amount: amount.toString(),
    })), airdropFixture.holders.map(({ holder, weight, amount }) => ({ holder, weight, amount })));
    assert.equal(epoch.commitment.rootHash, airdropFixture.rootHash);
    assert.equal(epoch.commitment.rootSum.toString(), airdropFixture.rootSum);
    assert.equal(epoch.commitment.leafCount, airdropFixture.leafCount);
    assert.equal(epoch.commitment.artifactHash, airdropFixture.artifactHash);
    assert.equal(hashTypedData(airdropCommitmentTypedData(Number(airdropFixture.chainId), airdropFixture.airdrop, epoch.commitment)), airdropFixture.typedDataDigest);
});
test("requires two matching provider snapshots before building a signable Airdrop epoch", () => {
    const weights = airdropFixture.holders.map(({ holder, weight }) => ({
        holder,
        weight: BigInt(weight),
    }));
    const primarySnapshot = {
        snapshotBlock: BigInt(airdropFixture.snapshotBlock),
        snapshotBlockHash: airdropFixture.snapshotBlockHash,
        snapshotTime: BigInt(airdropFixture.snapshotTime),
        totalEligibleWeight: BigInt(airdropFixture.totalEligibleWeight),
        weights,
    };
    const epoch = buildVerifiedAirdropEpoch({
        chainId: BigInt(airdropFixture.chainId),
        airdrop: airdropFixture.airdrop,
        accountId: airdropFixture.accountId,
        epochId: BigInt(airdropFixture.epochId),
        epochAmount: BigInt(airdropFixture.epochAmount),
        primarySnapshot,
        secondarySnapshot: { ...primarySnapshot, weights: [...weights].reverse() },
    });
    assert.equal(epoch.commitment.rootHash, airdropFixture.rootHash);
    assert.throws(() => buildVerifiedAirdropEpoch({
        chainId: BigInt(airdropFixture.chainId),
        airdrop: airdropFixture.airdrop,
        accountId: airdropFixture.accountId,
        epochId: BigInt(airdropFixture.epochId),
        epochAmount: BigInt(airdropFixture.epochAmount),
        primarySnapshot,
        secondarySnapshot: {
            ...primarySnapshot,
            snapshotBlockHash: `0x${"cc".repeat(32)}`,
        },
    }), /providers disagree.*do not sign/i);
    assert.throws(() => buildVerifiedAirdropEpoch({
        chainId: BigInt(airdropFixture.chainId),
        airdrop: airdropFixture.airdrop,
        accountId: airdropFixture.accountId,
        epochId: BigInt(airdropFixture.epochId),
        epochAmount: BigInt(airdropFixture.epochAmount),
        primarySnapshot,
        secondarySnapshot: {
            ...primarySnapshot,
            weights: weights.map((entry, index) => index === 0
                ? { ...entry, weight: entry.weight - 1n }
                : entry),
            totalEligibleWeight: BigInt(airdropFixture.totalEligibleWeight) - 1n,
        },
    }), /providers disagree.*do not sign/i);
});
//# sourceMappingURL=sdk.test.js.map