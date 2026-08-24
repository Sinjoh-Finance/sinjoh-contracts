import {
  encodeAbiParameters,
  encodeFunctionData,
  isAddress,
  isHex,
  keccak256,
  stringToHex,
  type Abi,
  type Address,
  type ContractFunctionArgs,
  type ContractFunctionName,
  type EncodeFunctionDataParameters,
  type Hex,
  parseUnits,
} from "viem";
import {
  projectFundingBandsV2Abi,
  projectGovernorV2Abi,
  projectMultisigAccountV2Abi,
  projectTreasuryVaultV2Abi,
} from "./abis.generated.js";
import type { FundingBandConfig } from "./types.js";

export interface GovernanceAction {
  target: Address;
  value: bigint;
  data: Hex;
}

export function governanceBatch(actions: readonly GovernanceAction[]) {
  if (actions.length === 0) throw new RangeError("Governance batch cannot be empty");
  return {
    targets: actions.map((action) => action.target),
    values: actions.map((action) => action.value),
    calldatas: actions.map((action) => action.data),
  } as const;
}

/** Encodes a wallet transaction that submits the same typed batch to a Multisig Account. */
export function encodeMultisigSubmission(actions: readonly GovernanceAction[]): Hex {
  const batch = governanceBatch(actions);
  return encodeFunctionData({
    abi: projectMultisigAccountV2Abi,
    functionName: "submit",
    args: [batch.targets, batch.values, batch.calldatas],
  });
}

/** Encodes a wallet transaction that proposes the same typed batch to Token Governance. */
export function encodeTokenGovernanceProposal(
  actions: readonly GovernanceAction[],
  description: string,
): Hex {
  if (description.trim().length === 0) throw new RangeError("Proposal description cannot be empty");
  const batch = governanceBatch(actions);
  return encodeFunctionData({
    abi: projectGovernorV2Abi,
    functionName: "propose",
    args: [batch.targets, batch.values, batch.calldatas, description],
  });
}

/** Encodes one typed module mutation for either Multisig or Token Governance workflows. */
export function encodeGovernanceAction<
  const TAbi extends Abi,
  TFunctionName extends ContractFunctionName<TAbi, "payable" | "nonpayable">,
>(parameters: {
  target: Address;
  abi: TAbi;
  functionName: TFunctionName;
  args: ContractFunctionArgs<TAbi, "payable" | "nonpayable", TFunctionName>;
  value?: bigint;
}): GovernanceAction {
  const { target, abi, functionName, args, value = 0n } = parameters;
  const data = encodeFunctionData(
    { abi, functionName, args } as unknown as EncodeFunctionDataParameters,
  );
  return { target, value, data };
}

export const fundingBandDestination = {
  creator: 0,
  treasury: 1,
  buybackBurn: 2,
  buybackAirdrop: 3,
  router: 4,
  raffle: 5,
  basketViaTreasury: 6,
} as const;

const SWAP_INTEGRATION_DOMAIN = keccak256(
  stringToHex("SINJOH_V2_SWAP_INTEGRATION_APPROVAL"),
);
const FUNDING_BAND_FACTORY_INTEGRATION_DOMAIN = keccak256(
  stringToHex("SINJOH_V2_FUNDING_BAND_FACTORY_INTEGRATION"),
);
const FUNDING_BAND_PAIR_INTEGRATION_DOMAIN = keccak256(
  stringToHex("SINJOH_V2_FUNDING_BAND_PAIR_INTEGRATION"),
);
const LAUNCHPAD_FACTORY_APPROVAL_DOMAIN = keccak256(
  stringToHex("SINJOH_V2_LAUNCHPAD_FACTORY_APPROVAL"),
);

/** Exact release leaf that authorizes one immutable launchpad adapter factory generation. */
export function launchpadFactoryApprovalLeaf(parameters: {
  chainId: bigint;
  factory: Address;
  factoryRuntimeHash: Hex;
}): Hex {
  assertChainId(parameters.chainId);
  assertNonzeroAddress(parameters.factory, "Launchpad adapter factory");
  assertBytes32(parameters.factoryRuntimeHash, "Launchpad adapter factory runtime hash");
  return doubleHash([
    { type: "bytes32" }, { type: "uint256" }, { type: "address" }, { type: "bytes32" },
  ], [
    LAUNCHPAD_FACTORY_APPROVAL_DOMAIN,
    parameters.chainId,
    parameters.factory,
    parameters.factoryRuntimeHash,
  ]);
}

/**
 * Builds the exact release-approval leaf for one production Funding Bands integration profile.
 * The leaf approves reviewed code and market infrastructure; each deployed guard separately binds
 * and validates its project's exact reference supply.
 */
export function swapIntegrationApprovalLeaf(parameters: {
  chainId: bigint;
  adapter: Address;
  adapterRuntimeHash: Hex;
  priceGuard: Address;
  priceGuardRuntimeHash: Hex;
}): Hex {
  assertChainId(parameters.chainId);
  assertNonzeroAddress(parameters.adapter, "Swap adapter");
  assertNonzeroAddress(parameters.priceGuard, "Price guard");
  assertBytes32(parameters.adapterRuntimeHash, "Swap adapter runtime hash");
  assertBytes32(parameters.priceGuardRuntimeHash, "Price guard runtime hash");
  return doubleHash([
    { type: "bytes32" }, { type: "uint256" }, { type: "address" },
    { type: "bytes32" }, { type: "address" }, { type: "bytes32" },
  ], [
    SWAP_INTEGRATION_DOMAIN, parameters.chainId, parameters.adapter,
    parameters.adapterRuntimeHash, parameters.priceGuard, parameters.priceGuardRuntimeHash,
  ]);
}

export function fundingBandFactoryIntegrationApprovalLeaf(parameters: {
  chainId: bigint;
  integrationFactory: Address;
  v3Factory: Address;
  v3FactoryRuntimeHash: Hex;
  quoteAsset: Address;
  positionManager: Address;
  positionManagerRuntimeHash: Hex;
  quoteUsdOracle: Address;
  quoteUsdOracleRuntimeHash: Hex;
}): Hex {
  assertChainId(parameters.chainId);
  assertNonzeroAddress(parameters.integrationFactory, "Funding Band integration factory");
  assertNonzeroAddress(parameters.v3Factory, "V3 factory");
  assertNonzeroAddress(parameters.quoteAsset, "Quote asset");
  assertNonzeroAddress(parameters.positionManager, "Position manager");
  assertNonzeroAddress(parameters.quoteUsdOracle, "Quote/USD oracle");
  assertBytes32(parameters.v3FactoryRuntimeHash, "V3 factory runtime hash");
  assertBytes32(parameters.positionManagerRuntimeHash, "Position manager runtime hash");
  assertBytes32(parameters.quoteUsdOracleRuntimeHash, "Quote/USD oracle runtime hash");
  return doubleHash([
    { type: "bytes32" }, { type: "uint256" }, { type: "address" },
    { type: "address" }, { type: "bytes32" }, { type: "address" },
    { type: "address" }, { type: "bytes32" }, { type: "address" }, { type: "bytes32" },
  ], [
    FUNDING_BAND_FACTORY_INTEGRATION_DOMAIN, parameters.chainId,
    parameters.integrationFactory, parameters.v3Factory, parameters.v3FactoryRuntimeHash,
    parameters.quoteAsset, parameters.positionManager, parameters.positionManagerRuntimeHash,
    parameters.quoteUsdOracle, parameters.quoteUsdOracleRuntimeHash,
  ]);
}

export function fundingBandPairIntegrationApprovalLeaf(parameters: {
  chainId: bigint;
  marketCapGuard: Address;
  marketCapGuardRuntimeHash: Hex;
  positionAdapter: Address;
  positionAdapterRuntimeHash: Hex;
}): Hex {
  assertChainId(parameters.chainId);
  assertNonzeroAddress(parameters.marketCapGuard, "Market-cap guard");
  assertNonzeroAddress(parameters.positionAdapter, "Position adapter");
  assertBytes32(parameters.marketCapGuardRuntimeHash, "Market-cap guard runtime hash");
  assertBytes32(parameters.positionAdapterRuntimeHash, "Position adapter runtime hash");
  return doubleHash([
    { type: "bytes32" }, { type: "uint256" }, { type: "address" },
    { type: "bytes32" }, { type: "address" }, { type: "bytes32" },
  ], [
    FUNDING_BAND_PAIR_INTEGRATION_DOMAIN, parameters.chainId, parameters.marketCapGuard,
    parameters.marketCapGuardRuntimeHash, parameters.positionAdapter,
    parameters.positionAdapterRuntimeHash,
  ]);
}

export type SimpleFundingBandDestination =
  | typeof fundingBandDestination.creator
  | typeof fundingBandDestination.treasury
  | typeof fundingBandDestination.router
  | typeof fundingBandDestination.basketViaTreasury;

/** Converts a human-readable USD market cap into the protocol's fixed 8-decimal representation. */
export function marketCapUsdE8(value: string): bigint {
  const result = parseUnits(value, 8);
  if (result <= 0n) throw new RangeError("Market cap must be greater than zero");
  return result;
}

/** Builds a no-route destination config for destinations that need no adapter calldata. */
export function simpleFundingBandConfig(parameters: {
  lowerMarketCapUsd: string;
  upperMarketCapUsd: string;
  subjectAmount: bigint;
  destination: SimpleFundingBandDestination;
}): FundingBandConfig {
  const lowerMarketCapUsdE8 = marketCapUsdE8(parameters.lowerMarketCapUsd);
  const upperMarketCapUsdE8 = marketCapUsdE8(parameters.upperMarketCapUsd);
  if (lowerMarketCapUsdE8 >= upperMarketCapUsdE8) {
    throw new RangeError("Upper market cap must be greater than lower market cap");
  }
  if (parameters.subjectAmount <= 0n) {
    throw new RangeError("Subject amount must be greater than zero");
  }
  return {
    lowerMarketCapUsdE8,
    upperMarketCapUsdE8,
    subjectAmount: parameters.subjectAmount,
    destination: parameters.destination,
    destinationConfig: "0x",
  };
}

/** Builds the exact Treasury-prefund + band-create governance batch. */
export function buildFundingBandCreationActions(parameters: {
  treasury: Address;
  fundingBands: Address;
  subject: Address;
  config: FundingBandConfig;
  observationData?: Hex;
}): readonly [GovernanceAction, GovernanceAction] {
  const { treasury, fundingBands, subject, config, observationData = "0x" } = parameters;
  return [
    encodeGovernanceAction({
      target: treasury,
      abi: projectTreasuryVaultV2Abi,
      functionName: "send",
      args: [subject, config.subjectAmount, fundingBands],
    }),
    encodeGovernanceAction({
      target: fundingBands,
      abi: projectFundingBandsV2Abi,
      functionName: "createBand",
      args: [config, observationData],
    }),
  ];
}

function assertBytes32(value: Hex, label: string): void {
  if (!isHex(value) || value.length !== 66) throw new RangeError(`${label} must be exactly 32 bytes`);
}

function assertChainId(value: bigint): void {
  if (value <= 0n) throw new RangeError("Chain ID must be greater than zero");
}

function assertNonzeroAddress(value: Address, label: string): void {
  if (!isAddress(value) || /^0x0{40}$/i.test(value)) {
    throw new RangeError(`${label} must be a valid nonzero address`);
  }
}

function doubleHash(types: readonly object[], values: readonly unknown[]): Hex {
  const inner = keccak256(encodeAbiParameters(types as never, values as never));
  return keccak256(inner);
}
