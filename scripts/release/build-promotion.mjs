#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { loadReleaseBundle } from "./release-bundle.mjs";
import {
  collectPromotionContracts,
  resolvePromotionConsumers
} from "./promotion-model.mjs";

const repoRoot = resolve(import.meta.dirname, "../..");
const hashPattern = /^0x[0-9a-fA-F]{64}$/;

function argument(name) {
  const index = process.argv.indexOf(name);
  return index === -1 ? undefined : process.argv[index + 1];
}

function git(args) {
  return execFileSync("git", args, { cwd: repoRoot, encoding: "utf8" }).trim();
}

function sha256(contents) {
  return createHash("sha256").update(contents).digest("hex");
}

const releaseId = argument("--release-id");
const chainId = Number(argument("--network"));
const channel = argument("--channel");
const releaseBundle = argument("--release-bundle");
const candidatePromotion = argument("--candidate-promotion");
const requireClean = process.argv.includes("--require-clean");
if (!releaseId || !/^[a-zA-Z0-9][a-zA-Z0-9._-]{2,79}$/.test(releaseId)) {
  throw new Error("--release-id must be 3-80 safe filename characters");
}
if (![4663, 46630].includes(chainId)) throw new Error("--network must be 4663 or 46630");
if (!["candidate", "active"].includes(channel)) throw new Error("--channel must be candidate or active");
if (!releaseBundle) throw new Error("--release-bundle is required");
if (channel === "active" && !candidatePromotion) {
  throw new Error("active promotion requires --candidate-promotion from the attested candidate artifact");
}
if (requireClean && git(["status", "--porcelain", "--untracked-files=normal"])) {
  throw new Error("promotion manifests require a clean Git worktree");
}

const manifestRelative = chainId === 4663
  ? "mainnet-deployments.json"
  : "deployments/manifests/46630/current.json";
const manifestContents = readFileSync(resolve(repoRoot, manifestRelative));
const manifest = JSON.parse(manifestContents);
if (manifest.chainId !== chainId) throw new Error("deployment manifest chain mismatch");
if (chainId === 46630 && manifest.status !== "deployed") {
  throw new Error("testnet promotion requires a deployed manifest");
}
if (channel === "active" && chainId === 4663 && manifest.releaseCandidate !== false) {
  throw new Error("mainnet releaseCandidate must be exactly false before active promotion");
}
if (channel === "active" && chainId === 46630) {
  const unhealthy = Object.entries(manifest.services ?? {}).filter(([, status]) => status !== "healthy");
  if (unhealthy.length > 0) throw new Error(`testnet services are not healthy: ${unhealthy.map(([name]) => name).join(", ")}`);
}

const network = JSON.parse(
  readFileSync(resolve(repoRoot, `deployments/networks/${chainId}.json`), "utf8")
);
const verifiedRelease = loadReleaseBundle(releaseBundle, {
  releaseId,
  chainId,
  network: network.slug,
  repoRoot,
});
const contracts = {};
if (chainId === 4663) {
  collectPromotionContracts(manifest.currentInfrastructure ?? {}, "contracts", contracts);
  collectPromotionContracts(manifest.dependencies ?? {}, "dependencies", contracts);
  collectPromotionContracts(manifest.letscashDependencies ?? {}, "dependencies.letscash", contracts);
} else {
  collectPromotionContracts(manifest.contracts ?? {}, "contracts", contracts);
  collectPromotionContracts(manifest.dependencies ?? {}, "dependencies", contracts);
}
if (Object.keys(contracts).length === 0) throw new Error("promotion contains no contracts");
for (const [path, contract] of Object.entries(contracts)) {
  if (!hashPattern.test(contract.runtimeCodeHash ?? "")) {
    throw new Error(`${path} is not pinned to a runtime code hash`);
  }
}

const bindings = JSON.parse(
  readFileSync(resolve(repoRoot, "deployments/consumers/bindings.json"), "utf8")
);
const promotion = {
  schemaVersion: 1,
  releaseId,
  channel,
  chainId,
  network: network.slug,
  source: {
    repository: "Sinjoh-Finance/sinjoh-contracts",
    commit: verifiedRelease.release.sourceCommit,
    releaseManifestSha256: verifiedRelease.releaseManifestSha256,
    deploymentManifest: manifestRelative,
    deploymentManifestSha256: sha256(manifestContents)
  },
  generatedAt: new Date().toISOString(),
  contracts,
  consumers: resolvePromotionConsumers(bindings, contracts, chainId, manifest)
};

if (channel === "active") {
  const candidate = JSON.parse(readFileSync(resolve(candidatePromotion), "utf8"));
  if (candidate.channel !== "candidate") throw new Error("candidate artifact has the wrong channel");
  for (const field of ["releaseId", "chainId", "network"]) {
    if (candidate[field] !== promotion[field]) throw new Error(`candidate ${field} mismatch`);
  }
  const candidateSource = { ...candidate.source };
  const activeSource = { ...promotion.source };
  delete candidateSource.deploymentManifestSha256;
  delete activeSource.deploymentManifestSha256;
  if (JSON.stringify(candidateSource) !== JSON.stringify(activeSource)) {
    throw new Error("active promotion differs from candidate release identity");
  }
  for (const field of ["contracts", "consumers"]) {
    if (JSON.stringify(candidate[field]) !== JSON.stringify(promotion[field])) {
      throw new Error(`active promotion differs from candidate ${field}`);
    }
  }
}

const outputDirectory = resolve(repoRoot, ".release-bundles", releaseId, "promotions", channel);
if (existsSync(outputDirectory)) {
  throw new Error(`release ID already has a promotion artifact: ${releaseId}`);
}
mkdirSync(outputDirectory, { recursive: true });
const serialized = `${JSON.stringify(promotion, null, 2)}\n`;
writeFileSync(resolve(outputDirectory, "promotion.json"), serialized);
writeFileSync(
  resolve(outputDirectory, "promotion.sha256"),
  `${sha256(serialized)}  promotion.json\n`
);
console.log(outputDirectory);
