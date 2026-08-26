#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync, realpathSync } from "node:fs";
import { relative, resolve } from "node:path";

const repoRoot = resolve(import.meta.dirname, "../..");

function argument(name, fallback = undefined) {
  const index = process.argv.indexOf(name);
  return index === -1 ? fallback : process.argv[index + 1];
}

function cast(args) {
  return execFileSync("cast", args, { cwd: repoRoot, encoding: "utf8" }).trim();
}

function rpcOptions(rpcUrl) {
  return [
    "--rpc-url",
    rpcUrl,
    "--rpc-headers",
    "User-Agent: Sinjoh-Release-Verifier/1.0"
  ];
}

function assertionValue(assertion, output) {
  const value = output.split(/\s+/, 1)[0];
  if (assertion.type === "address") return value.toLowerCase();
  if (assertion.type === "bool") return value === "true";
  return value;
}

function collectContracts(value, path, contracts) {
  if (Array.isArray(value)) {
    value.forEach((entry, index) => collectContracts(entry, `${path}[${index}]`, contracts));
    return;
  }
  if (!value || typeof value !== "object") return;
  if (path.endsWith(".supersedes")) return;
  if (typeof value.address === "string" && !value.runtimeCodeHash) {
    throw new Error(`${path}: contract address is not pinned to a runtimeCodeHash`);
  }
  if (typeof value.address === "string" && typeof value.runtimeCodeHash === "string") {
    contracts.push({
      path,
      address: value.address,
      runtimeCodeHash: value.runtimeCodeHash.toLowerCase(),
      deploymentBlock: value.deploymentBlock
    });
  }
  for (const [key, nested] of Object.entries(value)) {
    const hash = value[`${key}RuntimeCodeHash`];
    if (
      key !== "address" &&
      typeof nested === "string" &&
      /^0x[0-9a-fA-F]{40}$/.test(nested) &&
      typeof hash === "string"
    ) {
      contracts.push({
        path: `${path}.${key}`,
        address: nested,
        runtimeCodeHash: hash.toLowerCase(),
        deploymentBlock: value[`${key}DeploymentBlock`]
      });
    }
  }
  for (const [key, nested] of Object.entries(value)) {
    collectContracts(nested, `${path}.${key}`, contracts);
  }
}

function collectImplementationBindings(value, path, bindings) {
  if (Array.isArray(value)) {
    value.forEach((entry, index) => collectImplementationBindings(entry, `${path}[${index}]`, bindings));
    return;
  }
  if (!value || typeof value !== "object") return;
  if (value.implementationBinding?.kind === "eip1967") {
    if (
      !/^0x[0-9a-fA-F]{40}$/.test(value.address ?? "") ||
      !/^0x[0-9a-fA-F]{40}$/.test(value.implementation ?? "") ||
      !/^0x[0-9a-fA-F]{64}$/.test(value.implementationBinding.slot ?? "")
    ) {
      throw new Error(`${path}: incomplete EIP-1967 implementation binding`);
    }
    bindings.push({
      path,
      proxy: value.address,
      implementation: value.implementation.toLowerCase(),
      slot: value.implementationBinding.slot
    });
  }
  for (const [key, nested] of Object.entries(value)) {
    collectImplementationBindings(nested, `${path}.${key}`, bindings);
  }
}

function storageAddress(value) {
  if (!/^0x[0-9a-fA-F]{64}$/.test(value)) throw new Error(`invalid storage word ${value}`);
  return `0x${value.slice(-40)}`.toLowerCase();
}

const chainId = Number(argument("--network"));
const rpcUrl = argument("--rpc-url");
const secondaryRpcUrl = argument("--secondary-rpc-url");
const manifestPath = argument(
  "--manifest",
  chainId === 4663 ? "mainnet-deployments.json" : "deployments/manifests/46630/current.json"
);
const requireFinalized = process.argv.includes("--require-finalized");
const requireSecondary = process.argv.includes("--require-secondary");

if (![4663, 46630].includes(chainId)) throw new Error("--network must be 4663 or 46630");
if (!rpcUrl) throw new Error("--rpc-url is required");
if (requireSecondary && !secondaryRpcUrl) throw new Error("--secondary-rpc-url is required");
if (Number(cast(["chain-id", ...rpcOptions(rpcUrl)])) !== chainId) throw new Error("primary RPC chain mismatch");
if (secondaryRpcUrl && Number(cast(["chain-id", ...rpcOptions(secondaryRpcUrl)])) !== chainId) {
  throw new Error("secondary RPC chain mismatch");
}

const requestedManifest = resolve(repoRoot, manifestPath);
const resolvedManifest = realpathSync(requestedManifest);
if (relative(repoRoot, resolvedManifest).startsWith("..")) {
  throw new Error("--manifest must resolve inside the repository");
}
if (!resolvedManifest.endsWith(".json")) throw new Error("--manifest must be a JSON file");
const manifest = JSON.parse(readFileSync(resolvedManifest, "utf8"));
if (manifest.chainId !== chainId) throw new Error("manifest chain mismatch");

const roots = chainId === 4663
  ? [manifest.currentInfrastructure, manifest.dependencies, manifest.letscashDependencies]
  : [manifest.contracts];
const contracts = [];
roots.forEach((root, index) => collectContracts(root, `root[${index}]`, contracts));
if (contracts.length === 0) throw new Error("manifest contains no code-hash-pinned contracts");
const implementationBindings = [];
roots.forEach((root, index) => collectImplementationBindings(root, `root[${index}]`, implementationBindings));

const finalized = requireFinalized
  ? Number(cast(["block", "finalized", "--field", "number", ...rpcOptions(rpcUrl)]))
  : null;
const secondaryFinalized = requireFinalized && secondaryRpcUrl
  ? Number(cast(["block", "finalized", "--field", "number", ...rpcOptions(secondaryRpcUrl)]))
  : null;
const failures = [];
for (const contract of contracts) {
  const primaryHash = cast(["codehash", contract.address, ...rpcOptions(rpcUrl)]).toLowerCase();
  if (primaryHash !== contract.runtimeCodeHash) {
    failures.push(`${contract.path}: primary code hash ${primaryHash} != ${contract.runtimeCodeHash}`);
  }
  if (secondaryRpcUrl) {
    const secondaryHash = cast(["codehash", contract.address, ...rpcOptions(secondaryRpcUrl)]).toLowerCase();
    if (secondaryHash !== primaryHash) {
      failures.push(`${contract.path}: RPC providers disagree (${primaryHash} != ${secondaryHash})`);
    }
  }
  if (requireFinalized && Number.isInteger(contract.deploymentBlock) && contract.deploymentBlock > finalized) {
    failures.push(`${contract.path}: deployment block ${contract.deploymentBlock} exceeds finalized ${finalized}`);
  }
  if (
    requireFinalized &&
    Number.isInteger(contract.deploymentBlock) &&
    secondaryFinalized !== null &&
    contract.deploymentBlock > secondaryFinalized
  ) {
    failures.push(
      `${contract.path}: deployment block ${contract.deploymentBlock} exceeds secondary finalized ${secondaryFinalized}`
    );
  }
}
for (const binding of implementationBindings) {
  try {
    const primaryValue = storageAddress(cast([
      "storage",
      binding.proxy,
      binding.slot,
      ...rpcOptions(rpcUrl)
    ]));
    if (primaryValue !== binding.implementation) {
      failures.push(
        `${binding.path}: primary EIP-1967 implementation ${primaryValue} != ${binding.implementation}`
      );
    }
    if (secondaryRpcUrl) {
      const secondaryValue = storageAddress(cast([
        "storage",
        binding.proxy,
        binding.slot,
        ...rpcOptions(secondaryRpcUrl)
      ]));
      if (secondaryValue !== primaryValue) {
        failures.push(
          `${binding.path}: RPC providers disagree on EIP-1967 implementation (${primaryValue} != ${secondaryValue})`
        );
      }
    }
  } catch (error) {
    failures.push(`${binding.path}: EIP-1967 read failed (${error.message.split("\n", 1)[0]})`);
  }
}

const assertionsPath = resolve(repoRoot, `deployments/assertions/${chainId}.json`);
let assertionCount = 0;
if (existsSync(assertionsPath)) {
  const assertionsDocument = JSON.parse(readFileSync(assertionsPath, "utf8"));
  if (assertionsDocument.chainId !== chainId) {
    failures.push(`assertion chain mismatch (${assertionsDocument.chainId} != ${chainId})`);
  }
  for (const assertion of assertionsDocument.assertions ?? []) {
    assertionCount += 1;
    const expected = assertion.type === "address"
      ? assertion.expected.toLowerCase()
      : assertion.expected;
    try {
      const primaryOutput = cast([
        "call",
        assertion.address,
        assertion.signature,
        ...rpcOptions(rpcUrl)
      ]);
      const primaryValue = assertionValue(assertion, primaryOutput);
      if (primaryValue !== expected) {
        failures.push(`${assertion.id}: primary value ${primaryValue} != ${expected}`);
      }
      if (secondaryRpcUrl) {
        const secondaryOutput = cast([
          "call",
          assertion.address,
          assertion.signature,
          ...rpcOptions(secondaryRpcUrl)
        ]);
        const secondaryValue = assertionValue(assertion, secondaryOutput);
        if (secondaryValue !== primaryValue) {
          failures.push(
            `${assertion.id}: RPC providers disagree (${primaryValue} != ${secondaryValue})`
          );
        }
      }
    } catch (error) {
      failures.push(`${assertion.id}: call failed (${error.message.split("\n", 1)[0]})`);
    }
  }
}

if (failures.length > 0) {
  failures.forEach((failure) => console.error(`error: ${failure}`));
  process.exit(1);
}
console.log(`verified ${contracts.length} code-hash-pinned contracts on chain ${chainId}`);
if (implementationBindings.length > 0) {
  console.log(`verified ${implementationBindings.length} EIP-1967 implementation bindings`);
}
if (assertionCount > 0) console.log(`verified ${assertionCount} owner/admin/config assertions`);
if (requireFinalized) console.log(`finalized block: ${finalized}`);
if (secondaryFinalized !== null) console.log(`secondary finalized block: ${secondaryFinalized}`);
