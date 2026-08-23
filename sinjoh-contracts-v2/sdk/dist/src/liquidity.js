import { encodeAbiParameters, encodeFunctionData, getAddress, isAddress, } from "viem";
import { projectLiquidityManagerV2Abi } from "./abis.generated.js";
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
const BURN_ADDRESS = "0x000000000000000000000000000000000000dead";
const MAX_UINT128 = 2n ** 128n - 1n;
const MAX_UINT48 = 2n ** 48n - 1n;
const MAX_UINT256 = 2n ** 256n - 1n;
const liquidityConfigParameters = [{
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
    }];
export const liquidityVenue = {
    uniswapV3: 0,
    uniswapV4: 1,
};
export const liquidityFeeDestination = {
    creator: "creator",
    treasury: "treasury",
    recycle: "recycle",
    funder: "funder",
};
/** Hydrates one frozen account config without exposing integration plumbing to the creator. */
export function buildLiquidityAccountConfig(parameters) {
    const { profile, choices } = parameters;
    if (profile.id.trim().length === 0)
        throw new RangeError("Liquidity profile ID cannot be empty");
    if (profile.venue !== 0 && profile.venue !== 1)
        throw new RangeError("Liquidity venue is unsupported");
    assertAddress(profile.quoteAsset, "Liquidity quote asset", profile.venue === 1);
    assertAddress(profile.swapAdapter, "Liquidity swap adapter");
    assertAddress(profile.priceGuard, "Liquidity price guard");
    assertAddress(profile.hooks, "Liquidity hook", true);
    if (profile.venue === 0 && profile.hooks.toLowerCase() !== ZERO_ADDRESS) {
        throw new RangeError("Uniswap V3 liquidity cannot use a hook");
    }
    if (!Number.isInteger(profile.poolFee) || profile.poolFee < 0 || profile.poolFee > 16_777_215) {
        throw new RangeError("Liquidity pool fee must fit uint24");
    }
    if (profile.venue === 0 && profile.poolFee === 0) {
        throw new RangeError("Uniswap V3 liquidity requires a nonzero pool fee");
    }
    if (!Number.isInteger(profile.tickSpacing) || profile.tickSpacing < -8_388_608 || profile.tickSpacing > 8_388_607) {
        throw new RangeError("Liquidity tick spacing must fit int24");
    }
    if (profile.tickSpacing <= 0) {
        throw new RangeError("Liquidity requires positive tick spacing");
    }
    if (!/^0x(?:[0-9a-fA-F]{2})+$/.test(profile.swapRouteData) || profile.swapRouteData.length > 2_050) {
        throw new RangeError("Liquidity route data must contain between 1 and 1024 bytes");
    }
    if (!Number.isInteger(profile.maxMintSlippageBps)
        || profile.maxMintSlippageBps < 0
        || profile.maxMintSlippageBps > 500)
        throw new RangeError("Liquidity mint slippage cannot exceed 5%");
    if (!Number.isInteger(choices.quoteSwapBps) || choices.quoteSwapBps < 4_500 || choices.quoteSwapBps > 5_500) {
        throw new RangeError("Liquidity split must swap between 45% and 55% into the project token");
    }
    assertUnsigned(choices.minNotionalPerMint, MAX_UINT128, "Minimum liquidity contribution");
    assertUnsigned(choices.maxNotionalPerMint, MAX_UINT128, "Maximum liquidity contribution");
    if (choices.minNotionalPerMint === 0n || choices.minNotionalPerMint > choices.maxNotionalPerMint) {
        throw new RangeError("Liquidity contribution limits are invalid");
    }
    assertUnsigned(choices.minMintInterval, MAX_UINT48, "Liquidity mint cadence");
    const feeMode = feeModeFor(choices.feeDestination);
    let feeRecipient = ZERO_ADDRESS;
    if (choices.feeDestination === "creator") {
        assertAddress(parameters.creator, "Creator");
        feeRecipient = getAddress(parameters.creator);
    }
    else if (choices.feeDestination === "treasury") {
        if (parameters.treasury === undefined) {
            throw new RangeError("Treasury fee delivery requires the project's Treasury");
        }
        assertAddress(parameters.treasury, "Treasury");
        feeRecipient = getAddress(parameters.treasury);
    }
    return {
        venue: profile.venue,
        quoteAsset: getAddress(profile.quoteAsset),
        poolFee: profile.poolFee,
        tickSpacing: profile.tickSpacing,
        hooks: getAddress(profile.hooks),
        swapAdapter: getAddress(profile.swapAdapter),
        priceGuard: getAddress(profile.priceGuard),
        swapRouteData: profile.swapRouteData,
        quoteSwapBps: choices.quoteSwapBps,
        maxMintSlippageBps: profile.maxMintSlippageBps,
        minNotionalPerMint: choices.minNotionalPerMint,
        maxNotionalPerMint: choices.maxNotionalPerMint,
        minMintInterval: Number(choices.minMintInterval),
        feeMode,
        feeRecipient,
    };
}
/**
 * Normal one-transaction launch path. Creator/Treasury fee recipients remain canonical
 * placeholders until the Launcher materializes the predicted project addresses atomically.
 */
export function buildLiquidityLaunchAccountConfig(parameters) {
    if (parameters.choices.feeDestination === "treasury" && parameters.treasuryEnabled !== true) {
        throw new RangeError("Treasury fee delivery requires Treasury to be enabled for this launch");
    }
    const resolved = buildLiquidityAccountConfig({
        ...parameters,
        creator: "0x0000000000000000000000000000000000000001",
        treasury: "0x0000000000000000000000000000000000000002",
    });
    return { ...resolved, feeRecipient: ZERO_ADDRESS };
}
/** Exact Solidity `abi.encode(Config)` payload used by Router funding actions. */
export function encodeLiquidityAccountConfig(config) {
    return encodeAbiParameters(liquidityConfigParameters, [config]);
}
/** Encodes a permissionless mint/increase attempt; the frozen guard remains authoritative. */
export function encodeLiquidityMintCall(parameters) {
    assertAddress(parameters.manager, "Liquidity Manager");
    assertAddress(parameters.funder, "Liquidity funder");
    assertAddress(parameters.subject, "Project token");
    if (parameters.notional <= 0n || parameters.notional > MAX_UINT256) {
        throw new RangeError("Liquidity notional must be a positive uint256");
    }
    const callerMinimumOutput = parameters.callerMinimumOutput ?? 0n;
    if (callerMinimumOutput < 0n || callerMinimumOutput > MAX_UINT256) {
        throw new RangeError("Liquidity minimum output must fit uint256");
    }
    const guardData = parameters.guardData ?? "0x";
    if (!/^0x(?:[0-9a-fA-F]{2})*$/.test(guardData) || guardData.length > 2_050) {
        throw new RangeError("Liquidity guard data cannot exceed 1024 bytes");
    }
    return keeperCall("mint", parameters.manager, encodeFunctionData({
        abi: projectLiquidityManagerV2Abi,
        functionName: "mint",
        args: [parameters.funder, parameters.subject, parameters.notional, callerMinimumOutput, guardData],
    }));
}
export function encodeLiquidityCollectCall(parameters) {
    assertAddress(parameters.manager, "Liquidity Manager");
    assertAddress(parameters.funder, "Liquidity funder");
    assertAddress(parameters.subject, "Project token");
    return keeperCall("collect", parameters.manager, encodeFunctionData({
        abi: projectLiquidityManagerV2Abi,
        functionName: "collect",
        args: [parameters.funder, parameters.subject],
    }));
}
export function encodeLiquidityFeeDeliveryCall(parameters) {
    assertAddress(parameters.manager, "Liquidity Manager");
    assertAddress(parameters.recipient, "Liquidity fee recipient");
    assertAddress(parameters.asset, "Liquidity fee asset", true);
    if (parameters.amount <= 0n || parameters.amount > MAX_UINT256) {
        throw new RangeError("Liquidity fee amount must be a positive uint256");
    }
    return keeperCall("send-fee", parameters.manager, encodeFunctionData({
        abi: projectLiquidityManagerV2Abi,
        functionName: "sendFee",
        args: [parameters.recipient, parameters.asset, parameters.amount],
    }));
}
export function encodeLiquidityProtocolFeeDeliveryCall(parameters) {
    assertAddress(parameters.manager, "Liquidity Manager");
    assertAddress(parameters.asset, "Liquidity protocol-fee asset", true);
    if (parameters.amount <= 0n || parameters.amount > MAX_UINT256) {
        throw new RangeError("Liquidity protocol fee must be a positive uint256");
    }
    return keeperCall("send-protocol-fee", parameters.manager, encodeFunctionData({
        abi: projectLiquidityManagerV2Abi,
        functionName: "sendProtocolFee",
        args: [parameters.asset, parameters.amount],
    }));
}
function feeModeFor(destination) {
    if (destination === "creator")
        return 0;
    if (destination === "treasury")
        return 1;
    if (destination === "recycle")
        return 2;
    if (destination === "funder")
        return 3;
    throw new RangeError("Liquidity fee destination is unsupported");
}
function keeperCall(kind, manager, data) {
    return { kind, to: getAddress(manager), value: 0n, data };
}
function assertAddress(value, label, allowZero = false) {
    if (!isAddress(value))
        throw new RangeError(`${label} must be a valid address`);
    const normalized = value.toLowerCase();
    if ((!allowZero && normalized === ZERO_ADDRESS) || normalized === BURN_ADDRESS) {
        throw new RangeError(`${label} cannot be the zero or burn address`);
    }
}
function assertUnsigned(value, maximum, label) {
    if (value < 0n || value > maximum)
        throw new RangeError(`${label} is out of range`);
}
//# sourceMappingURL=liquidity.js.map