# Sinjoh Randomness

Verifiable randomness for Robinhood Chain, where Chainlink VRF is not deployed.

An ECVRF proof over secp256k1, verified on-chain against one immutable public key
using Chainlink's own verifier vendored unmodified. No oracle network, no second
chain, no messaging layer, no subscription.

Specification: [`SPEC.md`](./SPEC.md).

```text
requestRandomness(roundId) ──► seal(requestId) ──► fulfill(requestId, proof) ──► deliver(requestId)
   consumer, at commit          pins the input        verifies the proof          calls back
```

Every step after the request is permissionless. None of them can alter a value.

## Design points

- **The input is bound to the hash of the block the request landed in.** Without
  that, a party holding both the key and the consumer's committed data could grind
  offline — evaluate candidate trees until a chosen address wins, with nothing to
  see afterwards. A transaction cannot know its own block's hash, so grinding now
  needs the sequencer *and* the key.
- **Sealing is separate from proving.** The 255-block hash window is a hard
  deadline, so it applies only to a cheap call anyone can make. After sealing, the
  proof has no deadline at all.
- **Verification is separate from delivery.** A reverting consumer never forces an
  85k-gas proof to be verified twice, and delivery retries forever.
- **Submission is permissionless** because a proof authenticates itself against the
  immutable key. A wrong key produces no valid proof; a proof over a different
  input is rejected.
- **The contract holds nothing.** No custody, no fee, no gas balance. Whoever
  submits a step pays for it.

## The residual

Once an input is sealed, the key holder computes the outcome before anyone else and
can decline to publish, forcing the consumer's own timeout. Re-rolling across rounds
costs almost nothing. This cannot be fixed with one key.

Hold the key somewhere that does not also control the consumer's committed data,
monitor abandoned rounds, and disclose the residual in any interface built on it.

## Local verification

```sh
forge fmt --check
forge lint
forge test
forge build --sizes
```

20 tests, including a full round trip with a genuine ECVRF proof, forged-key and
wrong-input rejection, tampering with each proof component, the seal window at both
edges, and gas ceilings per step.

[`test/EcvrfProver.sol`](./test/EcvrfProver.sol) is the reference prover and the
specification the off-chain prover must reproduce. It inherits `VRF` so hash-to-curve
and the challenge scalar come from the verifier itself.

## Vendored code

[`src/libraries/VRF.sol`](./src/libraries/VRF.sol) is Chainlink's ECVRF verifier,
byte-identical to `smartcontractkit/chainlink-evm` and excluded from `forge fmt` so
it stays diffable upstream. Do not edit it.

Consumer: [`sinjoh-raffle-rewards`](../sinjoh-raffle-rewards).
