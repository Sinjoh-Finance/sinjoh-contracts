# Pons v2 compatibility report

Local compatibility was tested on 2026-08-12. A read-only Robinhood Chain mainnet
fork lifecycle was added and passed on 2026-08-14. Fork state is disposable: no
mainnet transaction or wallet was used.

## Source model

The compatibility harness follows the official `ponsdotdev/ponsfamily` source at
commit `836f0f97f9a9569855876570d6778501c163c883`.

The production-facing verifier models these Pons v2 facts:

- `PonsV2LaunchFactory.getLaunchedToken(token)` is the canonical launch record.
- `deployer` is the immutable launch creator. The mutable
  `creatorFeeRecipient` does not control Funding Bands.
- Funding Bands activation requires `GraduationPhase.PoolCreated`.
- The graduated `PoolKey` is reconstructed from the record's pair token, pool
  fee, tick spacing, and shared `PonsV2MemeHook`.
- The launch token must independently report the same factory, deployer, and
  bonding curve as the factory record.
- Native ETH and canonical WETH quotes are accepted. Other Pons v2 quote assets
  are rejected by this release.
- Pons v2's hook enables `beforeInitialize` and `afterSwap`, but no add/remove
  liquidity callback. Funding Bands therefore freezes empty v4 hook data for
  this profile.

Pons v2 does not store the original configured supply in its per-token launch
record. The verifier snapshots the token's current `totalSupply()` when Funding
Bands is activated. This is stable for ordinary Pons v2 operation, although a
holder can voluntarily burn their own tokens before activation.

## Local tests

`test/SinjohPonsV2Profile.t.sol` covers:

1. Canonical graduated launch resolution and exact `PoolId` reconstruction.
2. Rejection before graduation, for unsupported quote assets, counterfeit token
   metadata, and non-empty launch data.
3. Native-ETH Pons v2 mint, later increase, full burn/settlement, ETH wrapping,
   exact 1% protocol fee, and creator snapshotting.
4. WETH-quoted Pons v2 mint, increase, full settlement, subject-fee delivery,
   and exact 1% protocol fee.
5. The full ten-band Pons v2 create-and-fund batch using one context-bound signed
   below-price observation.

The mock PositionManager rejects the test if Funding Bands supplies the wrong
Pons hook or any non-empty hook data. The lifecycle tests therefore exercise the
same v4 action encodings used by the core contract for mint, increase, and burn.

Run only the Pons v2 suite:

```sh
forge test --match-contract SinjohPonsV2ProfileTest -vv
```

## Verdict

The Funding Bands v4 execution path is mechanically compatible with the current
Pons v2 deployment after graduation. `test/SinjohPonsV2.mainnet.fork.t.sol`
launches and graduates a fresh token through the real Pons contracts, registers
and funds a band twice, crosses it with a real hooked v4 swap, burns the position,
receives native ETH from the canonical PoolManager, wraps it, and verifies the
1% fee and liabilities. `SinjohV4SignedBandPriceGuard` supplies the production
spot-plus-signed-reference model.

This is still not an audit or deployment authorization. The live fork uses the
production `SinjohSignedEthUsdOracle` model rather than a mock, but the offchain
reference-tick and ETH/USD publishers, signer custody, Fee Router runtime hash,
and all deployment inputs must be operationally rehearsed and independently
reviewed before an immutable deployment.
