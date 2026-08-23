import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import test from "node:test";
import { decodeFunctionData } from "viem";
import { buildFundingBandCreationActions, encodeGovernanceAction, encodeMultisigSubmission, encodeTokenGovernanceProposal, erc4626BasketYieldAdapterFactoryAbi, fundingBandDestination, marketCapUsdE8, projectFundingBandsV2Abi, projectGovernorV2Abi, projectLauncherV2Abi, projectMultisigAccountV2Abi, projectRegistryV2Abi, projectTreasuryVaultV2Abi, simpleFundingBandConfig, } from "../src/index.js";
const fixture = JSON.parse(await readFile(resolve(process.cwd(), "fixtures/treasury-send.json"), "utf8"));
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
//# sourceMappingURL=sdk.test.js.map