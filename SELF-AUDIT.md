# Review record: `sinjoh-raffle-rewards` and `sinjoh-randomness`

This record combines the original author's self-audit with the later independent
branch takeover review. It records what was checked, fixed, and measured against
the live chain, and — most importantly — what these exercises cannot establish.

## Independent takeover review — 2026-08-01

A second agent reviewed the entire branch against `origin/main` without accepting
the original self-audit as evidence. The review found and corrected additional
issues across the contracts, keeper, indexer, and documentation:

1. the keeper rejected the final valid block of both 255-block hash windows;
2. the production ECVRF prover accepted caller-supplied nonces, making accidental
   nonce reuse and secret-key disclosure possible;
3. round artifacts omitted the snapshot hash, Merkle proofs, and deterministic
   content hash required for reproducibility;
4. transfer replay did not enforce canonical intra-block log order and the round
   builder failed to exclude the bound subject token;
5. the clone implementation itself remained publicly initializable;
6. immutable raffle configuration accepted randomness and ERC-20 prize-asset
   addresses without deployed code;
7. basis-point multiplication could overflow for a valid maximum-size token pool;
8. raffle and randomness handlers were unreachable from the Envio chain config;
9. repeated factory events erased existing raffle aggregates;
10. initialization events omitted the frozen configuration and exclusions needed
    by the indexer; and
11. deferred-settlement events lacked gross/tax data, so the indexer recorded
    incorrect prize and tax totals and could not identify settled rounds reliably.

Focused regression tests were added for these cases. The remaining release gaps
are listed at the end of this document.

## Stock-reward review — 2026-08-03

The stock-reward payout path was reviewed after it was written. No incorrect accounting was
found: the swap is balance-delta measured on both sides, the tax and recycle shares never leave
WETH, and per-asset solvency is asserted on every deferred credit. Four things were changed.

### 7. A dead route permanently stranded a fixed share of every round — fixed

Every route component is immutable, and the slot's stock is derived from the VRF seed. A guard
that stops quoting therefore made a fixed fraction of all future slots unclaimable, with no
setter, no owner, and no way to disable the route. The reserve sat until `expireRound` returned it
to the pool and the winner received nothing.

The first fix considered was a `try/catch` around the swap falling back to WETH. That is wrong:
`InsufficientOutput` is the honest signal that a prize is large relative to the pool, and an
immediate fallback would downgrade every winner whose claim hit a momentary oracle deviation.

`claimFunding` instead opens only in the final quarter of the claim window and only to the
winner. Transient failures and real slippage are retried for stock across the first three
quarters; the concession belongs to the winner, so a keeper cannot take it on their behalf.
`testDeadStockRouteStillPaysTheWinnerInTheWindowTail` drives a permanently dead guard through
both refusals and the eventual payout.

### 8. The invariant suite never touched the stock path — fixed

The strict 16,384-call suite this document cites configured `stockRewards` as an empty list, so
`_settleStockPrize`, `stockOwed`, `totalStockOwed`, and `deliverStockOwed` had no invariant
coverage at all. The per-stock solvency invariant this specification requires was asserted in
prose only.

The suite is now a base class with two concrete configurations, so every existing invariant runs
against the stock raffle as well, plus three stock-specific ones. The handler drives guarded
swaps, per-stock deferred credits, and the funding-asset fallback. Both configurations complete
16,384 calls with zero reverts. Reachability was verified rather than assumed: a temporary
invariant confirmed that stock actually arrives at a holder and that the fallback actually pays.

Wiring the stock tokens through a dedicated handler setter failed immediately — the fuzzer
targets every public function and called it on the direct suite with addresses holding no code.
They are passed through the already-guarded `initialize` instead.

### 9. The zero-value stock slot was untested — fixed

A slot share too small to survive the tax split funds no swap. That branch had no test;
`testZeroValueStockSlotSettlesWithoutSwapping` covers it.

### 10. The coverage figures in this document were stale — fixed

They described the branch before the stock path existed. The table below is re-measured.

### 11. A reverting raffle action starved the whole keeper queue — fixed

The keeper returns one action per pass. `nextMaintenanceAction` iterated rounds and returned the
first outstanding claim or deferred credit without checking whether it could currently succeed, so
a stock claim whose route could not quote — or a holder who still rejected the asset — became the
permanent head of the queue. Every later round's claim, delivery, and expiry was starved behind
it, and the raffle stopped making progress entirely.

This is the same defect the planner had already found and fixed for `pons:collect`, whose comment
records it verbatim. The `canSimulate` guard is now shared in `src/simulate.ts` and applied to all
three raffle action families that the chain can legitimately reject: `claim`, `deliver-owed`, and
`deliver-stock-owed`. A slot that cannot settle stays unpaid and is retried next pass instead of
blocking the queue.

Found by reading the keeper while closing item 8 below, not by a failing test — the existing
tests all used a single round, which is exactly the shape that cannot exhibit head-of-line
blocking.

### 13. The deployment gate was prose, and it was wrong to trust — fixed

The stock-route preconditions lived as roughly 420 lines of instructions across three documents,
performed by hand. Confirming a pool's observation cardinality, confirming a full TWAP window,
taking a live quote, executing a guarded swap, and sizing `maxPrize` against a guard bound in
another package were all steps a person had to do consistently, every time, in order.

`script/PreflightStockRoutes.s.sol` does all of it against live chain state in one non-broadcasting
run, and reports every failure rather than stopping at the first. `script/StockRouteManifest.sol`
holds the route table as compiled constants, so the fee tier a route executes in and the fee tier
its guard prices can no longer drift apart in prose — a mismatch that nothing on-chain compares
and that would have silently bounded the wrong market.

Run against mainnet today it fails 18 checks: AAPL, GOOGL, and RDDT sit at observation cardinality
1, below the guard's own minimum of 2, and no five-minute guard exists for any fee tier. That
finding was already recorded in `ROBINHOOD_STOCKS.md` for two of the three pools; the gate found
the third and the guard mismatch on its own.

A gate observed only to fail is indistinguishable from a broken gate, so
`PreflightStockRoutes.fork.t.sol` drives it both ways: MSTR passes every check against a compliant
guard — including a real swap through the real adapter delivering real stock — and fails against
the deployed 900-second guard, against a fee-tier mismatch, and against an unprimed pool.

### 12. The fork suite was passing without running — fixed

`RH_RPC_URL` was unset, so all four fork tests early-returned at roughly 2,300 gas each and
reported green. The mainnet RPC recorded in `mainnet-deployments.json` runs them for real.

They also had no stock coverage. `SinjohRaffleRewardsStockForkTest` now drives a full cycle
against real mainnet execution components — the reviewed `SinjohSimpleSwapAdapter` deployment, a
real deployed `SinjohSharedV3TwapPriceGuard`, and the canonical WETH/MSTR V3 pool — ending with
the winner holding real tokenized stock. This is the only test that could have caught a guard
which rejects the raffle's call shape, and it confirms the undocumented convention that the stock
asset is passed as the guard's `subject`. No mock built from the same reading of the interface
could establish that.

### 14. The copied Pons v2 factory interface did not match the deployed contracts — fixed

Pons v2 went live on mainnet on 2026-08-04, which turned "built against copied interfaces,
no address pinned" into something checkable. Checked against the verified sources, the copied
`TokenParams` was missing the deployed struct's trailing `bytes32 salt` field. A struct field
changes the ABI encoding and with it every `launchToken` selector: the router encoded
`0xa41d5f2b`, which exists on no deployed contract, so every v2 launch would have reverted.
Both suites were green because the mock was generated from the same wrong copy — the exact
blind spot finding 4 describes, on a new boundary.

Two wiring gaps surfaced in the same review. Curve fees only reach the Pons escrow through
`sweepFees`, which authorizes the curve's fee recipient (the router) or Pons's operator; the
router had no sweep method, so Sinjoh revenue — and with it all raffle funding — would have
stalled on the curve waiting for a third party. `sweepPonsV2CurveFees()` closes that, refusing
only earmarked buyback sweeps, and the keeper proposes it ahead of the escrow claim. And the
raffle documentation now specifies the complete v2 exclusion set: the per-launch curve
(computable pre-launch from the launch salt via `predictLaunchAddresses`, which is also what
resolves the launch-order circularity), plus the static factory, V4 PoolManager, buyback
vault, and hook. Without the curve exclusion, the curve is the largest holder in every
pre-graduation snapshot.

`SinjohFeeRouterV2.fork.t.sol` now drives a real launch with a real creator trade tax through
the verified factory on a mainnet fork — launch, taxed curve trade, permissionless sweep,
escrow claim, WETH wrap, `sync` — and pins every boundary selector. The verified v2 addresses
are recorded in `mainnet-deployments.json` under `externalDependencies.ponsV2`.

### 15. The launch-order tooling existed only as prose — fixed

The v2 exclusion guidance said "compute the curve address first"; nothing implemented it, which
made every future launch a human assembling three mutually referential addresses by hand. The
cycle — the router's address is needed to predict the curve, the curve to configure the raffle,
the raffle to configure the router — resolves because the router's clone address ignores its
configuration; that property, and the whole ordering, is now code:
`PonsV2LaunchPrediction.sol` assembles the factory's exact `LaunchDeployment` and asks the
deployed deployer for the CREATE2 result, so the derivation always runs on verified bytecode; a
mainnet-fork launch proves prediction equals reality; `PredictPonsV2Launch.s.sol` is the ops
command; the keeper's `ponsv2/predict.ts` and `ponsv2/raffle-launch.ts` are the UI-facing twins,
pinned byte-for-byte to the Solidity ABI and to canonical `abi.encode(Config)` through generated
fixtures; and `sinjoh-integration/` rehearses the complete lifecycle — prediction through a
committed round paying a real holder from real v2 revenue — against the live deployment.

During this work the user deployed `SinjohPonsV2AdapterFactory` from a parallel branch. The
adapter architecture supersedes this branch's router-direct launch/sweep/claim methods (drop
them at merge; the adapter incorporates the same salt fix, exemption passthrough, and curve
sweep independently). Everything else here is architecture-neutral: prediction takes the
initiating account as a parameter — the adapter, for adapter-owned launches — and the
raffle-side flow from `sync` onward is identical.

### 16. The prize assets themselves were never audited — closed

Everything upstream treated the eight tokenized stocks as opaque addresses. Sourcing them found
they are all one `BeaconProxy` bytecode behind a single shared beacon whose implementation
Robinhood can upgrade at any time — so the proxy codehash the checklist would naturally pin is
meaningless. The reviewed implementation was read in full: raw-balance ERC-20 (stock splits move
a separate `uiMultiplier`, never balances, so exact-delta delivery is split-proof), 18 decimals
across all eight, no transfer fee, and a discretionary role-set pause whose failure modes the
raffle already absorbs (retryable claims, retryable credits, the winner's WETH fallback).

The preflight now enforces this shape every run — beacon identity, implementation codehash so an
upstream upgrade fails the gate and forces re-review, decimals, live pause state, and a real
post-swap exact-transfer probe — because an upgraded stock that skims transfers would otherwise
strand every payout in permanently undeliverable credits.

Separately, `sinjoh-integration/test/ProductionPonsV2Raffle.fork.t.sol` now rehearses the launch
against the contracts actually deployed on mainnet — the agnostic router factory and the Pons v2
adapter factory — rather than this branch's local router. The raffle is the only locally deployed
contract in that test, which is exactly its remaining deployment status. `UI-HANDOFF.md` is the
external-team integration document; the rehearsal is its executable counterpart.

## What this is not

The contracts and their tests share one author. A misreading of the specification
produces a contract and a test that agree with each other, and no amount of green
suites detects that. This document narrows the space where such an error could
hide; it does not close it. **An external security audit remains a release gate.**

## Findings

### 1. A hostile adapter could re-enter delivery mid-commit — fixed

`commitRound` calls out to the randomness adapter while holding the reentrancy
guard. `receiveRandomness` had no guard, so an adapter could, from inside a request
for round N, call back and settle round N-1 with a seed of its choosing.

The adapter is already a trust boundary — a malicious one can deliver any seed at
any time — so this granted no new capability. It was still a reachable reentrancy
path across a state-changing function, and closing it costs nothing: no honest
adapter delivers randomness during a request.

`receiveRandomness` is now `nonReentrant`, and
`testHostileAdapterCannotReenterDelivery` drives an adapter that attempts exactly
this and asserts the revert.

### 2. Coverage instrumentation could not compile the raffle — fixed

Not a vulnerability, but it hid everything else. The generated 20-value getter for
`settings` was unencodable without via-IR, and `claim` carried too many live
locals. Neither could be measured, and the first successful measurement showed
**54% branch coverage** — nearly half the rejection paths had never executed.

`settings` is now internal behind `configuration()`, which returns one struct and
is a better ABI for indexers anyway. `claim` is split into `_requireWinningClaim`
and `_settleSlot`, which also puts every rejection before any state change.

### 3. The invariant suite was discarding a fifth of its calls — fixed

It ran with `fail_on_revert = false` and silently dropped 3,393 of 16,384 calls.
The handler also only ever claimed slot 0 of a single-winner round, so multi-winner
accounting — the trickiest arithmetic in the contract — had no invariant coverage
at all.

It now runs strict, completes 16,384 calls with zero reverts, and drives partial
claiming, deferred payment through a holder that rejects the prize asset, and
expiry of a partly claimed round. Turning it strict immediately surfaced a defect
in the handler itself: a fuzzer-supplied `uint8` of 255 overflowed in the slot
picker. That class of failure was previously invisible.

### 4. The package boundary had no signature check — fixed

The adapter interface is copied rather than imported, so no compiler ever sees both
sides. A parameter type could change on one side and both packages would build,
both suites would stay green, and the failure would appear as a reverted call
between two immutable contracts with no upgrade path.

Both packages now carry mirrored `InterfaceCompatibility` tests pinning
`requestRandomness(uint64)` and `receiveRandomness(bytes32,uint256)`. The raffle's
copied interface was also renamed to match the adapter's declaration.

### 5. The prover's scalar multiplication had no independent oracle — closed

`EcvrfProver` inherits hash-to-curve and the challenge scalar from the vendored
verifier, so those cannot drift from it. Scalar multiplication is the one piece
written locally, and a consistent error in it would be invisible to a round trip
that used the same code on both sides.

Two oracles that share no code with it now cover this. An Ethereum address is the
keccak of the public key, so Foundry's own secp256k1 validates `derivePublicKey`
exactly; and the verifier checks products by `ecrecover` rather than by
multiplying. Five thousand fuzz runs assert agreement, plus additivity and
doubling identities.

### 6. Two 25-second deadlines, measured not estimated — documented

Robinhood Chain mainnet produces a block every **0.1004 seconds**, averaged over
100,000 blocks. The 255-block hash window is therefore **about 25.6 seconds**, not
the "about a minute" the specifications previously assumed.

Two deadlines sit inside it: snapshot to `commitRound`, and commitment to `seal`.
Both are hard, and both are now stated with the measured figure in
`sinjoh-raffle-rewards/SPEC.md`, `sinjoh-randomness/SPEC.md`, and
`KEEPER_REQUIREMENTS.md`, along with the consequence for worker design — balances
must be maintained incrementally, because a worker that starts indexing at snapshot
time will not finish inside the window.

Neither failure loses value. A missed snapshot skips a round; a missed seal
abandons one and returns its reserve to the pool.

## Deliberately not fixed

**Fourteen defensive branches remain uncovered** in the raffle. The original four are the
paid-exceeds-prize assertion, the exact-spend mismatch, the solvency assertion, and one reentrancy
edge; the rest are the stock path's equivalents — per-asset solvency, the swap's two
balance-delta mismatches, and the guard-response rejections that a conforming guard cannot
produce. Each requires a malicious asset or an already-broken invariant to reach. Contorting tests
to touch them would prove less than it costs, and they are backstops rather than logic.

**Stray stock tokens are unrecoverable.** `sync()` credits only the funding asset, so a stock
token sent to the raffle directly can never leave: stock exits solely through `payStockWinner` and
`deliverStockOwed`, both bounded by `stockOwed`. This is the no-rescue design applied
consistently, and it is stated in `sinjoh-raffle-rewards/SPEC.md`, but it is a class of stuck
value that did not exist before stock rewards.

**The withholding residual in the randomness adapter is inherent**, not an
oversight. A single-key ECVRF cannot prevent its key holder from seeing an outcome
first and declining to publish. The mitigations are operational and are recorded in
`sinjoh-randomness/SPEC.md`: hold the key apart from the attestor, monitor abandoned
rounds, disclose it in any interface.

**`ArbSys` is mocked even under fork.** Its account holds a single `INVALID` opcode
because the precompile is node-implemented, so no local EVM can execute it. The
fork suites assert that fact, then etch a stand-in seeded from the fork's own
height. Everything else in those runs is genuine chain state.

## What was verified against Robinhood Chain mainnet

Both packages carry fork suites, run against `4663` at block 25,081,564 and above:

- the raffle's full cycle against the **real WETH deployment** — deposit, fund,
  commit, draw, claim, fee and tax delivery, solvency;
- unattributed WETH transfers requiring `sync`;
- the adapter's full request-seal-prove-deliver cycle on this chain's EVM, which
  matters because ECVRF verification leans on `MODEXP` and `ECRECOVER`;
- ECVRF verification gas on real configuration, inside its ceiling;
- forged-proof rejection;
- a **full stock cycle against real execution components** — the reviewed
  `SinjohSimpleSwapAdapter` deployment, a real deployed `SinjohSharedV3TwapPriceGuard`, and the
  canonical WETH/MSTR V3 pool — ending with the winner holding real tokenized stock, and the
  guard accepting the raffle's exact call shape including the stock asset as `subject`.

Set `RH_RPC_URL` to run them; without it they skip so the default suite stays offline. **A
skipped fork test reports as passing.** It early-returns at roughly 2,300 gas, which is the only
signal in the output that it did not run — check the gas, not the green. The public endpoint
recorded in `mainnet-deployments.json` is sufficient:

```bash
RH_RPC_URL=https://rpc.mainnet.chain.robinhood.com forge test --match-contract Fork
```

The stock fork suite forks latest and depends on live pool state, so it is a readiness probe. A
failure there is a signal about the chain — an unobservable TWAP window, a pool that cannot
absorb the slot — and not necessarily a regression in this code.

## Coverage and suite state

| | Lines | Branches |
|---|---|---|
| `SinjohRaffleRewards` | 96.73% | 87.83% |
| `SinjohRaffleRewardsFactory` | 100% | 100% |
| `SinjohEcvrfRandomness` | 98.48% | 95% |

The raffle rows were re-measured on 2026-08-03 with `forge coverage --ir-minimum`; Foundry warns
that its minimum via-IR source mapping can be less precise, and its line-level output on this
contract is visibly imprecise — it reports several unconditionally executed assertions as
unhit. The randomness row is carried forward from the takeover review because that package was
not touched by this change.

Branch coverage is lower than the 93.62% recorded before the stock path existed. That is the
stock path's own defensive branches, not a regression in what was already covered: 14 of 115
branches are uncovered, against 4 before. The raffle suite is 86 tests. Both invariant
configurations — direct payout and stock — run 16,384 calls each with zero reverts. `src/` is
warning-free under `forge lint` in both packages, and `VRF.sol` is byte-identical to the pinned
upstream commit recorded in `sinjoh-randomness/VENDORED.md`.

Suite totals across the branch: 86 raffle tests offline plus 6 against mainnet, 35 randomness
tests, 66 keeper tests, and 10 indexer tests. Both keeper and indexer type-check clean.

## Offchain implementation

The keeper now carries the pure half of the worker, each piece pinned to its
Solidity counterpart by fixtures generated from that counterpart:

| Module | Pinned against |
|---|---|
| `src/ecvrf/curve.ts`, `src/ecvrf/prover.ts` | proof fixtures from `EcvrfProver.sol`, plus viem's secp256k1 for public keys |
| `src/raffle/tree.ts` | root, sum, and every proof from `RaffleTree.sol` |
| `src/raffle/round.ts` | winning-index fixtures from the contract's own derivation |
| `src/abis.ts` | function selectors read from the compiled artifacts |

`src/raffle/tickets.ts` implements the `MIN_BALANCE` basis, with tests showing a
balance borrowed into the snapshot block earns nothing while a point snapshot would
have rewarded it. Transfer histories are required to be strictly ordered by block
and log index, and the effective exclusion set includes the bound subject and all
automatic contract exclusions. `src/raffle/sequencer.ts` holds the deadline rules,
including that the final window block remains valid and a later seal is terminal.

Regenerate the fixtures with `forge test --match-contract GenerateFixtures` in each
Solidity package and copy them into `sinjoh-keeper/test/fixtures`. A change to a
domain separator or a struct layout will fail the keeper's tests, which is the
point.

The chain-connected loop now lives in `src/raffle/service.ts`,
`src/randomness/service.ts`, and `src/transactions.ts`. It incrementally maintains
cross-provider Transfer history, persists immutable round evidence, separates the
attestor and ECVRF hosts, rechecks chain identity immediately before signing,
reconciles receipts after restarts, and services claims, expiry, abandonment, and
both WETH and asset-specific stock credits. Its end-to-end tests use mocked clients and never submit live
transactions.

## Still open before mainnet

1. External security audit. The blind-spot problem above is structural, and it now covers
   `claimFunding` and the keeper's simulate guard as well: both were written, tested, and
   reviewed by the same agent that found the defects they address.
2. ~~Static analysis.~~ Slither 0.11.4 was run on both packages. `sinjoh-randomness` reports zero
   findings. `sinjoh-raffle-rewards` reports fourteen, all triaged as false positives against
   this code: `weak-prng` on five modulo operations that distribute fee remainders and slot
   shares or index a VRF-supplied seed, none of which generate randomness; `divide-before-multiply`
   on the two quotient/remainder decompositions that exist specifically to avoid overflow while
   staying exact; `incorrect-equality` on four sentinel comparisons against internally controlled
   values rather than balances or timestamps; and `uninitialized-local` on three variables that
   rely on Solidity's zero-initialization deliberately. Aderyn was not run.
3. ~~The off-chain prover and the raffle worker do not exist yet.~~ Both the pure
   algorithms and chain-connected services now exist and have mocked lifecycle,
   timeout, restart, and reconciliation tests. A full request-seal-prove-deliver
   cycle with the real production key remains an operational pre-mainnet check.
4. The ECVRF key must be generated on the host that will hold it, and must not be
   the attestor's host.
5. ~~The raffle Envio handlers need an end-to-end simulation.~~
   `sinjoh-indexer/test/raffle-handlers.test.ts` drives the registered handlers themselves, in
   log order, against an in-memory context: a stock raffle from deployment through
   initialization, routes, binding, funding, commit, draw, one slot settled in stock, and one
   settled in WETH through `claimFunding`. That last case is the evidence for the claim that the
   fallback needed no indexer change.
6. The full eight-stock raffle still needs its guards deployed and three pools primed, but that
   is now one fork-tested broadcast (`DeployRafflePriceGuardsMainnet`, see the Remediation
   section of `sinjoh-raffle-rewards/ROBINHOOD_STOCKS.md`) followed by a passing preflight run.
   The fork test proved the sequence makes all eight routes quotable, and surfaced a real trap on
   the way: a V3 pool writes an observation only when a swap moves its tick, so a too-small seed
   swap silently does nothing — the script escalates and verifies instead of assuming. The
   controlled-mirror testnet lifecycle remains a prior gate, and broadcasting requires the
   deployer key, which is held by the operator, not this environment.
7. ~~`maxPrize` must be checked against each guard's hard input bound.~~ The preflight probes every
   route at the largest slot the candidate `MAX_PRIZE` can produce, so the bound is compared by
   taking a real quote rather than by reading two numbers in two packages.
8. The keeper no longer starves behind a failing slot (finding 11), but it still cannot tell a
   transiently failing route from a permanently dead one, and it does not notify anyone. A
   repeatedly unsettleable slot appears only as a `planned` journal record that never reaches
   `simulated`. Only the winner can invoke `claimFunding`, so somebody has to tell them. The
   right surface for that alert depends on how the operator consumes keeper output and is a
   product decision, not a contract one.
