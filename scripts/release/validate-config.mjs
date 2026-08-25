#!/usr/bin/env node
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join, relative, resolve } from "node:path";

const repoRoot = resolve(import.meta.dirname, "../..");
const errors = [];
const warnings = [];
const addressPattern = /^0x[0-9a-fA-F]{40}$/;
const hashPattern = /^0x[0-9a-fA-F]{64}$/;

function readJson(relativePath) {
  const absolutePath = resolve(repoRoot, relativePath);
  try {
    return JSON.parse(readFileSync(absolutePath, "utf8"));
  } catch (error) {
    errors.push(`${relativePath}: ${error.message}`);
    return null;
  }
}

function requireValue(condition, message) {
  if (!condition) errors.push(message);
}

function validateNetwork(chainId) {
  const path = `deployments/networks/${chainId}.json`;
  const profile = readJson(path);
  if (!profile) return;

  requireValue(profile.schemaVersion === 1, `${path}: schemaVersion must be 1`);
  requireValue(profile.chainId === chainId, `${path}: chainId must be ${chainId}`);
  requireValue(typeof profile.production === "boolean", `${path}: production must be boolean`);
  requireValue(profile.nativeCurrency?.symbol === "ETH", `${path}: native currency must be ETH`);
  requireValue(profile.rpc?.publicHttp?.startsWith("https://"), `${path}: public RPC must be HTTPS`);
  requireValue(profile.explorer?.apiUrl?.startsWith("https://"), `${path}: explorer API must be HTTPS`);
  requireValue(
    profile.finality?.releaseActivationBlockTag === "finalized",
    `${path}: releases must activate on the finalized block tag`
  );
  requireValue(
    profile.deployment?.githubActionsMayBroadcast === !profile.production,
    `${path}: only the non-production network may broadcast from GitHub Actions`
  );

  const manifest = profile.deployment?.currentManifest;
  requireValue(typeof manifest === "string", `${path}: currentManifest is required`);
  if (typeof manifest === "string") {
    requireValue(existsSync(resolve(repoRoot, manifest)), `${path}: manifest does not exist: ${manifest}`);
  }
}

function walkDeploymentValues(value, path) {
  if (Array.isArray(value)) {
    value.forEach((item, index) => walkDeploymentValues(item, `${path}[${index}]`));
    return;
  }
  if (!value || typeof value !== "object") return;
  if (path.endsWith(".supersedes")) return;

  if ("address" in value) {
    requireValue(addressPattern.test(value.address), `${path}.address: invalid address`);
    requireValue(hashPattern.test(value.runtimeCodeHash), `${path}.runtimeCodeHash: required for contract address`);
  }
  for (const [key, nested] of Object.entries(value)) {
    if ((key === "runtimeCodeHash" || key.endsWith("RuntimeCodeHash")) && nested !== null) {
      requireValue(hashPattern.test(nested), `${path}.${key}: invalid bytes32 hash`);
    }
    if (key === "deploymentTransaction") {
      requireValue(hashPattern.test(nested), `${path}.${key}: invalid transaction hash`);
    }
    walkDeploymentValues(nested, `${path}.${key}`);
  }
}

function validateDeploymentManifests() {
  const mainnet = readJson("mainnet-deployments.json");
  if (mainnet) {
    requireValue(mainnet.chainId === 4663, "mainnet-deployments.json: chainId must be 4663");
    requireValue(typeof mainnet.releaseCandidate === "boolean", "mainnet-deployments.json: releaseCandidate must be boolean");
    requireValue(addressPattern.test(mainnet.deployer), "mainnet-deployments.json: invalid deployer");
    requireValue(addressPattern.test(mainnet.governance), "mainnet-deployments.json: invalid governance");
    walkDeploymentValues(mainnet.currentInfrastructure, "mainnet-deployments.json.currentInfrastructure");
    walkDeploymentValues(mainnet.dependencies, "mainnet-deployments.json.dependencies");
    if (mainnet.releaseCandidate === true) {
      warnings.push("mainnet-deployments.json is still marked releaseCandidate=true");
    }
  }

  const testnet = readJson("deployments/manifests/46630/current.json");
  if (testnet) {
    requireValue(testnet.chainId === 46630, "testnet current manifest: chainId must be 46630");
    requireValue(
      ["not-deployed", "deployed", "superseded"].includes(testnet.status),
      "testnet current manifest: invalid status"
    );
    if (testnet.status === "deployed") {
      requireValue(hashPattern.test(`0x${testnet.sourceCommit}`), "testnet current manifest: invalid sourceCommit");
      requireValue(Object.keys(testnet.contracts ?? {}).length > 0, "testnet current manifest: no contracts");
      walkDeploymentValues(testnet.contracts, "testnet current manifest.contracts");
    }
  }
}

function validateOnchainAssertions(chainId) {
  const relativePath = `deployments/assertions/${chainId}.json`;
  const document = readJson(relativePath);
  if (!document) return;
  requireValue(document.schemaVersion === 1, `${relativePath}: schemaVersion must be 1`);
  requireValue(document.chainId === chainId, `${relativePath}: chainId must be ${chainId}`);
  requireValue(Array.isArray(document.assertions), `${relativePath}: assertions must be an array`);

  const ids = new Set();
  for (const assertion of document.assertions ?? []) {
    requireValue(
      typeof assertion.id === "string" && /^[a-z0-9][a-z0-9-]*$/.test(assertion.id),
      `${relativePath}: invalid assertion id`,
    );
    requireValue(!ids.has(assertion.id), `${relativePath}: duplicate assertion ${assertion.id}`);
    ids.add(assertion.id);
    requireValue(addressPattern.test(assertion.address), `${relativePath}: ${assertion.id} address`);
    requireValue(
      typeof assertion.signature === "string"
        && /^[A-Za-z_][A-Za-z0-9_]*\(\)\((address|bool|uint(8|16|24|32|48|64|128|256)?)\)$/.test(assertion.signature),
      `${relativePath}: ${assertion.id} signature`,
    );
    requireValue(
      ["address", "bool", "uint"].includes(assertion.type),
      `${relativePath}: ${assertion.id} type`,
    );
    if (assertion.type === "address") {
      requireValue(addressPattern.test(assertion.expected), `${relativePath}: ${assertion.id} expected address`);
    } else if (assertion.type === "bool") {
      requireValue(typeof assertion.expected === "boolean", `${relativePath}: ${assertion.id} expected bool`);
    } else if (assertion.type === "uint") {
      requireValue(
        typeof assertion.expected === "string" && /^(0|[1-9][0-9]*)$/.test(assertion.expected),
        `${relativePath}: ${assertion.id} expected uint`,
      );
    }
  }
  requireValue(ids.size > 0, `${relativePath}: no assertions`);
}

function validateDeploymentPlan(chainId) {
  const relativePath = `deployments/plans/${chainId}.json`;
  const plan = readJson(relativePath);
  if (!plan) return;
  requireValue(plan.chainId === chainId, `${relativePath}: chainId must be ${chainId}`);

  const ids = new Set();
  const positions = new Map();
  for (const [index, step] of (plan.steps ?? []).entries()) {
    requireValue(!ids.has(step.id), `${relativePath}: duplicate step ${step.id}`);
    ids.add(step.id);
    positions.set(step.id, index);
    requireValue(
      ["ready", "blocked", "complete", "deprecated"].includes(step.status),
      `${relativePath}: ${step.id} status`
    );
    requireValue(["protocol-deployer", "launch-deployer"].includes(step.signerRole), `${relativePath}: ${step.id} signerRole`);
    const scriptPath = step.script?.split(":", 1)[0];
    requireValue(
      typeof scriptPath === "string" && existsSync(resolve(repoRoot, step.package, scriptPath)),
      `${relativePath}: ${step.id} script does not exist`
    );
    if (chainId === 4663 && typeof scriptPath === "string") {
      const absoluteScript = resolve(repoRoot, step.package, scriptPath);
      if (existsSync(absoluteScript)) {
        requireValue(
          !readFileSync(absoluteScript, "utf8").includes("DEPLOYER_PRIVATE_KEY"),
          `${relativePath}: ${step.id} mainnet entrypoint may not consume a raw private key`
        );
      }
    } else if (chainId === 46630 && typeof scriptPath === "string") {
      const absoluteScript = resolve(repoRoot, step.package, scriptPath);
      if (existsSync(absoluteScript)) {
        requireValue(
          readFileSync(absoluteScript, "utf8").includes("TESTNET_DEPLOYER_ADDRESS"),
          `${relativePath}: ${step.id} must bind its key to TESTNET_DEPLOYER_ADDRESS`
        );
      }
    }
  }
  for (const step of plan.steps ?? []) {
    for (const dependency of step.dependsOn ?? []) {
      requireValue(ids.has(dependency), `${relativePath}: ${step.id} has unknown dependency ${dependency}`);
      requireValue(dependency !== step.id, `${relativePath}: ${step.id} depends on itself`);
      requireValue(
        (positions.get(dependency) ?? Number.MAX_SAFE_INTEGER) < (positions.get(step.id) ?? -1),
        `${relativePath}: ${step.id} dependency ${dependency} must appear earlier in the plan`
      );
    }
  }
}

function validatePromotionAuthority() {
  const schema = readJson("deployments/schema/promotion.schema.json");
  const repository = schema?.properties?.source?.properties?.repository?.const;
  requireValue(
    repository === "Sinjoh-Finance/sinjoh-contracts",
    "promotion schema must trust the canonical contracts repository"
  );
  requireValue(
    (schema?.properties?.source?.required ?? []).includes("releaseManifestSha256"),
    "promotion schema must bind the immutable release manifest"
  );

  const importer = readFileSync(resolve(repoRoot, "scripts/release/import-service-promotion.mjs"), "utf8");
  requireValue(
    importer.includes('Sinjoh-Finance/sinjoh-contracts'),
    "service promotion importer must trust the canonical contracts repository"
  );

  for (const entry of readdirSync(repoRoot, { withFileTypes: true })) {
    if (!entry.isDirectory() || !entry.name.startsWith("sinjoh-")) continue;
    const scriptRoot = resolve(repoRoot, entry.name, "script");
    if (!existsSync(scriptRoot)) continue;
    for (const script of readdirSync(scriptRoot)) {
      if (!script.endsWith(".s.sol") || script.includes("Testnet")) continue;
      const relativePath = `${entry.name}/script/${script}`;
      requireValue(
        !readFileSync(resolve(scriptRoot, script), "utf8").includes("DEPLOYER_PRIVATE_KEY"),
        `${relativePath}: mainnet-capable scripts may not consume a raw private key`
      );
    }
  }
}

function validateForkInventories() {
  const registered = new Set();
  for (const chainId of [4663, 46630]) {
    const relativePath = `deployments/forks/${chainId}.txt`;
    const lines = readFileSync(resolve(repoRoot, relativePath), "utf8").split(/\r?\n/);
    const seen = new Set();
    for (const line of lines) {
      const path = line.trim();
      if (!path || path.startsWith("#")) continue;
      requireValue(path.endsWith(".fork.t.sol"), `${relativePath}: non-fork test ${path}`);
      requireValue(existsSync(resolve(repoRoot, path)), `${relativePath}: missing ${path}`);
      requireValue(!seen.has(path), `${relativePath}: duplicate ${path}`);
      requireValue(!registered.has(path), `${relativePath}: ${path} is registered for more than one network`);
      seen.add(path);
      registered.add(path);
    }
    requireValue(seen.size > 0, `${relativePath}: no tests registered`);
  }

  for (const entry of readdirSync(repoRoot, { withFileTypes: true })) {
    if (!entry.isDirectory() || !entry.name.startsWith("sinjoh-")) continue;
    const testRoot = resolve(repoRoot, entry.name, "test");
    if (!existsSync(testRoot)) continue;
    const pending = [testRoot];
    while (pending.length > 0) {
      const directory = pending.pop();
      for (const child of readdirSync(directory, { withFileTypes: true })) {
        const absolute = join(directory, child.name);
        if (child.isDirectory()) pending.push(absolute);
        if (child.isFile() && child.name.endsWith(".fork.t.sol")) {
          const path = relative(repoRoot, absolute);
          requireValue(registered.has(path), `unregistered first-party fork test: ${path}`);
        }
      }
    }
  }
}

function validateConsumerBindings() {
  const path = "deployments/consumers/bindings.json";
  const bindings = readJson(path);
  if (!bindings) return;
  requireValue(bindings.schemaVersion === 1, `${path}: schemaVersion must be 1`);

  const consumers = Object.entries(bindings).filter(([name]) => name !== "schemaVersion");
  requireValue(consumers.length > 0, `${path}: at least one consumer is required`);
  for (const [consumerName, consumer] of consumers) {
    requireValue(
      consumer && typeof consumer === "object" && !Array.isArray(consumer),
      `${path}: ${consumerName} must be an object`,
    );
    for (const [contractName, contractPath] of Object.entries(consumer?.contracts ?? {})) {
      requireValue(/^[A-Za-z][A-Za-z0-9]*$/.test(contractName), `${path}: invalid ${consumerName} contract name ${contractName}`);
      requireValue(
        typeof contractPath === "string" && /^(contracts|dependencies)\./.test(contractPath),
        `${path}: invalid ${consumerName}.${contractName} canonical path`,
      );
    }
    for (const [variableName, binding] of Object.entries(consumer?.environment ?? {})) {
      requireValue(/^[A-Z][A-Z0-9_]*$/.test(variableName), `${path}: invalid environment name ${variableName}`);
      const hasValue = binding && Object.hasOwn(binding, "value");
      const hasPath = typeof binding?.path === "string";
      const hasManifestPath = typeof binding?.manifestPath === "string";
      requireValue(
        Number(hasValue) + Number(hasPath) + Number(hasManifestPath) === 1,
        `${path}: ${consumerName}.${variableName} must use exactly one of value, path, or manifestPath`,
      );
      if (hasPath) {
        requireValue(
          /^(contracts|dependencies)\./.test(binding.path),
          `${path}: ${consumerName}.${variableName} has invalid canonical path`,
        );
        requireValue(
          [
            "address",
            "runtimeCodeHash",
            "deploymentBlock",
            "sourceCommit",
            "buildHash",
            "approvalProof0",
            "approvalProof1",
            "approvalProof2",
            "approvalProof3",
          ].includes(binding.field),
          `${path}: ${consumerName}.${variableName} has invalid field`,
        );
      }
      if (hasManifestPath) {
        requireValue(
          /^currentInfrastructure\.[A-Za-z][A-Za-z0-9]*(?:\.[A-Za-z][A-Za-z0-9]*)+$/.test(binding.manifestPath),
          `${path}: ${consumerName}.${variableName} has invalid manifest path`,
        );
        requireValue(
          binding.format === "nonzero-address",
          `${path}: ${consumerName}.${variableName} manifest binding must validate as nonzero-address`,
        );
      } else {
        requireValue(
          binding?.format === undefined,
          `${path}: ${consumerName}.${variableName} format is only valid for manifest bindings`,
        );
      }
    }
  }
}

validateNetwork(4663);
validateNetwork(46630);
validateDeploymentManifests();
validateOnchainAssertions(4663);
validateDeploymentPlan(4663);
validateDeploymentPlan(46630);
validateForkInventories();
validateConsumerBindings();
validatePromotionAuthority();

for (const warning of warnings) console.warn(`warning: ${warning}`);
if (errors.length > 0) {
  for (const error of errors) console.error(`error: ${error}`);
  process.exit(1);
}
console.log("release configuration is valid");
