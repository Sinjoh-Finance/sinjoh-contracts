import { encodeFunctionData, getAddress, isAddress } from "viem";
import { projectAirdropV2Abi } from "./abis.generated.js";
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
const BURN_ADDRESS = "0x000000000000000000000000000000000000dead";
const MAX_PUSH_BATCH_SIZE = 64;
/** Reconstructs holder balances from the complete ordered ERC-20 Transfer history. */
export function reconstructHolderAirdropSnapshot(parameters) {
    const balances = new Map();
    validateOrderedEvents(parameters.transfers, parameters.snapshotBlock);
    for (const transfer of parameters.transfers) {
        assertAddress(transfer.from, "Transfer sender");
        assertAddress(transfer.to, "Transfer recipient");
        if (transfer.value < 0n)
            throw new RangeError("Transfer value cannot be negative");
        const from = transfer.from.toLowerCase();
        const to = transfer.to.toLowerCase();
        if (from !== ZERO_ADDRESS)
            debit(balances, from, transfer.value, "Transfer history");
        if (to !== ZERO_ADDRESS)
            credit(balances, to, transfer.value);
    }
    return snapshotFromBalances({ ...parameters, balances, aggregateSupply: parameters.totalSupply });
}
/** Reconstructs aggregate active stake by replaying the staking pool's canonical position events. */
export function reconstructStakerAirdropSnapshot(parameters) {
    const positions = new Map();
    validateOrderedEvents(parameters.events, parameters.snapshotBlock);
    for (const event of parameters.events) {
        const id = event.tokenId.toString();
        if (event.tokenId < 0n || event.amount <= 0n) {
            throw new RangeError("Staking position ID and amount must be positive");
        }
        if (event.eventName === "PositionCreated") {
            assertEligibleOwner(event.owner, "Position owner");
            if (positions.has(id))
                throw new RangeError(`Duplicate staking position ${id}`);
            positions.set(id, { owner: getAddress(event.owner), amount: event.amount });
            continue;
        }
        const position = positions.get(id);
        if (position === undefined)
            throw new RangeError(`Unknown staking position ${id}`);
        if (event.eventName === "PositionTransferred") {
            assertAddress(event.from, "Previous position owner");
            assertEligibleOwner(event.to, "Position recipient");
            if (position.owner.toLowerCase() !== event.from.toLowerCase()
                || position.amount !== event.amount)
                throw new RangeError(`Inconsistent transfer for staking position ${id}`);
            positions.set(id, { owner: getAddress(event.to), amount: event.amount });
        }
        else {
            assertAddress(event.owner, "Redeeming position owner");
            if (position.owner.toLowerCase() !== event.owner.toLowerCase()
                || position.amount !== event.amount)
                throw new RangeError(`Inconsistent redemption for staking position ${id}`);
            positions.delete(id);
        }
    }
    const balances = new Map();
    for (const position of positions.values()) {
        credit(balances, position.owner.toLowerCase(), position.amount);
    }
    return snapshotFromBalances({
        ...parameters,
        balances,
        aggregateSupply: parameters.totalStakedSupply,
    });
}
/** Builds bounded permissionless push calls while retaining zero-entitlement leaves for settlement. */
export function planAirdropPushBatches(parameters) {
    if (!Number.isSafeInteger(parameters.maxPushBatchSize)
        || parameters.maxPushBatchSize < 1
        || parameters.maxPushBatchSize > MAX_PUSH_BATCH_SIZE)
        throw new RangeError("Airdrop push batch size must be between 1 and 64");
    if (parameters.epoch.leaves.length !== parameters.epoch.proofs.length) {
        throw new RangeError("Airdrop leaves and proofs must have equal length");
    }
    const processed = new Set((parameters.processedHolders ?? []).map((holder) => {
        assertAddress(holder, "Processed holder");
        return holder.toLowerCase();
    }));
    const pending = parameters.epoch.leaves
        .map((leaf, index) => ({ leaf, proof: parameters.epoch.proofs[index], index }))
        .filter(({ leaf }) => !processed.has(leaf.holder.toLowerCase()));
    const batches = [];
    for (let offset = 0; offset < pending.length; offset += parameters.maxPushBatchSize) {
        const entries = pending.slice(offset, offset + parameters.maxPushBatchSize);
        batches.push({
            indices: entries.map(({ index }) => index),
            leaves: entries.map(({ leaf }) => leaf),
            proofs: entries.map(({ proof }) => {
                if (proof === undefined)
                    throw new RangeError("Missing Airdrop proof");
                return proof;
            }),
        });
    }
    return batches;
}
/** Encodes permissionless push transactions in the same bounded order as the published artifact. */
export function encodeAirdropPushCalls(parameters) {
    assertAddress(parameters.airdrop, "Airdrop contract");
    return parameters.batches.map((batch) => ({
        kind: "push",
        to: getAddress(parameters.airdrop),
        value: 0n,
        data: encodeFunctionData({
            abi: projectAirdropV2Abi,
            functionName: "push",
            args: [parameters.accountId, parameters.epochId, batch.leaves, batch.proofs],
        }),
    }));
}
/** Encodes a permissionless retry whose recipient and asset cannot be redirected by the caller. */
export function encodeAirdropRetryCreditCall(parameters) {
    assertAddress(parameters.airdrop, "Airdrop contract");
    assertAddress(parameters.recipient, "Credit recipient");
    assertAddress(parameters.asset, "Credit asset");
    if (parameters.maxAmount <= 0n)
        throw new RangeError("Retry amount must be greater than zero");
    return {
        kind: "retry-credit",
        to: getAddress(parameters.airdrop),
        value: 0n,
        data: encodeFunctionData({
            abi: projectAirdropV2Abi,
            functionName: "retryCredit",
            args: [parameters.recipient, parameters.asset, parameters.maxAmount],
        }),
    };
}
/** Encodes finalization after on-chain status confirms every committed leaf is settled. */
export function encodeAirdropFinalizeCall(parameters) {
    assertAddress(parameters.airdrop, "Airdrop contract");
    return {
        kind: "finalize",
        to: getAddress(parameters.airdrop),
        value: 0n,
        data: encodeFunctionData({
            abi: projectAirdropV2Abi,
            functionName: "finalizeEpoch",
            args: [parameters.accountId, parameters.epochId],
        }),
    };
}
function snapshotFromBalances(parameters) {
    const reconstructedSupply = [...parameters.balances.values()]
        .reduce((total, balance) => total + balance, 0n);
    if (reconstructedSupply !== parameters.aggregateSupply) {
        throw new RangeError("Reconstructed balances do not match the on-chain historical supply");
    }
    const exclusions = exclusionSet(parameters.exclusions);
    const weights = [...parameters.balances.entries()]
        .filter(([holder, weight]) => weight > 0n && !exclusions.has(holder))
        .map(([holder, weight]) => ({ holder: getAddress(holder), weight }));
    const eligible = weights.reduce((total, entry) => total + entry.weight, 0n);
    if (eligible !== parameters.totalEligibleWeight) {
        throw new RangeError("Reconstructed holders do not match the on-chain eligible supply");
    }
    return {
        snapshotBlock: parameters.snapshotBlock,
        snapshotBlockHash: parameters.snapshotBlockHash,
        snapshotTime: parameters.snapshotTime,
        totalEligibleWeight: eligible,
        weights,
    };
}
function validateOrderedEvents(events, snapshotBlock) {
    let previous;
    for (const event of events) {
        if (event.removed)
            throw new RangeError("Removed logs cannot be used for an Airdrop snapshot");
        if (event.blockNumber < 0n
            || event.blockNumber > snapshotBlock
            || !Number.isSafeInteger(event.transactionIndex)
            || event.transactionIndex < 0
            || !Number.isSafeInteger(event.logIndex)
            || event.logIndex < 0)
            throw new RangeError("Airdrop event position is invalid for the snapshot block");
        if (previous !== undefined && compareEventPosition(previous, event) >= 0) {
            throw new RangeError("Airdrop events must be complete and strictly ordered");
        }
        previous = event;
    }
}
function compareEventPosition(left, right) {
    if (left.blockNumber !== right.blockNumber)
        return left.blockNumber < right.blockNumber ? -1 : 1;
    if (left.transactionIndex !== right.transactionIndex) {
        return left.transactionIndex - right.transactionIndex;
    }
    return left.logIndex - right.logIndex;
}
function exclusionSet(supplied) {
    const exclusions = new Set([ZERO_ADDRESS, BURN_ADDRESS]);
    for (const address of supplied) {
        assertAddress(address, "Airdrop exclusion");
        exclusions.add(address.toLowerCase());
    }
    return exclusions;
}
function debit(balances, holder, amount, label) {
    const current = balances.get(holder) ?? 0n;
    if (current < amount)
        throw new RangeError(`${label} spends more than the reconstructed balance`);
    const next = current - amount;
    if (next === 0n)
        balances.delete(holder);
    else
        balances.set(holder, next);
}
function credit(balances, holder, amount) {
    balances.set(holder, (balances.get(holder) ?? 0n) + amount);
}
function assertAddress(value, label) {
    if (!isAddress(value))
        throw new RangeError(`${label} must be a valid address`);
}
function assertEligibleOwner(value, label) {
    assertAddress(value, label);
    const normalized = value.toLowerCase();
    if (normalized === ZERO_ADDRESS || normalized === BURN_ADDRESS) {
        throw new RangeError(`${label} cannot be the zero or burn address`);
    }
}
//# sourceMappingURL=airdrop-worker.js.map