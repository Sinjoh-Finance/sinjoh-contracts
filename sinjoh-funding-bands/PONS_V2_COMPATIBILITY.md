# Pons v2 compatibility report

Local compatibility was tested on 2026-08-12. A read-only Robinhood Chain mainnet
fork lifecycle was added and passed on 2026-08-14. Fork state is disposable: no
mainnet transaction or wallet was used.

## Source model

The compatibility harness follows the official `ponsdotdev/ponsfamily` source at
[commit `836f0f97f9a9569855876570d6778501c163c883`](https://github.com/ponsdotdev/ponsfamily/commit/836f0f97f9a9569855876570d6778501c163c883)
and pins the verified live [factory](https://robinhoodchain.blockscout.com/address/0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e)
and [hook](https://robinhoodchain.blockscout.com/address/0xE5e702641Ea86F4ae6cC3cDaeD2B886f976Be044)
runtime code hashes.

The production-facing verifier models these Pons v2 facts:

- `PonsV2LaunchFactory.getLaunchedToken(token)` is the canonical launch record.
- `deployer` is the immutable launch creator. The mutable
  `creatorFeeRecipient` does not control Funding Bands.
- Funding Bands activation requires `GraduationPhase.PoolCreated`.
- The graduated `PoolKey` is reconstructed from the record's pair token, pool
  fee, tick spacing, and shared `PonsV2MemeHook`.
- The launch token must independently report the same factory, deployer, and
  bonding curve as the factory record.
- Only native ETH quotes are accepted. The live Pons v2 factory currently rejects
  WETH with `PairTokenNotApproved()`; enabling it later requires a new reviewed
  immutable profile and live-fork lifecycle.
- Pons v2's hook enables `beforeInitialize` and `afterSwap`, but no add/remove
  liquidity callback. Funding Bands therefore freezes empty v4 hook data for
  this profile.

Pons v2 does not store the original configured supply in its per-token launch
record. For escrowed launches, the verifier snapshots `totalSupply()` in the
atomic launch transaction, before holders can burn. Activation preserves that
snapshot as the market-cap denominator, permits a lower live supply caused by
burns, and rejects any supply increase. Legacy creator-activated accounts retain their historical
post-graduation snapshot behavior.

## Local tests

`test/SinjohPonsV2Profile.t.sol` covers:

1. Canonical graduated launch resolution and exact `PoolId` reconstruction.
2. Rejection before graduation, for unsupported quote assets, counterfeit token
   metadata, and non-empty launch data.
3. Native-ETH Pons v2 mint, later increase, full burn/settlement, ETH wrapping,
   exact 1% protocol fee, and creator snapshotting.
4. Rejection of WETH-quoted records until the live Pons v2 factory supports them.
5. The full ten-band Pons v2 create-and-fund batch using canonical v4 StateView.
6. Archive/event-confirmed crossing, rejection before the immutable 15-second
   delay, hidden-reversal resets, and permanent eligibility after confirmation.

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
launches through the reviewed adapter generation, atomically escrows first-buy
inventory, graduates through the real Pons contracts, permissionlessly creates
and funds the saved band, crosses it with a real hooked v4 swap, burns the
position, receives native ETH from the canonical PoolManager, wraps it, verifies
the 1% fee and liabilities, and delivers the exact net assets to a code-hash-pinned
Fee Router while delivering the protocol fee separately. The creator performs no post-graduation
Funding Bands transaction. `SinjohV4ConfirmedBandPriceGuard` uses live canonical
StateView for create, fund, and arm operations, then requires a byte-identical
Alchemy/Envio replay of finalized v4 Swap history. A reversal restarts the timer;
confirmation after 15 uninterrupted seconds is permanent and has no execution expiry.

The fork also uses `SinjohV3EthUsdOracle` against the live canonical WETH/USDG
v3 pool: a 15-minute TWAP, 5% maximum spot/TWAP deviation, and `1e18` raw
liquidity floor. No ETH/USD signer or publisher is involved. This is still not an audit
or deployment authorization; the Fee Router runtime hash and all exact deployment
inputs must be rehearsed and independently reviewed before immutable deployment.
