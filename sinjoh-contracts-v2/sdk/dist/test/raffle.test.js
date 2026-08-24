import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import test from "node:test";
import { decodeFunctionData } from "viem";
import { buildRaffleRound, buildVerifiedRaffleRound, encodeRaffleClaimCalls, encodeRaffleCloseCall, encodeRaffleCommitCall, encodeRaffleRetryCall, encodeRaffleClaimOwedToCall, projectRaffleV2Abi, raffleWinningIndex, reconcileRaffleSnapshots, reconstructRaffleSnapshot, } from "../src/index.js";
const treeFixture = JSON.parse(await readFile(resolve(process.cwd(), "../../sinjoh-raffle-rewards/test/fixtures/ticket-tree.json"), "utf8"));
const slotFixture = JSON.parse(await readFile(resolve(process.cwd(), "../../sinjoh-raffle-rewards/test/fixtures/slot-indices.json"), "utf8"));
test("matches the normative Solidity Raffle ticket-tree fixture exactly", () => {
    const round = buildRaffleRound({
        chainId: BigInt(treeFixture.chainId),
        raffle: treeFixture.raffle,
        roundId: BigInt(treeFixture.roundId),
        snapshotBlock: BigInt(treeFixture.snapshotBlock),
        snapshotBlockHash: `0x${"ab".repeat(32)}`,
        basis: "min-balance",
        weightWindowBlocks: 100n,
        tokensPerTicket: 1n,
        maxTicketsPerHolder: 0n,
        winnersPerRound: 4,
        weights: treeFixture.leaves.map((leaf) => ({
            holder: leaf.holder,
            weight: BigInt(leaf.tickets),
        })),
    });
    assert.equal(round.commitment.rootHash, treeFixture.root);
    assert.equal(round.commitment.totalTickets, BigInt(treeFixture.rootSum));
    assert.equal(round.emptyLeafHash, treeFixture.emptyLeaf);
    assert.deepEqual(round.leaves.map((leaf) => ({
        holder: leaf.holder.toLowerCase(),
        tickets: Number(leaf.tickets),
        offset: Number(leaf.offset),
        leafHash: leaf.leafHash,
    })), treeFixture.leaves.map((leaf) => ({
        holder: leaf.holder.toLowerCase(),
        tickets: leaf.tickets,
        offset: leaf.offset,
        leafHash: leaf.leafHash,
    })));
    assert.deepEqual(round.proofs, treeFixture.leaves.map((leaf) => leaf.proof.map((node) => ({
        ...node,
        siblingSum: BigInt(node.siblingSum),
    }))));
});
test("matches Solidity winner indices and encodes commit plus every unpaid claim", () => {
    const round = buildRaffleRound({
        chainId: BigInt(treeFixture.chainId),
        raffle: treeFixture.raffle,
        roundId: BigInt(treeFixture.roundId),
        snapshotBlock: BigInt(treeFixture.snapshotBlock),
        snapshotBlockHash: `0x${"ab".repeat(32)}`,
        basis: "snapshot",
        weightWindowBlocks: 0n,
        tokensPerTicket: 1n,
        maxTicketsPerHolder: 0n,
        winnersPerRound: 4,
        weights: treeFixture.leaves.map((leaf) => ({ holder: leaf.holder, weight: BigInt(leaf.tickets) })),
    });
    const seed = BigInt(slotFixture.seed);
    assert.deepEqual(slotFixture.indices, [0, 1, 2, 3].map((slot) => Number(raffleWinningIndex({
        chainId: BigInt(slotFixture.chainId),
        raffle: slotFixture.raffle,
        roundId: BigInt(slotFixture.roundId),
        slot,
        seed,
        totalTickets: BigInt(slotFixture.totalTickets),
    }))));
    const commit = decodeFunctionData({
        abi: projectRaffleV2Abi,
        data: encodeRaffleCommitCall({ round }).data,
    });
    assert.equal(commit.functionName, "commitRound");
    const claims = encodeRaffleClaimCalls({
        round,
        seed,
        slotsPaidMask: 1 << 1,
    });
    assert.equal(claims.length, 3);
    assert.ok(claims.every((call) => decodeFunctionData({
        abi: projectRaffleV2Abi,
        data: call.data,
    }).functionName === "claim"));
});
test("reconstructs window-minimum weights and excludes burn custody automatically", () => {
    const snapshot = reconstructRaffleSnapshot({
        snapshotBlock: 20n,
        snapshotBlockHash: `0x${"20".repeat(32)}`,
        totalSupply: 100n,
        basis: "min-balance",
        weightWindowBlocks: 15n,
        exclusions: [],
        transfers: [
            {
                blockNumber: 1n, transactionIndex: 0, logIndex: 0,
                from: "0x0000000000000000000000000000000000000000",
                to: "0x0000000000000000000000000000000000001000",
                value: 100n,
            },
            {
                blockNumber: 10n, transactionIndex: 0, logIndex: 0,
                from: "0x0000000000000000000000000000000000001000",
                to: "0x0000000000000000000000000000000000002000",
                value: 40n,
            },
            {
                blockNumber: 12n, transactionIndex: 0, logIndex: 0,
                from: "0x0000000000000000000000000000000000002000",
                to: "0x000000000000000000000000000000000000dEaD",
                value: 10n,
            },
        ],
    });
    assert.deepEqual(snapshot.weights, [
        { holder: "0x0000000000000000000000000000000000001000", weight: 60n },
    ]);
    assert.throws(() => reconcileRaffleSnapshots({
        primary: snapshot,
        secondary: { ...snapshot, snapshotBlockHash: `0x${"21".repeat(32)}` },
    }), /providers disagree/);
    assert.equal(buildVerifiedRaffleRound({
        chainId: 8453n,
        raffle: "0x0000000000000000000000000000000000003000",
        roundId: 1n,
        tokensPerTicket: 10n,
        maxTicketsPerHolder: 0n,
        winnersPerRound: 1,
        primarySnapshot: snapshot,
        secondarySnapshot: snapshot,
    }).commitment.totalTickets, 6n);
});
test("encodes exact retry and terminal round work without redirectable recipients", () => {
    const raffle = "0x0000000000000000000000000000000000003000";
    const holder = "0x0000000000000000000000000000000000004000";
    assert.equal(decodeFunctionData({
        abi: projectRaffleV2Abi,
        data: encodeRaffleRetryCall({ raffle, holder }).data,
    }).functionName, "deliverOwed");
    assert.equal(decodeFunctionData({
        abi: projectRaffleV2Abi,
        data: encodeRaffleRetryCall({
            raffle, holder, stockAsset: "0x0000000000000000000000000000000000005000",
        }).data,
    }).functionName, "deliverStockOwed");
    assert.deepEqual(decodeFunctionData({
        abi: projectRaffleV2Abi,
        data: encodeRaffleClaimOwedToCall({ raffle, payoutRecipient: holder }).data,
    }), { functionName: "deliverOwedTo", args: [holder] });
    assert.deepEqual(decodeFunctionData({
        abi: projectRaffleV2Abi,
        data: encodeRaffleClaimOwedToCall({
            raffle,
            payoutRecipient: holder,
            stockAsset: "0x0000000000000000000000000000000000005000",
        }).data,
    }), {
        functionName: "deliverStockOwedTo",
        args: ["0x0000000000000000000000000000000000005000", holder],
    });
    assert.equal(decodeFunctionData({
        abi: projectRaffleV2Abi,
        data: encodeRaffleCloseCall({ raffle, roundId: 1n, mode: "expire" }).data,
    }).functionName, "expireRound");
});
//# sourceMappingURL=raffle.test.js.map