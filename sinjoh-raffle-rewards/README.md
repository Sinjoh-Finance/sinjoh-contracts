# Sinjoh Raffle Rewards

Immutable per-launch raffle rewards for subject-token holders. One ticket per
`tokensPerTicket` raw units held — 10,000 tokens in the reference configuration —
with hourly draws settled by verifiable randomness and a configurable payout tax
frozen before launch — split as you like between an immutable recipient and the
prize pool itself.

Specification: [`SPEC.md`](./SPEC.md).
Testnet-first stock rollout: [`TESTNET_STOCK_REWARDS.md`](./TESTNET_STOCK_REWARDS.md).
Robinhood mainnet route inventory: [`ROBINHOOD_STOCKS.md`](./ROBINHOOD_STOCKS.md).

## Shape

```text
platform fees ──► WETH prize pool ──► hourly round ──► VRF stock selection ──► winner
                       (1% intake fee)    (reserve at commit)   (guarded swap at claim)
```

- An off-chain worker snapshots holders each hour and commits a Merkle-sum tree of
  ticket counts. The attestor commits the root; it never picks the winner.
- The prize is a configured share of the pool, reserved at commit, before any
  randomness exists.
- A randomness adapter delivers one seed per round. Each winner slot's ticket
  index and, when configured, mystery-stock route are independently derived from that seed.
- Anyone submits the winning proof; the reference keeper does so automatically, so a winner
  does not connect a wallet or sign a claim. The contract derives the leaf's ticket
  interval from the proof itself, so the committed tree partitions the ticket
  range and cannot pay a slot twice.
- Unclaimed rounds return their WETH reserve to the pool. A rejected winner transfer becomes
  an asset-specific, indefinitely retryable credit. Nothing is redirected to an operator.
- The payout tax is two independent shares of each gross prize: `recipientTaxBps`
  goes to an immutable address selected as either the token creator or a configured
  `SinjohFeeRouter`, while `recycleTaxBps` returns to the pool and funds later
  rounds. Their sum is capped at 5,000 bps.
- An immutable, sorted stock list can enable a mystery prize per winning slot. The pool remains
  WETH; only the winner's net share is swapped through an immutable adapter, with a minimum
  output supplied by an immutable TWAP guard. Empty stock configuration preserves direct payout.
- A stock claim that cannot execute is retried for stock, not downgraded. Because every route
  component is immutable, a route that fails permanently would otherwise strand the same share of
  every future round: in the final quarter of the claim window the winner — and only the winner —
  can take that slot in WETH instead, via `claimFunding`.

The contract has no owner, no upgrade, no rescue role, no arbitrary call, and no
configuration setter. It imports no other Sinjoh contract.

## Randomness on Robinhood Chain

Chainlink VRF is **not** deployed on Robinhood Chain mainnet (chain `4663`), as of
July 2026. Chainlink's live services there are CCIP, Data Streams, and Data Feeds;
VRF v2.5's supported networks are Ethereum, Arbitrum, Base, OP, Polygon, BNB Chain,
Avalanche, Ronin, and Soneium.

Randomness is therefore an immutable adapter address chosen per deployment, behind
a two-function interface. The release configuration uses `SinjohEcvrfRandomness`
from [`sinjoh-randomness`](../sinjoh-randomness): a secp256k1 ECVRF proof verified
on-chain against one immutable public key. No oracle network, no second chain,
settlement in seconds.

`blockhash`, `ArbSys.arbBlockHash`, and `block.prevrandao` are rejected as
randomness sources on their own: the sequencer determines all three and the attestor
chooses commit timing. The adapter uses a block hash only as a *binding* — it pins
the proof input to a value nobody knew when the commitment was built, which is what
stops the attestor from grinding a root against a known output.

**The residual:** the adapter's key holder sees each outcome before publishing and
can withhold a proof, forcing that round to abandon. The key must not be held by
whoever runs the attestor, abandoned rounds must be monitored, and any interface
must disclose it. See [`sinjoh-randomness/SPEC.md`](../sinjoh-randomness/SPEC.md).

## Trust boundary

Same shape as `sinjoh-airdrop-distributor`: an ERC-20 has no on-chain holder set, so
an indexer reconstructs the snapshot and an immutable attestor commits it. The
attestor can misweight a holder inside the tree. It cannot pay more than the
reserved prize, cannot commit after seeing randomness, and cannot send value to an
address the proof does not select.

## Local verification

```sh
forge fmt --check
forge lint
forge test
forge coverage --report summary
forge build --sizes
```

79 tests across six suites, including six strict invariants, cover the spec's required list: commit ordering and
snapshot verification, prize freezing, randomness authentication and single
delivery, ticket-interval partitioning, falsified proofs, slot-once payment,
deferred payment to a rejecting winner, tax splitting and bounds, cumulative 1%
fees across both intake paths, expiry and abandonment, the pending-round cap, and
win frequency against ticket share. Stock coverage includes canonical immutable routes,
domain-separated selection, guarded minimum output, WETH-denominated tax/recycling, direct
delivery, and asset-specific retry credits.

The package vendors two micro-libraries (`Clones`, `SafeTransferLib`) and imports
nothing else. `test/RaffleTree.sol` is the reference tree builder the off-chain
worker must reproduce.

## Deployment

The stock-reward feature must complete the controlled-mirror testnet gate before any mainnet
deployment. Its price guards use an immutable five-minute TWAP; see
[`TESTNET_STOCK_REWARDS.md`](./TESTNET_STOCK_REWARDS.md). Testnet ticker matches are not treated as
approved Robinhood Stock Tokens.

After deploying and smoke-testing the testnet ECVRF adapter, deploy the testnet-locked raffle
factory:

```sh
DEPLOYER_PRIVATE_KEY=... RANDOMNESS_ADAPTER=... forge script \
  script/DeployRaffleRewardsFactoryTestnet.s.sol:DeployRaffleRewardsFactoryTestnet \
  --rpc-url https://rpc.testnet.chain.robinhood.com \
  --broadcast
```

[`script/DeployRaffleRewardsFactory.s.sol`](./script/DeployRaffleRewardsFactory.s.sol)
asserts chain ID `4663`, reads `ArbSys`, and requires `RANDOMNESS_ADAPTER` to have
code as a production smoke check. The raffle also rejects any configured ERC-20
prize asset or randomness adapter without code. Per-launch raffles are then created through the factory:
`predictRaffle` → configure the launch against the predicted address → `deployRaffle`
→ `bind(subject)` once the token exists.

The randomness adapter is immutable in every raffle. Deploy against
[`sinjoh-randomness`](../sinjoh-randomness) only after one full request-seal-prove-
deliver cycle has run against that adapter with the real key.
