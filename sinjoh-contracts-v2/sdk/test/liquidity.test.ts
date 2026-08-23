import assert from "node:assert/strict";
import test from "node:test";
import { decodeAbiParameters, decodeFunctionData } from "viem";
import {
  buildLiquidityAccountConfig,
  buildLiquidityLaunchAccountConfig,
  encodeLiquidityAccountConfig,
  encodeLiquidityCollectCall,
  encodeLiquidityFeeDeliveryCall,
  encodeLiquidityMintCall,
  encodeLiquidityProtocolFeeDeliveryCall,
  liquidityFeeDestination,
  liquidityVenue,
  projectLiquidityManagerV2Abi,
} from "../src/index.js";

const manager = "0x0000000000000000000000000000000000001000";
const subject = "0x0000000000000000000000000000000000002000";
const creator = "0x0000000000000000000000000000000000003000";
const treasury = "0x0000000000000000000000000000000000004000";
const quote = "0x0000000000000000000000000000000000005000";
const adapter = "0x0000000000000000000000000000000000006000";
const guard = "0x0000000000000000000000000000000000007000";

const configTuple = [{
  type: "tuple",
  components: [
    { name: "venue", type: "uint8" },
    { name: "quoteAsset", type: "address" },
    { name: "poolFee", type: "uint24" },
    { name: "tickSpacing", type: "int24" },
    { name: "hooks", type: "address" },
    { name: "swapAdapter", type: "address" },
    { name: "priceGuard", type: "address" },
    { name: "swapRouteData", type: "bytes" },
    { name: "quoteSwapBps", type: "uint16" },
    { name: "maxMintSlippageBps", type: "uint16" },
    { name: "minNotionalPerMint", type: "uint128" },
    { name: "maxNotionalPerMint", type: "uint128" },
    { name: "minMintInterval", type: "uint48" },
    { name: "feeMode", type: "uint8" },
    { name: "feeRecipient", type: "address" },
  ],
}] as const;

test("hydrates exact Liquidity config from product choices and a reviewed profile", () => {
  const config = buildLiquidityAccountConfig({
    profile: {
      id: "base-v3-usdc",
      venue: liquidityVenue.uniswapV3,
      quoteAsset: quote,
      poolFee: 3_000,
      tickSpacing: 60,
      hooks: "0x0000000000000000000000000000000000000000",
      swapAdapter: adapter,
      priceGuard: guard,
      swapRouteData: `0x${"00".repeat(32)}`,
      maxMintSlippageBps: 100,
    },
    choices: {
      quoteSwapBps: 5_000,
      minNotionalPerMint: 1_000n,
      maxNotionalPerMint: 1_000_000n,
      minMintInterval: 3_600n,
      feeDestination: liquidityFeeDestination.treasury,
    },
    creator,
    treasury,
  });
  assert.equal(config.feeMode, 1);
  assert.equal(config.feeRecipient, treasury);
  assert.equal(config.swapAdapter, adapter);
  assert.equal(config.priceGuard, guard);
  assert.equal(config.minMintInterval, 3_600);
  assert.deepEqual(decodeAbiParameters(configTuple, encodeLiquidityAccountConfig(config))[0], config);
  assert.equal(buildLiquidityLaunchAccountConfig({
    profile: {
      id: "base-v3-usdc",
      venue: liquidityVenue.uniswapV3,
      quoteAsset: quote,
      poolFee: 3_000,
      tickSpacing: 60,
      hooks: "0x0000000000000000000000000000000000000000",
      swapAdapter: adapter,
      priceGuard: guard,
      swapRouteData: `0x${"00".repeat(32)}`,
      maxMintSlippageBps: 100,
    },
    choices: {
      quoteSwapBps: 5_000,
      minNotionalPerMint: 1_000n,
      maxNotionalPerMint: 1_000_000n,
      minMintInterval: 3_600n,
      feeDestination: liquidityFeeDestination.treasury,
    },
    treasuryEnabled: true,
  }).feeRecipient, "0x0000000000000000000000000000000000000000");
});

test("rejects unsafe creator choices before any wallet transaction", () => {
  const base = {
    profile: {
      id: "base-v3-usdc",
      venue: liquidityVenue.uniswapV3,
      quoteAsset: quote,
      poolFee: 3_000,
      tickSpacing: 60,
      hooks: "0x0000000000000000000000000000000000000000",
      swapAdapter: adapter,
      priceGuard: guard,
      swapRouteData: "0x01",
      maxMintSlippageBps: 100,
    },
    creator,
  } as const;
  assert.throws(() => buildLiquidityAccountConfig({
    ...base,
    choices: {
      quoteSwapBps: 4_499,
      minNotionalPerMint: 1n,
      maxNotionalPerMint: 2n,
      minMintInterval: 0n,
      feeDestination: liquidityFeeDestination.creator,
    },
  }), /between 45% and 55%/);
  assert.throws(() => buildLiquidityAccountConfig({
    ...base,
    choices: {
      quoteSwapBps: 5_000,
      minNotionalPerMint: 1n,
      maxNotionalPerMint: 2n,
      minMintInterval: 0n,
      feeDestination: liquidityFeeDestination.treasury,
    },
  }), /requires the project's Treasury/);
  assert.throws(() => buildLiquidityLaunchAccountConfig({
    profile: base.profile,
    choices: {
      quoteSwapBps: 5_000,
      minNotionalPerMint: 1n,
      maxNotionalPerMint: 2n,
      minMintInterval: 0n,
      feeDestination: liquidityFeeDestination.treasury,
    },
  }), /requires Treasury to be enabled/);
  assert.throws(() => encodeLiquidityMintCall({
    manager,
    funder: treasury,
    subject,
    notional: 1n,
    guardData: `0x${"00".repeat(1_025)}`,
  }), /cannot exceed 1024 bytes/);
});

test("encodes the complete permissionless Liquidity work lifecycle", () => {
  const mint = decodeFunctionData({
    abi: projectLiquidityManagerV2Abi,
    data: encodeLiquidityMintCall({ manager, funder: treasury, subject, notional: 10_000n }).data,
  });
  assert.deepEqual(mint, {
    functionName: "mint",
    args: [treasury, subject, 10_000n, 0n, "0x"],
  });
  assert.equal(decodeFunctionData({
    abi: projectLiquidityManagerV2Abi,
    data: encodeLiquidityCollectCall({ manager, funder: treasury, subject }).data,
  }).functionName, "collect");
  assert.equal(decodeFunctionData({
    abi: projectLiquidityManagerV2Abi,
    data: encodeLiquidityFeeDeliveryCall({ manager, recipient: creator, asset: quote, amount: 5n }).data,
  }).functionName, "sendFee");
  assert.equal(decodeFunctionData({
    abi: projectLiquidityManagerV2Abi,
    data: encodeLiquidityProtocolFeeDeliveryCall({ manager, asset: quote, amount: 1n }).data,
  }).functionName, "sendProtocolFee");
});
