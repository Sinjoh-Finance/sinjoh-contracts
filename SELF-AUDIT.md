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

**Four defensive branches remain uncovered** in the raffle: the paid-exceeds-prize
assertion, the exact-spend mismatch, the solvency assertion, and one reentrancy
edge. Each requires a malicious asset or an already-broken invariant to reach.
Contorting tests to touch them would prove less than it costs, and they are
backstops rather than logic.

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
- forged-proof rejection.

Set `RH_RPC_URL` to run them; without it they skip so the default suite stays
offline.

## Coverage and suite state

| | Lines | Branches |
|---|---|---|
| `SinjohRaffleRewards` | 96.40% | 93.62% |
| `SinjohRaffleRewardsFactory` | 100% | 100% |
| `SinjohEcvrfRandomness` | 98.48% | 95% |

The raffle report was refreshed after the takeover corrections with
`forge coverage --ir-minimum`; Foundry warns that its minimum via-IR source mapping
can be less precise. Invariants run 16,384 calls each with zero reverts. `src/` is
warning-free under `forge lint` in both packages, and `VRF.sol` is byte-identical
to the pinned upstream commit recorded in `sinjoh-randomness/VENDORED.md`.

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

What is still missing is the chain-connected loop around this logic: signing,
submission, receipt reconciliation, retries, and the journal. The existing airdrop
worker is the template.

## Still open before mainnet

1. External security audit. The blind-spot problem above is structural.
2. Static analysis — neither slither nor aderyn is installed in this environment.
3. ~~The off-chain prover and the raffle worker do not exist yet.~~ Both now exist
   in `sinjoh-keeper` and are pinned to the Solidity references by committed
   fixtures: proof components, tree root and proofs, and winning-index derivation.
   What remains is the chain-connected loop — signing, submission, retries, and the
   operational journal — around the pure logic that is built and tested.
4. The ECVRF key must be generated on the host that will hold it, and must not be
   the attestor's host.
5. The raffle Envio handlers code-generate and type-check, and their settlement
   projection has a pure regression test, but they still need an end-to-end handler
   simulation against representative factory, raffle, and adapter logs.
