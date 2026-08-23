#!/usr/bin/env node
import { execFileSync, spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const repoRoot = resolve(import.meta.dirname, "../..");

function argument(name) {
  const index = process.argv.indexOf(name);
  return index === -1 ? undefined : process.argv[index + 1];
}

const stepId = argument("--step");
const rpcUrl = argument("--rpc-url") ?? process.env.ROBINHOOD_TESTNET_RPC_URL;
const broadcast = process.argv.includes("--broadcast");
const privateKey = process.env.DEPLOYER_PRIVATE_KEY;
const expectedDeployer = process.env.TESTNET_DEPLOYER_ADDRESS;

if (!stepId) throw new Error("--step is required");
if (!rpcUrl) throw new Error("--rpc-url or ROBINHOOD_TESTNET_RPC_URL is required");
if (!privateKey) throw new Error("the protected testnet deployer key is required");
if (!/^0x[0-9a-fA-F]{40}$/.test(expectedDeployer ?? "")) {
  throw new Error("TESTNET_DEPLOYER_ADDRESS must pin the testnet-only signer identity");
}
const derivedDeployer = execFileSync(
  "cast",
  ["wallet", "address", "--private-key", privateKey],
  { cwd: repoRoot, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] },
).trim();
if (derivedDeployer.toLowerCase() !== expectedDeployer.toLowerCase()) {
  throw new Error("protected testnet deployer key does not match TESTNET_DEPLOYER_ADDRESS");
}

const chainId = execFileSync("cast", ["chain-id", "--rpc-url", rpcUrl], {
  cwd: repoRoot,
  encoding: "utf8"
}).trim();
if (chainId !== "46630") throw new Error(`refusing testnet deployment on chain ${chainId}`);

const plan = JSON.parse(readFileSync(resolve(repoRoot, "deployments/plans/46630.json"), "utf8"));
const step = plan.steps.find((candidate) => candidate.id === stepId);
if (!step) throw new Error(`unknown testnet deployment step: ${stepId}`);
if (step.status !== "ready") throw new Error(`testnet deployment step is ${step.status}: ${stepId}`);
const current = JSON.parse(
  readFileSync(resolve(repoRoot, "deployments/manifests/46630/current.json"), "utf8")
);
const completedSteps = new Set(current.completedSteps ?? []);
const missingDependencies = (step.dependsOn ?? []).filter((dependency) => !completedSteps.has(dependency));
if (missingDependencies.length > 0) {
  throw new Error(
    `${step.id} requires finalized manifest steps: ${missingDependencies.join(", ")}`
  );
}

const forgeArguments = ["script", step.script, "--rpc-url", rpcUrl, "--slow"];
if (broadcast) {
  forgeArguments.push(
    "--broadcast",
    "--verify",
    "--verifier",
    "blockscout",
    "--verifier-url",
    "https://explorer.testnet.chain.robinhood.com/api/"
  );
}

console.log(`${broadcast ? "broadcasting" : "simulating"} ${step.id} from ${step.package}`);
const result = spawnSync("forge", forgeArguments, {
  cwd: resolve(repoRoot, step.package),
  env: {
    ...process.env,
    ROBINHOOD_TESTNET_RPC_URL: rpcUrl,
    DEPLOYER_PRIVATE_KEY: privateKey,
    TESTNET_DEPLOYER_ADDRESS: expectedDeployer,
  },
  stdio: "inherit"
});
if (result.error) throw result.error;
if (result.status !== 0) process.exit(result.status ?? 1);
if (broadcast) {
  console.log(
    `record ${step.id}, its transaction(s), finalized block, addresses, and runtime hashes in ` +
      "deployments/manifests/46630/current.json before running dependent steps"
  );
}
