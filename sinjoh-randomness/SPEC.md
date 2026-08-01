# SinjohEcvrfRandomness

Verifiable randomness for contracts on Robinhood Chain, where Chainlink VRF is not
deployed.

One immutable contract. An ECVRF proof over secp256k1 is verified on-chain against
one immutable public key, using Chainlink's own `VRF.sol` verifier vendored
unmodified. There is no oracle network, no second chain, and no messaging layer.

The package is standalone. It imports no Sinjoh contract; the consumer interface is
copied.

## Why it exists

Chainlink on Robinhood Chain mainnet provides CCIP, Data Streams, and Data Feeds.
VRF is not among them: VRF v2.5's supported networks are Ethereum, Arbitrum, Base,
OP, Polygon, BNB Chain, Avalanche, Ronin, and Soneium.

Every randomness source natively available on `4663` — `blockhash`,
`ArbSys.arbBlockHash`, `block.prevrandao`, timestamps — is determined by the
sequencer and unusable on its own for value-bearing selection. This package
generates randomness from a key nobody else holds and proves each output correct
on-chain, so neither the sequencer nor the caller can choose it.

## Interface

Copied by consumers, never imported:

```solidity
interface ISinjohRandomness {
    function requestRandomness(uint64 roundId) external returns (bytes32 requestId);
}

interface ISinjohRandomnessConsumer {
    function receiveRandomness(bytes32 requestId, uint256 seed) external;
}
```

Delivery is asynchronous and pull-based. A consumer must treat a request as
outstanding until `receiveRandomness` arrives, and must have its own timeout path.

## Trust boundary

ECVRF output is **deterministic**: for a fixed key and input there is exactly one
result, and it is publicly verifiable. That property is what makes it useful, and
also the source of every risk here.

The holder of the key can compute an output the moment its input is known. Two
consequences follow, and only one of them is fixable.

### Fixed: offline grinding

If the proof input were a function of data the consumer chooses — a committed
Merkle root, a snapshot block — then a party holding **both** the key and that data
could evaluate candidate inputs offline until one produced a favorable result, and
publish only that one. No withholding, no forfeited rounds, no visible evidence.
That is strictly worse than withholding and it defeats the construction entirely.

The input is therefore bound to the hash of the block the request landed in:

```text
alpha = keccak256(
    abi.encode(
        SINJOH_ECVRF_ALPHA_V1, chainid, address(adapter), consumer, roundId, entropy
    )
)

entropy = ArbSys.arbBlockHash(requestBlock)
```

A transaction cannot know the hash of the block it will be included in. So a
consumer cannot choose its committed data against a known output, and the key
holder cannot precompute an output for a future round. Grinding now requires the
sequencer *and* the key together.

### Not fixed: withholding

Once the input is sealed, the key holder computes the outcome before anyone else
and can simply decline to publish the proof. The consumer's round then reaches its
own timeout. An operator willing to forfeit rounds can re-roll across them, and the
re-roll is cheap: nothing is burned, the consumer recovers its own value, and the
only evidence is a round that failed to settle.

No single-key construction removes this. The mitigations are operational:

- the key should be held by a party that does not control the consumer's committed
  data, so that grinding remains impossible even where withholding does not;
- abandoned rounds are public and must be monitored — a rate materially above the
  chain's own failure rate is the signal;
- an interface built on this adapter must disclose the residual.

Operators who need withholding resistance as well need a multi-party or
network-backed source. That is a different protocol, not this one.

## Deployment

```solidity
constructor(uint256 publicKeyX, uint256 publicKeyY, uint256 chainId);
```

Everything is immutable. There is no owner, upgrade, pause, rescue, sweep, or
arbitrary call. The adapter holds no value: it takes no custody, charges no fee,
and needs no gas balance, because whoever submits a step pays for it.

The constructor rejects a coordinate pair that is not on secp256k1. It cannot check
that anyone holds the matching secret. That must be proved off-chain before any
consumer is configured — seal a throwaway request and verify a real proof against
the deployment.

A wrong key is unrecoverable: consumers bind to an adapter address immutably, so a
replacement adapter strands every consumer already pointed at the old one.

## Lifecycle

```text
requestRandomness(roundId)   consumer, in the transaction that commits its data
        │                    records requestBlock; no external call
        ▼
seal(requestId)              permissionless, in a LATER block, within 255; pins alpha
        │
        ▼
fulfill(requestId, proof)    permissionless; verifies against the immutable key,
        │                    stores the output; no external call
        ▼
deliver(requestId)           permissionless; calls the consumer
```

Every step is permissionless and none can alter a value. `seal` reads a block hash,
`fulfill` verifies mathematics, `deliver` forwards a derived seed.

### `requestRandomness(uint64 roundId) -> bytes32 requestId`

```text
requestId = keccak256(abi.encode(chainid, address(this), msg.sender, roundId))
```

Rules:

1. `msg.sender` is recorded as the consumer; there is no caller allowlist;
2. the request ID must be unrecorded — one request per `(consumer, roundId)`,
   forever;
3. `requestBlock` is recorded from `ArbSys.arbBlockNumber()`;
4. no external call is made and no value is spent, so a consumer's commit
   transaction cannot fail on this adapter's balance or state.

### `seal(bytes32 requestId) -> uint256 alpha`

Permissionless. Rules:

1. the request exists and is unsealed;
2. `ArbSys.arbBlockNumber() > requestBlock` — a block's hash is not available
   inside that block, which is exactly why this is a separate step;
3. `ArbSys.arbBlockNumber() <= requestBlock + 255`;
4. `ArbSys.arbBlockHash(requestBlock)` is nonzero;
5. the entropy is written once and can never be replaced.

**This is the tightest operational deadline in the system, and it is measured, not
estimated.** Robinhood Chain mainnet produces a block every **0.1004 seconds**,
averaged over 100,000 blocks, so the 255-block hash window is **about 25.6
seconds**. A missed window kills the request permanently — there is no second
entropy source and no way to re-pin it — and the consumer falls back to its own
timeout.

The keeper must therefore seal in the block immediately following the request,
which at this cadence is roughly a tenth of a second later. It must not wait on
anything else first, and a stuck seal transaction must be repriced rather than
left pending. A request whose seal is late by even half a minute is dead.

Sealing is separate from proving so the deadline applies only to a cheap call that
anyone can make. Once sealed, the proof may be submitted at any later time with no
deadline at all.

### `fulfill(bytes32 requestId, VRF.Proof calldata proof) -> uint256 output`

Permissionless, because a proof authenticates itself. Rules:

1. the request exists, is sealed, and is unfulfilled;
2. `proof.pk` equals the immutable public key — without this check any key would
   do and the adapter would guarantee nothing;
3. `proof.seed` equals the sealed `alpha`, so a proof over a different input cannot
   be replayed here;
4. `VRF._randomValueFromVRFProof` verifies the proof and returns the output;
5. the output is stored and the request marked fulfilled; no external call is made.

Verification and delivery are separate so a reverting consumer never forces the
proof to be verified again.

### `deliver(bytes32 requestId)`

Permissionless. Rules:

1. the request exists, is fulfilled, and is undelivered;
2. the seed is derived as

   ```text
   seed = keccak256(
       abi.encode(SINJOH_ECVRF_SEED_V1, chainid, address(this), requestId, output)
   )
   ```

3. the consumer is called;
4. the request is marked delivered **only on success** — a revert rolls the flag
   back so the attempt can be repeated forever.

The seed is a hash of the output and the request ID, never the raw VRF output. Two
consumers therefore never receive the same seed, and a consumer that mixes its own
address into whatever it derives stays independent of every other consumer.

## Cost

| Step | Measured |
|---|---|
| `requestRandomness` | 79,774 |
| `seal` | 61,741 |
| `fulfill` | 85,049 |
| `deliver` | 107,662 with a trivial consumer |

Every step is a local transaction paid by its submitter. There is no fee, no
subscription, no gas balance to maintain, and no declared limit that can be set too
low. `test/GasBounds.t.sol` pins each figure so a regression fails the build.

Settlement is bounded by how quickly the keeper seals and proves, not by any
external protocol. Expect seconds.

## The prover

`test/EcvrfProver.sol` is the reference implementation and the specification the
off-chain prover must reproduce. It inherits `VRF` so hash-to-curve, the challenge
scalar, and projective addition come from the verifier itself rather than a
parallel implementation that could drift.

Given a secret key `sk`, input `alpha`, and nonce `k`:

```text
pk     = sk * G
h      = hashToCurve(pk, alpha)
gamma  = sk * h
u      = k * G,  uWitness = address(u)
v      = k * h
c      = scalarFromCurvePoints(h, pk, gamma, uWitness, v)
s      = k - c*sk           (mod group order)
witnesses: cGammaWitness = c*gamma, sHashWitness = s*h
zInv   = inverse of the z from projectiveECAdd(cGammaWitness, sHashWitness)
```

Requirements on the production prover:

- the secret key never touches a chain, a repository, or a log;
- the nonce is nonzero, derived deterministically from `(sk, alpha)`, and **never
  reused across different inputs** — a repeated nonce over two inputs leaks the
  secret key by elementary algebra;
- proofs are produced only for inputs read from the deployed adapter, never for
  inputs computed locally, so the prover cannot be induced to sign a speculative
  input.

## Events

```solidity
event RandomnessRequested(bytes32 indexed requestId, address indexed consumer, uint64 roundId, uint64 requestBlock);
event RequestSealed(bytes32 indexed requestId, bytes32 entropy, uint256 alpha);
event ProofAccepted(bytes32 indexed requestId, uint256 output, address indexed prover);
event SeedDelivered(bytes32 indexed requestId, address indexed consumer, uint256 seed);
```

These must be sufficient to reconstruct every request's state and to prove that
each seal preceded its proof.

## Security requirements

- Immutable public key, checked to be on secp256k1 at construction.
- A proof is accepted only for the immutable key and only for the sealed input.
- One request per `(consumer, roundId)`, one seal per request, one accepted proof
  per request, one successful delivery per request.
- The proof input is bound to a block hash unknown when the request was built.
- Sealing is confined to the 255-block hash window and can never be replaced.
- Verification performs no external call; delivery is a separate retryable step.
- Delivery is per-request and cannot loop over consumers.
- No owner, upgrade, pause, sweep, rescue, key change, or arbitrary call.
- The contract never holds value and never requires a balance.
- Deployment scripts assert the chain ID and read `ArbSys` before deploying.

## Required tests

1. A full round trip with a genuine proof delivers a nonzero seed.
2. A proof from any other key is rejected.
3. A proof over any other input is rejected.
4. Tampering with `s`, `c`, or `gamma` fails verification.
5. Sealing in the request's own block reverts.
6. Sealing at block 255 succeeds; at 256 it reverts.
7. A second seal reverts, and a sealed input cannot move afterwards.
8. Proving before sealing reverts.
9. A second proof for the same request reverts.
10. A duplicate request for the same `(consumer, roundId)` reverts.
11. A reverting consumer is retryable and cannot be delivered twice.
12. Two consumers requesting the same round id receive different inputs and
    different seeds.
13. Anyone may submit a valid proof and a valid delivery.
14. An off-curve or zero public key is rejected at construction.
15. Each step stays inside its gas ceiling.
16. Fork test on Robinhood Chain mainnet with a real key, covering a full
    request-seal-prove-deliver cycle.

## Standalone verification

1. Compiles and deploys in a repository containing only itself and the vendored
   verifier.
2. Imports no Sinjoh contract; the consumer interface is copied.
3. Serves any consumer implementing `receiveRandomness`, not only a raffle.
4. Runs its complete test suite with no external network, service, or subscription.

## Vendored code

`src/libraries/VRF.sol` is Chainlink's ECVRF verifier, copied byte-identical from
`smartcontractkit/chainlink-evm` (`contracts/src/v0.8/vrf/VRF.sol`, MIT). It is
excluded from `forge fmt` so it stays diffable against upstream. Do not edit it: a
change there is a change to the verification rules.

## Deployment checklist

1. Generate the ECVRF key offline, on the host that will hold it, and record the
   public key coordinates.
2. Confirm the coordinates are on secp256k1 and that the production prover
   reproduces `EcvrfProver` outputs for a set of fixed inputs.
3. Measure Robinhood Chain's block time and record what 255 blocks means in
   seconds. That figure is the seal deadline and the keeper's schedule depends on
   it.
4. Deploy, then run one full cycle against a throwaway consumer: request, seal,
   prove with the real key, deliver.
5. Only then configure a consumer. The adapter address is immutable in each
   consumer, so a consumer deployed against an unverified adapter can never be
   repointed.
