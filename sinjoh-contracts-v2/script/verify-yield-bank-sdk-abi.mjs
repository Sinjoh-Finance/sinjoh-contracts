#!/usr/bin/env node
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const projectRoot = resolve(scriptDirectory, "..");
const sdkModulePath = resolve(
  process.argv[2] ?? resolve(projectRoot, "../../sinjoh-sdk/packages/sdk/dist/src/yield-banks.js"),
);
const sdk = await import(pathToFileURL(sdkModulePath).href);

const surfaces = [
  ["yieldBankCollectionAbi", "YieldBankCollection.sol/YieldBankCollection.json"],
  ["yieldBankNftAbi", "YieldBankNFT.sol/YieldBankNFT.json"],
  ["yieldBankRevenueRouterAbi", "CollectionRevenueRouter.sol/CollectionRevenueRouter.json"],
  ["yieldBankProceedsVaultAbi", "YieldBankProceedsVault.sol/YieldBankProceedsVault.json"],
  ["yieldBankDistributorAbi", "YieldBankDistributor.sol/YieldBankDistributor.json"],
  ["yieldBankAccountAbi", "YieldBankAccount.sol/YieldBankAccount.json"],
  ["yieldBankSleeveAbi", "BaseSleeve.sol/BaseSleeve.json"],
  ["yieldBankErc20Abi", "IERC20.sol/IERC20.json"],
  ["yieldBankStrategyAdapterAbi", "IStrategyAdapter.sol/IStrategyAdapter.json"],
  ["yieldBankDeltaAdapterAbi", "DeltaV3LPAdapter.sol/DeltaV3LPAdapter.json"],
  ["yieldBankStrategyRegistryAbi", "StrategyRegistry.sol/StrategyRegistry.json"],
  ["yieldBankAllocatorAbi", "CollectionPortfolioAllocator.sol/CollectionPortfolioAllocator.json"],
  ["yieldBankDeltaPoolControllerAbi", "DeltaPoolController.sol/DeltaPoolController.json"],
  ["yieldBankSystemFactoryAbi", "YieldBankSystemFactory.sol/YieldBankSystemFactory.json"],
  ["yieldBankProtocolRegistryAbi", "YieldBankProtocolRegistry.sol/YieldBankProtocolRegistry.json"],
  ["yieldBankSeaDropReadAbi", "ISeaDrop.sol/ISeaDrop.json"],
];

function parameterType(parameter) {
  if (!parameter.type.startsWith("tuple")) return parameter.type;
  const suffix = parameter.type.slice("tuple".length);
  return `(${(parameter.components ?? []).map(parameterType).join(",")})${suffix}`;
}

function functionRecord(entry) {
  return [
    `${entry.name}(${(entry.inputs ?? []).map(parameterType).join(",")})`,
    `(${(entry.outputs ?? []).map(parameterType).join(",")})`,
    entry.stateMutability,
  ].join(" -> ");
}

let checked = 0;
const failures = [];
for (const [exportName, artifactRelativePath] of surfaces) {
  const sdkAbi = sdk[exportName];
  if (!Array.isArray(sdkAbi)) {
    failures.push(`${exportName}: SDK export is missing`);
    continue;
  }
  const artifact = JSON.parse(await readFile(resolve(projectRoot, "out", artifactRelativePath), "utf8"));
  const contractFunctions = new Set(artifact.abi.filter((entry) => entry.type === "function")
    .map(functionRecord));
  for (const entry of sdkAbi.filter((candidate) => candidate.type === "function")) {
    checked += 1;
    const record = functionRecord(entry);
    if (!contractFunctions.has(record)) failures.push(`${exportName}: ${record}`);
  }
}

if (failures.length !== 0) {
  console.error(`Yield Banks SDK ABI verification failed (${failures.length} mismatch(es)):`);
  for (const failure of failures) console.error(`- ${failure}`);
  process.exitCode = 1;
} else {
  console.log(`Yield Banks SDK ABI verification passed: ${checked} function records match Solidity artifacts.`);
}
