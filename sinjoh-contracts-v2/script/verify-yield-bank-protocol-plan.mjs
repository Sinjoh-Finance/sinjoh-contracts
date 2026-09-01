#!/usr/bin/env node

import { readFile } from "node:fs/promises";
import { createRequire } from "node:module";

const requireFromSdk = createRequire(new URL("../sdk/package.json", import.meta.url));
const {
  concat,
  createPublicClient,
  encodeAbiParameters,
  getAddress,
  getContractAddress,
  http,
  keccak256,
} = requireFromSdk("viem");

const planPath = process.argv[2];
const rpcUrl = process.argv[3] ?? process.env.YIELD_BANK_RPC_URL;
if (!planPath || !rpcUrl) {
  throw new Error(
    "usage: node script/verify-yield-bank-protocol-plan.mjs <plan.json> <rpc-url>",
  );
}

const [planJson, registryArtifactJson, factoryDeployerArtifactJson] = await Promise.all([
  readFile(planPath, "utf8"),
  readFile("out/YieldBankProtocolRegistry.sol/YieldBankProtocolRegistry.json", "utf8"),
  readFile(
    "out/YieldBankSystemFactoryDeployer.sol/YieldBankSystemFactoryDeployer.json",
    "utf8",
  ),
]);
const plan = JSON.parse(planJson);
const registryArtifact = JSON.parse(registryArtifactJson);
const factoryDeployerArtifact = JSON.parse(factoryDeployerArtifactJson);

const addressPattern = /^0x[0-9a-fA-F]{40}$/;
const bytes32Pattern = /^0x[0-9a-fA-F]{64}$/;
const requiredKeys = new Set([
  "chainId",
  "deployer",
  "deployerNonce",
  "governance",
  "expectedRegistry",
  "expectedFactoryDeployer",
  "registryCreationCodeHash",
  "factoryDeployerCreationCodeHash",
]);
if (Object.keys(plan).length !== requiredKeys.size) {
  throw new Error("deployment plan has missing or additional fields");
}
for (const key of Object.keys(plan)) {
  if (!requiredKeys.has(key)) throw new Error(`unexpected plan field ${key}`);
}
if (!Number.isSafeInteger(plan.chainId) || plan.chainId <= 0) {
  throw new Error("invalid chainId");
}
if (!Number.isSafeInteger(plan.deployerNonce) || plan.deployerNonce < 0) {
  throw new Error("invalid deployerNonce");
}
for (const key of ["deployer", "governance", "expectedRegistry", "expectedFactoryDeployer"]) {
  if (!addressPattern.test(plan[key])) throw new Error(`invalid ${key}`);
}
for (const key of ["registryCreationCodeHash", "factoryDeployerCreationCodeHash"]) {
  if (!bytes32Pattern.test(plan[key])) throw new Error(`invalid ${key}`);
}

const deployer = getAddress(plan.deployer);
const governance = getAddress(plan.governance);
const expectedRegistry = getContractAddress({ from: deployer, nonce: BigInt(plan.deployerNonce) });
const expectedFactoryDeployer = getContractAddress({
  from: deployer,
  nonce: BigInt(plan.deployerNonce + 1),
});
const registryCreationCode = concat([
  registryArtifact.bytecode.object,
  encodeAbiParameters([{ type: "address" }], [governance]),
]);
const factoryDeployerCreationCode = concat([
  factoryDeployerArtifact.bytecode.object,
  encodeAbiParameters([{ type: "address" }], [expectedRegistry]),
]);

const equal = (actual, expected, label) => {
  if (actual.toLowerCase() !== expected.toLowerCase()) {
    throw new Error(`${label} is ${actual}, expected ${expected}`);
  }
};
equal(plan.expectedRegistry, expectedRegistry, "expectedRegistry");
equal(plan.expectedFactoryDeployer, expectedFactoryDeployer, "expectedFactoryDeployer");
equal(
  plan.registryCreationCodeHash,
  keccak256(registryCreationCode),
  "registryCreationCodeHash",
);
equal(
  plan.factoryDeployerCreationCodeHash,
  keccak256(factoryDeployerCreationCode),
  "factoryDeployerCreationCodeHash",
);

const client = createPublicClient({
  transport: http(rpcUrl, { retryCount: 10, retryDelay: 1_500 }),
});
const chainId = await client.getChainId();
if (chainId !== plan.chainId) throw new Error(`RPC chain is ${chainId}, expected ${plan.chainId}`);
const nonce = await client.getTransactionCount({ address: deployer, blockTag: "pending" });
if (nonce !== plan.deployerNonce) {
  throw new Error(`pending deployer nonce is ${nonce}, expected ${plan.deployerNonce}`);
}
for (const [label, address] of [
  ["expectedRegistry", expectedRegistry],
  ["expectedFactoryDeployer", expectedFactoryDeployer],
]) {
  const code = await client.getBytecode({ address });
  if (code && code !== "0x") throw new Error(`${label} ${address} already has code`);
}

console.log(
  JSON.stringify(
    {
      status: "valid",
      chainId,
      deployer,
      deployerNonce: nonce,
      governance,
      expectedRegistry,
      expectedFactoryDeployer,
      registryCreationCodeHash: keccak256(registryCreationCode),
      factoryDeployerCreationCodeHash: keccak256(factoryDeployerCreationCode),
    },
    null,
    2,
  ),
);
