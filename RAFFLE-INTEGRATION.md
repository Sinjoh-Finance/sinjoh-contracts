# Sinjoh Holder Raffle — integration guide

How to display a Sinjoh raffle's live data on your own site or app.

Everything here is read directly from the blockchain. There is no Sinjoh API
key, no rate limit imposed by us, and no server that can go down and take your
integration with it. If the chain is up, this data is available.

- **Chain**: Robinhood Chain, chain ID `4663`
- **Public RPC**: `https://rpc.mainnet.chain.robinhood.com`
- **Prize asset**: WETH `0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73` (18 decimals)

## Official sources, deployments, and ABIs

The canonical repositories are maintained by the
[`Sinjoh-Finance`](https://github.com/Sinjoh-Finance) organization. During the
private migration they require explicit GitHub access:

- Contracts and deployment provenance:
  `https://github.com/Sinjoh-Finance/sinjoh-contracts`
- TypeScript SDK and checked-in ABIs:
  `https://github.com/Sinjoh-Finance/sinjoh-sdk`
- Application:
  `https://github.com/Sinjoh-Finance/sinjoh-ui`

Until the SDK packages are published, use the public JSON API at
`https://api.sinjoh.com/v1` or a standard EVM client with the exact ABI:

- Source: `sinjoh-raffle-rewards/src/SinjohRaffleRewards.sol`
- Forge artifact after `forge build`:
  `sinjoh-raffle-rewards/out/SinjohRaffleRewards.sol/SinjohRaffleRewards.json`
- Checked-in SDK ABI:
  `packages/abis/src/generated/raffleRewards.ts`
- Factory source/artifact:
  `sinjoh-raffle-rewards/src/SinjohRaffleRewardsFactory.sol` and
  `sinjoh-raffle-rewards/out/SinjohRaffleRewardsFactory.sol/SinjohRaffleRewardsFactory.json`

Authoritative shared Robinhood Chain deployments:

| Contract | Address |
| --- | --- |
| Raffle factory | `0xd030064fb83d14c97c22a6b63bf376552eba7112` |
| Raffle implementation | `0x982F8B6612146E0963DFd18D74e1ffe4E110b47D` |
| ECVRF randomness adapter | `0xD16BCD59ca33C1e85578Aa5d60a02C4E2231c491` |
| Airdrop distributor | `0xa1d65242d367501d9a261389a69005e584f4786a` |
| WETH | `0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73` |

`mainnet-deployments.json` is the source of truth for deployment transactions,
blocks, and runtime code hashes. Each launch has its own raffle clone, so do
not call the implementation address for live state. Discover clone addresses
with `GET https://api.sinjoh.com/v1/tokens` or `RaffleDeployed`, then verify
`raffle.subject()` against the requested token.

Example values below use the MEGA launch:

| What | Address |
| --- | --- |
| Token (`$MEGA`) | `0x20c86dde46F7cB6B1adB52598d2f2dA70EcEf7d9` |
| Raffle | `0x9a5D5141721CA14D009ed7dD9b23A3E37948ea16` |
| Fee router | `0x8B3Ade830937F223F09E7aa7594FCf8bCe258601` |
| Raffle factory | `0xd030064fb83d14c97c22a6b63bf376552eba7112` |

## Finding the raffle for a token

Each launch publishes its raffle address. To discover raffles yourself, read
`RaffleDeployed` from the factory and keep the ones whose `subject()` matches
the token you care about:

```solidity
event RaffleDeployed(
    address indexed raffle,
    address indexed creator,
    bytes32 configHash,
    bytes32 userSalt,
    bytes32 derivedSalt,
    uint256 chainId,
    address implementation,
    bool created
);
```

A raffle names its token back: `raffle.subject()` returns the token address.
Verify this rather than trusting a mapping you were handed.

## The reads you actually need

```solidity
function subject()          view returns (address);  // the token
function availablePool()    view returns (uint256);  // prize pool, minus reserved
function nextPrize()        view returns (uint256);  // what the next round pays
function latestRoundId()    view returns (uint64);
function lastCommitAt()     view returns (uint64);   // unix seconds
function pendingRounds()    view returns (uint8);    // rounds awaiting settlement
function isExcluded(address holder) view returns (bool);
function winningIndex(uint64 roundId, uint8 slot) view returns (uint256);
function owed(address holder)       view returns (uint256);  // failed direct delivery only
function stockOwed(address holder, address asset) view returns (uint256);
function stockRewardCount() view returns (uint256);
function stockReward(uint256 index) view returns ((address asset, address swapAdapter,
    address priceGuard, bytes routeData, bytes guardData));
function deliverOwed(address holder) returns (uint256);
function deliverStockOwed(address holder, address asset) returns (uint256);

function rounds(uint64 roundId) view returns (
    bytes32 rootHash,
    bytes32 requestId,
    uint256 totalTickets,
    uint256 prize,
    uint256 paidTotal,
    uint256 seed,
    uint64  snapshotBlock,
    uint64  committedAt,
    uint64  drawnAt,
    uint16  slotsPaidMask,
    uint8   state
);

function configuration() view returns ((
    address creator, address attestor, address randomness, address prizeAsset,
    address protocolFeeRecipient, address taxRecipient,
    uint128 tokensPerTicket, uint128 maxTicketsPerHolder,
    uint128 minPrize, uint128 maxPrize,
    uint16 prizeBps, uint16 recipientTaxBps, uint16 recycleTaxBps,
    uint16 minConfirmations, uint8 winnersPerRound,
    uint32 minRoundInterval, uint32 weightWindowBlocks,
    uint32 randomnessTimeout, uint32 claimWindow, uint8 basis
));
```

`configuration()` is immutable — read it once at startup and cache it forever.
Nobody, including the creator, can change it after deployment.

### Round states

`rounds(id).state` is an enum:

| Value | State | Meaning |
| --- | --- | --- |
| 0 | `NONE` | round does not exist |
| 1 | `COMMITTED` | ticket tree committed, waiting on verifiable randomness |
| 2 | `DRAWN` | randomness sealed, winner determined, payout not yet executed |
| 3 | `SETTLED` | winner paid — this is the terminal happy state |
| 4 | `EXPIRED` | claim window elapsed; value returns to the pool |
| 5 | `ABANDONED` | randomness timed out; value returns to the pool |

Show state 1 as "drawing" and state 2 as "paying out". Both resolve on their
own; no user action is involved.

## Winners

The keeper normally submits each valid winning proof and pays the transaction
gas. Winners do not need to sign, approve, or claim from their own wallet.
`claim(...)` is permissionless, however, so another agent can submit the same
verified proof if the keeper is unavailable.

Listen for `PrizePaid` to discover completed direct payouts:

```solidity
event PrizePaid(
    uint64  indexed roundId,
    uint8   indexed slot,
    address indexed holder,   // the winner
    uint256 gross,
    uint256 recipientTax,
    uint256 recycleTax,
    uint256 net               // what actually landed in their wallet
);
```

Because `holder` is indexed, "has this wallet already been paid?" is a single
filtered log query. It does not answer whether the wallet has a pending win.
The other round-lifecycle events:

```solidity
event RoundCommitted(uint64 indexed roundId, uint64 snapshotBlock,
    bytes32 snapshotBlockHash, bytes32 rootHash, uint256 totalTickets,
    uint256 prize, uint8 winnersPerRound, bytes32 requestId);
event RandomnessReceived(uint64 indexed roundId, bytes32 requestId, uint256 seed);
```

For a payout that could not be delivered (a holder contract that rejects
transfers, say), the value is preserved as a retryable credit. Read
`owed(holder)` for the funding asset and `stockOwed(holder, asset)` for a stock
prize. These values appear only after a valid winning claim was settled; they
do not identify unsubmitted or pending winning proofs. Anyone can retry a
credit with `deliverOwed` or `deliverStockOwed`.

## Checking rewards for one wallet

There is no single on-chain `claimable(wallet)` view and the public API does
not currently provide a wallet reward endpoint. Use these definitions:

1. **Paid history:** query `PrizePaid` and `StockPrizePaid` with the indexed
   holder topic set to the wallet. The public
   `/v1/tokens/{token}/winners` endpoint currently returns `PrizePaid` history,
   not stock payouts or pending wins.
2. **Deferred delivery:** read `owed(wallet)` on every raffle clone. For each
   configured stock asset from `stockRewardCount()` and `stockReward(index)`,
   also read `stockOwed(wallet, asset)`. A positive value is retryable now
   through the matching permissionless delivery call.
3. **Pending winning slot:** read drawn rounds (`rounds(id).state == 2`) and
   each unpaid bit in `slotsPaidMask`, then compute
   `winningIndex(roundId, slot)`. The wallet is the winner only when that index
   falls inside its committed leaf's `[offset, offset + tickets)` interval.
   The leaf offset and proof live in the keeper's durable round artifact; they
   cannot be reconstructed from current wallet balance or contract storage
   alone.
4. **Holder airdrops:** these use `SinjohAirdropDistributor` and are push-only.
   There is no user claim. `paid(accountId, wallet)` reports cumulative delivery
   for a known `(funder, subject, asset)` account; pending entitlement requires
   the latest committed Merkle-sum leaf and is not exposed by the raffle API.

If an integration must show pending raffle wins before settlement, it needs a
proof service over the keeper's durable artifacts. Until that service is
published, label API results "paid rewards" or "winner history," never
"claimable rewards."

## Working example (viem)

```js
import { createPublicClient, http, parseAbi, formatEther } from "viem";

const RAFFLE = "0x9a5D5141721CA14D009ed7dD9b23A3E37948ea16";
const WALLET = "0x95eb02912A7795e2ED0332E537fA8dbA82907a28";

const abi = parseAbi([
  "function subject() view returns (address)",
  "function availablePool() view returns (uint256)",
  "function nextPrize() view returns (uint256)",
  "function latestRoundId() view returns (uint64)",
  "function lastCommitAt() view returns (uint64)",
  "function owed(address holder) view returns (uint256)",
  "function stockOwed(address holder,address asset) view returns (uint256)",
  "function stockRewardCount() view returns (uint256)",
  "function stockReward(uint256 index) view returns ((address asset,address swapAdapter,address priceGuard,bytes routeData,bytes guardData))",
  "function winningIndex(uint64 roundId,uint8 slot) view returns (uint256)",
  "function rounds(uint64 roundId) view returns (bytes32 rootHash,bytes32 requestId,uint256 totalTickets,uint256 prize,uint256 paidTotal,uint256 seed,uint64 snapshotBlock,uint64 committedAt,uint64 drawnAt,uint16 slotsPaidMask,uint8 state)",
  "function configuration() view returns ((address creator,address attestor,address randomness,address prizeAsset,address protocolFeeRecipient,address taxRecipient,uint128 tokensPerTicket,uint128 maxTicketsPerHolder,uint128 minPrize,uint128 maxPrize,uint16 prizeBps,uint16 recipientTaxBps,uint16 recycleTaxBps,uint16 minConfirmations,uint8 winnersPerRound,uint32 minRoundInterval,uint32 weightWindowBlocks,uint32 randomnessTimeout,uint32 claimWindow,uint8 basis))",
  "event PrizePaid(uint64 indexed roundId,uint8 indexed slot,address indexed holder,uint256 gross,uint256 recipientTax,uint256 recycleTax,uint256 net)",
]);

const client = createPublicClient({
  transport: http("https://rpc.mainnet.chain.robinhood.com"),
});
const raffle = { address: RAFFLE, abi };

const [pool, nextPrize, latestRoundId, lastCommitAt, config] = await Promise.all([
  client.readContract({ ...raffle, functionName: "availablePool" }),
  client.readContract({ ...raffle, functionName: "nextPrize" }),
  client.readContract({ ...raffle, functionName: "latestRoundId" }),
  client.readContract({ ...raffle, functionName: "lastCommitAt" }),
  client.readContract({ ...raffle, functionName: "configuration" }),
]);

// Next draw becomes eligible one minRoundInterval after the last commit.
const eligibleAt = Number(lastCommitAt) + config.minRoundInterval;
const secondsUntilDraw = Math.max(0, eligibleAt - Math.floor(Date.now() / 1000));

console.log(`pool        ${formatEther(pool)} WETH`);
console.log(`next prize  ${formatEther(nextPrize)} WETH`);
console.log(`next draw   ${secondsUntilDraw > 0 ? `${secondsUntilDraw}s` : "any moment"}`);

// Retryable direct credit after an already-settled delivery failure. This is
// not a pending winning proof or a general claimable balance.
const deferred = await client.readContract({
  ...raffle,
  functionName: "owed",
  args: [WALLET],
});
console.log(`deferred    ${formatEther(deferred)} WETH`);

// This wallet's completed direct payouts, from the raffle's deployment block.
const winners = await client.getLogs({
  address: RAFFLE,
  event: abi.find((x) => x.name === "PrizePaid"),
  args: { holder: WALLET },
  fromBlock: 29791812n,   // MEGA raffle deployment block
  toBlock: "latest",
});

for (const { args } of winners.reverse()) {
  console.log(`round ${args.roundId}  ${args.holder}  ${formatEther(args.net)} WETH`);
}
```

## Tickets and odds

Do not compute a holder's tickets from their current balance. The rule:

- One ticket per `tokensPerTicket` held (10,000 `$MEGA` on the MEGA launch).
- Tickets count the holder's **lowest balance across the snapshot window**
  (`weightWindowBlocks`), not their balance at draw time. Buying right before a
  draw earns nothing.
- `maxTicketsPerHolder` caps a single wallet when nonzero (`0` = uncapped).
- Protocol contracts (pools, routers, the raffle itself) are excluded — check
  `isExcluded(holder)`.

Reproducing the exact ticket count means replaying `Transfer` logs across the
window, which is what the keeper does when it builds each round. If you only
need to show a holder their standing, the honest approximation is
`min(balance over window) / tokensPerTicket`, and odds are
`tickets / rounds(id).totalTickets` for a committed round. Label it as an
estimate until the round commits, because `totalTickets` is not known before
that.

## Gotchas worth knowing up front

**The prize is a share of the pool, not the whole pool.** `prizeBps` is the
per-round payout share — `500` = 5% on the MEGA launch. The pool is designed to
persist and keep paying, not to drain. `nextPrize()` already does this math;
show that value rather than the pool balance.

**Draws are keeper-driven.** `minRoundInterval` is a floor, not a timetable.
A round becomes *eligible* one interval after `lastCommitAt`, and an off-chain
keeper commits it shortly after. "Any moment" is the honest label once eligible;
do not render a countdown that hits zero and then sits at zero looking broken.

**Rounds can legitimately be skipped.** If no wallet holds a full ticket, there
is no draw that round and nothing is lost.

**Blocks are fast — budget lookbacks in blocks, not intuition.** The chain
produces ~10 blocks/second (~36,000 per hour), so 100,000 blocks is under three
hours — roughly two hourly rounds. A full day is ~865,000 blocks.

**Wide log ranges are fine here.** The public RPC served a filtered
(address + topic) `eth_getLogs` across 1,000,000 blocks in well under a second,
so you can pull a raffle's entire winner history in one call by starting from
its deployment block. Chunk to ~2,000 blocks only if you point at a provider
that rejects the wide range, or if you drop the topic filter.

**Providers disagree at the tip.** The public RPC can trail other providers by
several blocks. If you cross-check two providers, clamp reads to the lower head
or you will ask for blocks one of them does not have yet.

**Amounts are `uint256` wei.** Use `bigint` end to end and format only at the
display layer. WETH is 18 decimals; the launch token may differ — read
`decimals()`.

## Verifying fairness

Winner selection uses ECVRF randomness, and every round is auditable after the
fact:

- `rounds(id).snapshotBlock` and `snapshotBlockHash` pin the ticket snapshot to
  a specific block, committed *before* randomness arrives.
- `rounds(id).rootHash` is the Merkle-sum root of the ticket tree.
- `rounds(id).seed` is the verifiable seed, and
  `winningIndex(roundId, slot)` is the winning ticket index it selected.

The snapshot is committed before the seed exists, so the ticket set cannot be
adjusted to fit a winner.
