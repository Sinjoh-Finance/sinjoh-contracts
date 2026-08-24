const addressPattern = /^0x[0-9a-fA-F]{40}$/;
const bytes32Pattern = /^0x[0-9a-fA-F]{64}$/;
const commitPattern = /^[0-9a-f]{40}$/;
const buildPattern = /^[0-9a-fA-F]{64}$/;

export const projectV2DeploymentKeys = [
  "raffleImplementation",
  "fundingBandV3IntegrationFactory",
  "fundingBandQuoteUsdOracle",
  "projectV3PriceGuard500",
  "projectV3PriceGuard3000",
  "projectV3PriceGuard10000",
  "ponsProjectAdapterFactory",
  "ponsProjectAdapterImplementation",
  "poolsInstantProjectAdapterFactory",
  "poolsInstantNoFeeProjectAdapterFactory",
  "poolsLbpProjectAdapterFactory",
  "poolsProjectRegistrationHelper",
  "ponsProjectTokenFactory",
  "launchpadProjectTokenFactory",
  "registry",
  "deploymentEngine",
  "launchValidator",
  "launcher"
];

const receiptParent = {
  ponsProjectAdapterImplementation: "ponsProjectAdapterFactory"
};

function successfulReceipt(receipt) {
  if (!receipt) return false;
  try {
    return BigInt(receipt.status) === 1n;
  } catch {
    return false;
  }
}

function deploymentBlock(receipt) {
  const value = receipt.blockNumber;
  const block = typeof value === "number" ? value : Number(BigInt(value));
  if (!Number.isSafeInteger(block) || block <= 0) throw new Error("invalid deployment block");
  return block;
}

export function buildProjectV2MainnetEntry(manifest, broadcasts) {
  if (manifest?.chainId !== 4663 || manifest.protocolVersion !== 2) {
    throw new Error("Project V2 release manifest must target chain 4663 and protocol version 2");
  }
  if (!commitPattern.test(manifest.gitCommit ?? "")) throw new Error("invalid release gitCommit");
  if (!buildPattern.test(manifest.buildHash ?? "")) throw new Error("invalid release buildHash");
  if (!Array.isArray(manifest.ponsLaunchpadApprovalProof)
      || manifest.ponsLaunchpadApprovalProof.length !== 3
      || manifest.ponsLaunchpadApprovalProof.some((node) => !bytes32Pattern.test(node))) {
    throw new Error("Pons approval proof must contain exactly three bytes32 nodes");
  }

  const receiptByHash = new Map();
  const transactionByAddress = new Map();
  for (const broadcast of broadcasts) {
    if (broadcast?.chain !== 4663) throw new Error("broadcast chain mismatch");
    for (const receipt of broadcast.receipts ?? []) {
      const hash = receipt.transactionHash?.toLowerCase();
      if (hash) receiptByHash.set(hash, receipt);
    }
    for (const transaction of broadcast.transactions ?? []) {
      const address = transaction.contractAddress?.toLowerCase();
      const hash = transaction.hash?.toLowerCase();
      if (!address || !hash) continue;
      const receipt = receiptByHash.get(hash);
      if (!successfulReceipt(receipt)) {
        throw new Error(`deployment transaction ${transaction.hash} is missing a successful receipt`);
      }
      transactionByAddress.set(address, { transaction, receipt });
    }
  }

  const deploymentByKey = new Map();
  for (const key of projectV2DeploymentKeys) {
    const address = manifest[key];
    if (!addressPattern.test(address ?? "")) throw new Error(`invalid release address ${key}`);
    const runtimeCodeHash = manifest[`${key}RuntimeHash`];
    if (!bytes32Pattern.test(runtimeCodeHash ?? "")) {
      throw new Error(`invalid release runtime hash ${key}RuntimeHash`);
    }
    const parent = receiptParent[key];
    const receiptSource = parent ? deploymentByKey.get(parent) : transactionByAddress.get(address.toLowerCase());
    if (!receiptSource) throw new Error(`no broadcast receipt found for ${key} at ${address}`);
    deploymentByKey.set(key, receiptSource);
  }

  const entry = {
    sourceCommit: manifest.gitCommit,
    buildHash: manifest.buildHash,
    approvalProof0: manifest.ponsLaunchpadApprovalProof[0],
    approvalProof1: manifest.ponsLaunchpadApprovalProof[1],
    approvalProof2: manifest.ponsLaunchpadApprovalProof[2]
  };
  for (const key of projectV2DeploymentKeys) {
    const { transaction, receipt } = deploymentByKey.get(key);
    entry[key] = {
      address: manifest[key],
      deploymentTransaction: transaction.hash,
      deploymentBlock: deploymentBlock(receipt),
      runtimeCodeHash: manifest[`${key}RuntimeHash`].toLowerCase()
    };
  }
  return entry;
}
