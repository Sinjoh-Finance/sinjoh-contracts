#!/usr/bin/env node
import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { delimiter, resolve } from "node:path";
import { spawnSync } from "node:child_process";

const repoRoot = resolve(import.meta.dirname, "../..");
const fixtureRoot = mkdtempSync(resolve(repoRoot, ".verify-eip1967-"));
const binRoot = mkdtempSync(resolve(tmpdir(), "sinjoh-cast-"));
const proxy = "0x1111111111111111111111111111111111111111";
const currentImplementation = "0x2222222222222222222222222222222222222222";
const staleImplementation = "0x3333333333333333333333333333333333333333";
const proxyHash = `0x${"11".repeat(32)}`;
const currentHash = `0x${"22".repeat(32)}`;
const staleHash = `0x${"33".repeat(32)}`;
const slot = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";

try {
  writeFileSync(resolve(binRoot, "cast"), `#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  chain-id) echo 46630 ;;
  codehash)
    address="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"
    case "$address" in
      ${proxy}) echo ${proxyHash} ;;
      ${currentImplementation}) echo ${currentHash} ;;
      ${staleImplementation}) echo ${staleHash} ;;
      *) exit 2 ;;
    esac
    ;;
  storage) echo 0x0000000000000000000000002222222222222222222222222222222222222222 ;;
  *) exit 2 ;;
esac
`, { mode: 0o755 });

  function verify(implementation, implementationRuntimeCodeHash) {
    const manifestPath = resolve(fixtureRoot, "manifest.json");
    writeFileSync(manifestPath, `${JSON.stringify({
      chainId: 46630,
      contracts: {
        factoryProxy: {
          address: proxy,
          runtimeCodeHash: proxyHash,
          implementation,
          implementationRuntimeCodeHash,
          implementationBinding: { kind: "eip1967", slot }
        }
      }
    }, null, 2)}\n`);
    return spawnSync(process.execPath, [
      "scripts/release/verify-deployment.mjs",
      "--network", "46630",
      "--rpc-url", "https://primary.invalid",
      "--manifest", manifestPath
    ], {
      cwd: repoRoot,
      encoding: "utf8",
      env: { ...process.env, PATH: `${binRoot}${delimiter}${process.env.PATH}` }
    });
  }

  const current = verify(currentImplementation, currentHash);
  assert.equal(current.status, 0, current.stderr);
  assert.match(current.stdout, /verified 1 EIP-1967 implementation bindings/);

  const stale = verify(staleImplementation, staleHash);
  assert.notEqual(stale.status, 0);
  assert.match(
    stale.stderr,
    /primary EIP-1967 implementation 0x2222222222222222222222222222222222222222 != 0x3333333333333333333333333333333333333333/
  );
  console.log("EIP-1967 deployment verification tests passed");
} finally {
  rmSync(fixtureRoot, { recursive: true, force: true });
  rmSync(binRoot, { recursive: true, force: true });
}
