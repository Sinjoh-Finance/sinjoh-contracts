#!/usr/bin/env node

import { readFile } from "node:fs/promises";
import { createRequire } from "node:module";

const requireFromSdk = createRequire(new URL("../sdk/package.json", import.meta.url));
const { createPublicClient, getAddress, http, keccak256, parseAbi } = requireFromSdk("viem");

const manifestPath = process.argv[2];
const rpcUrls = process.argv.slice(3);
if (!manifestPath || rpcUrls.length === 0) {
  throw new Error(
    "usage: node script/verify-yield-bank-protocol-deployment.mjs <manifest.json> <rpc-url> [rpc-url...]",
  );
}
const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
const registryAbi = parseAbi(["function governance() view returns (address)"]);
const factoryDeployerAbi = parseAbi(["function registry() view returns (address)"]);

const verifyProvider = async (rpcUrl) => {
  const client = createPublicClient({
    transport: http(rpcUrl, { retryCount: 10, retryDelay: 1_500 }),
  });
  const chainId = await client.getChainId();
  if (chainId !== manifest.chainId) {
    throw new Error(`${rpcUrl}: chain is ${chainId}, expected ${manifest.chainId}`);
  }
  const registry = getAddress(manifest.registry.address);
  const factoryDeployer = getAddress(manifest.factoryDeployer.address);
  const [registryCode, factoryDeployerCode, governance, boundRegistry] = await Promise.all([
    client.getBytecode({ address: registry }),
    client.getBytecode({ address: factoryDeployer }),
    client.readContract({ address: registry, abi: registryAbi, functionName: "governance" }),
    client.readContract({
      address: factoryDeployer,
      abi: factoryDeployerAbi,
      functionName: "registry",
    }),
  ]);
  if (!registryCode || registryCode === "0x") throw new Error(`${rpcUrl}: registry has no code`);
  if (!factoryDeployerCode || factoryDeployerCode === "0x") {
    throw new Error(`${rpcUrl}: factory deployer has no code`);
  }
  const equal = (actual, expected, label) => {
    if (actual.toLowerCase() !== expected.toLowerCase()) {
      throw new Error(`${rpcUrl}: ${label} is ${actual}, expected ${expected}`);
    }
  };
  equal(keccak256(registryCode), manifest.registry.runtimeCodeHash, "registry runtime hash");
  equal(
    keccak256(factoryDeployerCode),
    manifest.factoryDeployer.runtimeCodeHash,
    "factory deployer runtime hash",
  );
  equal(governance, manifest.governance, "registry governance");
  equal(boundRegistry, registry, "factory deployer registry");
  return {
    rpcUrl,
    chainId,
    registryRuntimeCodeHash: keccak256(registryCode),
    factoryDeployerRuntimeCodeHash: keccak256(factoryDeployerCode),
  };
};

const results = [];
for (const rpcUrl of rpcUrls) results.push(await verifyProvider(rpcUrl));
console.log(JSON.stringify({ status: "verified", providers: results }, null, 2));
