const addressPattern = /^0x[0-9a-fA-F]{40}$/;
const hashPattern = /^0x[0-9a-fA-F]{64}$/;
const zeroAddress = "0x0000000000000000000000000000000000000000";

const inheritedAttestationFields = [
  "sourceCommit",
  "buildHash",
  "approvalProof0",
  "approvalProof1",
  "approvalProof2",
  "approvalProof3"
];

export function collectPromotionContracts(value, prefix, contracts, inheritedAttestation = {}) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return;
  const attestation = { ...inheritedAttestation };
  for (const field of inheritedAttestationFields) {
    if (value[field] !== undefined) attestation[field] = value[field];
  }
  for (const [key, nested] of Object.entries(value)) {
    if (["bindings", "operations", "supersedes", "verified"].includes(key)) continue;
    const path = prefix ? `${prefix}.${key}` : key;
    if (typeof nested === "string" && addressPattern.test(nested)) {
      const runtimeCodeHash = value[`${key}RuntimeCodeHash`];
      if (typeof runtimeCodeHash !== "string" || !hashPattern.test(runtimeCodeHash)) continue;
      const entry = { ...attestation, address: nested };
      const deploymentBlock = value[`${key}DeploymentBlock`];
      entry.runtimeCodeHash = runtimeCodeHash.toLowerCase();
      if (Number.isInteger(deploymentBlock)) entry.deploymentBlock = deploymentBlock;
      contracts[path] = entry;
      continue;
    }
    if (!nested || typeof nested !== "object" || Array.isArray(nested)) continue;
    if (typeof nested.address === "string" && addressPattern.test(nested.address)) {
      const entry = { ...attestation, address: nested.address };
      for (const field of [
        "runtimeCodeHash",
        "deploymentBlock",
        "deploymentTransaction",
        "implementation",
        "implementationRuntimeCodeHash",
        ...inheritedAttestationFields
      ]) {
        if (nested[field] !== undefined) entry[field] = nested[field];
      }
      contracts[path] = entry;
    } else {
      collectPromotionContracts(nested, path, contracts, attestation);
    }
  }
}

function resolveManifestValue(manifest, path) {
  let value = manifest;
  for (const segment of path.split(".")) {
    if (!value || typeof value !== "object" || Array.isArray(value) || !Object.hasOwn(value, segment)) {
      throw new Error(`manifest binding references missing ${path}`);
    }
    value = value[segment];
  }
  return value;
}

function validateBoundValue(value, format, label) {
  if (format === undefined) return;
  if (format === "nonzero-address") {
    if (typeof value !== "string" || !addressPattern.test(value) || value.toLowerCase() === zeroAddress) {
      throw new Error(`${label} must resolve to a complete non-zero address`);
    }
    return;
  }
  throw new Error(`${label} uses unsupported format ${format}`);
}

export function resolvePromotionConsumers(bindings, contracts, chainId, manifest = {}) {
  const consumers = {};
  for (const [consumerName, definition] of Object.entries(bindings)) {
    if (consumerName === "schemaVersion") continue;
    const consumer = {};
    if (definition.contracts) {
      consumer.contracts = {};
      for (const [name, path] of Object.entries(definition.contracts)) {
        const entry = contracts[path];
        if (!entry) throw new Error(`${consumerName}.${name} references missing ${path}`);
        consumer.contracts[name] = entry;
      }
    }
    if (definition.environment) {
      consumer.environment = {};
      for (const [name, binding] of Object.entries(definition.environment)) {
        if (binding.value !== undefined) {
          consumer.environment[name] = name.endsWith("CHAIN_ID") ? chainId : binding.value;
          continue;
        }
        if (binding.manifestPath !== undefined) {
          const value = resolveManifestValue(manifest, binding.manifestPath);
          validateBoundValue(value, binding.format, `${consumerName}.${name}`);
          consumer.environment[name] = value;
          continue;
        }
        const entry = contracts[binding.path];
        if (!entry || entry[binding.field] === undefined) {
          throw new Error(`${consumerName}.${name} references missing ${binding.path}.${binding.field}`);
        }
        consumer.environment[name] = entry[binding.field];
      }
    }
    consumers[consumerName] = consumer;
  }
  return consumers;
}
