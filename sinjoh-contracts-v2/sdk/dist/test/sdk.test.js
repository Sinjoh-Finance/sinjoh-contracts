import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import test from "node:test";
import { decodeFunctionData } from "viem";
import { encodeGovernanceAction, erc4626BasketYieldAdapterFactoryAbi, projectLauncherV2Abi, projectRegistryV2Abi, projectTreasuryVaultV2Abi, } from "../src/index.js";
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
//# sourceMappingURL=sdk.test.js.map