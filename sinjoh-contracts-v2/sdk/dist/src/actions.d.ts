import { type Abi, type Address, type ContractFunctionArgs, type ContractFunctionName, type Hex } from "viem";
import type { FundingBandConfig } from "./types.js";
export interface GovernanceAction {
    target: Address;
    value: bigint;
    data: Hex;
}
export declare function governanceBatch(actions: readonly GovernanceAction[]): {
    readonly targets: `0x${string}`[];
    readonly values: bigint[];
    readonly calldatas: `0x${string}`[];
};
/** Encodes a wallet transaction that submits the same typed batch to a Multisig Account. */
export declare function encodeMultisigSubmission(actions: readonly GovernanceAction[]): Hex;
/** Encodes a wallet transaction that proposes the same typed batch to Token Governance. */
export declare function encodeTokenGovernanceProposal(actions: readonly GovernanceAction[], description: string): Hex;
/** Encodes one typed module mutation for either Multisig or Token Governance workflows. */
export declare function encodeGovernanceAction<const TAbi extends Abi, TFunctionName extends ContractFunctionName<TAbi, "payable" | "nonpayable">>(parameters: {
    target: Address;
    abi: TAbi;
    functionName: TFunctionName;
    args: ContractFunctionArgs<TAbi, "payable" | "nonpayable", TFunctionName>;
    value?: bigint;
}): GovernanceAction;
export declare const fundingBandDestination: {
    readonly creator: 0;
    readonly treasury: 1;
    readonly buybackBurn: 2;
    readonly buybackAirdrop: 3;
    readonly router: 4;
    readonly raffle: 5;
    readonly basketViaTreasury: 6;
};
/**
 * Builds the exact release-approval leaf for one production Funding Bands integration profile.
 * The leaf approves reviewed code and market infrastructure; each deployed guard separately binds
 * and validates its project's exact reference supply.
 */
export declare function swapIntegrationApprovalLeaf(parameters: {
    chainId: bigint;
    adapter: Address;
    adapterRuntimeHash: Hex;
    priceGuard: Address;
    priceGuardRuntimeHash: Hex;
}): Hex;
export declare function fundingBandFactoryIntegrationApprovalLeaf(parameters: {
    chainId: bigint;
    integrationFactory: Address;
    v3Factory: Address;
    v3FactoryRuntimeHash: Hex;
    quoteAsset: Address;
    positionManager: Address;
    positionManagerRuntimeHash: Hex;
    quoteUsdOracle: Address;
    quoteUsdOracleRuntimeHash: Hex;
}): Hex;
export declare function fundingBandPairIntegrationApprovalLeaf(parameters: {
    chainId: bigint;
    marketCapGuard: Address;
    marketCapGuardRuntimeHash: Hex;
    positionAdapter: Address;
    positionAdapterRuntimeHash: Hex;
}): Hex;
export type SimpleFundingBandDestination = typeof fundingBandDestination.creator | typeof fundingBandDestination.treasury | typeof fundingBandDestination.router | typeof fundingBandDestination.basketViaTreasury;
/** Converts a human-readable USD market cap into the protocol's fixed 8-decimal representation. */
export declare function marketCapUsdE8(value: string): bigint;
/** Builds a no-route destination config for destinations that need no adapter calldata. */
export declare function simpleFundingBandConfig(parameters: {
    lowerMarketCapUsd: string;
    upperMarketCapUsd: string;
    subjectAmount: bigint;
    destination: SimpleFundingBandDestination;
}): FundingBandConfig;
/** Builds the exact Treasury-prefund + band-create governance batch. */
export declare function buildFundingBandCreationActions(parameters: {
    treasury: Address;
    fundingBands: Address;
    subject: Address;
    config: FundingBandConfig;
    observationData?: Hex;
}): readonly [GovernanceAction, GovernanceAction];
//# sourceMappingURL=actions.d.ts.map