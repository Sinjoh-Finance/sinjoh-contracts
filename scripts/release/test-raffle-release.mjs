import assert from "node:assert/strict";
import test from "node:test";
import { runtimeMatchesArtifact } from "./verify-raffle-release.mjs";

const artifact = { deployedBytecode: { object: "0x60000000f3", immutableReferences: { "1": [{ start: 1, length: 3 }] } } };
test("compiler-declared immutable addresses may differ from the zero-filled template", () => {
  assert.equal(runtimeMatchesArtifact("0x60abcdefF3", artifact), true);
});
test("different executable code fails despite identical pinned address metadata", () => {
  assert.equal(runtimeMatchesArtifact("0x61abcdeff3", artifact), false);
  assert.equal(runtimeMatchesArtifact("0x60abcdeffd", artifact), false);
  assert.equal(runtimeMatchesArtifact("0x", artifact), false);
  assert.equal(runtimeMatchesArtifact("0x60abcdeff300", artifact), false);
});
test("invalid immutable offsets fail closed", () => {
  assert.equal(runtimeMatchesArtifact("0x60abcdeff3", { deployedBytecode: { ...artifact.deployedBytecode, immutableReferences: { "1": [{ start: 0, length: 6 }] } } }), false);
});
