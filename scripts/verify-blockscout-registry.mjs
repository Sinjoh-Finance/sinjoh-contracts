#!/usr/bin/env node

import { readFile } from "node:fs/promises";

const registry = JSON.parse(
  await readFile(new URL("../blockscout-verification.json", import.meta.url), "utf8"),
);
const failures = [];

if (registry.schemaVersion !== 1) failures.push("schemaVersion must be 1");
if (registry.network?.chainId !== 4663) failures.push("chainId must be 4663");
if (!Array.isArray(registry.contracts)) failures.push("contracts must be an array");
if (!Array.isArray(registry.historical?.contracts)) {
  failures.push("historical.contracts must be an array");
}

const currentContracts = Array.isArray(registry.contracts) ? registry.contracts : [];
const historicalContracts = Array.isArray(registry.historical?.contracts)
  ? registry.historical.contracts
  : [];
const contracts = [...currentContracts, ...historicalContracts];
const uniqueAddresses = new Set(contracts.map(({ address }) => address.toLowerCase()));
if (uniqueAddresses.size !== contracts.length) failures.push("contract addresses must be unique");

for (const entry of contracts) {
  const label = `${entry.contract ?? "unknown"} (${entry.address ?? "no address"})`;
  if (!/^0x[0-9a-fA-F]{40}$/.test(entry.address ?? "")) {
    failures.push(`${label}: invalid address`);
  }
  if (!entry.tag || !entry.source || !entry.contract) {
    failures.push(`${label}: missing provenance fields`);
  }
  if (entry.explorer?.isVerified !== true) failures.push(`${label}: not verified`);
  if (entry.explorer?.creationStatus !== "success") {
    failures.push(`${label}: creation bytecode was not verified`);
  }
  if (entry.explorer?.changedBytecode !== false) {
    failures.push(`${label}: explorer reports changed bytecode`);
  }
}

const summary = registry.summary ?? {};
const expectedSummary = {
  contracts: contracts.length,
  firstParty: contracts.filter(({ sourceLicense }) => sourceLicense === "Apache-2.0").length,
  upstream: contracts.filter(({ sourceLicense }) => sourceLicense !== "Apache-2.0").length,
  verified: contracts.filter(({ explorer }) => explorer?.isVerified === true).length,
  creationBytecodeMatched: contracts.filter(
    ({ explorer }) =>
      explorer?.creationStatus === "success" && explorer?.changedBytecode === false,
  ).length,
};
for (const [key, expected] of Object.entries(expectedSummary)) {
  if (summary[key] !== expected) {
    failures.push(`summary.${key}: expected ${expected}, found ${summary[key]}`);
  }
}

if (failures.length > 0) {
  console.error(failures.map((failure) => `- ${failure}`).join("\n"));
  process.exit(1);
}

console.log(
  `verified registry: ${contracts.length} unique contracts, ` +
    `${expectedSummary.creationBytecodeMatched} creation-bytecode matches`,
);
