# SinjohAirdropDistributor

An immutable-attestor sink that pushes funded assets directly to holders of a subject token. Holders do not sign, approve, or claim.

The distributor is standalone. Any EOA, treasury, or `SinjohFeeRouter` can create and fund its own isolated distribution account.

## Trust boundary

ERC-20 holders cannot be enumerated on-chain. An off-chain indexer computes deterministic holder snapshots and an immutable attestor commits them.

The attestor is trusted to:

- index the canonical chain correctly;
- wait for the configured confirmation depth;
- apply the specified snapshot algorithm;
- preserve each holder’s cumulative entitlement across epochs;
- keep its signing/calling authority secure.

The contract independently enforces:

- atomic funding attribution;
- Merkle-sum proof validity;
- total commitment no greater than total funding;
- strict epoch ordering and immutable roots;
- exclusion membership;
- monotonic per-holder payments;
- global liquid solvency.

An attestor can still underpay, omit, duplicate, or misweight a holder. It cannot commit a root whose verified total exceeds funded assets.

Operators who want a different trust boundary deploy another distributor with another immutable attestor.

## Deployment

Constructor immutables:

```solidity
constructor(address attestor, address protocolFeeRecipient);
```

`attestor` may be an EOA or a contract wallet such as a Safe. It cannot be changed.
`protocolFeeRecipient` is the immutable destination for the distributor's fixed 1%
funding fee and cannot be zero.

Robinhood Chain is an Arbitrum Orbit chain. Solidity `block.number` is the parent-chain estimate, while RPC `eth_blockNumber` is the L2 height. The distributor therefore uses the canonical `ArbSys` precompile at `0x0000000000000000000000000000000000000064`:

```solidity
interface IArbSys {
    function arbBlockNumber() external view returns (uint256);
    function arbBlockHash(uint256 arbBlockNum) external view returns (bytes32);
}
```

Epoch code must never compare an indexer’s L2 snapshot height with Solidity `block.number` or verify it with the `BLOCKHASH` opcode.

There is no owner, registry, upgrade, rescue role, or arbitrary call.

## Account identity

```text
accountId = keccak256(abi.encode(funder, subject, asset))
```

Every funder has an independent account for each `(subject, asset)` pair. One funder cannot configure, commit, spend, or strand another funder’s balance.

## Atomic funding

```solidity
interface ISinjohSink {
    function fund(
        address subject,
        address asset,
        uint256 amount,
        bytes calldata config
    ) external payable returns (uint256 received);
}
```

`msg.sender` is the funder.

For ERC-20:

1. `msg.value == 0`;
2. record distributor balance before;
3. `safeTransferFrom(msg.sender, address(this), amount)`;
4. record balance after;
5. require `received == amount`.

For native ETH:

- `asset == address(0)`;
- `msg.value == amount`;
- `received == amount`.

The distributor calculates `fee = received * 100 / 10_000`. The account's
`totalFunded` increases by the net amount, while `protocolOwed[asset]` increases by
the fee. `totalLiability[asset]` initially increases by the full measured receipt,
covering both obligations. `fund()` returns the gross measured receipt so it remains
compatible with fee-router sink accounting.

Anyone may call `sendProtocolFee(asset, amount)`, but delivery can only go to the
immutable `protocolFeeRecipient`. Successful delivery reduces both
`protocolOwed[asset]` and `totalLiability[asset]`.

A previous direct transfer cannot be claimed or attributed.

Fee-on-transfer and rebasing assets are unsupported.

## First-fund configuration

The first successful funding call decodes:

```solidity
struct Config {
    uint128 minPayout;
    uint16 maxBatchSize;
    uint16 minConfirmations;
    address[] exclusions;
}
```

Requirements:

- `minPayout > 0`;
- `maxBatchSize` is within a protocol constant;
- `minConfirmations` is nonzero and at most 255;
- exclusions are sorted, unique, nonzero, and at most 32 entries.

The distributor automatically excludes:

- `address(0)`;
- `0x000000000000000000000000000000000000dEaD`;
- the distributor;
- the funder.

The configured list normally adds:

- subject/quote pools;
- launchpad curves and hooks;
- lockers;
- vesting, treasury, or escrow contracts that must not receive holder distributions.

The complete set and `configHash` are frozen for this account. Every later `fund()` must supply the same canonical configuration hash.

Configuration is account-scoped. An unrelated first funder cannot freeze exclusions or floors for other funders.

## Epoch commitment

```solidity
struct EpochCommitment {
    bytes32 rootHash;
    uint256 rootSum;
    uint64 snapshotBlock;
    bytes32 snapshotBlockHash;
}

function commitEpoch(
    address funder,
    address subject,
    address asset,
    uint64 epochId,
    uint64 snapshotBlock,
    bytes32 snapshotBlockHash,
    bytes32 rootHash,
    uint256 rootSum
) external; // onlyAttestor
```

Rules:

1. the funding account must exist;
2. `epochId == latestEpochId + 1`;
3. snapshot block strictly increases;
4. `ArbSys.arbBlockNumber() >= snapshotBlock + minConfirmations`;
5. `ArbSys.arbBlockNumber() <= snapshotBlock + 255`;
6. `ArbSys.arbBlockHash(snapshotBlock) == snapshotBlockHash`;
7. root hash and root sum are nonzero;
8. root sum is no less than the previous epoch’s root sum;
9. root sum is no greater than `totalFunded`;
10. the commitment is written once and can never be replaced.

The 255-L2-block window makes the snapshot hash verifiable through `ArbSys`. The operator must select a confirmation depth appropriate to Robinhood Chain and commit before the L2 hash expires.

A reorganization deeper than the configured depth remains an explicit attestor risk. The reference operator must compare the snapshot hash through at least two independent RPC providers before committing.

## Merkle-sum tree

Each leaf commits both a hash and a sum:

```text
leafHash = keccak256(
    abi.encode(
        keccak256("SINJOH_AIRDROP_LEAF_V1"),
        block.chainid,
        address(distributor),
        accountId,
        epochId,
        snapshotBlock,
        holder,
        cumulativeAmount
    )
)

leafSum = cumulativeAmount
```

Internal nodes are direction-aware:

```text
nodeHash = keccak256(
    abi.encode(
        keccak256("SINJOH_AIRDROP_NODE_V1"),
        leftHash,
        leftSum,
        rightHash,
        rightSum
    )
)

nodeSum = leftSum + rightSum
```

Proof elements contain:

```solidity
struct ProofElement {
    bytes32 siblingHash;
    uint256 siblingSum;
    bool siblingIsLeft;
}
```

Verification reconstructs both `rootHash` and `rootSum`. Checked arithmetic is required for every sum.
Each proof is capped at 64 elements.

This prevents a root from hiding individual entitlements whose aggregate exceeds the committed and funded total.

## Deterministic indexer algorithm

For every epoch:

1. Select a canonical snapshot block that has reached the configured confirmation depth.
   The block number is the RPC/L2 height returned by `eth_blockNumber`, which must equal `ArbSys.arbBlockNumber()` at the same head.
2. Reconstruct raw subject-token balances from `Transfer` events from deployment through that block.
3. Cross-check total reconstructed supply against `totalSupply()` at the snapshot block.
4. Remove every immutable excluded address.
5. Compute `eligibleSupply` as the sum of remaining raw balances.
6. Select a new `rootSum` no greater than `totalFunded`.
7. Compute `epochBudget = rootSum - previousRootSum`.
8. Allocate the epoch budget pro-rata using raw balances:

   ```text
   baseDelta(holder) = floor(epochBudget * rawBalance(holder) / eligibleSupply)
   ```

9. Assign the remaining raw units, one per holder in ascending address order, until the epoch budget is exhausted.
10. Add each delta to the holder’s previous cumulative entitlement.
11. Preserve leaves for previously entitled holders even if their current balance is zero.
12. Produce exactly one leaf per holder, sorted by address.
13. Assert off-chain that leaf sums equal `rootSum`.
14. Store the complete leaf set, proofs, snapshot block/hash, eligible supply, budget, rounding residual, and software version.

If `eligibleSupply == 0`, no epoch may be committed.

Balances and entitlements use raw units. ERC-8056 UI multipliers are never applied to holder weights.

## Push

```solidity
struct Leaf {
    address holder;
    uint256 cumulativeAmount;
}

function push(
    address funder,
    address subject,
    address asset,
    uint64 epochId,
    Leaf[] calldata leaves,
    ProofElement[][] calldata proofs
) external;
```

`push()` is permissionless.

Batch requirements:

- nonempty and no larger than the account’s immutable maximum;
- leaves and proofs have equal length;
- holders are strictly ascending and therefore unique;
- every proof is valid against the selected epoch’s hash and sum;
- no holder is excluded.

An invalid proof reverts the whole batch before any payment attempt. Proof failure is not described as a per-leaf revert.

After all proofs validate, each leaf is processed:

```text
delta = max(cumulativeAmount - paid[accountId][holder], 0)
```

- zero delta is skipped;
- delta below `minPayout` is skipped and remains payable later;
- otherwise payment is attempted through an isolated external self-call.

## Transfer-failure isolation

The outer `push()` calls an `onlySelf` payment function for one holder:

```solidity
function _pay(
    bytes32 accountId,
    address holder,
    uint256 cumulativeAmount
) external; // onlySelf
```

The inner call:

1. rechecks delta and exclusion;
2. updates `paid` and `totalPaid`;
3. transfers ETH or ERC-20;
4. verifies the distributor’s exact balance decrease;
5. decreases `totalLiability[asset]` by the exact amount paid;
6. asserts `totalPaid <= latestRootSum <= totalFunded`.

If the transfer reverts, all inner state and aggregate-liability changes roll back.
The outer call catches the failure, emits `PaymentFailed`, and continues to the next
already-validated leaf.

The outer function is reentrancy-guarded. The inner function is callable only by the distributor itself.

## Cumulative behavior

`paid[accountId][holder]` is lifetime paid value.

Consequences:

- old proofs cannot double-pay;
- a missed epoch is absorbed by a later cumulative root;
- dust below the floor accumulates;
- pushing the same valid batch twice pays zero the second time;
- holders can be pushed in arbitrary batches and epochs.

The attestor must never decrease a holder’s cumulative entitlement. The contract cannot efficiently prove cross-root per-holder monotonicity without a zero-knowledge state-transition proof; this remains an explicit attestor obligation.

An incorrect overpayment cannot be clawed back. A later epoch may correct an underpayment but cannot reverse value already transferred.

## Solvency

For every asset:

```text
totalLiability[asset]
  = sum(totalFunded[accounts for asset] - totalPaid[accounts for asset])
  + protocolOwed[asset]

balance(distributor, asset) >= totalLiability[asset]
```

This is conservative because uncommitted funding remains a liability.
The sum defines the invariant; execution uses the constant-time aggregate and never
enumerates accounts. Committing an epoch changes no liability.

For every account:

```text
totalPaid <= latestRootSum <= totalFunded
```

No account may use another account’s uncommitted or unpaid funding even when both use the same ERC-20.

## Floor

`minPayout` is an immutable raw amount for one funding account.

It is not an ETH or USD equivalent. Operators choose it before first funding and must display:

- asset decimals;
- raw floor;
- current approximate display value;
- warning that market value can change.

Changing a floor requires a new funding account, normally a new funder/router address or distributor deployment.

## Liveness and permanent failure

Version one holds no gas reserve and does not reimburse callers.

If:

- no epoch is committed, funding remains uncommitted;
- nobody calls `push`, entitlements remain pending;
- a recipient cannot accept the asset, its payment remains pending;
- the attestor disappears permanently, uncommitted and future value remains stranded.

There is no timeout sweep, refund, fallback recipient, or admin recovery. Value earmarked for holders is never redirected.

## Events and indexer contract

The contract must emit enough information to reproduce all state:

- `AccountConfigured`;
- `Funded`;
- `EpochCommitted`;
- `PaymentSucceeded`;
- `PaymentFailed`.

The reference indexer publishes a versioned GraphQL schema with:

- account configuration and exclusions;
- funding history and `totalFunded`;
- epoch metadata, root hash/sum, snapshot block/hash, and algorithm version;
- complete sorted leaves and Merkle-sum proofs;
- `paid` and `totalPaid`;
- pending delta and floor eligibility;
- failed-payment history.

The ABI, entity schema, GraphQL queries, and deterministic rounding fixtures are part of the implementation repository and its compatibility tests.

Envio HyperIndex 3.2.1 is the initial reference implementation. It may use HyperSync or redundant RPC sources. A provider name never appears in the contract.

## ERC-8056

- weights use raw `balanceOf`;
- funding, commitments, floors, and payments use raw units;
- `uiMultiplier()` is a display-only concern;
- optional ERC-8056 events are not required for balance reconstruction.

Core execution never calls ERC-8056 interfaces.

## Security requirements

- Reentrancy guard on funding and push.
- Fixed 1% funding fee with an immutable recipient and permissionless exact delivery.
- Exact balance-delta verification.
- Account-scoped funding and payment accounting.
- Domain-separated, direction-aware Merkle-sum proofs.
- Checked sum arithmetic.
- Strict epoch and snapshot ordering.
- Snapshot block-hash verification inside the EVM history window.
- L2 block number and hash reads exclusively through Robinhood’s `ArbSys` precompile.
- Whole-batch proof validation before payment attempts.
- External self-call isolation for recipient transfer failures.
- No arbitrary target, sweep, rescue, root replacement, or attestor change.
- Standard non-rebasing ERC-20 allowlist at the integration layer.

## Required tests

1. A separate ERC-20 transfer cannot be claimed as funding.
2. A front-runner cannot steal another funder’s attribution.
3. Fee-on-transfer funding reverts without credit.
4. One funder cannot spend another account’s balance.
5. A root sum above total funding reverts.
6. A proof with a falsified sibling sum or direction reverts.
7. Invalid proof reverts before any payment.
8. Recipient transfer failure rolls back only that recipient’s payment.
9. Duplicate or unsorted holders revert.
10. Old roots and repeated batches cannot double-pay.
11. Below-floor entitlement carries into later epochs.
12. Replaced, skipped, or nonmonotonic epoch IDs revert.
13. Wrong or expired snapshot block hashes revert.
14. Supplying the parent-chain `block.number` domain in place of the L2 height reverts.
15. Reconstructed leaf sums equal committed root sums for fixed fixtures.
16. Raw ERC-8056 balance fixtures remain unaffected by multiplier changes.
17. Protocol fees are exactly 1% of measured funding and cannot be redirected.
18. Invariant: per-asset liabilities never exceed balances.
19. Invariant: `totalPaid <= latestRootSum <= totalFunded`.
20. Invariant: aggregate liabilities equal account liabilities plus protocol fees.

## Standalone verification

1. Compiles and deploys in a repository containing only itself and standard libraries.
2. Imports no other Sinjoh contract.
3. Works when funded directly by an EOA.
4. Supports any standard ERC-20 subject/asset pair.
5. Its complete indexer compatibility suite runs without a `SinjohFeeRouter`.
