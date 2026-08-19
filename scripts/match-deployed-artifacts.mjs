#!/usr/bin/env node

import { readdir, readFile, writeFile } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import path from "node:path";

const ADDRESS = /^0x[0-9a-fA-F]{40}$/;
const RPC_URL = process.env.RH_RPC_URL ?? "https://rpc.mainnet.chain.robinhood.com";

function usage() {
  console.error(
    "usage: node scripts/match-deployed-artifacts.mjs " +
      "<worktree> <output.json> <package> [package ...]",
  );
  process.exit(2);
}

const [worktreeArg, outputArg, ...packageArgs] = process.argv.slice(2);
if (!worktreeArg || !outputArg || packageArgs.length === 0) usage();

const worktree = path.resolve(worktreeArg);
const output = path.resolve(outputArg);

function collectAddresses(value, pointer = "", parent = null, results = []) {
  if (typeof value === "string" && ADDRESS.test(value)) {
    results.push({
      address: value,
      manifestPath: pointer || "/",
      deploymentTransaction:
        parent && typeof parent.deploymentTransaction === "string"
          ? parent.deploymentTransaction
          : null,
      deploymentBlock:
        parent && Number.isInteger(parent.deploymentBlock) ? parent.deploymentBlock : null,
      runtimeCodeHash:
        parent && typeof parent.runtimeCodeHash === "string" ? parent.runtimeCodeHash : null,
    });
    return results;
  }
  if (Array.isArray(value)) {
    value.forEach((entry, index) =>
      collectAddresses(entry, `${pointer}/${index}`, value, results),
    );
    return results;
  }
  if (value && typeof value === "object") {
    for (const [key, entry] of Object.entries(value)) {
      const escaped = key.replaceAll("~", "~0").replaceAll("/", "~1");
      collectAddresses(entry, `${pointer}/${escaped}`, value, results);
    }
  }
  return results;
}

async function walkJsonFiles(directory) {
  const files = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const absolute = path.join(directory, entry.name);
    if (entry.isDirectory()) files.push(...(await walkJsonFiles(absolute)));
    else if (entry.isFile() && entry.name.endsWith(".json")) files.push(absolute);
  }
  return files;
}

function referenceRanges(bytecode) {
  const ranges = [];
  for (const refs of Object.values(bytecode.immutableReferences ?? {})) {
    ranges.push(...refs);
  }
  for (const fileRefs of Object.values(bytecode.linkReferences ?? {})) {
    for (const refs of Object.values(fileRefs)) ranges.push(...refs);
  }
  return ranges.sort((a, b) => a.start - b.start);
}

function matchesRuntime(templateHex, runtimeHex, ranges) {
  const template = Buffer.from(
    templateHex.replace(/^0x/, "").replaceAll(/[^0-9a-fA-F]/g, "0"),
    "hex",
  );
  const runtime = Buffer.from(runtimeHex.replace(/^0x/, ""), "hex");
  if (template.length === 0 || template.length !== runtime.length) return false;

  const ignored = new Uint8Array(template.length);
  for (const { start, length } of ranges) {
    if (start < 0 || length < 0 || start + length > ignored.length) return false;
    ignored.fill(1, start, start + length);
  }
  for (let index = 0; index < template.length; index += 1) {
    if (!ignored[index] && template[index] !== runtime[index]) return false;
  }
  return true;
}

async function loadArtifacts(packageName) {
  const out = path.join(worktree, packageName, "out");
  const artifacts = [];
  for (const artifactPath of await walkJsonFiles(out)) {
    let artifact;
    try {
      artifact = JSON.parse(await readFile(artifactPath, "utf8"));
    } catch {
      continue;
    }
    const compilationTarget = Object.entries(artifact.metadata?.settings?.compilationTarget ?? {});
    if (
      compilationTarget.length !== 1 ||
      !compilationTarget[0][0].startsWith("src/") ||
      typeof compilationTarget[0][1] !== "string" ||
      typeof artifact.deployedBytecode?.object !== "string" ||
      artifact.deployedBytecode.object === "0x"
    ) {
      continue;
    }
    const [[sourceName, contractName]] = compilationTarget;
    artifacts.push({
      package: packageName,
      source: sourceName,
      contract: contractName,
      artifact: path.relative(worktree, artifactPath),
      runtime: artifact.deployedBytecode.object,
      referenceRanges: referenceRanges(artifact.deployedBytecode),
    });
  }
  return artifacts;
}

async function rpc(method, params) {
  for (let attempt = 1; attempt <= 8; attempt += 1) {
    const response = await fetch(RPC_URL, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
    });
    if (response.ok) {
      const payload = await response.json();
      if (payload.error) throw new Error(`${method}: ${JSON.stringify(payload.error)}`);
      return payload.result;
    }
    if (response.status !== 429 || attempt === 8) {
      throw new Error(`${method}: HTTP ${response.status}`);
    }
    await new Promise((resolve) => setTimeout(resolve, attempt * 750));
  }
  throw new Error(`${method}: retry budget exhausted`);
}

async function mapConcurrent(values, limit, callback) {
  const results = new Array(values.length);
  let cursor = 0;
  async function worker() {
    while (cursor < values.length) {
      const index = cursor;
      cursor += 1;
      results[index] = await callback(values[index], index);
    }
  }
  await Promise.all(Array.from({ length: Math.min(limit, values.length) }, worker));
  return results;
}

let manifest;
try {
  manifest = JSON.parse(await readFile(path.join(worktree, "mainnet-deployments.json"), "utf8"));
} catch (error) {
  if (!process.env.DEPLOYMENT_MANIFEST || error.code !== "ENOENT") throw error;
  manifest = JSON.parse(await readFile(path.resolve(process.env.DEPLOYMENT_MANIFEST), "utf8"));
}
const addressEntries = collectAddresses(manifest);
if (process.env.DEPLOYMENT_MANIFEST) {
  const canonicalManifest = JSON.parse(
    await readFile(path.resolve(process.env.DEPLOYMENT_MANIFEST), "utf8"),
  );
  addressEntries.push(...collectAddresses(canonicalManifest));
}
if (process.env.DEPLOYMENT_REF) {
  const refManifest = JSON.parse(
    execFileSync(
      "git",
      ["-C", worktree, "show", `${process.env.DEPLOYMENT_REF}:mainnet-deployments.json`],
      { encoding: "utf8" },
    ),
  );
  addressEntries.push(...collectAddresses(refManifest));
}
const uniqueAddresses = [...new Map(addressEntries.map((entry) => [entry.address.toLowerCase(), entry])).values()];
const artifacts = (await Promise.all(packageArgs.map(loadArtifacts))).flat();
const codes = await mapConcurrent(uniqueAddresses, 3, async (entry) => ({
  ...entry,
  runtime: await rpc("eth_getCode", [entry.address, "latest"]),
}));

const matches = [];
for (const candidate of codes) {
  if (candidate.runtime === "0x") continue;
  for (const artifact of artifacts) {
    if (matchesRuntime(artifact.runtime, candidate.runtime, artifact.referenceRanges)) {
      matches.push({
        manifestPath: candidate.manifestPath,
        address: candidate.address,
        package: artifact.package,
        source: artifact.source,
        contract: artifact.contract,
        artifact: artifact.artifact,
        deploymentTransaction: candidate.deploymentTransaction,
        deploymentBlock: candidate.deploymentBlock,
        runtimeCodeHash: candidate.runtimeCodeHash,
        ignoredRuntimeRanges: artifact.referenceRanges,
      });
    }
  }
}

matches.sort((a, b) =>
  a.manifestPath.localeCompare(b.manifestPath) || a.contract.localeCompare(b.contract),
);
await writeFile(
  output,
  `${JSON.stringify(
    {
      schemaVersion: 1,
      chainId: manifest.chainId,
      rpcUrl: RPC_URL,
      packages: packageArgs,
      candidateAddresses: uniqueAddresses.length,
      artifactCount: artifacts.length,
      matches,
    },
    null,
    2,
  )}\n`,
);
console.log(`matched ${matches.length} deployed addresses to ${artifacts.length} artifacts`);
