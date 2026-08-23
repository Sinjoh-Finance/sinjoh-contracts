import { encodeFunctionData, getAddress, isAddress } from "viem";
import { projectRaffleV2Abi } from "./abis.generated.js";
import { raffleWinningIndex, } from "./raffle.js";
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
const BURN_ADDRESS = "0x000000000000000000000000000000000000dead";
/** Replays complete ERC-20 history and computes snapshot or window-minimum holder weights. */
export function reconstructRaffleSnapshot(parameters) {
    if (parameters.snapshotBlock < 0n)
        throw new RangeError("Snapshot block cannot be negative");
    if (parameters.totalSupply < 0n)
        throw new RangeError("Historical supply cannot be negative");
    if (!/^0x[0-9a-fA-F]{64}$/.test(parameters.snapshotBlockHash)) {
        throw new RangeError("Snapshot block hash must be exactly 32 bytes");
    }
    if ((parameters.basis === "snapshot" && parameters.weightWindowBlocks !== 0n)
        || (parameters.basis === "min-balance" && parameters.weightWindowBlocks <= 0n)
        || parameters.weightWindowBlocks > parameters.snapshotBlock)
        throw new RangeError("Raffle weight window does not match the selected basis");
    validateOrderedTransfers(parameters.transfers, parameters.snapshotBlock);
    const balances = new Map();
    const minima = new Map();
    const windowStart = parameters.snapshotBlock - parameters.weightWindowBlocks;
    let windowInitialized = parameters.basis === "snapshot";
    for (const transfer of parameters.transfers) {
        assertAddress(transfer.from, "Transfer sender");
        assertAddress(transfer.to, "Transfer recipient");
        if (transfer.value < 0n)
            throw new RangeError("Transfer value cannot be negative");
        if (!windowInitialized && transfer.blockNumber >= windowStart) {
            for (const [holder, balance] of balances)
                minima.set(holder, balance);
            windowInitialized = true;
        }
        const from = transfer.from.toLowerCase();
        const to = transfer.to.toLowerCase();
        if (parameters.basis === "min-balance" && transfer.blockNumber >= windowStart) {
            if (from !== ZERO_ADDRESS && !minima.has(from))
                minima.set(from, balances.get(from) ?? 0n);
            if (to !== ZERO_ADDRESS && !minima.has(to))
                minima.set(to, balances.get(to) ?? 0n);
        }
        if (from !== ZERO_ADDRESS)
            debit(balances, from, transfer.value);
        if (to !== ZERO_ADDRESS)
            balances.set(to, (balances.get(to) ?? 0n) + transfer.value);
        if (parameters.basis === "min-balance" && transfer.blockNumber >= windowStart) {
            if (from !== ZERO_ADDRESS)
                updateMinimum(minima, from, balances.get(from) ?? 0n);
            if (to !== ZERO_ADDRESS)
                updateMinimum(minima, to, balances.get(to) ?? 0n);
        }
    }
    if (!windowInitialized) {
        for (const [holder, balance] of balances)
            minima.set(holder, balance);
    }
    const reconstructedSupply = [...balances.values()].reduce((sum, value) => sum + value, 0n);
    if (reconstructedSupply !== parameters.totalSupply) {
        throw new RangeError("Reconstructed balances do not match the on-chain historical supply");
    }
    const excluded = exclusionSet(parameters.exclusions);
    const source = parameters.basis === "snapshot" ? balances : minima;
    const weights = [...source.entries()]
        .filter(([holder, weight]) => weight > 0n && !excluded.has(holder))
        .map(([holder, weight]) => ({ holder: getAddress(holder), weight }))
        .sort((left, right) => BigInt(left.holder) < BigInt(right.holder) ? -1 : 1);
    return {
        snapshotBlock: parameters.snapshotBlock,
        snapshotBlockHash: parameters.snapshotBlockHash,
        basis: parameters.basis,
        weightWindowBlocks: parameters.weightWindowBlocks,
        totalSupply: parameters.totalSupply,
        weights,
    };
}
/** Encodes the only attestor transaction after two-provider artifact reconciliation. */
export function encodeRaffleCommitCall(parameters) {
    const commitment = parameters.round.commitment;
    return {
        kind: "commit",
        to: parameters.round.raffle,
        value: 0n,
        data: encodeFunctionData({
            abi: projectRaffleV2Abi,
            functionName: "commitRound",
            args: [
                commitment.roundId,
                commitment.snapshotBlock,
                commitment.snapshotBlockHash,
                commitment.rootHash,
                commitment.totalTickets,
            ],
        }),
    };
}
/** Locates every winning ticket interval and encodes permissionless direct/stock claim attempts. */
export function encodeRaffleClaimCalls(parameters) {
    const paidMask = parameters.slotsPaidMask ?? 0;
    if (!Number.isInteger(paidMask) || paidMask < 0 || paidMask > 65_535) {
        throw new RangeError("Paid-slot mask must fit uint16");
    }
    const calls = [];
    for (let slot = 0; slot < parameters.round.winnersPerRound; slot += 1) {
        if ((paidMask & (1 << slot)) !== 0)
            continue;
        const index = raffleWinningIndex({
            chainId: parameters.round.chainId,
            raffle: parameters.round.raffle,
            roundId: parameters.round.commitment.roundId,
            slot,
            seed: parameters.seed,
            totalTickets: parameters.round.commitment.totalTickets,
        });
        const leafIndex = parameters.round.leaves.findIndex((leaf) => index >= leaf.offset && index < leaf.offset + leaf.tickets);
        const leaf = parameters.round.leaves[leafIndex];
        const proof = parameters.round.proofs[leafIndex];
        if (leaf === undefined || proof === undefined)
            throw new Error("Winning ticket has no Raffle leaf");
        calls.push({
            kind: "claim",
            to: parameters.round.raffle,
            value: 0n,
            data: encodeFunctionData({
                abi: projectRaffleV2Abi,
                functionName: "claim",
                args: [
                    parameters.round.commitment.roundId,
                    slot,
                    { holder: leaf.holder, tickets: leaf.tickets },
                    proof,
                ],
            }),
        });
    }
    return calls;
}
export function encodeRaffleRetryCall(parameters) {
    assertAddress(parameters.raffle, "Raffle contract");
    assertAddress(parameters.holder, "Raffle winner");
    if (parameters.stockAsset !== undefined)
        assertAddress(parameters.stockAsset, "Stock asset");
    return {
        kind: parameters.stockAsset === undefined ? "retry" : "retry-stock",
        to: getAddress(parameters.raffle),
        value: 0n,
        data: parameters.stockAsset === undefined
            ? encodeFunctionData({
                abi: projectRaffleV2Abi,
                functionName: "deliverOwed",
                args: [parameters.holder],
            })
            : encodeFunctionData({
                abi: projectRaffleV2Abi,
                functionName: "deliverStockOwed",
                args: [parameters.holder, parameters.stockAsset],
            }),
    };
}
/** Encodes the winner's own redirect of a deferred direct or stock prize. */
export function encodeRaffleClaimOwedToCall(parameters) {
    assertAddress(parameters.raffle, "Raffle contract");
    assertAddress(parameters.payoutRecipient, "Payout recipient");
    if (parameters.stockAsset !== undefined)
        assertAddress(parameters.stockAsset, "Stock asset");
    return {
        kind: parameters.stockAsset === undefined ? "claim-owed" : "claim-stock-owed",
        to: getAddress(parameters.raffle),
        value: 0n,
        data: parameters.stockAsset === undefined
            ? encodeFunctionData({
                abi: projectRaffleV2Abi,
                functionName: "deliverOwedTo",
                args: [parameters.payoutRecipient],
            })
            : encodeFunctionData({
                abi: projectRaffleV2Abi,
                functionName: "deliverStockOwedTo",
                args: [parameters.stockAsset, parameters.payoutRecipient],
            }),
    };
}
export function encodeRaffleCloseCall(parameters) {
    assertAddress(parameters.raffle, "Raffle contract");
    if (parameters.roundId <= 0n)
        throw new RangeError("Round ID must be greater than zero");
    return {
        kind: parameters.mode,
        to: getAddress(parameters.raffle),
        value: 0n,
        data: encodeFunctionData({
            abi: projectRaffleV2Abi,
            functionName: parameters.mode === "expire" ? "expireRound" : "abandonRound",
            args: [parameters.roundId],
        }),
    };
}
function validateOrderedTransfers(transfers, snapshotBlock) {
    let previous;
    for (const transfer of transfers) {
        if (transfer.removed)
            throw new RangeError("Removed transfer logs cannot enter a Raffle snapshot");
        if (transfer.blockNumber < 0n
            || transfer.blockNumber > snapshotBlock
            || !Number.isSafeInteger(transfer.transactionIndex)
            || transfer.transactionIndex < 0
            || !Number.isSafeInteger(transfer.logIndex)
            || transfer.logIndex < 0)
            throw new RangeError("Raffle transfer position is invalid for the snapshot block");
        if (previous !== undefined && compareEvents(previous, transfer) >= 0) {
            throw new RangeError("Raffle transfer history must be complete and strictly ordered");
        }
        previous = transfer;
    }
}
function compareEvents(left, right) {
    if (left.blockNumber !== right.blockNumber)
        return left.blockNumber < right.blockNumber ? -1 : 1;
    if (left.transactionIndex !== right.transactionIndex)
        return left.transactionIndex - right.transactionIndex;
    return left.logIndex - right.logIndex;
}
function debit(balances, holder, amount) {
    const current = balances.get(holder) ?? 0n;
    if (current < amount)
        throw new RangeError("Raffle transfer history starts late or is inconsistent");
    balances.set(holder, current - amount);
}
function updateMinimum(minima, holder, balance) {
    const current = minima.get(holder);
    if (current === undefined || balance < current)
        minima.set(holder, balance);
}
function exclusionSet(exclusions) {
    const result = new Set([ZERO_ADDRESS, BURN_ADDRESS]);
    for (const exclusion of exclusions) {
        assertAddress(exclusion, "Raffle exclusion");
        result.add(exclusion.toLowerCase());
    }
    return result;
}
function assertAddress(value, label) {
    if (!isAddress(value))
        throw new RangeError(`${label} must be a valid address`);
}
//# sourceMappingURL=raffle-worker.js.map