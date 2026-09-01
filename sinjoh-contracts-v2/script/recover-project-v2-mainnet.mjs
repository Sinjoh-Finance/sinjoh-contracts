#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { buildProjectV2MainnetEntry } from "../../scripts/release/project-v2-mainnet-entry.mjs";

const requireFromSdk = createRequire(new URL("../sdk/package.json", import.meta.url));
const { concatHex, encodeAbiParameters, keccak256, stringToHex } = requireFromSdk("viem");

export const RECOVERY_CONFIRMATION = "I_UNDERSTAND_THIS_BROADCASTS_MAINNET";
export const RECOVERY_REHEARSAL_CONFIRMATION = "I_UNDERSTAND_THIS_DOES_NOT_BROADCAST";
export const DEPLOYER = "0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49";
export const CHAIN_ID = 4663;
export const RECOVERY_GAS_ESTIMATE_MULTIPLIER = 200;
export const HISTORICAL_GAS_REPLAYS = [
  { action: "raffle", sent: 6_527_678, required: 6_753_849 },
  { action: "fundingBandIntegration", sent: 5_940_155, required: 6_045_982 },
  { action: "quoteOracle", sent: 378_002, required: 433_667 },
  { action: "guard500", sent: 2_037_102, required: 2_182_108 },
  { action: "guard3000", sent: 2_037_102, required: 2_182_108 },
  { action: "guard10000", sent: 2_037_102, required: 2_182_108 },
  { action: "ponsTokenFactory", sent: 4_939_988, required: 5_049_945 },
  { action: "launchpadTokenFactory", sent: 4_055_671, required: 4_199_769 }
];
// Both approved providers replayed the failed CREATEs to the final RETURN and agreed on these
// code-deposit floors and fresh estimates made with the former 160% setting. Scaling those
// estimates to 200% materially widens the narrowest (quote-oracle) safety margin while unused
// gas is not charged and Robinhood Chain's block gas limit is not the constraint.
export const LIVE_CREATE_GAS_REHEARSALS = [
  { action: "raffle", requiredFloor: 6_722_994, estimateAt160: 8_099_696 },
  { action: "fundingBandIntegration", requiredFloor: 6_024_143, estimateAt160: 7_370_851 },
  { action: "quoteOracle", requiredFloor: 427_100, estimateAt160: 470_793 },
  { action: "guard", requiredFloor: 2_173_000, estimateAt160: 2_528_969 },
  { action: "ponsTokenFactory", requiredFloor: 4_988_389, estimateAt160: 6_130_107 },
  { action: "launchpadTokenFactory", requiredFloor: 4_145_273, estimateAt160: 5_033_078 }
];

export function assertGasMultiplier(multiplier = RECOVERY_GAS_ESTIMATE_MULTIPLIER) {
  if (multiplier < RECOVERY_GAS_ESTIMATE_MULTIPLIER) {
    throw new Error("configured gas multiplier is below the approved 200% recovery policy");
  }
  for (const replay of HISTORICAL_GAS_REPLAYS) {
    if (replay.sent * multiplier < replay.required * 100) {
      throw new Error(`${replay.action}: configured gas multiplier is below historical replay`);
    }
  }
  for (const replay of LIVE_CREATE_GAS_REHEARSALS) {
    const scaledEstimate = Math.floor(replay.estimateAt160 * multiplier / 160);
    if (scaledEstimate <= replay.requiredFloor) {
      throw new Error(`${replay.action}: configured gas multiplier is below live trace floor`);
    }
  }
}

export function recoverySignerArguments(environmentInput) {
  if (environmentInput.FOUNDRY_KEYSTORE_PATH) {
    const arguments_ = ["--keystore", environmentInput.FOUNDRY_KEYSTORE_PATH];
    if (environmentInput.FOUNDRY_PASSWORD_FILE) {
      arguments_.push("--password-file", environmentInput.FOUNDRY_PASSWORD_FILE);
    }
    return arguments_;
  }
  if (!environmentInput.FOUNDRY_ACCOUNT) throw new Error("FOUNDRY_ACCOUNT is required");
  if (environmentInput.FOUNDRY_PASSWORD_FILE) {
    throw new Error("FOUNDRY_PASSWORD_FILE requires FOUNDRY_KEYSTORE_PATH");
  }
  return ["--account", environmentInput.FOUNDRY_ACCOUNT];
}

const packageDirectory = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const repoRoot = resolve(packageDirectory, "..");
const scriptTarget = "script/RecoverProjectLauncherV2.s.sol:RecoverProjectLauncherV2";
function broadcastArtifactFor(action) {
  const functionName = action.signature.slice(0, action.signature.indexOf("("));
  return resolve(
    packageDirectory,
    `broadcast/RecoverProjectLauncherV2.s.sol/4663/${functionName}-latest.json`
  );
}

const createActions = [
  ["raffle", "deployRaffle()", "RECOVERY_RAFFLE_IMPLEMENTATION"],
  ["fundingBandIntegration", "deployFundingBandIntegration()", "RECOVERY_FUNDING_BAND_V3_INTEGRATION_FACTORY"],
  ["quoteOracle", "deployQuoteOracle()", "RECOVERY_FUNDING_BAND_QUOTE_USD_ORACLE"],
  ["guard500", "deployGuard500()", "RECOVERY_PROJECT_V3_PRICE_GUARD_500"],
  ["guard3000", "deployGuard3000()", "RECOVERY_PROJECT_V3_PRICE_GUARD_3000"],
  ["guard10000", "deployGuard10000()", "RECOVERY_PROJECT_V3_PRICE_GUARD_10000"],
  ["stakingStore", "deployStakingStore()", "RECOVERY_STAKING_CREATION_CODE_STORE"],
  ["ponsTokenFactory", "deployPonsTokenFactory()", "RECOVERY_PONS_PROJECT_TOKEN_FACTORY"],
  ["launchpadTokenFactory", "deployLaunchpadTokenFactory()", "RECOVERY_LAUNCHPAD_PROJECT_TOKEN_FACTORY"],
  ["registry", "deployRegistry()", "RECOVERY_REGISTRY"],
  ["deploymentEngine", "deployEngine()", "RECOVERY_DEPLOYMENT_ENGINE"],
  ["launchValidator", "deployValidator()", "RECOVERY_LAUNCH_VALIDATOR"],
  ["launcher", "deployLauncher()", "RECOVERY_LAUNCHER"]
];

const callActions = [
  ["bindPons", "bindPonsProjectV2()", "PONS_PROJECT_ADAPTER_FACTORY"],
  ["bindPoolsInstant", "bindPoolsInstantProjectV2()", "POOLS_INSTANT_PROJECT_ADAPTER_FACTORY"],
  ["bindPoolsInstantNoFee", "bindPoolsInstantNoFeeProjectV2()", "POOLS_INSTANT_NO_FEE_PROJECT_ADAPTER_FACTORY"],
  ["bindPoolsLbp", "bindPoolsLbpProjectV2()", "POOLS_LBP_PROJECT_ADAPTER_FACTORY"]
];

export function buildActionPlan(startingNonce, computeAddress) {
  const base = BigInt(startingNonce);
  const actions = createActions.map(([id, signature, expectedEnvironment], index) => ({
    id,
    signature,
    kind: "create",
    nonce: Number(base + BigInt(index)),
    expectedEnvironment,
    expectedAddress: computeAddress(base + BigInt(index))
  }));
  for (const [offset, [id, signature, targetEnvironment]] of callActions.entries()) {
    actions.push({
      id,
      signature,
      kind: "call",
      nonce: Number(base + BigInt(createActions.length + offset)),
      targetEnvironment
    });
  }
  return actions;
}

export function authoritativeSingleReceipt(artifact, action) {
  if (artifact?.chain !== CHAIN_ID) throw new Error(`${action.id}: broadcast chain mismatch`);
  if (artifact.transactions?.length !== 1 || artifact.receipts?.length !== 1) {
    throw new Error(`${action.id}: expected exactly one transaction and one receipt`);
  }
  const receipt = artifact.receipts[0];
  if (BigInt(receipt.status) !== 1n) throw new Error(`${action.id}: receipt failed`);
  if (!/^0x[0-9a-fA-F]{64}$/.test(receipt.transactionHash ?? "")) {
    throw new Error(`${action.id}: receipt has no authoritative transaction hash`);
  }
  const contractAddress = receipt.contractAddress?.toLowerCase() ?? null;
  if (action.kind === "create") {
    if (contractAddress !== action.expectedAddress.toLowerCase()) {
      throw new Error(`${action.id}: receipt contractAddress mismatch`);
    }
  } else if (contractAddress && contractAddress !== "0x0000000000000000000000000000000000000000") {
    throw new Error(`${action.id}: call receipt unexpectedly created a contract`);
  }
  return receipt;
}

export function plannedArtifactIdentity(artifact, action, environment) {
  if (artifact?.transactions?.length !== 1) {
    throw new Error(`${action.id}: expected exactly one planned transaction`);
  }
  const transaction = artifact.transactions[0]?.transaction;
  if (!transaction || !/^0x[0-9a-fA-F]+$/.test(transaction.input ?? "")) {
    throw new Error(`${action.id}: artifact transaction input is missing`);
  }
  if (BigInt(transaction.nonce) !== BigInt(action.nonce)) {
    throw new Error(`${action.id}: artifact nonce mismatch`);
  }
  if (transaction.from?.toLowerCase() !== DEPLOYER.toLowerCase()) {
    throw new Error(`${action.id}: artifact sender mismatch`);
  }
  if (action.kind === "create") {
    if (transaction.to) throw new Error(`${action.id}: artifact CREATE has a target`);
    if (artifact.transactions[0].contractAddress?.toLowerCase() !== action.expectedAddress.toLowerCase()) {
      throw new Error(`${action.id}: artifact predicted address mismatch`);
    }
  } else {
    const target = environment[action.targetEnvironment];
    if (transaction.to?.toLowerCase() !== target.toLowerCase()) {
      throw new Error(`${action.id}: artifact target mismatch`);
    }
    if (transaction.input.toLowerCase() !== expectedCallData(action, environment).toLowerCase()) {
      throw new Error(`${action.id}: artifact calldata mismatch`);
    }
  }
  return transaction.input;
}

function run(command, args, options = {}) {
  try {
    const output = execFileSync(command, args, {
      cwd: packageDirectory,
      encoding: "utf8",
      stdio: options.capture === false ? "inherit" : ["ignore", "pipe", "pipe"],
      env: options.env ?? process.env
    });
    return typeof output === "string" ? output.trim() : "";
  } catch (error) {
    const status = Number.isInteger(error?.status) ? ` (exit ${error.status})` : "";
    const stderr = typeof error?.stderr === "string"
      ? error.stderr
        .replaceAll(/https?:\/\/[^\s"']+/g, "[RPC_URL_REDACTED]")
        .trim()
      : "";
    throw new Error(`${command} failed${status}${stderr ? `: ${stderr}` : ""}`);
  }
}

function cast(rpc, args) {
  return run("cast", args, { env: { ...process.env, ETH_RPC_URL: rpc } });
}

function rpcHost(url, role) {
  let host;
  try {
    host = new URL(url).hostname.toLowerCase();
  } catch {
    throw new Error(`${role} RPC URL is invalid`);
  }
  const allowed = role === "primary"
    ? host.endsWith(".core.chainstack.com") || host.endsWith(".p2pify.com")
    : host.endsWith(".quiknode.pro");
  if (!allowed) throw new Error(`${role} RPC host is not an approved provider`);
  return host;
}

function sameJson(left, right, context) {
  if (JSON.stringify(left) !== JSON.stringify(right)) {
    throw new Error(`${context}: Chainstack and QuickNode disagree`);
  }
}

function dualJson(primary, secondary, args, context) {
  const left = JSON.parse(cast(primary, [...args, "--json"]));
  const right = JSON.parse(cast(secondary, [...args, "--json"]));
  sameJson(left, right, context);
  return left;
}

function dualCall(primary, secondary, address, signature) {
  const left = cast(primary, ["call", address, signature]);
  const right = cast(secondary, ["call", address, signature]);
  if (left !== right) throw new Error(`${address} ${signature}: providers disagree`);
  return left;
}

function dualCode(primary, secondary, address) {
  const left = cast(primary, ["code", address]);
  const right = cast(secondary, ["code", address]);
  if (left !== right) throw new Error(`${address}: runtime code differs between providers`);
  if (left === "0x") throw new Error(`${address}: no runtime code`);
  return left;
}

export function safeNonceFromViews(views) {
  const primaryPending = BigInt(views.primaryPending);
  const secondaryPending = BigInt(views.secondaryPending);
  const primaryLatest = BigInt(views.primaryLatest);
  const secondaryLatest = BigInt(views.secondaryLatest);
  if (primaryPending !== secondaryPending) {
    throw new Error("deployer pending nonce differs between providers");
  }
  if (primaryLatest !== secondaryLatest) {
    throw new Error("deployer latest nonce differs between providers");
  }
  if (primaryPending !== primaryLatest) {
    throw new Error("deployer has a pre-existing pending transaction");
  }
  return primaryPending;
}

function currentNonce(primary, secondary) {
  return safeNonceFromViews({
    primaryPending: cast(primary, ["nonce", "--block", "pending", DEPLOYER]),
    secondaryPending: cast(secondary, ["nonce", "--block", "pending", DEPLOYER]),
    primaryLatest: cast(primary, ["nonce", "--block", "latest", DEPLOYER]),
    secondaryLatest: cast(secondary, ["nonce", "--block", "latest", DEPLOYER])
  });
}

function assertChain(primary, secondary) {
  const left = Number(cast(primary, ["chain-id"]));
  const right = Number(cast(secondary, ["chain-id"]));
  if (left !== CHAIN_ID || right !== CHAIN_ID) throw new Error("RPC chain mismatch");
}

function computeAddress(nonce) {
  const output = run("cast", ["compute-address", "--nonce", nonce.toString(), DEPLOYER]);
  const address = output.split(/\s+/).at(-1);
  if (!/^0x[0-9a-fA-F]{40}$/.test(address)) throw new Error("could not compute CREATE address");
  return address;
}

function stateEnvironment(plan, baseline, environmentInput = process.env) {
  const environment = { ...environmentInput };
  for (const action of plan) {
    if (action.expectedEnvironment) environment[action.expectedEnvironment] = action.expectedAddress;
  }
  const manifestKeys = {
    PROTOCOL_FEE_RECIPIENT: "protocolFeeRecipient",
    RANDOMNESS_ADAPTER: "randomnessAdapter",
    FUNDING_BAND_QUOTE_ASSET: "fundingBandQuoteAsset",
    FUNDING_BAND_QUOTE_USD_AGGREGATOR: "fundingBandQuoteUsdAggregator",
    V3_FACTORY: "v3Factory",
    V3_POSITION_MANAGER: "v3PositionManager",
    V4_POSITION_MANAGER: "v4PositionManager",
    V4_STATE_VIEW: "v4StateView",
    PERMIT2: "permit2"
  };
  for (const [environmentKey, manifestKey] of Object.entries(manifestKeys)) {
    const value = baseline[manifestKey];
    if (!/^0x[0-9a-fA-F]{40}$/.test(value ?? "")) {
      throw new Error(`baseline manifest is missing ${manifestKey}`);
    }
    environment[environmentKey] = value;
  }
  Object.assign(environment, {
    EXPECTED_CHAIN_ID: String(CHAIN_ID),
    DEPLOYER_ADDRESS: DEPLOYER,
    TOKEN_CREATION_CODE_STORE: "0x6C6f900411ce5B01305edb911D6ABf6224a0BBbd",
    MULTISIG_CREATION_CODE_STORE: "0x05EF504e5F145155053DeB4BfEa57265cF26274f",
    TIMELOCK_CREATION_CODE_STORE: "0x59B79DC8c60d7Ae0C7be77eBC85aa58fFf35E2F8",
    TREASURY_CREATION_CODE_STORE: "0x9bDf550190C5cF664fA3d1BC0Ad4e4bEAA6684bD",
    AIRDROP_CREATION_CODE_STORE: "0x11C0d799698680eB24568219391e2b90ba5C100f",
    ROUTER_CREATION_CODE_STORE: "0x24B9C2bBe7D6B4cEDfAEF0603Dd10707D76d7423",
    BANDS_CREATION_CODE_STORE: "0x9D33ef24921b32eBcD169BaDd2cA5F0ca1fD6409",
    LIQUIDITY_CREATION_CODE_STORE: "0xeE91bcb930FE37c0bF432108865Ba2b1Aac88c64",
    PROJECT_SWAP_ADAPTER: "0xc9F600ebaf9EE1F4a24568D2e4Af9E8df1e07D7B",
    PROJECT_SWAP_ADAPTER_RUNTIME_HASH: "0x17b8eecc60ff9af5768240b0384e96c4e54fd8611355297e45146303294c6ac6",
    PONS_LAUNCH_FACTORY: "0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e",
    PONS_LAUNCH_FACTORY_RUNTIME_HASH: "0x89a27da6f703e0a7cdd4f233e7cb57604ff75b164530962d3ff7cf8483a67d84",
    PONS_PROJECT_ADAPTER_FACTORY: "0xa16389c14c9299A4317D50aEfd5e4cC442F2dF0d",
    PONS_PROJECT_ADAPTER_FACTORY_RUNTIME_HASH: "0x42b9b3eca3f4bf37072bcf60f3405e30bd6e95e7279c307cdef9c5905f67f3bf",
    PONS_PROJECT_ADAPTER_IMPLEMENTATION: "0xC5C7B33708121d542AC8172104D1d708DF61cA37",
    PONS_PROJECT_ADAPTER_IMPLEMENTATION_RUNTIME_HASH: "0x305007652acf94952e5feb97add75c50ed8934365c67b3f1522eaf4809810841",
    PONS_STANDARD_ADAPTER_IMPLEMENTATION: "0xAf3D6710621697d25096E01367A3D0490Fd11e2b",
    PONS_STANDARD_ADAPTER_IMPLEMENTATION_RUNTIME_HASH: "0x5cc42a8a6ac7a9a792a04427f52063e5a8f4fb2c72fa614d46c1bc528d20ab4e",
    PONS_LAUNCH_DEPLOYER: "0x3711ceA4feaDE896C913C68F01Eda97Cb06D1A42",
    PONS_LAUNCH_DEPLOYER_RUNTIME_HASH: "0xeade22566c766377f6adfb99534f2772251efad9568642c0704a7051418e624c",
    PONS_FEE_ESCROW: "0xd3AFEB2a57f70eF218Aa82451c51B2fb0416Ac9e",
    PONS_FEE_ESCROW_RUNTIME_HASH: "0xf25f75cfbc1637ba068dc34f69098fa4e8a80f8ee8fe7bf7820594e0b3fed2f1",
    POOLS_INSTANT_PROJECT_ADAPTER_FACTORY: "0x7e49bbC2b1A96d635C66E192972D90467cbEbBe8",
    POOLS_INSTANT_PROJECT_ADAPTER_FACTORY_RUNTIME_HASH: "0x04a414d27a03e6e1fd240d4032f3b8cbc918c5259cef95f1c434c14444566a4c",
    POOLS_INSTANT_NO_FEE_PROJECT_ADAPTER_FACTORY: "0xbF6c13570B255826A438319EdFE986764039557B",
    POOLS_INSTANT_NO_FEE_PROJECT_ADAPTER_FACTORY_RUNTIME_HASH: "0x6031b24a36b3034851bae6b0d890a77615c0b9ee2b32af9d17277c2606a29314",
    POOLS_LBP_PROJECT_ADAPTER_FACTORY: "0xCcC944A29D6eb84b4a4B9522800e3f2FdD53da19",
    POOLS_LBP_PROJECT_ADAPTER_FACTORY_RUNTIME_HASH: "0xa0840e9b1e794827d4dfe824e976555a1a1eff77dc3c0c0e0d4bb727e6739e73",
    POOLS_PROJECT_REGISTRATION_HELPER: "0xE0F87B203384c48DE52Fe5A57a3Fc4A1704e49fa",
    POOLS_PROJECT_REGISTRATION_HELPER_RUNTIME_HASH: "0x34bd1ccd3740087c6fa60792496ff3a479f1d10c8c2e81a8bafb0f8dff011d8b",
    PONS_MEME_HOOK: "0xE5e702641Ea86F4ae6cC3cDaeD2B886f976Be044",
    PONS_MEME_HOOK_RUNTIME_HASH: "0xc21b1e6c1b45403e81a581f22ed6d9c747997af1cfdac1b1dc9f4b1d346a10db",
    PONS_LAUNCH_LOCKER: "0x267444D099b10fB5Ed7c3Cc7B7c767AdcA574952",
    PONS_LAUNCH_LOCKER_RUNTIME_HASH: "0x58455f80b3773871d601a025e56ec27c71ab3bbb8e2ca6b17828954450742025",
    PONS_BUYBACK_VAULT: "0x42df2a798f82289E177311362e8f5ccC45c1219c",
    PONS_BUYBACK_VAULT_RUNTIME_HASH: "0x5de8480874faffefa539648f1a7d6c1e69b39da3fa34de22fc95eb7586aece03",
    PONS_POOL_MANAGER: "0x8366a39CC670B4001A1121B8F6A443A643e40951",
    PONS_POOL_MANAGER_RUNTIME_HASH: "0xbd3881180b547f5fe817545743cfb4343e96b1bc6640dcd70c106b0066e95626"
  });
  return environment;
}

function assertFixedRuntimes(primary, secondary, environment) {
  for (const [addressKey, hashKey] of [
    ["PROJECT_SWAP_ADAPTER", "PROJECT_SWAP_ADAPTER_RUNTIME_HASH"],
    ["PONS_LAUNCH_FACTORY", "PONS_LAUNCH_FACTORY_RUNTIME_HASH"],
    ["PONS_PROJECT_ADAPTER_FACTORY", "PONS_PROJECT_ADAPTER_FACTORY_RUNTIME_HASH"],
    ["PONS_PROJECT_ADAPTER_IMPLEMENTATION", "PONS_PROJECT_ADAPTER_IMPLEMENTATION_RUNTIME_HASH"],
    ["PONS_STANDARD_ADAPTER_IMPLEMENTATION", "PONS_STANDARD_ADAPTER_IMPLEMENTATION_RUNTIME_HASH"],
    ["PONS_LAUNCH_DEPLOYER", "PONS_LAUNCH_DEPLOYER_RUNTIME_HASH"],
    ["PONS_FEE_ESCROW", "PONS_FEE_ESCROW_RUNTIME_HASH"],
    ["PONS_MEME_HOOK", "PONS_MEME_HOOK_RUNTIME_HASH"],
    ["PONS_LAUNCH_LOCKER", "PONS_LAUNCH_LOCKER_RUNTIME_HASH"],
    ["PONS_BUYBACK_VAULT", "PONS_BUYBACK_VAULT_RUNTIME_HASH"],
    ["PONS_POOL_MANAGER", "PONS_POOL_MANAGER_RUNTIME_HASH"],
    ["POOLS_INSTANT_PROJECT_ADAPTER_FACTORY", "POOLS_INSTANT_PROJECT_ADAPTER_FACTORY_RUNTIME_HASH"],
    ["POOLS_INSTANT_NO_FEE_PROJECT_ADAPTER_FACTORY", "POOLS_INSTANT_NO_FEE_PROJECT_ADAPTER_FACTORY_RUNTIME_HASH"],
    ["POOLS_LBP_PROJECT_ADAPTER_FACTORY", "POOLS_LBP_PROJECT_ADAPTER_FACTORY_RUNTIME_HASH"],
    ["POOLS_PROJECT_REGISTRATION_HELPER", "POOLS_PROJECT_REGISTRATION_HELPER_RUNTIME_HASH"]
  ]) {
    const actual = run("cast", ["keccak", dualCode(primary, secondary, environment[addressKey])]);
    if (actual.toLowerCase() !== environment[hashKey].toLowerCase()) {
      throw new Error(`${environment[addressKey]}: fixed runtime hash mismatch`);
    }
  }
  for (const [targetKey, signature, expectedKey] of [
    ["PONS_PROJECT_ADAPTER_FACTORY", "implementation()(address)", "PONS_STANDARD_ADAPTER_IMPLEMENTATION"],
    ["PONS_PROJECT_ADAPTER_FACTORY", "launchFactory()(address)", "PONS_LAUNCH_FACTORY"],
    ["PONS_PROJECT_ADAPTER_FACTORY", "feeEscrow()(address)", "PONS_FEE_ESCROW"],
    ["PONS_LAUNCH_FACTORY", "launchDeployer()(address)", "PONS_LAUNCH_DEPLOYER"],
    ["PONS_LAUNCH_FACTORY", "feeEscrow()(address)", "PONS_FEE_ESCROW"],
    ["PONS_LAUNCH_FACTORY", "memeHook()(address)", "PONS_MEME_HOOK"],
    ["PONS_LAUNCH_FACTORY", "locker()(address)", "PONS_LAUNCH_LOCKER"],
    ["PONS_LAUNCH_FACTORY", "buybackVault()(address)", "PONS_BUYBACK_VAULT"],
    ["PONS_LAUNCH_FACTORY", "poolManager()(address)", "PONS_POOL_MANAGER"]
  ]) {
    if (dualCall(primary, secondary, environment[targetKey], signature).toLowerCase()
        !== environment[expectedKey].toLowerCase()) {
      throw new Error(`${environment[targetKey]} ${signature}: fixed dependency mismatch`);
    }
  }
}

function assertOwnershipAndBindingProgress(primary, secondary, environment, state) {
  const zero = "0x0000000000000000000000000000000000000000";
  for (const address of [
    environment.PONS_LAUNCH_FACTORY,
    environment.PONS_MEME_HOOK,
    environment.PONS_LAUNCH_LOCKER,
    environment.PONS_BUYBACK_VAULT
  ]) {
    if (dualCall(primary, secondary, address, "owner()(address)").toLowerCase()
        !== DEPLOYER.toLowerCase()) {
      throw new Error(`${address}: ownership handoff to ${DEPLOYER} is incomplete`);
    }
    if (dualCall(primary, secondary, address, "pendingOwner()(address)").toLowerCase() !== zero) {
      throw new Error(`${address}: pending ownership transfer must be resolved first`);
    }
  }

  for (const [key, actionId, fields] of [
    ["PONS_PROJECT_ADAPTER_FACTORY", "bindPons", [
      ["projectLauncher()(address)", "RECOVERY_LAUNCHER"],
      ["projectRegistry()(address)", "RECOVERY_REGISTRY"],
      ["projectTokenFactory()(address)", "RECOVERY_PONS_PROJECT_TOKEN_FACTORY"],
      ["projectImplementation()(address)", "PONS_PROJECT_ADAPTER_IMPLEMENTATION"]
    ]],
    ["POOLS_INSTANT_PROJECT_ADAPTER_FACTORY", "bindPoolsInstant", [
      ["projectLauncher()(address)", "RECOVERY_LAUNCHER"],
      ["projectRegistry()(address)", "RECOVERY_REGISTRY"],
      ["projectTokenFactory()(address)", "RECOVERY_LAUNCHPAD_PROJECT_TOKEN_FACTORY"]
    ]],
    ["POOLS_INSTANT_NO_FEE_PROJECT_ADAPTER_FACTORY", "bindPoolsInstantNoFee", [
      ["projectLauncher()(address)", "RECOVERY_LAUNCHER"],
      ["projectRegistry()(address)", "RECOVERY_REGISTRY"],
      ["projectTokenFactory()(address)", "RECOVERY_LAUNCHPAD_PROJECT_TOKEN_FACTORY"]
    ]],
    ["POOLS_LBP_PROJECT_ADAPTER_FACTORY", "bindPoolsLbp", [
      ["projectLauncher()(address)", "RECOVERY_LAUNCHER"],
      ["projectRegistry()(address)", "RECOVERY_REGISTRY"],
      ["projectTokenFactory()(address)", "RECOVERY_LAUNCHPAD_PROJECT_TOKEN_FACTORY"],
      ["projectRegistrationHelper()(address)", "POOLS_PROJECT_REGISTRATION_HELPER"]
    ]]
  ]) {
    const address = environment[key];
    if (dualCall(primary, secondary, address, "binder()(address)").toLowerCase()
        !== DEPLOYER.toLowerCase()) {
      throw new Error(`${address}: binder mismatch`);
    }
    for (const [signature, expectedKey] of fields) {
      const expected = state.actions[actionId] ? environment[expectedKey] : zero;
      if (dualCall(primary, secondary, address, signature).toLowerCase() !== expected.toLowerCase()) {
        throw new Error(`${address}: binding state is inconsistent with the recovery journal`);
      }
    }
  }
}

function assertReusedStores(primary, secondary, environment) {
  const sources = [
    ["TOKEN_CREATION_CODE_STORE", "ProjectVotesToken"],
    ["MULTISIG_CREATION_CODE_STORE", "ProjectMultisigAccountV2"],
    ["TIMELOCK_CREATION_CODE_STORE", "ProjectTimelockV2"],
    ["TREASURY_CREATION_CODE_STORE", "ProjectTreasuryVaultV2"],
    ["AIRDROP_CREATION_CODE_STORE", "ProjectAirdropV2"],
    ["ROUTER_CREATION_CODE_STORE", "ProjectRouterV2"],
    ["BANDS_CREATION_CODE_STORE", "ProjectFundingBandsV2"],
    ["LIQUIDITY_CREATION_CODE_STORE", "ProjectLiquidityManagerV2"]
  ];
  for (const [key, contract] of sources) {
    const bytecode = run("forge", ["inspect", contract, "bytecode"]);
    const sourceHash = run("cast", ["keccak", bytecode]);
    const liveHash = dualCall(primary, secondary, environment[key], "creationCodeHash()(bytes32)");
    if (sourceHash.toLowerCase() !== liveHash.toLowerCase()) {
      throw new Error(`${contract}: reused store does not match the forced source build`);
    }
  }
}

function recoveryBuildFingerprint() {
  const contracts = [
    "RecoverProjectLauncherV2",
    "ProjectRaffleV2",
    "FundingBandV3IntegrationFactory",
    "FundingBandQuoteUsdOracleAdapter",
    "ProjectV3TwapPriceGuard",
    "CreationCodeStoreV2",
    "ProjectVotesTokenFactoryV2",
    "LaunchpadProjectVotesTokenFactoryV2",
    "ProjectRegistryV2",
    "ProjectLaunchDeployerV2",
    "ProjectLaunchValidatorV2",
    "ProjectLauncherV2",
    "ProjectVotesToken",
    "ProjectMultisigAccountV2",
    "ProjectTimelockV2",
    "ProjectStakingPoolV2",
    "ProjectTreasuryVaultV2",
    "ProjectAirdropV2",
    "ProjectRouterV2",
    "ProjectFundingBandsV2",
    "ProjectLiquidityManagerV2"
  ];
  const hash = createHash("sha256");
  for (const contract of contracts) {
    hash.update(contract);
    hash.update("\0");
    hash.update(run("forge", ["inspect", contract, "bytecode"]));
    hash.update("\0");
  }
  return hash.digest("hex");
}

function writeState(path, state) {
  const temporary = `${path}.tmp`;
  writeFileSync(temporary, `${JSON.stringify(state, null, 2)}\n`, { mode: 0o600 });
  renameSync(temporary, path);
}

function recordVerifiedAction(statePath, state, action, environment, transactionHash, verified) {
  const identity = action.kind === "create"
    ? { contractAddress: action.expectedAddress }
    : { target: environment[action.targetEnvironment] };
  state.actions[action.id] = {
    nonce: action.nonce,
    transactionHash,
    ...identity,
    ...verified
  };
  writeState(statePath, state);
}

function reconcileMinedAction(primary, secondary, action, environment, state, statePath) {
  const artifactPath = broadcastArtifactFor(action);
  if (!existsSync(artifactPath)) {
    throw new Error(`${action.id}: nonce advanced but no action artifact exists for reconciliation`);
  }
  const artifact = JSON.parse(readFileSync(artifactPath, "utf8"));
  const plannedInput = plannedArtifactIdentity(artifact, action, environment);
  const receipt = authoritativeSingleReceipt(artifact, action);
  const plannedInputHash = run("cast", ["keccak", plannedInput]);
  const identity = action.kind === "create"
    ? { contractAddress: action.expectedAddress }
    : { target: environment[action.targetEnvironment] };
  const verified = verifyAttestation(
    primary,
    secondary,
    action,
    {
      nonce: action.nonce,
      transactionHash: receipt.transactionHash,
      inputHash: plannedInputHash,
      ...identity
    },
    environment
  );
  if (action.kind === "call") verifyCallState(primary, secondary, action, environment);
  recordVerifiedAction(
    statePath,
    state,
    action,
    environment,
    receipt.transactionHash,
    verified
  );
}

export function validateJournalIdentity(action, record, environment) {
  if (record.nonce === undefined || BigInt(record.nonce) !== BigInt(action.nonce)) {
    throw new Error(`${action.id}: journal nonce mismatch`);
  }
  if (!/^0x[0-9a-fA-F]{64}$/.test(record.transactionHash ?? "")) {
    throw new Error(`${action.id}: journal transaction hash is missing or invalid`);
  }
  if (action.kind === "create") {
    if (record.contractAddress?.toLowerCase() !== action.expectedAddress.toLowerCase()) {
      throw new Error(`${action.id}: journal contractAddress mismatch`);
    }
  } else {
    const target = environment[action.targetEnvironment];
    if (record.target?.toLowerCase() !== target.toLowerCase()) {
      throw new Error(`${action.id}: journal target mismatch`);
    }
  }
}

function assertStoredAttestation(action, record) {
  if (!/^0x[0-9a-fA-F]{64}$/.test(record.inputHash ?? "")) {
    throw new Error(`${action.id}: journal input hash is missing or invalid`);
  }
  if (record.blockNumber === undefined) {
    throw new Error(`${action.id}: journal block number is missing`);
  }
  if (action.kind === "create" && !/^0x[0-9a-fA-F]{64}$/.test(record.runtimeHash ?? "")) {
    throw new Error(`${action.id}: journal runtime hash is missing or invalid`);
  }
}

function verifyAttestation(primary, secondary, action, record, environment) {
  validateJournalIdentity(action, record, environment);
  const transaction = dualJson(primary, secondary, ["tx", record.transactionHash], `${action.id} transaction`);
  const receipt = dualJson(primary, secondary, ["receipt", record.transactionHash], `${action.id} receipt`);
  if (BigInt(transaction.nonce) !== BigInt(action.nonce)) throw new Error(`${action.id}: nonce mismatch`);
  if (transaction.from.toLowerCase() !== DEPLOYER.toLowerCase()) throw new Error(`${action.id}: sender mismatch`);
  if (BigInt(receipt.status) !== 1n) throw new Error(`${action.id}: failed receipt`);
  if (record.blockNumber !== undefined && BigInt(receipt.blockNumber) !== BigInt(record.blockNumber)) {
    throw new Error(`${action.id}: block number changed`);
  }
  const inputHash = run("cast", ["keccak", transaction.input]);
  if (record.inputHash && inputHash !== record.inputHash) throw new Error(`${action.id}: calldata changed`);

  if (action.kind === "create") {
    if (receipt.contractAddress?.toLowerCase() !== action.expectedAddress.toLowerCase()) {
      throw new Error(`${action.id}: receipt contractAddress mismatch`);
    }
    const runtimeHash = run("cast", ["keccak", dualCode(primary, secondary, action.expectedAddress)]);
    if (record.runtimeHash && runtimeHash !== record.runtimeHash) throw new Error(`${action.id}: runtime changed`);
    return { inputHash, runtimeHash, blockNumber: receipt.blockNumber };
  }
  const target = environment[action.targetEnvironment];
  if (transaction.to?.toLowerCase() !== target.toLowerCase()) throw new Error(`${action.id}: target mismatch`);
  const expectedInput = expectedCallData(action, environment);
  if (transaction.input.toLowerCase() !== expectedInput.toLowerCase()) {
    throw new Error(`${action.id}: live calldata does not match the exact intended binding`);
  }
  return { inputHash, blockNumber: receipt.blockNumber };
}

export function assertJournalPrefix(plan, state) {
  let missingSeen = false;
  for (const action of plan) {
    if (!state.actions?.[action.id]) {
      missingSeen = true;
    } else if (missingSeen) {
      throw new Error(`${action.id}: recovery journal skips an earlier action`);
    }
  }
}

function prepareResume(primary, secondary, plan, environment, state, statePath) {
  assertJournalPrefix(plan, state);
  for (const action of plan) {
    const record = state.actions[action.id];
    if (record) {
      assertStoredAttestation(action, record);
      verifyAttestation(primary, secondary, action, record, environment);
      if (action.kind === "call") verifyCallState(primary, secondary, action, environment);
      continue;
    }
    const nonce = currentNonce(primary, secondary);
    if (nonce === BigInt(action.nonce) + 1n) {
      reconcileMinedAction(primary, secondary, action, environment, state, statePath);
    } else if (nonce !== BigInt(action.nonce)) {
      throw new Error(`${action.id}: nonce drift; expected ${action.nonce}, observed ${nonce}`);
    }
    break;
  }
}

function expectedCallData(action, environment) {
  const launcher = environment.RECOVERY_LAUNCHER;
  const registry = environment.RECOVERY_REGISTRY;
  if (action.id === "bindPons") {
    return run("cast", [
      "calldata", "bindProjectV2(address,address,address,address)",
      launcher, registry, environment.RECOVERY_PONS_PROJECT_TOKEN_FACTORY,
      environment.PONS_PROJECT_ADAPTER_IMPLEMENTATION
    ]);
  }
  if (action.id === "bindPoolsLbp") {
    return run("cast", [
      "calldata", "bindProjectV2(address,address,address,address)",
      launcher, registry, environment.RECOVERY_LAUNCHPAD_PROJECT_TOKEN_FACTORY,
      environment.POOLS_PROJECT_REGISTRATION_HELPER
    ]);
  }
  return run("cast", [
    "calldata", "bindProjectV2(address,address,address)",
    launcher, registry, environment.RECOVERY_LAUNCHPAD_PROJECT_TOKEN_FACTORY
  ]);
}

function verifyCallState(primary, secondary, action, environment) {
  const launcher = environment.RECOVERY_LAUNCHER;
  const registry = environment.RECOVERY_REGISTRY;
  const launchpadFactory = environment.RECOVERY_LAUNCHPAD_PROJECT_TOKEN_FACTORY;
  if (action.id === "bindPons") {
    const target = environment.PONS_PROJECT_ADAPTER_FACTORY;
    const expected = [launcher, registry, environment.RECOVERY_PONS_PROJECT_TOKEN_FACTORY, environment.PONS_PROJECT_ADAPTER_IMPLEMENTATION];
    const signatures = ["projectLauncher()(address)", "projectRegistry()(address)", "projectTokenFactory()(address)", "projectImplementation()(address)"];
    signatures.forEach((signature, index) => {
      if (dualCall(primary, secondary, target, signature).toLowerCase() !== expected[index].toLowerCase()) {
        throw new Error(`${action.id}: post-state mismatch`);
      }
    });
  } else {
    const target = environment[action.targetEnvironment];
    const expected = [launcher, registry, launchpadFactory];
    const signatures = ["projectLauncher()(address)", "projectRegistry()(address)", "projectTokenFactory()(address)"];
    signatures.forEach((signature, index) => {
      if (dualCall(primary, secondary, target, signature).toLowerCase() !== expected[index].toLowerCase()) {
        throw new Error(`${action.id}: post-state mismatch`);
      }
    });
    if (action.id === "bindPoolsLbp"
        && dualCall(primary, secondary, target, "projectRegistrationHelper()(address)").toLowerCase()
          !== environment.POOLS_PROJECT_REGISTRATION_HELPER.toLowerCase()) {
      throw new Error(`${action.id}: helper mismatch`);
    }
  }
}

const releaseContracts = [
  "ProjectVotesToken", "ProjectMultisigAccountV2", "ProjectTimelockV2",
  "ProjectStakingPoolV2", "ProjectTreasuryVaultV2", "ProjectAirdropV2",
  "ProjectRouterV2", "ProjectFundingBandsV2", "ProjectRaffleV2",
  "ProjectLiquidityManagerV2", "UniswapV3FundingBandMarketCapGuard",
  "UniswapV3FundingBandPositionAdapter", "FundingBandV3IntegrationFactory",
  "FundingBandQuoteUsdOracleAdapter", "ProjectV3TwapPriceGuard", "CreationCodeStoreV2",
  "ProjectRegistryV2", "ProjectLaunchDeployerV2", "ProjectLaunchValidatorV2",
  "ProjectLauncherV2", "ProjectVotesTokenFactoryV2", "LaunchpadProjectVotesTokenFactoryV2"
];

function assertCleanTrackedWorktree() {
  if (run("git", ["status", "--porcelain", "--untracked-files=no"], {
    env: process.env
  })) {
    throw new Error("recovery requires a clean tracked worktree so release metadata is reproducible");
  }
}

function releaseMetadata() {
  const material = [];
  for (const contract of releaseContracts) {
    material.push(run("forge", ["inspect", contract, "bytecode"]));
    material.push(run("forge", ["inspect", contract, "deployedBytecode"]));
  }
  return {
    gitCommit: run("git", ["rev-parse", "HEAD"], { env: process.env }),
    sourceTreeHash: run("git", ["rev-parse", "HEAD:sinjoh-contracts-v2"], { env: process.env }),
    buildHash: createHash("sha256").update(material.join("\n")).digest("hex")
  };
}

export function assertCompleteJournal(plan, state) {
  const missing = plan.filter((action) => !state.actions?.[action.id]);
  if (missing.length !== 0) {
    throw new Error(`recovery journal is incomplete: ${missing.map(({ id }) => id).join(", ")}`);
  }
}

export function buildApprovalTree(leaves) {
  if (!Array.isArray(leaves) || leaves.length !== 8
      || leaves.some((leaf) => !/^0x[0-9a-fA-F]{64}$/.test(leaf))) {
    throw new Error("approval tree requires exactly eight bytes32 leaves");
  }
  if (new Set(leaves.map((leaf) => leaf.toLowerCase())).size !== 8) {
    throw new Error("approval tree leaves must be unique");
  }
  const pairHash = (left, right) => {
    const ordered = BigInt(left) < BigInt(right) ? [left, right] : [right, left];
    return keccak256(concatHex(ordered));
  };
  const levels = [leaves];
  while (levels.at(-1).length > 1) {
    const prior = levels.at(-1);
    const next = [];
    for (let index = 0; index < prior.length; index += 2) {
      next.push(pairHash(prior[index], prior[index + 1]));
    }
    levels.push(next);
  }
  const proofs = leaves.map((_, leafIndex) => {
    const proof = [];
    let index = leafIndex;
    for (let level = 0; level < levels.length - 1; level += 1) {
      proof.push(levels[level][index ^ 1]);
      index = Math.floor(index / 2);
    }
    return proof;
  });
  return { root: levels.at(-1)[0], proofs };
}

function approvalData(manifest) {
  const bytes32Type = { type: "bytes32" };
  const uint256Type = { type: "uint256" };
  const addressType = { type: "address" };
  const doubleHash = (types, values) => keccak256(keccak256(encodeAbiParameters(types, values)));
  const swapDomain = keccak256(stringToHex("SINJOH_V2_SWAP_INTEGRATION_APPROVAL"));
  const fundingDomain = keccak256(stringToHex("SINJOH_V2_FUNDING_BAND_FACTORY_INTEGRATION"));
  const launchpadDomain = keccak256(stringToHex("SINJOH_V2_LAUNCHPAD_FACTORY_APPROVAL"));
  const swapLeaf = (guard, guardHash) => doubleHash(
    [bytes32Type, uint256Type, addressType, bytes32Type, addressType, bytes32Type],
    [swapDomain, BigInt(CHAIN_ID), manifest.projectSwapAdapter,
      manifest.projectSwapAdapterRuntimeHash, guard, guardHash]
  );
  const launchpadLeaf = (factory, runtimeHash) => doubleHash(
    [bytes32Type, uint256Type, addressType, bytes32Type],
    [launchpadDomain, BigInt(CHAIN_ID), factory, runtimeHash]
  );
  const leaves = [
    swapLeaf(manifest.projectV3PriceGuard500, manifest.projectV3PriceGuard500RuntimeHash),
    swapLeaf(manifest.projectV3PriceGuard3000, manifest.projectV3PriceGuard3000RuntimeHash),
    swapLeaf(manifest.projectV3PriceGuard10000, manifest.projectV3PriceGuard10000RuntimeHash),
    doubleHash(
      [bytes32Type, uint256Type, addressType, addressType, bytes32Type,
        addressType, addressType, bytes32Type, addressType, bytes32Type],
      [fundingDomain, BigInt(CHAIN_ID), manifest.fundingBandV3IntegrationFactory,
        manifest.v3Factory, manifest.v3FactoryRuntimeHash, manifest.fundingBandQuoteAsset,
        manifest.v3PositionManager, manifest.v3PositionManagerRuntimeHash,
        manifest.fundingBandQuoteUsdOracle, manifest.fundingBandQuoteUsdOracleRuntimeHash]
    ),
    launchpadLeaf(manifest.ponsProjectAdapterFactory, manifest.ponsProjectAdapterFactoryRuntimeHash),
    launchpadLeaf(
      manifest.poolsInstantProjectAdapterFactory,
      manifest.poolsInstantProjectAdapterFactoryRuntimeHash
    ),
    launchpadLeaf(
      manifest.poolsInstantNoFeeProjectAdapterFactory,
      manifest.poolsInstantNoFeeProjectAdapterFactoryRuntimeHash
    ),
    launchpadLeaf(manifest.poolsLbpProjectAdapterFactory, manifest.poolsLbpProjectAdapterFactoryRuntimeHash)
  ];
  const { root, proofs } = buildApprovalTree(leaves);
  return { leaves, proofs, root };
}

function buildRecoveryManifest(primary, secondary, baseline, plan, state, environment) {
  assertCompleteJournal(plan, state);
  const metadata = releaseMetadata();
  const manifest = {
    ...baseline,
    chainId: CHAIN_ID,
    protocolVersion: 2,
    ...metadata,
    compiler: "solc-0.8.28",
    evmVersion: "cancun",
    optimizerEnabled: true,
    optimizerRuns: 200,
    viaIr: true,
    broadcaster: DEPLOYER,
    ponsProjectAdapterFactory: environment.PONS_PROJECT_ADAPTER_FACTORY,
    ponsProjectAdapterFactoryRuntimeHash: environment.PONS_PROJECT_ADAPTER_FACTORY_RUNTIME_HASH,
    ponsProjectAdapterImplementation: environment.PONS_PROJECT_ADAPTER_IMPLEMENTATION,
    ponsProjectAdapterImplementationRuntimeHash:
      environment.PONS_PROJECT_ADAPTER_IMPLEMENTATION_RUNTIME_HASH,
    poolsInstantProjectAdapterFactory: environment.POOLS_INSTANT_PROJECT_ADAPTER_FACTORY,
    poolsInstantProjectAdapterFactoryRuntimeHash:
      environment.POOLS_INSTANT_PROJECT_ADAPTER_FACTORY_RUNTIME_HASH,
    poolsInstantNoFeeProjectAdapterFactory:
      environment.POOLS_INSTANT_NO_FEE_PROJECT_ADAPTER_FACTORY,
    poolsInstantNoFeeProjectAdapterFactoryRuntimeHash:
      environment.POOLS_INSTANT_NO_FEE_PROJECT_ADAPTER_FACTORY_RUNTIME_HASH,
    poolsLbpProjectAdapterFactory: environment.POOLS_LBP_PROJECT_ADAPTER_FACTORY,
    poolsLbpProjectAdapterFactoryRuntimeHash:
      environment.POOLS_LBP_PROJECT_ADAPTER_FACTORY_RUNTIME_HASH,
    poolsProjectRegistrationHelper: environment.POOLS_PROJECT_REGISTRATION_HELPER,
    poolsProjectRegistrationHelperRuntimeHash:
      environment.POOLS_PROJECT_REGISTRATION_HELPER_RUNTIME_HASH,
    ponsLaunchFactory: environment.PONS_LAUNCH_FACTORY,
    ponsLaunchFactoryRuntimeHash: environment.PONS_LAUNCH_FACTORY_RUNTIME_HASH,
    fundingBandMarketCapGuardRuntimeTemplateHash: run("cast", [
      "keccak", run("forge", ["inspect", "UniswapV3FundingBandMarketCapGuard", "deployedBytecode"])
    ]),
    fundingBandPositionAdapterRuntimeTemplateHash: run("cast", [
      "keccak", run("forge", ["inspect", "UniswapV3FundingBandPositionAdapter", "deployedBytecode"])
    ])
  };
  const dynamic = {
    raffle: "raffleImplementation",
    fundingBandIntegration: "fundingBandV3IntegrationFactory",
    quoteOracle: "fundingBandQuoteUsdOracle",
    guard500: "projectV3PriceGuard500",
    guard3000: "projectV3PriceGuard3000",
    guard10000: "projectV3PriceGuard10000",
    ponsTokenFactory: "ponsProjectTokenFactory",
    launchpadTokenFactory: "launchpadProjectTokenFactory",
    registry: "registry",
    deploymentEngine: "deploymentEngine",
    launchValidator: "launchValidator",
    launcher: "launcher"
  };
  for (const [actionId, manifestKey] of Object.entries(dynamic)) {
    const record = state.actions[actionId];
    manifest[manifestKey] = record.contractAddress;
    manifest[`${manifestKey}RuntimeHash`] = record.runtimeHash;
  }
  for (const [manifestKey, environmentKey] of [
    ["protocolFeeRecipient", "PROTOCOL_FEE_RECIPIENT"],
    ["randomnessAdapter", "RANDOMNESS_ADAPTER"],
    ["projectSwapAdapter", "PROJECT_SWAP_ADAPTER"],
    ["fundingBandQuoteAsset", "FUNDING_BAND_QUOTE_ASSET"],
    ["fundingBandQuoteUsdAggregator", "FUNDING_BAND_QUOTE_USD_AGGREGATOR"],
    ["v3Factory", "V3_FACTORY"],
    ["v3PositionManager", "V3_POSITION_MANAGER"],
    ["v4PositionManager", "V4_POSITION_MANAGER"],
    ["v4StateView", "V4_STATE_VIEW"],
    ["permit2", "PERMIT2"]
  ]) manifest[manifestKey] = environment[environmentKey];

  const stores = {
    tokenCreationCodeHash: "TOKEN_CREATION_CODE_STORE",
    multisigCreationCodeHash: "MULTISIG_CREATION_CODE_STORE",
    timelockCreationCodeHash: "TIMELOCK_CREATION_CODE_STORE",
    stakingCreationCodeHash: "RECOVERY_STAKING_CREATION_CODE_STORE",
    treasuryCreationCodeHash: "TREASURY_CREATION_CODE_STORE",
    airdropCreationCodeHash: "AIRDROP_CREATION_CODE_STORE",
    routerCreationCodeHash: "ROUTER_CREATION_CODE_STORE",
    bandsCreationCodeHash: "BANDS_CREATION_CODE_STORE",
    liquidityCreationCodeHash: "LIQUIDITY_CREATION_CODE_STORE"
  };
  for (const [manifestKey, environmentKey] of Object.entries(stores)) {
    manifest[manifestKey] = dualCall(
      primary, secondary, environment[environmentKey], "creationCodeHash()(bytes32)"
    );
  }
  const approval = approvalData(manifest);
  [
    "swapApprovalLeaf500", "swapApprovalLeaf3000", "swapApprovalLeaf10000",
    "fundingBandIntegrationLeaf", "ponsLaunchpadApprovalLeaf",
    "poolsInstantLaunchpadApprovalLeaf", "poolsInstantNoFeeLaunchpadApprovalLeaf",
    "poolsLbpLaunchpadApprovalLeaf"
  ].forEach((field, index) => { manifest[field] = approval.leaves[index]; });
  [
    "swapApprovalProof500", "swapApprovalProof3000", "swapApprovalProof10000",
    "fundingBandIntegrationProof", "ponsLaunchpadApprovalProof",
    "poolsInstantLaunchpadApprovalProof", "poolsInstantNoFeeLaunchpadApprovalProof",
    "poolsLbpLaunchpadApprovalProof"
  ].forEach((field, index) => { manifest[field] = approval.proofs[index]; });
  manifest.integrationApprovalRoot = approval.root;
  if (dualCall(primary, secondary, manifest.deploymentEngine, "integrationApprovalRoot()(bytes32)")
      .toLowerCase() !== approval.root.toLowerCase()) {
    throw new Error("receipt-backed deployment engine approval root does not match reconstructed root");
  }
  return manifest;
}

function verifierEnvironment(environment, manifest) {
  const result = {
    ...environment,
    EXPECTED_CHAIN_ID: String(CHAIN_ID),
    RELEASE_GIT_COMMIT: manifest.gitCommit,
    RELEASE_SOURCE_TREE_HASH: manifest.sourceTreeHash,
    RELEASE_BUILD_HASH: manifest.buildHash
  };
  const keys = [
    "protocolFeeRecipient", "projectSwapAdapter", "projectSwapAdapterRuntimeHash",
    "fundingBandQuoteAsset", "fundingBandQuoteAssetRuntimeHash",
    "fundingBandQuoteUsdAggregator", "fundingBandQuoteUsdAggregatorRuntimeHash",
    "randomnessAdapter", "randomnessAdapterRuntimeHash", "v3Factory", "v3FactoryRuntimeHash",
    "v3PositionManager", "v3PositionManagerRuntimeHash", "v4PositionManager",
    "v4PositionManagerRuntimeHash", "v4StateView", "v4StateViewRuntimeHash", "permit2",
    "permit2RuntimeHash", "ponsProjectAdapterFactory", "ponsProjectAdapterFactoryRuntimeHash",
    "poolsInstantProjectAdapterFactory", "poolsInstantProjectAdapterFactoryRuntimeHash",
    "poolsInstantNoFeeProjectAdapterFactory", "poolsInstantNoFeeProjectAdapterFactoryRuntimeHash",
    "poolsLbpProjectAdapterFactory", "poolsLbpProjectAdapterFactoryRuntimeHash",
    "ponsProjectAdapterImplementation", "ponsProjectAdapterImplementationRuntimeHash",
    "poolsProjectRegistrationHelper", "poolsProjectRegistrationHelperRuntimeHash",
    "ponsLaunchFactory", "ponsLaunchFactoryRuntimeHash"
  ];
  for (const key of keys) {
    result[key.replace(/([a-z0-9])([A-Z])/g, "$1_$2").toUpperCase()] = manifest[key];
  }
  return result;
}

function successfulDeploymentReceipt(broadcast, address) {
  const matches = (broadcast.receipts ?? []).filter((receipt) => {
    try {
      return receipt.contractAddress?.toLowerCase() === address.toLowerCase()
        && BigInt(receipt.status) === 1n;
    } catch {
      return false;
    }
  });
  if (matches.length !== 1) throw new Error(`expected one authoritative deployment receipt for ${address}`);
  return matches[0];
}

function verifyPromotionEntryReceipts(primary, secondary, entry) {
  for (const [key, deployment] of Object.entries(entry)) {
    if (!deployment || typeof deployment !== "object" || !deployment.address) continue;
    const receipt = dualJson(
      primary, secondary, ["receipt", deployment.deploymentTransaction], `${key} promotion receipt`
    );
    const transaction = dualJson(
      primary, secondary, ["tx", deployment.deploymentTransaction], `${key} promotion transaction`
    );
    if (BigInt(receipt.status) !== 1n
        || receipt.contractAddress?.toLowerCase() !== deployment.address.toLowerCase()) {
      throw new Error(`${key}: promotion receipt does not attest the deployed address`);
    }
    if (transaction.from?.toLowerCase() !== DEPLOYER.toLowerCase()) {
      throw new Error(`${key}: promotion deployment sender mismatch`);
    }
    if (Number(BigInt(receipt.blockNumber)) !== deployment.deploymentBlock) {
      throw new Error(`${key}: promotion deployment block mismatch`);
    }
    const runtimeHash = run("cast", ["keccak", dualCode(primary, secondary, deployment.address)]);
    if (runtimeHash.toLowerCase() !== deployment.runtimeCodeHash.toLowerCase()) {
      throw new Error(`${key}: promotion runtime hash mismatch`);
    }
  }
}

export function canonicalArtifactJson(value) {
  return `${JSON.stringify(value, null, 2)}\n`;
}

export function assertArtifactIdentity(contents, expectedValue, label = "recovery artifact") {
  if (contents !== canonicalArtifactJson(expectedValue)) {
    throw new Error(`${label}: existing content does not exactly match recovered state`);
  }
}

export function writeOrValidateArtifact(path, value) {
  if (existsSync(path)) {
    assertArtifactIdentity(readFileSync(path, "utf8"), value, path);
    return "validated";
  }
  writeFileSync(path, canonicalArtifactJson(value), { flag: "wx", mode: 0o600 });
  return "created";
}

export function assertRecoveryArtifactsIdentity(recorded, expected) {
  if (recorded !== undefined && JSON.stringify(recorded) !== JSON.stringify(expected)) {
    throw new Error("journaled recovery artifact identity does not match reconstructed artifacts");
  }
}

function artifactSha256(value) {
  return createHash("sha256").update(canonicalArtifactJson(value)).digest("hex");
}

function verifyAndFinalizeManifest(manifestPath, manifest, verificationEnvironment, primary, secondary) {
  const pendingManifest = `${manifestPath}.pending`;
  if (existsSync(manifestPath) && existsSync(pendingManifest)) {
    throw new Error("both final and pending recovery manifests exist");
  }
  const verificationPath = existsSync(manifestPath) ? manifestPath : pendingManifest;
  writeOrValidateArtifact(verificationPath, manifest);
  run("node", ["script/verify-release-manifest.mjs", verificationPath], {
    env: verificationEnvironment
  });
  run("node", ["script/verify-deployed-release.mjs", verificationPath], {
    env: { ...verificationEnvironment, RPC_URL: primary }
  });
  run("node", ["script/verify-deployed-release.mjs", verificationPath], {
    env: { ...verificationEnvironment, RPC_URL: secondary }
  });
  if (verificationPath === pendingManifest) renameSync(pendingManifest, manifestPath);
}

function emitRecoveryArtifacts(primary, secondary, baseline, plan, state, environment) {
  assertCompleteJournal(plan, state);
  const suffix = `${CHAIN_ID}-${state.startingNonce}`;
  const manifestPath = resolve(
    packageDirectory,
    environment.RECOVERY_MANIFEST_PATH ?? `deployments/project-v2-recovery-manifest-${suffix}.json`
  );
  const entryPath = resolve(
    packageDirectory,
    environment.RECOVERY_PROMOTION_ENTRY_PATH
      ?? `deployments/project-v2-recovery-promotion-entry-${suffix}.json`
  );
  const consumerPath = resolve(
    packageDirectory,
    environment.RECOVERY_CONSUMER_INPUT_PATH
      ?? `deployments/project-v2-recovery-consumer-input-${suffix}.json`
  );
  const manifest = buildRecoveryManifest(primary, secondary, baseline, plan, state, environment);
  const ponsBroadcast = JSON.parse(readFileSync(resolve(
    repoRoot,
    "sinjoh-launchpad-adapters/broadcast/DeployPonsV2AdapterFactory.s.sol/4663/run-latest.json"
  ), "utf8"));
  const poolsBroadcast = JSON.parse(readFileSync(resolve(
    repoRoot,
    "sinjoh-launchpad-adapters/broadcast/DeployPoolsTradeAdapterFactories.s.sol/4663/run-latest.json"
  ), "utf8"));
  const recoveryBroadcasts = plan.filter(({ kind }) => kind === "create")
    .map((action) => JSON.parse(readFileSync(broadcastArtifactFor(action), "utf8")));
  const entry = buildProjectV2MainnetEntry(
    manifest, [ponsBroadcast, poolsBroadcast, ...recoveryBroadcasts]
  );
  verifyPromotionEntryReceipts(primary, secondary, entry);

  const factoryReceipt = successfulDeploymentReceipt(
    ponsBroadcast, environment.PONS_PROJECT_ADAPTER_FACTORY
  );
  const normalFactory = {
    address: environment.PONS_PROJECT_ADAPTER_FACTORY,
    deploymentTransaction: factoryReceipt.transactionHash,
    deploymentBlock: Number(BigInt(factoryReceipt.blockNumber)),
    runtimeCodeHash: environment.PONS_PROJECT_ADAPTER_FACTORY_RUNTIME_HASH,
    verified: {
      implementation: environment.PONS_STANDARD_ADAPTER_IMPLEMENTATION,
      implementationRuntimeCodeHash: environment.PONS_STANDARD_ADAPTER_IMPLEMENTATION_RUNTIME_HASH,
      projectImplementation: environment.PONS_PROJECT_ADAPTER_IMPLEMENTATION,
      projectImplementationRuntimeCodeHash:
        environment.PONS_PROJECT_ADAPTER_IMPLEMENTATION_RUNTIME_HASH,
      launchFactory: environment.PONS_LAUNCH_FACTORY,
      launchFactoryRuntimeCodeHash: environment.PONS_LAUNCH_FACTORY_RUNTIME_HASH,
      launchDeployer: environment.PONS_LAUNCH_DEPLOYER,
      launchDeployerRuntimeCodeHash: environment.PONS_LAUNCH_DEPLOYER_RUNTIME_HASH,
      feeEscrow: environment.PONS_FEE_ESCROW,
      feeEscrowRuntimeCodeHash: environment.PONS_FEE_ESCROW_RUNTIME_HASH,
      memeHook: environment.PONS_MEME_HOOK,
      memeHookRuntimeCodeHash: environment.PONS_MEME_HOOK_RUNTIME_HASH,
      launchLocker: environment.PONS_LAUNCH_LOCKER,
      launchLockerRuntimeCodeHash: environment.PONS_LAUNCH_LOCKER_RUNTIME_HASH,
      buybackVault: environment.PONS_BUYBACK_VAULT,
      buybackVaultRuntimeCodeHash: environment.PONS_BUYBACK_VAULT_RUNTIME_HASH,
      poolManager: environment.PONS_POOL_MANAGER,
      poolManagerRuntimeCodeHash: environment.PONS_POOL_MANAGER_RUNTIME_HASH,
      deploymentChainId: CHAIN_ID
    }
  };
  const consumerInput = {
    currentInfrastructure: {
      ponsV2AdapterFactory: normalFactory,
      ponsV2AdapterImplementation: {
        address: environment.PONS_STANDARD_ADAPTER_IMPLEMENTATION,
        deploymentTransaction: factoryReceipt.transactionHash,
        deploymentBlock: Number(BigInt(factoryReceipt.blockNumber)),
        runtimeCodeHash: environment.PONS_STANDARD_ADAPTER_IMPLEMENTATION_RUNTIME_HASH,
        verified: {
          factory: environment.PONS_PROJECT_ADAPTER_FACTORY,
          constructorDeployment: true
        }
      },
      projectV2: entry
    }
  };
  const artifacts = {
    manifestPath,
    manifestSha256: artifactSha256(manifest),
    promotionEntryPath: entryPath,
    promotionEntrySha256: artifactSha256(entry),
    consumerInputPath: consumerPath,
    consumerInputSha256: artifactSha256(consumerInput)
  };
  assertRecoveryArtifactsIdentity(state.recoveryArtifacts, artifacts);

  const verificationEnvironment = verifierEnvironment(environment, manifest);
  verifyAndFinalizeManifest(
    manifestPath, manifest, verificationEnvironment, primary, secondary
  );
  writeOrValidateArtifact(entryPath, entry);
  writeOrValidateArtifact(consumerPath, consumerInput);
  return artifacts;
}

export function runRecovery(overrides = {}) {
  const environmentInput = { ...process.env, ...overrides };
  const rehearsalOnly = environmentInput.REHEARSE_PROJECT_V2_RECOVERY
    === RECOVERY_REHEARSAL_CONFIRMATION;
  if (!rehearsalOnly && environmentInput.EXECUTE_PROJECT_V2_RECOVERY !== RECOVERY_CONFIRMATION) {
    throw new Error(`refusing to broadcast; set EXECUTE_PROJECT_V2_RECOVERY=${RECOVERY_CONFIRMATION}`);
  }
  if (!rehearsalOnly) recoverySignerArguments(environmentInput);
  if (environmentInput.FOUNDRY_PASSWORD_FILE
      && !existsSync(environmentInput.FOUNDRY_PASSWORD_FILE)) {
    throw new Error("FOUNDRY_PASSWORD_FILE does not exist");
  }
  assertCleanTrackedWorktree();
  const primary = environmentInput.RPC_URL;
  const secondary = environmentInput.RPC_VERIFICATION_URL;
  if (!primary || !secondary || primary === secondary) throw new Error("two independent RPC URLs are required");
  rpcHost(primary, "primary");
  rpcHost(secondary, "secondary");
  assertChain(primary, secondary);
  assertGasMultiplier();

  const baselinePath = resolve(
    packageDirectory,
    environmentInput.BASELINE_RELEASE_MANIFEST ?? "deployments/project-launcher-v2-4663-e7bed3c-canonical.json"
  );
  const baseline = JSON.parse(readFileSync(baselinePath, "utf8"));
  const statePath = resolve(
    packageDirectory,
    environmentInput.RECOVERY_STATE_PATH ?? "deployments/project-v2-recovery-state-4663.json"
  );

  let state;
  let freshState = false;
  if (existsSync(statePath)) {
    state = JSON.parse(readFileSync(statePath, "utf8"));
    if (state.schemaVersion !== "1.0" || state.chainId !== CHAIN_ID
        || state.deployer.toLowerCase() !== DEPLOYER.toLowerCase()) {
      throw new Error("recovery state identity mismatch");
    }
  } else {
    freshState = true;
    const startingNonce = currentNonce(primary, secondary);
    if (environmentInput.RECOVERY_EXPECTED_STARTING_NONCE
        && startingNonce !== BigInt(environmentInput.RECOVERY_EXPECTED_STARTING_NONCE)) {
      throw new Error("freshly observed nonce does not equal RECOVERY_EXPECTED_STARTING_NONCE");
    }
    state = {
      schemaVersion: "1.0",
      chainId: CHAIN_ID,
      deployer: DEPLOYER,
      startingNonce: Number(startingNonce),
      actions: {}
    };
  }

  const plan = buildActionPlan(state.startingNonce, computeAddress);
  const environment = stateEnvironment(plan, baseline, environmentInput);
  environment.RPC_URL = primary;
  environment.RPC_VERIFICATION_URL = secondary;
  environment.ETH_RPC_URL = primary;
  console.log(state.buildFingerprint
    ? "Recovery build fingerprint found; validating the cached forced build."
    : "Building recovery contracts from scratch.");
  run("forge", state.buildFingerprint ? ["build"] : ["build", "--force"], { env: environment });
  const buildFingerprint = recoveryBuildFingerprint();
  if (state.buildFingerprint && state.buildFingerprint !== buildFingerprint) {
    throw new Error("forced recovery build differs from the journaled build");
  }
  state.buildFingerprint = buildFingerprint;
  assertReusedStores(primary, secondary, environment);
  assertFixedRuntimes(primary, secondary, environment);
  if (freshState) writeState(statePath, state);
  prepareResume(primary, secondary, plan, environment, state, statePath);
  assertOwnershipAndBindingProgress(primary, secondary, environment, state);
  console.log("Dual-provider runtime, ownership, nonce and binding preflight passed.");

  if (rehearsalOnly) {
    const action = plan.find((candidate) => !state.actions[candidate.id]);
    if (!action) {
      console.log("Recovery journal is already complete; no action remains to rehearse.");
      return state;
    }
    console.log(`Rehearsing ${action.id} without signing or broadcasting.`);
    run(
      "forge",
      [
        "script", scriptTarget,
        "--sig", action.signature,
        "--sender", DEPLOYER,
        "--gas-estimate-multiplier", String(RECOVERY_GAS_ESTIMATE_MULTIPLIER)
      ],
      { env: environment }
    );
    console.log(`${action.id} rehearsal passed without broadcasting.`);
    return state;
  }

  for (const [actionIndex, action] of plan.entries()) {
    const record = state.actions[action.id];
    if (record) {
      assertStoredAttestation(action, record);
      verifyAttestation(primary, secondary, action, record, environment);
      if (action.kind === "call") verifyCallState(primary, secondary, action, environment);
      continue;
    }

    const nonce = currentNonce(primary, secondary);
    if (nonce === BigInt(action.nonce) + 1n) {
      reconcileMinedAction(primary, secondary, action, environment, state, statePath);
      continue;
    }
    if (nonce !== BigInt(action.nonce)) {
      throw new Error(`${action.id}: nonce drift; expected ${action.nonce}, observed ${nonce}`);
    }

    const signerArguments = recoverySignerArguments(environmentInput);
    console.log(`[${actionIndex + 1}/${plan.length}] Broadcasting ${action.id} at nonce ${action.nonce}.`);
    run(
      "forge",
      [
        "script", scriptTarget,
        "--sig", action.signature,
        "--sender", DEPLOYER,
        ...signerArguments,
        "--broadcast",
        "--slow",
        "--gas-estimate-multiplier", String(RECOVERY_GAS_ESTIMATE_MULTIPLIER)
      ],
      { env: environment }
    );
    const artifact = JSON.parse(readFileSync(broadcastArtifactFor(action), "utf8"));
    const plannedInput = plannedArtifactIdentity(artifact, action, environment);
    const authoritativeReceipt = authoritativeSingleReceipt(artifact, action);
    const transactionHash = authoritativeReceipt.transactionHash;
    const plannedInputHash = run("cast", ["keccak", plannedInput]);
    const identity = action.kind === "create"
      ? { contractAddress: action.expectedAddress }
      : { target: environment[action.targetEnvironment] };
    const verified = verifyAttestation(
      primary,
      secondary,
      action,
      { nonce: action.nonce, transactionHash, inputHash: plannedInputHash, ...identity },
      environment
    );
    if (action.kind === "call") verifyCallState(primary, secondary, action, environment);
    recordVerifiedAction(statePath, state, action, environment, transactionHash, verified);
    console.log(`[${actionIndex + 1}/${plan.length}] ${action.id} verified: ${transactionHash}`);
  }
  state.recoveryArtifacts = emitRecoveryArtifacts(
    primary, secondary, baseline, plan, state, environment
  );
  writeState(statePath, state);
  return state;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    const state = runRecovery();
    const rehearsalOnly = process.env.REHEARSE_PROJECT_V2_RECOVERY
      === RECOVERY_REHEARSAL_CONFIRMATION;
    console.log(rehearsalOnly
      ? `Project V2 recovery rehearsal completed with ${Object.keys(state.actions).length} recorded actions.`
      : `Project V2 recovery completed with ${Object.keys(state.actions).length} verified actions.`);
  } catch (error) {
    console.error(`Project V2 recovery aborted: ${error.message}`);
    process.exitCode = 1;
  }
}
