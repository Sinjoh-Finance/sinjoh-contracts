# SinjohRaffleRewards

An immutable per-launch raffle that pays a prize asset to holders of one subject
token, selected by verifiable randomness in proportion to whole tickets held.

```text
tickets(holder) = floor(weight(holder) / tokensPerTicket)
```

The reference configuration sets `tokensPerTicket` to 10,000 whole subject tokens,
so a holder of 35,000 tokens holds three tickets and a holder of 9,999 holds none.

The raffle is standalone. Any EOA, treasury, fee router, or platform fee process
can deposit the prize asset. It imports no other Sinjoh contract, has no owner,
no upgrade path, no rescue role, and no arbitrary call.

## Why holders cannot be enumerated on-chain

An ERC-20 has no holder set. The raffle therefore uses the same trust boundary as
`SinjohAirdropDistributor`: an off-chain indexer reconstructs a deterministic
snapshot and an immutable attestor commits it as a Merkle-sum root of ticket
counts.

The attestor is trusted to:

- index the canonical chain correctly;
- wait for the configured confirmation depth;
- apply the deterministic ticket algorithm in this document;
- apply the immutable exclusion set;
- keep its calling authority secure.

The contract independently enforces:

- the snapshot block hash, depth, and strict ordering;
- one immutable, unreplaceable commitment per round;
- that randomness is requested only after the root is written;
- that the winning ticket index is inside the committed total;
- that a claimed leaf's ticket interval, derived from its own proof, contains the
  winning index;
- that every round pays at most its reserved prize, exactly once per slot;
- global solvency of the prize asset.

An attestor can still misweight, omit, or duplicate a holder inside the tree. It
cannot pay more than the reserved prize, cannot commit a root after seeing the
randomness, and cannot direct value to an address the proof does not select.
Operators who want a different boundary deploy another raffle with another
attestor.

## Deployment and binding

Instances are EIP-1167 clones created with `CREATE2` and initialized atomically by
`SinjohRaffleRewardsFactory`, matching `SinjohPonsV1Adapter` and
`SinjohFeeRouter`.

The raffle address must exist before the subject token, because a launch flow
names the raffle as a fee destination while creating the token. The factory
therefore predicts the clone address from creator, salt, chain ID, implementation,
factory, and canonical configuration hash, with `subject` encoded as zero.

```solidity
function predictRaffle(address creator, bytes32 salt, bytes32 configHash)
    external view returns (address raffle);

function deployRaffle(bytes32 salt, Config calldata config)
    external returns (address raffle);

function bind(address subject) external; // creator-only, once
```

Rules:

- deployment chain ID must equal the configured chain ID (`4663` for Robinhood
  Chain mainnet);
- reusing a salt with a different configuration reverts;
- `bind` is callable once by the immutable creator and only with a nonzero
  contract address that is not the prize asset;
- no round may be committed and no funding may be attributed before binding;
- deposits received before binding are creditable by `sync()` after binding.

Robinhood Chain is an Arbitrum Orbit chain. Solidity `block.number` is the
parent-chain estimate. Every L2 height and block hash is read through the
canonical `ArbSys` precompile at
`0x0000000000000000000000000000000000000064`:

```solidity
interface IArbSys {
    function arbBlockNumber() external view returns (uint256);
    function arbBlockHash(uint256 arbBlockNum) external view returns (bytes32);
}
```

Snapshot code must never compare an indexer's L2 height with Solidity
`block.number` or verify it with the `BLOCKHASH` opcode.

## Configuration

Frozen at initialization. There is no setter for any field.

```solidity
enum TicketBasis {
    SNAPSHOT,          // raw balance at the snapshot block
    MIN_BALANCE        // minimum raw balance across the weight window
}

struct Config {
    address creator;
    address attestor;
    address randomness;            // immutable randomness adapter
    address prizeAsset;            // address(0) = native ETH
    address protocolFeeRecipient;
    address taxRecipient;          // required when recipientTaxBps != 0
    uint128 tokensPerTicket;       // raw subject units per ticket
    uint128 maxTicketsPerHolder;   // 0 = uncapped
    uint128 minPrize;              // raw prize units
    uint128 maxPrize;              // 0 = unbounded
    uint16  prizeBps;              // share of the available pool per round
    uint16  recipientTaxBps;       // tax share delivered to taxRecipient
    uint16  recycleTaxBps;         // tax share returned to the prize pool
    uint16  minConfirmations;
    uint8   winnersPerRound;
    uint32  minRoundInterval;      // seconds between commitments
    uint32  weightWindowBlocks;    // required when basis == MIN_BALANCE
    uint32  randomnessTimeout;     // seconds before a pending round is abandonable
    uint32  claimWindow;           // seconds after the draw
    TicketBasis basis;
    address[] exclusions;          // sorted, unique, nonzero, <= 32
}
```

Bounds, enforced at initialization:

| Field | Rule |
|---|---|
| `tokensPerTicket` | nonzero |
| `prizeBps` | 1 to 10,000 |
| `recipientTaxBps + recycleTaxBps` | 0 to `MAX_PAYOUT_TAX_BPS` (5,000) |
| `minPrize` | nonzero |
| `maxPrize` | zero, or at least `minPrize` |
| `winnersPerRound` | 1 to 16 |
| `minRoundInterval` | 600 to 604,800 seconds |
| `minConfirmations` | 1 to 255 |
| `weightWindowBlocks` | zero for `SNAPSHOT`; 1 to 1,000,000 for `MIN_BALANCE` |
| `randomnessTimeout` | 900 to 86,400 seconds |
| `claimWindow` | 3,600 to 2,592,000 seconds |
| `exclusions` | sorted ascending, unique, nonzero, at most 32 |
| addresses | attestor, randomness, protocol fee recipient nonzero; tax recipient nonzero when `recipientTaxBps != 0` |

`configHash` is `keccak256` of the canonical encoding with `subject` as zero. It is
stored and used by `fund()`.

The raffle always excludes `address(0)`,
`0x000000000000000000000000000000000000dEaD`, itself, and the bound subject token.
The configured list normally adds pools, launchpad curves and hooks, lockers,
vesting, treasury, and escrow contracts.

Reference launch values for an hourly raffle:

```text
tokensPerTicket   = 10_000 * 10**18
prizeBps          = 500          // 5% of the available pool each hour
winnersPerRound   = 1
minRoundInterval  = 3600
basis             = MIN_BALANCE
weightWindowBlocks= one hour of L2 blocks
recipientTaxBps   = as chosen before launch
recycleTaxBps     = as chosen before launch
randomnessTimeout = 3600         // seal is the only deadline; the rest can wait
claimWindow       = 604800
```

At 5% per round, roughly half of an unreplenished pool is paid out over 14 rounds.
The prize is a share of the pool, never a fixed obligation, so the raffle cannot
become insolvent through configuration alone.

## Deposits

The prize asset is a single immutable asset. A second asset requires a second
deployment.

### Attributed funding

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

Requirements:

- `subject` equals the bound subject;
- `asset` equals `prizeAsset`;
- `config` is empty or hashes to `configHash`;
- ERC-20: `msg.value == 0`, measure balance before, `safeTransferFrom`, measure
  after, require `received == amount`;
- native: `asset == address(0)`, `msg.value == amount`.

This makes the raffle a valid `SinjohFeeRouter` sink allocation without the router
importing it.

### Unattributed deposits

Platform fees, creator top-ups, and donations may arrive as an ordinary transfer.
The raffle accepts native ETH through `receive()` when the prize asset is native,
and accepts ERC-20 transfers by construction.

```solidity
function sync() external returns (uint256 credited, uint256 fee);
```

`sync()` is permissionless. It credits the entire unaccounted balance — the
balance above all recorded liabilities — into the prize pool. There is no funder
identity, because a raffle prize has no per-funder ownership. This is the deposit
account the platform fee process targets.

Attribution is still never inferred: `fund()` credits a measured receipt inside its
own call, and `sync()` credits only value that is provably not already a liability.

### Protocol fee

Consistent with the rest of the family, the raffle charges a fixed cumulative 1% on
measured intake through both paths:

```text
protocolOwed advances so that
protocolOwed + protocolPaid == floor(cumulativeIntake * 100 / 10_000)
```

Splitting deposits across transactions cannot reduce it. Delivery is
permissionless and can only reach the immutable recipient:

```solidity
function sendProtocolFee(uint256 amount) external;
```

Fee-on-transfer and rebasing assets are unsupported as prize or subject assets.

## Round lifecycle

```text
COMMITTED --(randomness delivered)--> DRAWN --(claims)--> SETTLED
    |                                   |
    | randomnessTimeout                 | claimWindow
    v                                   v
 ABANDONED                           EXPIRED
```

Up to `MAX_PENDING_ROUNDS` (4) rounds may be `COMMITTED` at once, so one stalled
randomness request does not halt the raffle. Every round holds its own reserve.

### 1. Commit

```solidity
function commitRound(
    uint64 roundId,
    uint64 snapshotBlock,
    bytes32 snapshotBlockHash,
    bytes32 rootHash,
    uint256 totalTickets
) external returns (uint256 prize); // onlyAttestor
```

Rules:

1. the subject is bound;
2. `roundId == latestRoundId + 1`;
3. `snapshotBlock` strictly exceeds the previous round's;
4. `block.timestamp >= lastCommitAt + minRoundInterval`, except for the first
   round, which has no previous commitment to measure from;
5. `ArbSys.arbBlockNumber() >= snapshotBlock + minConfirmations`;
6. `ArbSys.arbBlockNumber() <= snapshotBlock + 255`;
7. `ArbSys.arbBlockHash(snapshotBlock) == snapshotBlockHash`;
8. `rootHash != 0` and `totalTickets != 0`;
9. fewer than `MAX_PENDING_ROUNDS` rounds are `COMMITTED`;
10. the computed prize is at least `minPrize`;
11. the commitment is written once and can never be replaced.

The prize is fixed at commit time, before randomness exists:

```text
prize = min(maxPrize or infinity, floor(availablePool * prizeBps / 10_000))
require prize >= minPrize
availablePool -= prize
reserved[roundId] = prize
```

Freezing the prize at commit removes any incentive to time a deposit against a
known outcome, and makes the payout independent of later deposits or claims.

The same transaction requests randomness from the immutable adapter and stores the
returned `requestId`. A commitment without a request is not possible, and a
request cannot precede a root.

The 255-L2-block hash window is short on a fast Orbit chain. The worker must pick
`minConfirmations` so that commitment lands well inside it, and the interface must
treat a missed window as a skipped round, never as a reason to reuse a stale
snapshot.

### 2. Draw

```solidity
function receiveRandomness(bytes32 requestId, uint256 seed) external; // onlyRandomness
```

Rules:

- `msg.sender` is the immutable adapter;
- `requestId` maps to a `COMMITTED` round;
- the round has not already been drawn or abandoned;
- `seed != 0`;
- the round is written once; a second delivery for the same `requestId` reverts.

Winning indices are derived from the single seed:

```text
index(k) = uint256(
    keccak256(abi.encode(SINJOH_RAFFLE_SLOT_V1, chainid, raffle, roundId, k, seed))
) % totalTickets
```

for `k` in `[0, winnersPerRound)`. Modulo bias is negligible because
`totalTickets` is many orders of magnitude below `2**256`; it is stated rather than
mitigated.

Slots are independent. The same holder may win more than one slot in a round, in
proportion to their tickets. This is deliberate: removing replacement would either
bias the distribution or require unbounded on-chain rejection sampling.

Slot prizes:

```text
slotPrize = prize / winnersPerRound
slot 0 additionally receives prize % winnersPerRound
```

`receiveRandomness` performs no transfer and calls nothing external, so a
randomness adapter can never be a reentrancy path into payment.

### 3. Claim

```solidity
struct Leaf {
    address holder;
    uint256 tickets;
}

struct ProofElement {
    bytes32 siblingHash;
    uint256 siblingSum;
    bool siblingIsLeft;
}

function claim(
    uint64 roundId,
    uint8 slot,
    Leaf calldata leaf,
    ProofElement[] calldata proof
) external returns (uint256 paid);
```

`claim()` is permissionless — a keeper, an interface, or the winner may submit it.
Payment always goes to `leaf.holder`.

Rules:

1. the round is `DRAWN` and `block.timestamp <= drawnAt + claimWindow`;
2. `slot < winnersPerRound` and the slot is unpaid;
3. `leaf.tickets != 0` and `leaf.holder` is not excluded;
4. `proof.length <= 64`;
5. proof verification reconstructs `rootHash` equal to the committed root and
   `rootSum` equal to the committed `totalTickets`;
6. the offset derived from the proof satisfies
   `offset <= index(slot) < offset + leaf.tickets`.

The slot is marked paid before any transfer.

### 4. Expiry and abandonment

```solidity
function expireRound(uint64 roundId) external;   // after drawnAt + claimWindow
function abandonRound(uint64 roundId) external;  // after committedAt + randomnessTimeout
```

Both are permissionless. Each returns the round's unpaid reserve to the available
pool and closes the round permanently.

An abandoned round can never be re-requested or re-committed. Randomness for one
snapshot is requested exactly once, so no party can re-roll a snapshot by
withholding a fulfillment and asking again. A later round takes a fresh snapshot,
a fresh root, and a fresh request.

There is no sweep, refund path, fallback recipient, or admin recovery. Unclaimed
value returns to the same prize pool it came from and is never redirected.

## Ticket-interval Merkle-sum tree

Leaves are sorted ascending by holder, one leaf per eligible holder, `tickets`
nonzero:

```text
leafHash = keccak256(
    abi.encode(
        keccak256("SINJOH_RAFFLE_LEAF_V1"),
        block.chainid,
        address(raffle),
        roundId,
        snapshotBlock,
        holder,
        tickets
    )
)

leafSum = tickets
```

The leaf set is padded to a power of two with:

```text
emptyHash = keccak256(abi.encode(keccak256("SINJOH_RAFFLE_EMPTY_V1"), roundId))
emptySum  = 0
```

Internal nodes are direction-aware:

```text
nodeHash = keccak256(
    abi.encode(
        keccak256("SINJOH_RAFFLE_NODE_V1"),
        leftHash, leftSum, rightHash, rightSum
    )
)

nodeSum = leftSum + rightSum
```

Verification walks the proof from the leaf and accumulates three values:

```text
hash   -> must equal the committed rootHash
sum    -> must equal the committed totalTickets
offset -> sum of every left sibling's sum encountered on the path
```

`offset` is the leaf's ticket-interval start. It is **derived**, not committed in
the leaf, so a valid sum tree partitions `[0, totalTickets)` into disjoint,
contiguous intervals by construction. Two different leaves cannot both contain one
index, and no index inside the total can be unreachable. A malformed root cannot
create overlapping intervals that pay one slot twice, because a slot pays once
regardless.

All sum arithmetic is checked. Padding leaves carry zero tickets and therefore own
an empty interval that no index can select.

## Payment and tax

Payment for one slot happens through an isolated external self-call, matching the
distributor's failure isolation:

```solidity
function _payWinner(
    uint64 roundId,
    uint8 slot,
    address holder,
    uint256 slotPrize
) external; // onlySelf
```

The inner call:

1. computes the two tax shares and the winner's net:

   ```text
   recipientTax = floor(slotPrize * recipientTaxBps / 10_000)
   recycleTax   = floor(slotPrize * recycleTaxBps   / 10_000)
   net          = slotPrize - recipientTax - recycleTax
   ```

2. increases `taxOwed` by `recipientTax` and the available pool by `recycleTax`;
3. decreases `reserved[roundId]` by `slotPrize`;
4. transfers `net` to the holder;
5. verifies the raffle's balance decreased by exactly `net`;
6. asserts the round's paid total never exceeds its committed prize.

If the transfer reverts, every inner state change rolls back and the outer call
credits `owed[holder] += net`, emits `PaymentDeferred`, and still marks the slot
settled. Deferred value is delivered later by anyone:

```solidity
function deliverOwed(address holder) external returns (uint256 amount);
function sendTax(uint256 amount) external;
```

Neither call lets the caller choose a destination. `sendTax` can only reach the
immutable `taxRecipient`; with a zero recipient share `taxOwed` never accrues, so
the call has nothing to deliver.

Both shares apply to the gross slot prize, before the winner's transfer, and each
is floored independently so neither can round into the other. Any rounding dust
stays with the winner.

The two shares are independent, so a launch can deliver part of the tax and
recycle the rest — a 10% tax configured as 700/300 sends 7% of every prize to the
recipient and returns 3% to the pool. Setting one share to zero gives the pure
delivery or pure self-sustaining behavior.

Recycling slows the pool's decay. At `prizeBps = 500` with 300 bps recycled, 5% of
the pool leaves each round and 0.15% returns, so the effective drain is 4.85% and
the pool's half-life stretches from about 13.5 rounds to about 14. Every recycled
unit is still paid to a holder, just in a later round.

Combined with the 1% intake fee, an interface must display the effective take:

```text
winner receives =
    deposit * 0.99
    * prizeBps-derived share
    * (1 - (recipientTaxBps + recycleTaxBps) / 10_000)
```

Interfaces must show both tax shares in basis points, the prize asset decimals,
and the current approximate display value, with an explicit note that a
configured tax is immutable for the life of the deployment. `MAX_PAYOUT_TAX_BPS`
is deliberately permissive at 5,000 so an unusual reward design does not require a
new implementation; a launch configuring anything near it must surface that
prominently, because half of every prize never reaches the winner.

## Randomness

Randomness is not built into the raffle. It is an immutable adapter address chosen
before deployment.

```solidity
interface ISinjohRaffleRandomness {
    function requestRandomness(uint64 roundId) external returns (bytes32 requestId);
}

interface ISinjohRandomnessConsumer {
    function receiveRandomness(bytes32 requestId, uint256 seed) external;
}
```

Adapter requirements, normative for any adapter used with this raffle:

1. `requestId` is unique per `(consumer, roundId)` and never reused;
2. the adapter records the calling consumer and delivers only to that address;
3. exactly one delivery per request succeeds;
4. the delivered seed is unpredictable to the consumer, the attestor, the caller,
   and any observer at request time;
5. the seed does not depend on block hash, timestamp, coinbase, `prevrandao`, or
   any value a keeper, sequencer, or attestor can grind;
6. delivery costs are paid by the adapter's own funding, never from the prize pool;
7. an adapter may serve many raffles.

An adapter that cannot satisfy (4) and (5) must not be used. `blockhash`,
`ArbSys.arbBlockHash`, and `block.prevrandao` are explicitly rejected: on an Orbit
chain the sequencer determines all three, and the attestor chooses commit timing.

### Chainlink VRF is not deployed on Robinhood Chain

Verified July 2026: Chainlink on Robinhood Chain mainnet covers CCIP, Data
Streams, and Data Feeds. Chainlink VRF v2.5's supported-network list is Ethereum,
Arbitrum, Base, OP, Polygon, BNB Chain, Avalanche, Ronin, and Soneium. Chain
`4663` is not on it.

A deployment script must therefore never assume a local VRF coordinator, and this
implementation must not import `VRFConsumerBaseV2Plus`.

### Selected adapter: on-chain ECVRF

The release configuration uses `SinjohEcvrfRandomness`, specified in
[`sinjoh-randomness`](../sinjoh-randomness/SPEC.md). A secp256k1 ECVRF proof is
verified on-chain against one immutable public key. There is no oracle network, no
second chain, and no subscription; settlement is seconds.

What the raffle depends on, and nothing more:

1. `requestRandomness(roundId)` records a request and makes **no external call and
   spends no value**, so `commitRound` cannot fail on the adapter's state;
2. `receiveRandomness(requestId, seed)` arrives later, from the immutable adapter
   address only, at most once per request;
3. the seed is unpredictable to the attestor, the creator, any holder, and the
   raffle at commit time;
4. delivery may never arrive, which is what `randomnessTimeout` and `abandonRound`
   exist for.

The adapter secures point (3) by binding its proof input to the hash of the block
the request landed in. Because `requestRandomness` is called from inside
`commitRound`, that is the hash of the block containing the commitment itself,
which nobody can know while building the transaction. The attestor therefore cannot
choose a root against a known output, and the key holder cannot precompute an
output for a future round.

Settlement has one hard deadline: the adapter's `seal` must run inside the L2's
255-block hash window, which on a fast Orbit chain may be about a minute. A missed
seal kills that round's randomness permanently and the round abandons. Everything
after sealing is unbounded in time, so `randomnessTimeout = 3,600` gives an hourly
raffle a full round to recover from a prover outage.

### The residual, and who carries it

The adapter's key holder computes the outcome before anyone else once the input is
sealed, and can decline to publish, forcing this round to abandon. Re-rolling
across rounds is cheap: the reserve returns to the pool and the only evidence is a
round that failed to settle.

Two obligations follow for any operator of this protocol:

- the ECVRF key must not be held by the party that also runs the attestor.
  Together they would permit offline grinding, which the block-hash binding
  otherwise prevents;
- `RoundAbandoned` events are public and must be monitored. A rate materially above
  the chain's own failure rate is the signal that rounds are being re-rolled.

An interface built on this protocol must disclose that residual. The raffle
contract cannot detect or prevent it.

## Deterministic worker algorithm

Once per `minRoundInterval`, for round `n`:

1. Select a candidate snapshot block at the configured confirmation depth, read as
   the L2 height from `eth_blockNumber`, which must equal `ArbSys.arbBlockNumber()`
   at the same head.
2. Verify the snapshot block hash through at least two independently operated RPC
   endpoints.
3. Reconstruct raw subject balances from `Transfer` logs from the deployment block
   through the snapshot block.
4. Cross-check reconstructed supply against `totalSupply()` at that block.
5. Under `MIN_BALANCE`, additionally compute each holder's minimum raw balance over
   `[snapshotBlock - weightWindowBlocks, snapshotBlock]` from the same log stream.
6. Remove every excluded address, including the automatic exclusions.
7. Compute `tickets = floor(weight / tokensPerTicket)`, then apply
   `maxTicketsPerHolder` when nonzero.
8. Drop holders with zero tickets.
9. Sort remaining holders ascending by address; assert uniqueness.
10. Compute `totalTickets` as the checked sum of leaf tickets.
11. Build the padded, direction-aware Merkle-sum tree; assert the root sum equals
    `totalTickets`.
12. Persist the complete leaf set, all proofs, snapshot block and hash, weight
    basis, window, ticket size, cap, and algorithm version, plus a deterministic
    content hash of the artifact.
13. Commit with the attestor signer, inside the confirmation and 255-block window.
14. After `RandomnessReceived`, compute each slot's index, locate the owning leaf
    by interval, and submit `claim` for each slot.
15. Reconcile `PrizePaid`, `PaymentDeferred`, `RoundExpired`, and `RoundAbandoned`.

If `totalTickets == 0` the round is skipped and no commitment is made. A skipped
round consumes no reserve.

Balances and tickets use raw units. ERC-8056 UI multipliers are never applied to
ticket weights; `uiMultiplier()` is display-only and core execution never calls
ERC-8056 interfaces.

`MIN_BALANCE` is the default basis because a point snapshot lets an address borrow
or buy a balance in the snapshot block and sell immediately afterwards. A minimum
over the round window makes that attack cost a full window of exposure. The
contract cannot verify which basis was applied; it is an attestor obligation, and
the basis is published in the immutable configuration so any observer can recompute
the tree and detect a deviation.

## Solvency

For the prize asset:

```text
balance(raffle) >=
      availablePool
    + sum(reserved[round] for open rounds)
    + totalOwed
    + protocolOwed
    + taxOwed
```

Per round:

```text
paid[round] <= reserved-at-commit[round]
```

Execution maintains constant-time aggregates and never enumerates rounds or
holders. Every unit held by the raffle belongs to exactly one of: available pool,
a round reserve, a deferred winner credit, protocol fees, or payout tax.

## Events

```solidity
event RaffleInitialized(bytes32 configHash, address creator, address randomness);
event SubjectBound(address indexed subject);
event Deposited(address indexed source, uint256 gross, uint256 fee, uint256 net, bool attributed);
event RoundCommitted(uint64 indexed roundId, uint64 snapshotBlock, bytes32 snapshotBlockHash, bytes32 rootHash, uint256 totalTickets, uint256 prize, bytes32 requestId);
event RandomnessReceived(uint64 indexed roundId, bytes32 requestId, uint256 seed);
event PrizePaid(uint64 indexed roundId, uint8 indexed slot, address indexed holder, uint256 gross, uint256 recipientTax, uint256 recycleTax, uint256 net);
event PaymentDeferred(uint64 indexed roundId, uint8 slot, address indexed holder, uint256 amount);
event OwedDelivered(address indexed holder, uint256 amount);
event RoundExpired(uint64 indexed roundId, uint256 returned);
event RoundAbandoned(uint64 indexed roundId, uint256 returned);
event ProtocolFeeSent(uint256 amount);
event TaxSent(uint256 amount);
```

The events must be sufficient to reproduce all contract state without an archive
trace.

## Indexer contract

The reference Envio indexer publishes a versioned schema with:

- raffle configuration, exclusions, and derived ticket parameters;
- deposit history, split into attributed and swept, gross, fee, and net;
- round metadata: snapshot block and hash, root, total tickets, prize, request ID,
  state, and timestamps;
- seed, derived slot indices, and per-slot resolution;
- the complete sorted leaf set and proofs for every committed round;
- pending claims with time remaining in the claim window;
- deferred credits, expired and abandoned reserves;
- protocol fee and payout tax accrual and delivery.

Provider names never appear in the contract. The ABI, entity schema, and
deterministic tree fixtures are part of the implementation repository's
compatibility tests.

## Security requirements

- Reentrancy guard on `fund`, `sync`, `claim`, `deliverOwed`, `sendProtocolFee`,
  and `sendTax`.
- Randomness requested strictly after the root is written, in the same
  transaction, and exactly once per round.
- Randomness delivery accepted only from the immutable adapter, only once per
  request, and never inside a payment path.
- Prize reserved at commit, before the seed exists.
- Domain-separated, direction-aware Merkle-sum proofs with checked arithmetic and
  a 64-element cap.
- Ticket interval derived from the proof, never supplied by the caller.
- Per-slot single payment, enforced before any transfer.
- Exact balance-delta verification on every receipt and payment.
- External self-call isolation for winner transfer failure.
- L2 height and block hash read exclusively through `ArbSys`.
- Cumulative 1% intake fee with an immutable recipient and permissionless exact
  delivery.
- Immutable payout tax shares whose sum is bounded by `MAX_PAYOUT_TAX_BPS`, each
  floored independently, with an immutable delivery destination.
- No owner, upgrade, sweep, rescue, arbitrary call, attestor change, adapter
  change, root replacement, or configuration setter.
- Chain-ID and dependency-code-hash assertions in deployment scripts.

## Required tests

1. A commitment cannot be replaced, skipped, or reordered.
2. Randomness delivered before a commitment, or for an unknown request, reverts.
3. A second delivery for the same request reverts and cannot change a drawn round.
4. A round's prize is unchanged by deposits made after its commitment.
5. An index at `totalTickets` or above is unreachable; index `totalTickets - 1`
   resolves to the last leaf.
6. Proofs with a falsified sibling sum, direction, or padded leaf revert.
7. A leaf whose derived interval excludes the winning index reverts.
8. A valid claim cannot be replayed, and a second address cannot claim the same
   slot.
9. A reverting winner defers exactly its net amount and does not block other slots
   or rounds.
10. Each tax share equals `floor(gross * bps / 10_000)` at zero and at the cap; a
    split configuration credits both destinations from one payout; a zero
    recipient share needs no recipient address and accrues nothing to deliver.
11. Protocol fees equal exactly 1% of cumulative measured intake across `fund` and
    `sync`, and cannot be reduced by splitting or redirected.
12. An unattributed transfer is credited only by `sync()` and cannot be claimed as
    a funder's deposit.
13. Fee-on-transfer prize assets revert without credit.
14. Wrong, stale, or parent-chain-domain snapshot block hashes revert.
15. Expiry and abandonment return exactly the unpaid reserve and permanently close
    the round.
16. A stalled round does not block up to `MAX_PENDING_ROUNDS - 1` further rounds.
17. Commits inside `minRoundInterval` revert.
18. Ticket math: 9,999 tokens yields zero tickets, 10,000 yields one, 35,000 yields
    three, and `maxTicketsPerHolder` caps a whale in the reference fixtures.
19. Raw ERC-8056 balance fixtures are unaffected by multiplier changes.
20. Invariant: balance is at least pool plus reserves plus owed plus fees plus tax.
21. Invariant: per-round paid never exceeds the reserve fixed at commit.
22. Invariant: the sum over all rounds of paid, returned, and reserved equals total
    committed prizes.
23. Fuzz: for uniform seeds, per-holder win frequency matches ticket share within
    statistical tolerance on fixed trees.
24. Fork: a full hourly cycle against a real subject token on Robinhood Chain
    mainnet with a mocked randomness adapter, then with the selected live adapter.

## Standalone verification

1. Compiles and deploys in a repository containing only itself and standard
   libraries.
2. Imports no other Sinjoh contract; the sink interface is copied, not imported.
3. Works when funded directly by an EOA with no fee router deployed.
4. Works with any standard non-rebasing ERC-20 subject and any standard prize
   asset, including native ETH.
5. Runs its complete indexer compatibility suite without any other Sinjoh package.
6. Runs against a mock randomness adapter with no Chainlink deployment present.

## Open decisions

These require a decision before implementation; each has a stated default in this
document.

1. ~~**Randomness adapter.**~~ **Resolved:** on-chain ECVRF, specified in
   [`sinjoh-randomness`](../sinjoh-randomness/SPEC.md). Blocking item before any
   mainnet raffle: measure Robinhood Chain's block time, because 255 blocks is the
   seal deadline and the keeper's schedule depends on it.
2. ~~**`MAX_PAYOUT_TAX_BPS`.**~~ **Resolved:** 5,000. Deliberately permissive so a
   novel reward design can be supported without a new implementation and factory.
   Interfaces carry the burden of displaying a high configured tax clearly.
3. ~~**Protocol intake fee.**~~ **Resolved:** kept at 1%, matching every other
   Sinjoh protocol. Value routed through a fee router is charged 1% there and 1%
   here, the same stacking the airdrop distributor already has.
4. ~~**Payout tax destination.**~~ **Resolved:** both at once. `recipientTaxBps`
   and `recycleTaxBps` are independent shares of each gross prize.
5. **Prize asset.** One immutable asset per deployment. Multi-asset raffles are
   out of scope and would need their own specification.
