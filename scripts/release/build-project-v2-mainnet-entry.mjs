#!/usr/bin/env node
import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { buildProjectV2MainnetEntry } from "./project-v2-mainnet-entry.mjs";

function argument(name) {
  const index = process.argv.indexOf(name);
  return index === -1 ? undefined : process.argv[index + 1];
}

const repoRoot = resolve(import.meta.dirname, "../..");
const manifestPath = resolve(repoRoot, argument("--release-manifest") ?? "");
const outputPath = resolve(repoRoot, argument("--output") ?? "");
const broadcastPaths = [
  "sinjoh-launchpad-adapters/broadcast/DeployPonsV2AdapterFactory.s.sol/4663/run-latest.json",
  "sinjoh-launchpad-adapters/broadcast/DeployPoolsTradeAdapterFactories.s.sol/4663/run-latest.json",
  "sinjoh-contracts-v2/broadcast/DeployProjectLauncherV2.s.sol/4663/run-latest.json"
];

if (!argument("--release-manifest") || !argument("--output")) {
  throw new Error("--release-manifest and --output are required");
}

const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
const broadcasts = broadcastPaths.map((path) => JSON.parse(readFileSync(resolve(repoRoot, path), "utf8")));
const output = `${JSON.stringify(buildProjectV2MainnetEntry(manifest, broadcasts), null, 2)}\n`;
writeFileSync(outputPath, output, { flag: "wx" });
console.log(outputPath);
