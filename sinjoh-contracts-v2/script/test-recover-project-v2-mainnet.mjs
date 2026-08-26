#!/usr/bin/env node
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  CHAIN_ID,
  HISTORICAL_GAS_REPLAYS,
  LIVE_CREATE_GAS_REHEARSALS,
  RECOVERY_CONFIRMATION,
  RECOVERY_GAS_ESTIMATE_MULTIPLIER,
  assertGasMultiplier,
  assertCompleteJournal,
  assertArtifactIdentity,
  assertJournalPrefix,
  assertRecoveryArtifactsIdentity,
  authoritativeSingleReceipt,
  buildApprovalTree,
  buildActionPlan,
  plannedArtifactIdentity,
  runRecovery,
  safeNonceFromViews,
  writeOrValidateArtifact,
  validateJournalIdentity
} from "./recover-project-v2-mainnet.mjs";

const addresses = new Map();
const plan = buildActionPlan(9000n, (nonce) => {
  const address = `0x${nonce.toString(16).padStart(40, "0")}`;
  addresses.set(nonce, address);
  return address;
});

assert.equal(plan.length, 17);
assert.equal(plan.filter((action) => action.kind === "create").length, 13);
assert.equal(plan.filter((action) => action.kind === "call").length, 4);
assert.equal(plan[0].nonce, 9000);
assert.equal(plan[12].nonce, 9012);
assert.equal(plan[13].nonce, 9013);
assert.equal(plan[16].nonce, 9016);
assert.equal(plan[12].expectedAddress, addresses.get(9012n));
assert.equal(safeNonceFromViews({
  primaryPending: "7833",
  secondaryPending: "7833",
  primaryLatest: "7833",
  secondaryLatest: "7833"
}), 7833n);
assert.throws(() => safeNonceFromViews({
  primaryPending: "7834",
  secondaryPending: "7834",
  primaryLatest: "7833",
  secondaryLatest: "7833"
}), /pre-existing pending transaction/);
assert.throws(() => safeNonceFromViews({
  primaryPending: "7833",
  secondaryPending: "7834",
  primaryLatest: "7833",
  secondaryLatest: "7833"
}), /pending nonce differs between providers/);
assert.throws(() => safeNonceFromViews({
  primaryPending: "7833",
  secondaryPending: "7833",
  primaryLatest: "7833",
  secondaryLatest: "7832"
}), /latest nonce differs between providers/);
assert.equal(RECOVERY_GAS_ESTIMATE_MULTIPLIER, 200);
assert.equal(
  Math.max(...HISTORICAL_GAS_REPLAYS.map(({ sent, required }) => Math.ceil(required * 100 / sent))),
  115
);
assert.throws(() => assertGasMultiplier(160), /below the approved 200% recovery policy/);
assert.throws(() => assertGasMultiplier(126), /below the approved 200% recovery policy/);
assert.doesNotThrow(() => assertGasMultiplier(200));
for (const rehearsal of LIVE_CREATE_GAS_REHEARSALS) {
  assert.ok(
    Math.floor(rehearsal.estimateAt160 * RECOVERY_GAS_ESTIMATE_MULTIPLIER / 160)
      > rehearsal.requiredFloor
  );
}

const leaves = Array.from(
  { length: 8 },
  (_, index) => `0x${(index + 1).toString(16).padStart(64, "0")}`
);
const approvalTree = buildApprovalTree(leaves);
assert.match(approvalTree.root, /^0x[0-9a-f]{64}$/);
assert.equal(approvalTree.proofs.length, 8);
assert.ok(approvalTree.proofs.every((proof) => proof.length === 3));
assert.throws(() => buildApprovalTree([...leaves.slice(0, 7), leaves[0]]), /must be unique/);
assert.throws(() => buildApprovalTree(leaves.slice(0, 7)), /exactly eight/);

const journalHash = `0x${"ab".repeat(32)}`;
assert.throws(
  () => assertCompleteJournal(plan, { actions: {} }),
  /recovery journal is incomplete/
);
assert.doesNotThrow(() => assertCompleteJournal(
  plan,
  { actions: Object.fromEntries(plan.map(({ id }) => [id, { transactionHash: journalHash }])) }
));
assert.doesNotThrow(() => assertJournalPrefix(plan, {
  actions: Object.fromEntries(plan.slice(0, 3).map(({ id }) => [id, {}]))
}));
assert.throws(() => assertJournalPrefix(plan, {
  actions: { [plan[1].id]: {} }
}), /skips an earlier action/);

assert.doesNotThrow(() => validateJournalIdentity(
  plan[0],
  { nonce: 9000, transactionHash: journalHash, contractAddress: plan[0].expectedAddress },
  {}
));
assert.throws(
  () => validateJournalIdentity(
    plan[0],
    { nonce: 9001, transactionHash: journalHash, contractAddress: plan[0].expectedAddress },
    {}
  ),
  /journal nonce mismatch/
);

const orchestratorSource = readFileSync(
  new URL("./recover-project-v2-mainnet.mjs", import.meta.url),
  "utf8"
);
assert.doesNotMatch(orchestratorSource, /--rpc-url|private-key|PRIVATE_KEY/);
assert.doesNotMatch(orchestratorSource, /console\.(?:log|error)\([^\n]*(?:RPC_URL|ETH_RPC_URL|primary|secondary)/);
assert.match(orchestratorSource, /\["nonce", "--block", "pending", DEPLOYER\]/);
assert.match(orchestratorSource, /\["nonce", "--block", "latest", DEPLOYER\]/);

const artifactValue = { chainId: CHAIN_ID, actions: 17 };
const artifactDirectory = mkdtempSync(join(tmpdir(), "project-v2-recovery-test-"));
const artifactPath = join(artifactDirectory, "artifact.json");
assert.equal(writeOrValidateArtifact(artifactPath, artifactValue), "created");
assert.equal(writeOrValidateArtifact(artifactPath, artifactValue), "validated");
assert.doesNotThrow(() => assertArtifactIdentity(
  readFileSync(artifactPath, "utf8"), artifactValue
));
writeFileSync(artifactPath, `${JSON.stringify({ chainId: CHAIN_ID, actions: 16 })}\n`);
assert.throws(
  () => writeOrValidateArtifact(artifactPath, artifactValue),
  /does not exactly match recovered state/
);
const artifactJournal = {
  manifestPath: "/tmp/manifest.json",
  manifestSha256: "1".repeat(64)
};
assert.doesNotThrow(() => assertRecoveryArtifactsIdentity(artifactJournal, artifactJournal));
assert.throws(
  () => assertRecoveryArtifactsIdentity(
    artifactJournal,
    { ...artifactJournal, manifestSha256: "2".repeat(64) }
  ),
  /journaled recovery artifact identity/
);
rmSync(artifactDirectory, { recursive: true });
assert.throws(
  () => validateJournalIdentity(
    plan[0],
    { nonce: 9000, transactionHash: journalHash, contractAddress: plan[1].expectedAddress },
    {}
  ),
  /journal contractAddress mismatch/
);
assert.throws(
  () => validateJournalIdentity(plan[0], { nonce: 9000 }, {}),
  /transaction hash is missing or invalid/
);

const create = plan[0];
const authoritativeHash = `0x${"12".repeat(32)}`;
const artifactWithWrongTransactionHash = {
  chain: CHAIN_ID,
  transactions: [{
    hash: `0x${"34".repeat(32)}`,
    contractAddress: create.expectedAddress
  }],
  receipts: [{
    transactionHash: authoritativeHash,
    status: "0x1",
    contractAddress: create.expectedAddress,
    blockNumber: "0x123"
  }]
};
artifactWithWrongTransactionHash.transactions[0].transaction = {
  nonce: "0x2328",
  from: "0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49",
  to: null,
  input: "0x6000"
};
assert.equal(
  authoritativeSingleReceipt(artifactWithWrongTransactionHash, create).transactionHash,
  authoritativeHash
);
assert.equal(plannedArtifactIdentity(artifactWithWrongTransactionHash, create, {}), "0x6000");
assert.throws(
  () => plannedArtifactIdentity(
    {
      ...artifactWithWrongTransactionHash,
      transactions: [{
        ...artifactWithWrongTransactionHash.transactions[0],
        transaction: {
          ...artifactWithWrongTransactionHash.transactions[0].transaction,
          nonce: "0x2329"
        }
      }]
    },
    create,
    {}
  ),
  /artifact nonce mismatch/
);

assert.throws(
  () => authoritativeSingleReceipt(
    {
      ...artifactWithWrongTransactionHash,
      receipts: [{ ...artifactWithWrongTransactionHash.receipts[0], contractAddress: plan[1].expectedAddress }]
    },
    create
  ),
  /contractAddress mismatch/
);
assert.throws(
  () => authoritativeSingleReceipt(
    { ...artifactWithWrongTransactionHash, transactions: [{}, {}] },
    create
  ),
  /exactly one transaction/
);
assert.throws(
  () => authoritativeSingleReceipt(
    {
      ...artifactWithWrongTransactionHash,
      receipts: [{ ...artifactWithWrongTransactionHash.receipts[0], status: "0x0" }]
    },
    create
  ),
  /receipt failed/
);

const call = plan.at(-1);
assert.equal(
  authoritativeSingleReceipt(
    {
      chain: CHAIN_ID,
      transactions: [{ hash: `0x${"56".repeat(32)}` }],
      receipts: [{ transactionHash: authoritativeHash, status: "0x1", contractAddress: null }]
    },
    call
  ).transactionHash,
  authoritativeHash
);

assert.throws(
  () => runRecovery({ EXECUTE_PROJECT_V2_RECOVERY: "" }),
  new RegExp(`set EXECUTE_PROJECT_V2_RECOVERY=${RECOVERY_CONFIRMATION}`)
);

console.log("Project V2 receipt-gated recovery tests passed");
