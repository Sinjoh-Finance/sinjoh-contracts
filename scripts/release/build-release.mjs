#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  cpSync,
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  rmSync,
  statSync,
  writeFileSync
} from "node:fs";
import { basename, join, relative, resolve } from "node:path";

const repoRoot = resolve(import.meta.dirname, "../..");
const packages = [
  "sinjoh-fee-router",
  "sinjoh-revenue-collector",
  "sinjoh-airdrop-distributor",
  "sinjoh-liquidity-manager",
  "sinjoh-funding-bands",
  "sinjoh-raffle-rewards",
  "sinjoh-randomness",
  "sinjoh-treasury-vault",
  "sinjoh-pons-v1-adapter",
  "sinjoh-launchpad-adapters",
  "sinjoh-protocol-upgrade",
  "sinjoh-integration"
];

function argument(name, fallback = undefined) {
  const index = process.argv.indexOf(name);
  return index === -1 ? fallback : process.argv[index + 1];
}

function run(command, args) {
  return execFileSync(command, args, { cwd: repoRoot, encoding: "utf8" }).trim();
}

function sha256(contents) {
  return createHash("sha256").update(contents).digest("hex");
}

function keccak(bytecode) {
  if (!bytecode || bytecode === "0x" || !/^0x[0-9a-fA-F]+$/.test(bytecode)) return null;
  return run("cast", ["keccak", bytecode]);
}

function walk(directory) {
  if (!existsSync(directory)) return [];
  const files = [];
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) files.push(...walk(path));
    else if (entry.isFile()) files.push(path);
  }
  return files;
}

const releaseId = argument("--release-id");
const chainId = Number(argument("--network"));
const requireClean = process.argv.includes("--require-clean");
const outputArgument = argument("--output", `.release-bundles/${releaseId ?? "invalid"}`);

if (!releaseId || !/^[a-zA-Z0-9][a-zA-Z0-9._-]{2,79}$/.test(releaseId)) {
  throw new Error("--release-id must be 3-80 safe filename characters");
}
if (![4663, 46630].includes(chainId)) throw new Error("--network must be 4663 or 46630");

const networkPath = resolve(repoRoot, `deployments/networks/${chainId}.json`);
const network = JSON.parse(readFileSync(networkPath, "utf8"));
const sourceCommit = run("git", ["rev-parse", "HEAD"]);
const status = run("git", ["status", "--porcelain", "--untracked-files=normal"]);
const sourceTreeClean = status.length === 0;
if (requireClean && !sourceTreeClean) throw new Error("release builds require a clean Git worktree");

const output = resolve(repoRoot, outputArgument);
const allowedRoot = resolve(repoRoot, ".release-bundles");
if (output !== allowedRoot && !output.startsWith(`${allowedRoot}/`)) {
  throw new Error("release output must be inside .release-bundles/");
}
rmSync(output, { recursive: true, force: true });
mkdirSync(join(output, "artifacts"), { recursive: true });

cpSync(networkPath, join(output, "network.json"));
const planPath = resolve(repoRoot, `deployments/plans/${chainId}.json`);
if (existsSync(planPath)) cpSync(planPath, join(output, "deployment-plan.json"));

const inputs = [];
const artifacts = [];
for (const packageName of packages) {
  const packageRoot = resolve(repoRoot, packageName);
  const configPath = join(packageRoot, "foundry.toml");
  if (!existsSync(configPath)) continue;
  const gitTree = run("git", ["rev-parse", `HEAD:${packageName}`]);
  inputs.push({
    package: packageName,
    gitTree,
    foundryConfigSha256: sha256(readFileSync(configPath))
  });

  const artifactRoot = join(packageRoot, "out");
  for (const artifactPath of walk(artifactRoot).filter((path) => path.endsWith(".json"))) {
    let artifact;
    try {
      artifact = JSON.parse(readFileSync(artifactPath, "utf8"));
    } catch {
      continue;
    }
    const target = artifact.metadata?.settings?.compilationTarget;
    if (!target || Object.keys(target).length !== 1) continue;
    const [sourceName, contractName] = Object.entries(target)[0];
    if (!sourceName.startsWith("src/")) continue;

    const creationCode = artifact.bytecode?.object;
    const runtimeCode = artifact.deployedBytecode?.object;
    const linkReferences = artifact.bytecode?.linkReferences ?? {};
    const runtimeLinkReferences = artifact.deployedBytecode?.linkReferences ?? {};
    const destinationName = `${basename(sourceName, ".sol")}__${contractName}.json`;
    const destinationDirectory = join(output, "artifacts", packageName);
    mkdirSync(destinationDirectory, { recursive: true });
    cpSync(artifactPath, join(destinationDirectory, destinationName));
    artifacts.push({
      package: packageName,
      source: sourceName,
      contract: contractName,
      artifact: `artifacts/${packageName}/${destinationName}`,
      artifactSha256: sha256(readFileSync(artifactPath)),
      requiresLinking:
        Object.keys(linkReferences).length > 0 || Object.keys(runtimeLinkReferences).length > 0,
      linkReferences,
      runtimeLinkReferences,
      creationCodeKeccak256: keccak(creationCode),
      runtimeTemplateKeccak256: keccak(runtimeCode)
    });
  }
}

if (artifacts.length === 0) {
  throw new Error("no first-party artifacts found; run scripts/contracts-ci.sh build all first");
}

const release = {
  schemaVersion: 1,
  releaseId,
  chainId,
  network: network.slug,
  sourceCommit,
  sourceTreeClean,
  createdAt: new Date().toISOString(),
  toolchain: {
    forge: run("forge", ["--version"]).split("\n")[0],
    cast: run("cast", ["--version"]).split("\n")[0],
    solidity: "0.8.28",
    evmVersion: "cancun"
  },
  inputs,
  artifacts: artifacts.sort((a, b) => `${a.package}/${a.contract}`.localeCompare(`${b.package}/${b.contract}`))
};
writeFileSync(join(output, "release.json"), `${JSON.stringify(release, null, 2)}\n`);

const checksumLines = walk(output)
  .filter((path) => statSync(path).isFile() && basename(path) !== "checksums.sha256")
  .sort()
  .map((path) => `${sha256(readFileSync(path))}  ${relative(output, path)}`);
writeFileSync(join(output, "checksums.sha256"), `${checksumLines.join("\n")}\n`);

console.log(output);

