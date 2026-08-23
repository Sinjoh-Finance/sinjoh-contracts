import { type Address, type Hex } from "viem";
import type { LiquidityAccountConfig, LiquidityFundingConfig } from "./types.js";
export declare const liquidityVenue: {
    readonly uniswapV3: 0;
    readonly uniswapV4: 1;
};
export declare const liquidityFeeDestination: {
    readonly creator: "creator";
    readonly treasury: "treasury";
    readonly recycle: "recycle";
    readonly funder: "funder";
};
export type LiquidityFeeDestination = typeof liquidityFeeDestination[keyof typeof liquidityFeeDestination];
/** Off-chain-reviewed integration data frozen by the first funder for one isolated account. */
export interface LiquidityDeploymentProfile {
    id: string;
    venue: 0 | 1;
    quoteAsset: Address;
    poolFee: number;
    tickSpacing: number;
    hooks: Address;
    swapAdapter: Address;
    priceGuard: Address;
    swapRouteData: Hex;
    maxMintSlippageBps: number;
    integrationApprovalProof: readonly Hex[];
}
/** Product choices that are safe and understandable in a creator flow. */
export interface LiquidityProductChoices {
    quoteSwapBps: number;
    minNotionalPerMint: bigint;
    maxNotionalPerMint: bigint;
    minMintInterval: bigint;
    feeDestination: LiquidityFeeDestination;
}
export interface LiquidityKeeperCall {
    kind: "mint" | "collect" | "send-fee" | "send-protocol-fee";
    to: Address;
    value: 0n;
    data: Hex;
}
/** Hydrates one frozen account config without exposing integration plumbing to the creator. */
export declare function buildLiquidityAccountConfig(parameters: {
    profile: LiquidityDeploymentProfile;
    choices: LiquidityProductChoices;
    creator: Address;
    treasury?: Address;
}): LiquidityAccountConfig;
/**
 * Normal one-transaction launch path. Creator/Treasury fee recipients remain canonical
 * placeholders until the Launcher materializes the predicted project addresses atomically.
 */
export declare function buildLiquidityLaunchAccountConfig(parameters: {
    profile: LiquidityDeploymentProfile;
    choices: LiquidityProductChoices;
    treasuryEnabled?: boolean;
}): LiquidityAccountConfig;
/** Exact Solidity `abi.encode(FundingConfig)` payload used by Router/direct funding. */
export declare function encodeLiquidityFundingConfig(funding: LiquidityFundingConfig): Hex;
/** Builds and encodes the reviewed config plus its release approval proof. */
export declare function encodeLiquidityAccountConfig(config: LiquidityAccountConfig, integrationApprovalProof: readonly Hex[]): Hex;
/** Encodes a permissionless mint/increase attempt; the frozen guard remains authoritative. */
export declare function encodeLiquidityMintCall(parameters: {
    manager: Address;
    funder: Address;
    subject: Address;
    notional: bigint;
    callerMinimumOutput?: bigint;
    guardData?: Hex;
}): LiquidityKeeperCall;
export declare function encodeLiquidityCollectCall(parameters: {
    manager: Address;
    funder: Address;
    subject: Address;
}): LiquidityKeeperCall;
export declare function encodeLiquidityFeeDeliveryCall(parameters: {
    manager: Address;
    recipient: Address;
    asset: Address;
    amount: bigint;
}): LiquidityKeeperCall;
export declare function encodeLiquidityProtocolFeeDeliveryCall(parameters: {
    manager: Address;
    asset: Address;
    amount: bigint;
}): LiquidityKeeperCall;
//# sourceMappingURL=liquidity.d.ts.map