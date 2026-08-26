#!/usr/bin/env node
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { mkdtempSync, mkdirSync, unlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { resolve } from "node:path";
import { auditStaleReferences, deriveReferenceInventory } from "./stale-reference-audit.mjs";

const OLD = "0x1111111111111111111111111111111111111111";
const OLD_HASH = `0x${"11".repeat(32)}`;
const CURRENT = "0x2222222222222222222222222222222222222222";
const CURRENT_HASH = `0x${"22".repeat(32)}`;

const manifest = {
  chainId: 4663,
  currentInfrastructure: {
    adapter: { address: CURRENT, runtimeCodeHash: CURRENT_HASH },
    adapterHistoricalGenerations: {
      first: { address: OLD, runtimeCodeHash: OLD_HASH }
    }
  }
};

const inventory = deriveReferenceInventory(manifest);
assert.equal(inventory.current.size, 2);
assert.equal(inventory.historical.size, 2);
assert.equal(inventory.displaced.size, 2);

function writeJson(path, value) {
  writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`);
}

function fixture({ stale = false, staleTest = false, staleHistory = false, wrongPromotionManifestSha = false, wrongSdkManifest = false } = {}) {
  const root = mkdtempSync(resolve(tmpdir(), "sinjoh-stale-audit-"));
  const manifestPath = resolve(root, "manifest.json");
  const promotionPath = resolve(root, "promotion.json");
  const sdkRoot = resolve(root, "sdk");
  mkdirSync(resolve(sdkRoot, "config/releases"), { recursive: true });
  mkdirSync(resolve(sdkRoot, "src"), { recursive: true });
  mkdirSync(resolve(sdkRoot, "tests"), { recursive: true });
  const manifestContents = Buffer.from(`${JSON.stringify(manifest, null, 2)}\n`);
  writeFileSync(manifestPath, manifestContents);
  const manifestSha = createHash("sha256").update(manifestContents).digest("hex");
  const promotion = {
    schemaVersion: 1,
    channel: "active",
    chainId: 4663,
    source: { deploymentManifestSha256: wrongPromotionManifestSha ? "00".repeat(32) : manifestSha },
    contracts: { adapter: { address: CURRENT, runtimeCodeHash: CURRENT_HASH } }
  };
  writeJson(promotionPath, promotion);
  const promotionContents = Buffer.from(`${JSON.stringify(promotion, null, 2)}\n`);
  const promotionSha = createHash("sha256").update(promotionContents).digest("hex");
  writeFileSync(resolve(sdkRoot, "config/releases/active.json"), promotionContents);
  writeFileSync(resolve(sdkRoot, "config/releases/active.sha256"), `${promotionSha}  active.json\n`);
  writeFileSync(resolve(sdkRoot, "mainnet-deployments.json"), wrongSdkManifest ? "{}\n" : manifestContents);
  writeFileSync(resolve(sdkRoot, "src/current.ts"), `export const current = "${CURRENT}";\n${stale ? `export const stale = "${OLD}";\n` : ""}`);
  if (staleTest) writeFileSync(resolve(sdkRoot, "tests/history.test.ts"), `assert.equal(old, "${OLD}");\n`);
  if (staleHistory) writeFileSync(resolve(sdkRoot, "src/history.ts"), `// stale-reference-audit: historical ${OLD}\nexport const old = "${OLD}";\n`);
  writeFileSync(resolve(sdkRoot, ".git"), "gitdir: fixture\n");
  return { root, manifestPath, promotionPath, sdkRoot };
}

function runFixture(paths) {
  // Replace git discovery for the synthetic repository with an actual tiny repository.
  writeFileSync(resolve(paths.sdkRoot, ".gitignore"), "\n");
  // A .git pointer written above is not usable; replace the fixture root with a repository.
  unlinkSync(resolve(paths.sdkRoot, ".git"));
  execFileSync("git", ["init", "-q", paths.sdkRoot]);
  execFileSync("git", ["-C", paths.sdkRoot, "add", "."]);
  return auditStaleReferences({ manifest: paths.manifestPath, promotion: paths.promotionPath, sdk_root: paths.sdkRoot });
}

const clean = runFixture(fixture({ staleTest: true, staleHistory: true }));
assert.equal(clean.verdict, "pass");
assert.equal(clean.scan.counts["displaced-test"], 1);
assert.equal(clean.scan.counts["displaced-explicit-history"], 1);
assert.ok(clean.scan.counts["displaced-historical-namespace"] >= 2);

const dirty = runFixture(fixture({ stale: true }));
assert.equal(dirty.verdict, "fail");
const staleFailure = dirty.scan.failures.find(({ type }) => type === "stale-reference");
assert.equal(staleFailure.value, OLD);
assert.equal(staleFailure.path, "src/current.ts");

const digestMismatch = runFixture(fixture({ wrongPromotionManifestSha: true }));
assert.equal(digestMismatch.verdict, "fail");
assert.ok(digestMismatch.scan.failures.some(({ type }) => type === "manifest-digest-mismatch"));

const importMismatch = runFixture(fixture({ wrongSdkManifest: true }));
assert.equal(importMismatch.verdict, "fail");
assert.ok(importMismatch.scan.failures.some(({ type, label }) => type === "artifact-mismatch" && label === "sdk deployment manifest"));

console.log("stale-reference audit tests passed");
