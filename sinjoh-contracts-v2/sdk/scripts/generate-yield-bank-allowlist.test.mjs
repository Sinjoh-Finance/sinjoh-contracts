import assert from "node:assert/strict";
import test from "node:test";
import { buildAllowlist, verifyProof } from "./generate-yield-bank-allowlist.mjs";

const snapshot = {
  token: "0x2cC0FAC44B8252f6B10208B091aFf2c94B4da77D",
  snapshotBlock: 1,
  snapshotBlockHash: `0x${"11".repeat(32)}`,
  holders: [
    { address: "0x0000000000000000000000000000000000000001", balance: "10000000", classification: "Holder" },
    { address: "0x0000000000000000000000000000000000000002", balance: "1000000", classification: "Holder" },
    { address: "0x0000000000000000000000000000000000000003", balance: "100000", classification: "Holder" },
    { address: "0x0000000000000000000000000000000000000004", balance: "10000", classification: "Holder" },
    { address: "0x0000000000000000000000000000000000000005", balance: "9999.999", classification: "Holder" },
    { address: "0x000000000000000000000000000000000000dEaD", balance: "100000000", classification: "Burn" },
  ],
};

const stages = [
  ["Alpha", "10000000", "500000000000000000", "1", "3", "1"],
  ["Prime", "1000000", "100000000000000000", "3", "33", "2"],
  ["Premium", "100000", "30000000000000000", "5", "333", "3"],
  ["Standard", "10000", "10000000000000000", "10", "3333", "4"],
].map(([name, minimumBalance, mintPrice, maxTotalMintableByWallet, maxTokenSupplyForStage, dropStageIndex], index) => ({
  name,
  minimumBalance,
  mintPrice,
  maxTotalMintableByWallet,
  maxTokenSupplyForStage,
  dropStageIndex,
  startTime: String(100 + index * 10),
  endTime: String(109 + index * 10),
  feeBps: "1000",
  restrictFeeRecipients: true,
}));

test("cascades higher eligibility into every lower Piggy Bank tier", () => {
  const artifact = buildAllowlist(snapshot, { stages });
  assert.equal(artifact.entries.length, 10);
  assert.deepEqual(
    stages.map((stage) => artifact.entries.filter((entry) => entry.stage === stage.name).length),
    [1, 2, 3, 4],
  );
  assert.equal(new Set(artifact.entries.map((entry) => entry.address)).size, 4);
  assert.ok(artifact.entries.every((entry) => verifyProof(entry.leaf, entry.proof, artifact.root)));
});

test("rejects incomplete and overlapping launch terms", () => {
  assert.throws(
    () => buildAllowlist(snapshot, { stages: [{ ...stages[0], startTime: null }] }),
    /startTime is required/,
  );
  assert.throws(
    () => buildAllowlist(snapshot, { stages: [stages[0], { ...stages[1], minimumBalance: "10000000" }] }),
    /strictly descending/,
  );
});
