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

const FUNDING_BAND_INTEGRATION_DOMAIN = keccak256(
  stringToHex("SINJOH_V2_FUNDING_BAND_INTEGRATION"),
);

/**
 * Builds the exact release-approval leaf for one production Funding Bands integration profile.
 * The leaf approves reviewed code and market infrastructure; each deployed guard separately binds
 * and validates its project's exact reference supply.
 */
export function fundingBandIntegrationApprovalLeaf(parameters: {
  chainId: bigint;
  poolRuntimeHash: Hex;
  quoteAsset: Address;
  marketCapGuardRuntimeHash: Hex;
  positionAdapterRuntimeHash: Hex;
  positionManagerRuntimeHash: Hex;
}): Hex {
  if (parameters.chainId <= 0n) throw new RangeError("Chain ID must be greater than zero");
  if (!isAddress(parameters.quoteAsset) || /^0x0{40}$/i.test(parameters.quoteAsset)) {
    throw new RangeError("Quote asset must be a valid nonzero address");
  }
  assertBytes32(parameters.poolRuntimeHash, "Pool runtime hash");
  assertBytes32(parameters.marketCapGuardRuntimeHash, "Market-cap guard runtime hash");
  assertBytes32(parameters.positionAdapterRuntimeHash, "Position adapter runtime hash");
  assertBytes32(parameters.positionManagerRuntimeHash, "Position manager runtime hash");

  const inner = keccak256(
    encodeAbiParameters(
      [
        { type: "bytes32" },
        { type: "uint256" },
        { type: "bytes32" },
        { type: "address" },
        { type: "bytes32" },
        { type: "bytes32" },
        { type: "bytes32" },
      ],
      [
        FUNDING_BAND_INTEGRATION_DOMAIN,
        parameters.chainId,
        parameters.poolRuntimeHash,
        parameters.quoteAsset,
        parameters.marketCapGuardRuntimeHash,
        parameters.positionAdapterRuntimeHash,
        parameters.positionManagerRuntimeHash,
      ],
    ),
  );
  return keccak256(inner);
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
