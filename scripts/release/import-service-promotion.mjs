#!/usr/bin/env node
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";

const repoRoot = resolve(import.meta.dirname, "../..");

function argument(name) {
  const index = process.argv.indexOf(name);
  return index === -1 ? undefined : process.argv[index + 1];
}

const source = argument("--file");
const expectedSha256 = argument("--sha256")?.toLowerCase();
const channel = argument("--channel");
const attestationBundle = argument("--attestation-bundle");
if (!source) throw new Error("--file is required");
if (!/^[0-9a-f]{64}$/.test(expectedSha256 ?? "")) {
  throw new Error("--sha256 must be 64 lowercase hex characters");
}
if (!["candidate", "active"].includes(channel)) {
  throw new Error("--channel must be candidate or active");
}

const contents = readFileSync(resolve(source));
const verifyArguments = [
  "attestation", "verify", resolve(source),
  "--repo", "Sinjoh-Finance/sinjoh-contracts",
  "--signer-workflow", "Sinjoh-Finance/sinjoh-contracts/.github/workflows/publish-promotion.yml",
];
if (attestationBundle) verifyArguments.push("--bundle", resolve(attestationBundle));
execFileSync("gh", verifyArguments, { stdio: "inherit" });
const actualSha256 = createHash("sha256").update(contents).digest("hex");
if (actualSha256 !== expectedSha256) {
  throw new Error(`promotion digest mismatch: expected ${expectedSha256}, received ${actualSha256}`);
}
const promotion = JSON.parse(contents);
if (promotion.schemaVersion !== 1) throw new Error("unsupported promotion schemaVersion");
if (promotion.source?.repository !== "Sinjoh-Finance/sinjoh-contracts") {
  throw new Error("untrusted promotion source repository");
}
if (promotion.channel !== channel) {
  throw new Error(`artifact channel is ${promotion.channel}, not ${channel}`);
}
const expectedNetwork = promotion.chainId === 4663 ? "robinhood-mainnet" : promotion.chainId === 46630 ? "robinhood-testnet" : undefined;
if (!expectedNetwork || promotion.network !== expectedNetwork) throw new Error("unsupported promotion chain/network");
if (!/^[0-9a-f]{40}$/.test(promotion.source?.commit ?? "")) throw new Error("invalid source commit");
if (!/^[0-9a-f]{64}$/.test(promotion.source?.releaseManifestSha256 ?? "")) throw new Error("invalid release digest");
if (!/^[0-9a-f]{64}$/.test(promotion.source?.deploymentManifestSha256 ?? "")) throw new Error("invalid deployment digest");
if (!promotion.consumers?.railway?.environment) {
  throw new Error("promotion has no Railway environment binding");
}

const destinationDirectory = resolve(repoRoot, "sinjoh-keeper/config/releases");
mkdirSync(destinationDirectory, { recursive: true });
writeFileSync(resolve(destinationDirectory, `${channel}.json`), contents);
writeFileSync(
  resolve(destinationDirectory, `${channel}.sha256`),
  `${actualSha256}  ${channel}.json\n`,
);
console.log(`imported ${promotion.releaseId} for services as ${channel} (${actualSha256})`);
