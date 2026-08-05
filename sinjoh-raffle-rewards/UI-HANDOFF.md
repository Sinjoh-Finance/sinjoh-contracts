# SinjohRaffleRewards — UI integration handoff

For an external team integrating the raffle into their own UI. This document is
self-contained: everything you must call, display, and never do. The executable
counterpart is `sinjoh-integration/test/ProductionPonsV2Raffle.fork.t.sol`,
which performs the entire launch and settlement flow against the deployed
mainnet contracts — when this document and that test disagree, the test wins.

## 1. What the product is

A per-launch, immutable raffle for holders of one subject token. Holders are
entered automatically by holding: they never sign, register, approve, or claim.
An off-chain keeper snapshots holders, commits a Merkle-sum root, verifiable
randomness (ECVRF) picks winner slots, and the keeper submits winning proofs
itself. Prizes are either the funding asset (WETH) or — when the raffle is
configured with stock rewards — a VRF-selected tokenized stock ("mystery
stock"), bought at claim time through an immutable, oracle-guarded swap.

Every parameter is frozen at deployment. There is no owner, no upgrade, no
setter, no rescue. What the UI reads at deployment is true forever.

## 2. Addresses

Live on Robinhood Chain mainnet (chainId 4663, RPC
`https://rpc.mainnet.chain.robinhood.com`) — canonical record:
`mainnet-deployments.json` at the repo root:

| Contract | Address |
|---|---|
| Agnostic fee-router factory | `0xA1F721a697Dd03a45f264F53bCBFd121212318eD` |
| Pons v2 adapter factory | `0xdb02cC8bbEb1F4B0A98f974a8768c08370d1a821` |
| Pons v2 launch factory (external) | `0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e` |
| WETH | `0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73` |
| Swap adapter (stock routes) | `0xc9F600ebaf9EE1F4a24568D2e4Af9E8df1e07D7B` |

Not yet deployed — required before the first raffle; obtain from the Sinjoh
team's deployment record when live:

- `SinjohRaffleRewardsFactory` (script exists: `DeployRaffleRewardsFactory.s.sol`)
- `SinjohEcvrfRandomness` adapter (the raffle's `randomness` config value)
- Three five-minute TWAP price guards + primed pools (stock raffles only;
  gated by `PreflightStockRoutes` — a raffle with stock rewards must not be
  deployed until that preflight passes)

## 3. The launch flow (order is load-bearing)

Three addresses reference each other (router → adapter, raffle exclusions →
curve, router sink → raffle). The cycle resolves because clone addresses ignore
their configuration and the Pons launch is CREATE2-derived. Perform exactly:

1. **Predict the adapter**: `adapterFactory.predictAddress(creator, adapterSalt)`.
2. **Predict the router**: `routerFactory.predictLaunchpadAddress(creator, routerSalt)`.
3. **Predict token + curve**: assemble the launch params (fee recipient = the
   predicted adapter, `buybackEnabled` **must** be false,
   `expectedEconomics = ponsFactory.previewLaunchEconomics(configId, pairToken)`
   pinned, a fresh `salt`) and predict with `originalDeployer` = the predicted
   adapter. Off-chain: `sinjoh-keeper/src/ponsv2/predict.ts`
   (`predictLaunchAddresses`). On-chain/ops: `PonsV2LaunchPrediction.sol` /
   `script/PredictPonsV2Launch.s.sol`.
4. **Build the raffle config**: exclusions = predicted curve + Pons factory +
   V4 PoolManager + buyback vault + meme hook + the adapter, sorted ascending
   (`raffleExclusionsForLaunch` in `predict.ts` returns the static set +
   curve, sorted). Compute `configHash` with `raffleConfigHash` in
   `sinjoh-keeper/src/ponsv2/raffle-launch.ts` and, if the address is needed
   pre-deploy, `raffleFactory.predictRaffle(creator, salt, configHash)`.
5. **Deploy the raffle**: `raffleFactory.deployRaffle(salt, config)`.
6. **Deploy the router**: `routerFactory.deployForLaunchpad(creator,
   routerSalt, config)` with `launchpadAdapter` = predicted adapter and a
   bucket allocation naming the raffle as an `isSink` destination.
7. **Deploy the adapter**: `adapterFactory.deploy(creator, router, adapterSalt)`.
8. **Launch**: `adapter.launch{value: launchFee (+ developerBuy for native)}
   (params, configId, pairToken, developerBuy, minTokensOut,
   snipeTaxExemptions)`. Verify the returned token and curve equal the
   predictions; abort the flow if not (an owner retune raced you — the pinned
   `expectedEconomics` makes the launch revert rather than land unpredicted).
9. **Bind the raffle**: `raffle.bind(token)` — raffle creator only, once.

Notes for the launch form:

- **Creator trade tax**: 0 (off) or 1–5000 bps requested; the live Pons cap is
  `ponsFactory.maxCreatorTaxBps()` (currently 1000 = 10%) — read it live and
  clamp the input to the lower bound.
- **Snipe-tax exemptions**: wallets the team declares for opening buys. The
  factory auto-exempts the adapter; user-entered wallets go in the array.
- **Developer buy**: adapter forwards purchased tokens to the creator wallet in
  the launch transaction; requires `minTokensOut != 0`.
- **Pair asset**: native ETH or an approved ERC-20. Raffle-funded launches use
  native/WETH; the raffle's `prizeAsset` is WETH.
- **Salt reuse reverts.** Generate a fresh salt per attempt; identical params +
  salt collide with the already-deployed pair.

## 4. Read surface

### Indexer (Envio, GraphQL) — preferred for lists and history

| Entity | Contents |
|---|---|
| `Raffle` | frozen configuration, subject, running totals (deposited, prizes committed, paid, tax, recycled), latest round |
| `RaffleRound` | per round: state (`COMMITTED`/`DRAWN`/`SETTLED`/`EXPIRED`/`ABANDONED`), root, totalTickets, prize, seed, slotsPaid, snapshot block |
| `RafflePrize` | per winning slot: holder, gross/taxes/net, payoutAsset, payoutAmount, fundingSpent, deferred flag |
| `RaffleStockReward` | the immutable stock route list by index |
| `RaffleExclusion` | every excluded address with source (`CONFIGURED`/`AUTOMATIC`/`SUBJECT`) |

### Contract views (per-user, real-time)

- `configuration()` — the whole frozen `Settings` struct in one call.
- `ticketsFor(weight)` — tickets for a raw balance; **user odds =
  ticketsFor(balance) / round.totalTickets** for a committed round.
- `nextPrize()` — the prize the next round would reserve right now.
- `rounds(roundId)` — state, prize, seed, drawnAt, slotsPaidMask.
- `winningIndex(roundId, slot)` / `selectedStock(roundId, slot)` — after draw.
- `slotPrize(roundId, slot)` — a slot's gross share.
- `owed(holder)` / `stockOwed(holder, asset)` — deferred credits to surface as
  "pending delivery" with a retry button.
- `fundingFallbackAt(roundId)` — when `claimFunding` opens (see §6).
- `payoutTaxBps()` — total payout tax to display.

### Events for live updates

`RoundCommitted`, `RandomnessReceived`, `PrizePaid`, `StockPrizePaid`,
`PaymentDeferred`, `StockPaymentDeferred`, `OwedDelivered`,
`StockOwedDelivered`, `RoundExpired`, `RoundAbandoned`.

## 5. What users actually do (almost nothing)

The keeper commits rounds, submits winning claims, retries deferred deliveries,
and expires stale rounds. The UI needs **no required user transaction** for the
core loop. Optional user-facing actions, all permissionless unless noted:

| Action | When to show |
|---|---|
| `deliverOwed(holder)` / `deliverStockOwed(holder, asset)` | when the credit view is nonzero — "retry delivery" |
| `claimFunding(roundId, slot, leaf, proof)` | **winner's wallet only** (contract enforces `msg.sender == leaf.holder`), only after `fundingFallbackAt(roundId)`, only on stock raffles, only for an unpaid slot — "take WETH instead" |
| `claim(...)` | normally the keeper's job; expose only as a fallback "claim now" using the proof from the keeper's published round artifact |

## 6. Stock prizes — display rules that will bite you

- **`payoutAmount` is raw, 18 decimals.** Every stock is a Robinhood
  `BeaconProxy` with raw-balance ERC-20 semantics. Splits change the token's
  `uiMultiplier()`, never balances. **Displayed shares = raw amount ×
  uiMultiplier() ÷ 1e18-scale** (read the multiplier live from the token; do
  not cache across sessions).
- **Reveal order**: the stock for a slot (`selectedStock`) is knowable the
  moment randomness lands, before the claim executes — fine to show as the
  "mystery reveal". The final share amount is known only at claim
  (`StockPrizePaid.payoutAmount`), because it depends on the live pool price.
- **Stocks can be paused** (compliance/halts, `paused()` on the token). A claim
  or delivery during a pause reverts and is retried by the keeper; show
  deferred stock credits as "delivery pending", never as failed. Value is never
  lost: credits are retryable forever, and the winner always has the
  `claimFunding` WETH exit in the window tail.
- A slot whose share is too small to fund a swap settles with
  `payoutAmount = 0` — display as "below minimum prize", not an error.

## 7. Money semantics

- Deposits are charged a **1% protocol fee** on intake (`Deposited.fee`).
- Each slot's gross share splits into `recipientTax` (to the immutable tax
  recipient), `recycleTax` (returned to the prize pool), and `net` (the
  winner's). Both taxes are shares of gross, floored; dust goes to the winner.
- The prize each round is `prizeBps` of the available pool (capped by
  `maxPrize`, floored by `minPrize`) — a share, never a fixed obligation.
- Unclaimed value returns to the pool at `expireRound`; nothing is ever
  redirected to an operator.

## 8. Error taxonomy (what to render, not retry)

| Revert | Meaning for the user |
|---|---|
| `ClaimWindowClosed` | round expired; value returned to the pool |
| `RandomnessPending` | drawn state not reached; show "drawing…" |
| `SlotAlreadyPaid` / `InvalidRound` | already settled; refresh state |
| `FallbackUnavailable` | `claimFunding` before its window or on a non-stock raffle |
| `Unauthorized` on `claimFunding` | connected wallet is not the winning holder |
| `QuoteExpired` / `InsufficientOutput` | stock route can't execute right now; keeper retries — show "pending" |
| `ExcludedHolder` | infrastructure addresses can't win; should never surface for a real user |

## 9. Never do these

- **Never let the user set slippage.** Claims take no slippage parameter; the
  immutable price guard supplies the minimum. There is nothing to configure.
- **Never assemble the exclusion list by hand.** Use the tooling (§3.4); a
  missing curve exclusion makes the launchpad win every raffle.
- **Never launch without a pinned `expectedEconomics`.** Zero waives the check
  and an owner retune can land the launch on unpredicted terms and addresses.
- **Never show `claimFunding` before `fundingFallbackAt`** or to non-winners.
- **Never cache `uiMultiplier()`** across sessions (splits), and never display
  raw stock amounts as share counts.
- **Never treat a skipped fork test or a green suite as chain verification** —
  the preflight and the integration rehearsals are the verification commands.

## 10. Verify your integration

```bash
# The full production flow your UI must reproduce, against live mainnet state:
cd sinjoh-integration && RH_RPC_URL=https://rpc.mainnet.chain.robinhood.com forge test --match-contract Production -vv

# Stock-route readiness (must pass before any stock raffle is deployed):
cd sinjoh-raffle-rewards && RAFFLE_GUARD_500=… RAFFLE_GUARD_3000=… RAFFLE_GUARD_10000=… MAX_PRIZE=… forge script script/PreflightStockRoutes.s.sol:PreflightStockRoutes --rpc-url https://rpc.mainnet.chain.robinhood.com
```

ABIs: build each package with `forge build` and read `out/<Name>.sol/<Name>.json`,
or use the typed helpers in `sinjoh-keeper/src/ponsv2/` (viem) which are
fixture-pinned to the Solidity encodings.
