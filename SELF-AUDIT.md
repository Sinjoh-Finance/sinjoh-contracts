# Self-audit: `sinjoh-raffle-rewards` and `sinjoh-randomness`

A review of the two new packages by their author, before independent audit. It
records what was checked, what was found and fixed, what was measured against the
live chain, and — most importantly — what this exercise cannot establish.

## What this is not

The contracts and their tests share one author. A misreading of the specification
produces a contract and a test that agree with each other, and no amount of green
suites detects that. This document narrows the space where such an error could
hide; it does not close it. **Independent review remains a release gate.**

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
| `SinjohRaffleRewards` | 98.15% | 95.65% |
| `SinjohRaffleRewardsFactory` | 95.45% | 100% |
| `SinjohEcvrfRandomness` | 98.48% | 95% |

Invariants run 16,384 calls each with zero reverts. `src/` is warning-free under
`forge lint` in both packages, and `VRF.sol` is byte-identical to upstream and
excluded from formatting so it stays diffable.

## Still open before mainnet

1. Independent audit. The blind-spot problem above is structural.
2. Static analysis — neither slither nor aderyn is installed in this environment.
3. The off-chain prover and the raffle worker do not exist yet; both must reproduce
   `EcvrfProver.sol` and `RaffleTree.sol` exactly, and the nonce rule matters —
   reusing a nonce across two inputs leaks the secret key.
4. The ECVRF key must be generated on the host that will hold it, and must not be
   the attestor's host.
