import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import test from "node:test";
import { decodeFunctionData, hashTypedData } from "viem";
import { airdropCommitmentTypedData, buildFundingBandCreationActions, buildAirdropEpoch, buildVerifiedAirdropEpoch, buildLaunchFromPreset, buildProjectLaunchConfig, buildProjectLaunchManifest, encodeAirdropAbortCall, encodeGovernanceAction, encodeAirdropFinalizeCall, encodeAirdropPushCalls, encodeAirdropRetryCreditCall, encodeAirdropClaimCreditToCall, encodeMultisigSubmission, encodeTokenGovernanceProposal, erc4626BasketYieldAdapterFactoryAbi, fundingBandDestination, fundingBandFactoryIntegrationApprovalLeaf, fundingBandPairIntegrationApprovalLeaf, swapIntegrationApprovalLeaf, marketCapUsdE8, projectLaunchManifestHash, projectAirdropV2Abi, projectFundingBandsV2Abi, projectGovernorV2Abi, projectLauncherV2Abi, projectMultisigAccountV2Abi, projectRegistryV2Abi, projectTreasuryVaultV2Abi, simpleFundingBandConfig, launchErrorMessage, launchpadFactoryApprovalLeaf, planAirdropPushBatches, reconstructHolderAirdropSnapshot, reconstructStakerAirdropSnapshot, serializeProjectLaunchManifest, } from "../src/index.js";
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
test("builds Solidity-identical release approval leaves", () => {
    assert.equal(launchpadFactoryApprovalLeaf({
        chainId: 8453n,
        factory: "0x0000000000000000000000000000000000001234",
        factoryRuntimeHash: `0x${"ab".repeat(32)}`,
    }), "0x061d585aaf83bb23e08c44bd63af3d43beb2ed43256fdca6e8d104dbfd2a7d6d");
    assert.equal(fundingBandFactoryIntegrationApprovalLeaf({
        chainId: 8453n,
        integrationFactory: "0x0000000000000000000000000000000000001000",
        v3Factory: "0x0000000000000000000000000000000000002000",
        v3FactoryRuntimeHash: `0x${"11".repeat(32)}`,
        quoteAsset: "0x0000000000000000000000000000000000003000",
        positionManager: "0x0000000000000000000000000000000000004000",
        positionManagerRuntimeHash: `0x${"44".repeat(32)}`,
        quoteUsdOracle: "0x0000000000000000000000000000000000005000",
        quoteUsdOracleRuntimeHash: `0x${"55".repeat(32)}`,
    }), "0x8b599ff7c8af966443ec43195e4a98f43687a1cd2ae1bffcf160b688b98b70a6");
    assert.equal(fundingBandPairIntegrationApprovalLeaf({
        chainId: 8453n,
        marketCapGuard: "0x0000000000000000000000000000000000006000",
        marketCapGuardRuntimeHash: `0x${"66".repeat(32)}`,
        positionAdapter: "0x0000000000000000000000000000000000007000",
        positionAdapterRuntimeHash: `0x${"77".repeat(32)}`,
    }), "0x65ddcc69d8940e9984c4599a44a1f18b98329eb956a16ab2efdaf778aeb52ddd");
    assert.equal(swapIntegrationApprovalLeaf({
        chainId: 8453n,
        adapter: "0x0000000000000000000000000000000000008000",
        adapterRuntimeHash: `0x${"88".repeat(32)}`,
        priceGuard: "0x0000000000000000000000000000000000009000",
        priceGuardRuntimeHash: `0x${"99".repeat(32)}`,
    }), "0x0f8910b46062a14419552a66b4a825d137cb506870a3f548c885256124efdb38");
});
test("builds launchpad governance without a second token allocation or preset-owned identities", () => {
    const zero = "0x0000000000000000000000000000000000000000";
    const policy = {
        id: "release-policy",
        protocolVersion: "2.0.0",
        modules: {
            treasury: true, router: true, staking: false, airdrop: false,
            basket: false, fundingBands: false, raffle: false, liquidity: false,
        },
        treasury: { basketAllocationBps: 0, basketRouteAssets: [] },
        routerRoutes: [],
        basket: {
            cadence: 0, eligibilityMode: 0, governanceUpdatesEnabled: false,
            burnTaxBps: 0, burnTaxDestination: 0, burnPriceSubject: 0n,
            airdropAccountConfig: "0x",
            allocation: { inputAssets: [], targets: [], swapLegs: [] },
        },
        basketERC4626Vaults: [],
        bands: {
            quoteAsset: zero, marketCapGuard: zero, positionAdapter: zero,
            twapWindow: 0, quoteUsdOracle: zero, confirmationPeriod: 0,
            maximumObservationAge: 0, integrationApprovalProof: [],
        },
        raffle: {
            creator: zero, attestor: zero, randomness: zero, prizeAsset: zero,
            protocolFeeRecipient: zero, taxRecipient: zero, tokensPerTicket: 0n,
            maxTicketsPerHolder: 0n, minPrize: 0n, maxPrize: 0n, prizeBps: 0,
            recipientTaxBps: 0, recycleTaxBps: 0, minConfirmations: 0,
            winnersPerRound: 0, minRoundInterval: 0, weightWindowBlocks: 0,
            randomnessTimeout: 0, claimWindow: 0, basis: 0, exclusions: [], stockRewards: [],
        },
        launchProfile: { canonicalPool: zero, additionalCustodyExclusions: [] },
    };
    const config = buildProjectLaunchConfig(policy, {
        creator: "0x0000000000000000000000000000000000001000",
        name: "Canonical",
        symbol: "ONE",
        totalSupply: 1000n,
        salt: `0x${"12".repeat(32)}`,
        distribution: "launchpad",
        governance: {
            mode: "multisig",
            voteSource: 0,
            multisigSigners: [
                "0x0000000000000000000000000000000000003000",
                "0x0000000000000000000000000000000000001000",
                "0x0000000000000000000000000000000000002000",
            ],
        },
    });
    assert.deepEqual(config.tokenAllocations, []);
    assert.deepEqual(config.governance.multisigSigners, [
        "0x0000000000000000000000000000000000001000",
        "0x0000000000000000000000000000000000002000",
        "0x0000000000000000000000000000000000003000",
    ]);
    assert.equal(config.governance.tokenGovernance.referenceSupply, 1000n);
    assert.throws(() => buildProjectLaunchConfig(policy, {
        creator: "0x0000000000000000000000000000000000001000",
        name: "Wrong",
        symbol: "TWO",
        totalSupply: 1000n,
        salt: `0x${"13".repeat(32)}`,
        distribution: "launchpad",
        tokenAllocations: [{ recipient: "0x0000000000000000000000000000000000001000", amount: 1000n }],
        governance: { mode: "token-holder", voteSource: 0 },
    }), /second token allocation/);
});
test("hydrates a reviewed launch preset from creator-owned fields only", () => {
    const curatedConfig = {
        governanceMode: 1,
        launchProfile: { canonicalPool: "0x0000000000000000000000000000000000009000" },
        bands: {
            marketCapGuard: "0x0000000000000000000000000000000000000000",
            positionAdapter: "0x0000000000000000000000000000000000000000",
            twapWindow: 900,
            quoteUsdOracle: "0x0000000000000000000000000000000000000000",
        },
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
    assert.deepEqual(config.bands, curatedConfig.bands);
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
    assert.match(launchErrorMessage("InvalidRaffleConfiguration"), /Refresh and try again/);
});
test("rejects Raffle presets that expose release-owned randomness infrastructure", () => {
    const preset = {
        id: "stale-raffle",
        protocolVersion: "2.0.0",
        config: {
            modules: { raffle: true },
            raffle: {
                creator: "0x0000000000000000000000000000000000000000",
                randomness: "0x0000000000000000000000000000000000001234",
                protocolFeeRecipient: "0x0000000000000000000000000000000000000000",
            },
        },
    };
    assert.throws(() => buildLaunchFromPreset(preset, {
        creator: "0x0000000000000000000000000000000000001000",
        name: "Project",
        symbol: "PRJ",
        totalSupply: 10n,
        salt: `0x${"22".repeat(32)}`,
        tokenAllocations: [
            { recipient: "0x0000000000000000000000000000000000002000", amount: 10n },
        ],
    }), /not compatible with this release/);
});
test("builds canonical project launch provenance only from matching preflight and Registry state", () => {
    const zero = "0x0000000000000000000000000000000000000000";
    const creator = "0x0000000000000000000000000000000000001000";
    const subject = "0x0000000000000000000000000000000000002000";
    const controller = "0x0000000000000000000000000000000000003000";
    const treasury = "0x0000000000000000000000000000000000004000";
    const launchConfigHash = `0x${"aa".repeat(32)}`;
    const projectId = `0x${"bb".repeat(32)}`;
    const addresses = {
        subject,
        controller,
        multisigAccount: controller,
        tokenGovernor: zero,
        tokenTimelock: zero,
        voteSource: zero,
        liquidVotes: zero,
        treasury,
        router: zero,
        stakingPool: zero,
        posNft: zero,
        airdrop: zero,
        raffle: zero,
        liquidityManager: zero,
        fundingBands: zero,
        fundingBandMarketCapGuard: zero,
        fundingBandPositionAdapter: zero,
        basketManager: zero,
        primaryBasketVault: zero,
        basketYieldAdapters: [],
        primaryBasketId: 0n,
    };
    const config = {
        creator,
        name: "Project",
        symbol: "PRJ",
        totalSupply: 1000n,
        governanceMode: 0,
        launchProfile: { canonicalPool: zero, additionalCustodyExclusions: [] },
        tokenAllocations: [{ recipient: creator, amount: 1000n }],
    };
    const preview = {
        launchConfigHash,
        projectId,
        enabledModules: 1n,
        addresses,
    };
    const record = {
        projectId,
        subject,
        creator,
        governanceMode: 0,
        controller,
        multisigAccount: controller,
        tokenGovernor: zero,
        tokenTimelock: zero,
        voteSource: zero,
        liquidVotes: zero,
        treasury,
        router: zero,
        stakingPool: zero,
        posNft: zero,
        airdrop: zero,
        raffle: zero,
        liquidityManager: zero,
        fundingBands: zero,
        basketManager: zero,
        primaryBasketId: 0n,
        canonicalPool: zero,
        referenceSupply: 1000n,
        launchedAt: 123n,
        protocolVersion: 2,
        enabledModules: 1n,
    };
    const manifest = buildProjectLaunchManifest({
        chainId: 8453n,
        transactionHash: `0x${"cc".repeat(32)}`,
        blockNumber: 123n,
        release: {
            gitCommit: "11".repeat(20),
            buildHash: "22".repeat(32),
            launcher: "0x0000000000000000000000000000000000005000",
            registry: "0x0000000000000000000000000000000000006000",
        },
        config,
        preview,
        record,
        registeredLaunchConfigHash: launchConfigHash,
    });
    const serialized = serializeProjectLaunchManifest(manifest);
    assert.equal(JSON.parse(serialized).configuration.totalSupply, "1000");
    assert.match(projectLaunchManifestHash(manifest), /^0x[0-9a-f]{64}$/);
    assert.equal(serialized, serializeProjectLaunchManifest(manifest));
    assert.throws(() => buildProjectLaunchManifest({
        chainId: 8453n,
        transactionHash: `0x${"cc".repeat(32)}`,
        blockNumber: 123n,
        release: manifest.release,
        config,
        preview,
        record: { ...record, treasury: zero },
        registeredLaunchConfigHash: launchConfigHash,
    }), /Treasury does not match/);
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
test("reconstructs holder weights in log order and always removes burn weight", () => {
    const snapshot = reconstructHolderAirdropSnapshot({
        snapshotBlock: 12n,
        snapshotBlockHash: `0x${"12".repeat(32)}`,
        snapshotTime: 1200n,
        totalSupply: 100n,
        totalEligibleWeight: 70n,
        exclusions: ["0x0000000000000000000000000000000000000002"],
        transfers: [
            {
                blockNumber: 10n,
                transactionIndex: 0,
                logIndex: 0,
                from: "0x0000000000000000000000000000000000000000",
                to: "0x0000000000000000000000000000000000000001",
                value: 100n,
            },
            {
                blockNumber: 11n,
                transactionIndex: 0,
                logIndex: 0,
                from: "0x0000000000000000000000000000000000000001",
                to: "0x000000000000000000000000000000000000dEaD",
                value: 10n,
            },
            {
                blockNumber: 12n,
                transactionIndex: 0,
                logIndex: 0,
                from: "0x0000000000000000000000000000000000000001",
                to: "0x0000000000000000000000000000000000000002",
                value: 20n,
            },
        ],
    });
    assert.deepEqual(snapshot.weights, [
        { holder: "0x0000000000000000000000000000000000000001", weight: 70n },
    ]);
    assert.equal(snapshot.totalEligibleWeight, 70n);
});
test("reconstructs current staker ownership from PoS position lifecycle events", () => {
    const snapshot = reconstructStakerAirdropSnapshot({
        snapshotBlock: 20n,
        snapshotBlockHash: `0x${"20".repeat(32)}`,
        snapshotTime: 2000n,
        totalStakedSupply: 70n,
        totalEligibleWeight: 70n,
        exclusions: [],
        events: [
            {
                eventName: "PositionCreated",
                blockNumber: 10n,
                transactionIndex: 0,
                logIndex: 0,
                tokenId: 1n,
                owner: "0x0000000000000000000000000000000000000001",
                amount: 70n,
            },
            {
                eventName: "PositionCreated",
                blockNumber: 11n,
                transactionIndex: 0,
                logIndex: 0,
                tokenId: 2n,
                owner: "0x0000000000000000000000000000000000000002",
                amount: 30n,
            },
            {
                eventName: "PositionTransferred",
                blockNumber: 12n,
                transactionIndex: 0,
                logIndex: 0,
                tokenId: 1n,
                from: "0x0000000000000000000000000000000000000001",
                to: "0x0000000000000000000000000000000000000003",
                amount: 70n,
            },
            {
                eventName: "PositionRedeemed",
                blockNumber: 13n,
                transactionIndex: 0,
                logIndex: 0,
                tokenId: 2n,
                owner: "0x0000000000000000000000000000000000000002",
                amount: 30n,
            },
        ],
    });
    assert.deepEqual(snapshot.weights, [
        { holder: "0x0000000000000000000000000000000000000003", weight: 70n },
    ]);
});
test("fails closed on incomplete event history and plans every unsettled leaf", () => {
    assert.throws(() => reconstructHolderAirdropSnapshot({
        snapshotBlock: 10n,
        snapshotBlockHash: `0x${"10".repeat(32)}`,
        snapshotTime: 1000n,
        totalSupply: 100n,
        totalEligibleWeight: 100n,
        exclusions: [],
        transfers: [{
                blockNumber: 10n,
                transactionIndex: 0,
                logIndex: 0,
                from: "0x0000000000000000000000000000000000000001",
                to: "0x0000000000000000000000000000000000000002",
                value: 1n,
            }],
    }), /spends more than the reconstructed balance/);
    const epoch = buildAirdropEpoch({
        chainId: BigInt(airdropFixture.chainId),
        airdrop: airdropFixture.airdrop,
        accountId: airdropFixture.accountId,
        epochId: BigInt(airdropFixture.epochId),
        snapshotBlock: BigInt(airdropFixture.snapshotBlock),
        snapshotBlockHash: airdropFixture.snapshotBlockHash,
        snapshotTime: BigInt(airdropFixture.snapshotTime),
        epochAmount: BigInt(airdropFixture.epochAmount),
        weights: airdropFixture.holders.map(({ holder, weight }) => ({
            holder,
            weight: BigInt(weight),
        })),
    });
    const batches = planAirdropPushBatches({
        epoch,
        processedHolders: [airdropFixture.holders[1]?.holder],
        maxPushBatchSize: 1,
    });
    assert.deepEqual(batches.map(({ indices }) => indices), [[0], [2]]);
    assert.equal(batches[1]?.leaves[0]?.amount, 0n);
    const pushCalls = encodeAirdropPushCalls({
        airdrop: airdropFixture.airdrop,
        accountId: airdropFixture.accountId,
        epochId: BigInt(airdropFixture.epochId),
        batches,
    });
    assert.deepEqual(decodeFunctionData({ abi: projectAirdropV2Abi, data: pushCalls[0]?.data }).functionName, "push");
    assert.equal(decodeFunctionData({
        abi: projectAirdropV2Abi,
        data: encodeAirdropRetryCreditCall({
            airdrop: airdropFixture.airdrop,
            recipient: airdropFixture.holders[0]?.holder,
            asset: "0x0000000000000000000000000000000000009000",
            maxAmount: 4n,
        }).data,
    }).functionName, "retryCredit");
    assert.deepEqual(decodeFunctionData({
        abi: projectAirdropV2Abi,
        data: encodeAirdropClaimCreditToCall({
            airdrop: airdropFixture.airdrop,
            asset: "0x0000000000000000000000000000000000009000",
            maxAmount: 4n,
            payoutRecipient: "0x0000000000000000000000000000000000008000",
        }).data,
    }), {
        functionName: "claimCreditTo",
        args: [
            "0x0000000000000000000000000000000000009000",
            4n,
            "0x0000000000000000000000000000000000008000",
        ],
    });
    assert.equal(decodeFunctionData({
        abi: projectAirdropV2Abi,
        data: encodeAirdropFinalizeCall({
            airdrop: airdropFixture.airdrop,
            accountId: airdropFixture.accountId,
            epochId: BigInt(airdropFixture.epochId),
        }).data,
    }).functionName, "finalizeEpoch");
    assert.equal(decodeFunctionData({
        abi: projectAirdropV2Abi,
        data: encodeAirdropAbortCall({
            airdrop: airdropFixture.airdrop,
            accountId: airdropFixture.accountId,
            epochId: BigInt(airdropFixture.epochId),
        }).data,
    }).functionName, "abortEpoch");
});
//# sourceMappingURL=sdk.test.js.map