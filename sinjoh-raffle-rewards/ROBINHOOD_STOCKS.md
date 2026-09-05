# Robinhood Chain mainnet approved stock routes

The testnet-first rollout and controlled-mirror requirements are in
[`TESTNET_STOCK_REWARDS.md`](./TESTNET_STOCK_REWARDS.md). Nothing in this file authorizes a mainnet
broadcast.

Production mystery-stock raffles use WETH
`0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73` as their accounting asset and the
following immutable, address-sorted `stockRewards` list. The pool observations below were read
from the canonical V3 factory at Robinhood Chain block `25200376` on 2026-08-01.

| Index order | Symbol | Asset | V3 fee | Canonical WETH pool |
|---:|---|---|---:|---|
| 0 | RDDT | `0x05b37Fb53A299a1b874A619e1c4C404D52C36F4C` | 10000 | `0xA541143F20D7b0643123064aBF25F423E375b531` |
| 1 | GME | `0x1b0E319c6A659F002271B69dB8A7df2F911c153E` | 500 | `0xc6BCC95043DC48C204bB2D57fb264a10Efe0a607` |
| 2 | TSLA | `0x322F0929c4625eD5bAd873c95208D54E1c003b2d` | 3000 | `0xA953CA88ff430e9487c60cA34d757414f4efdA07` |
| 3 | COIN | `0x6330D8C3178a418788dF01a47479c0ce7CCF450b` | 3000 | `0x6707aeAc7D0e519B083219d27BB427364363183A` |
| 4 | AAPL | `0xaF3D76f1834A1d425780943C99Ea8A608f8a93f9` | 500 | `0x8bb3514e2204E1cDF3Ac149EFEe7Ff04D91B719f` |
| 5 | NVDA | `0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC` | 3000 | `0xC0Be1cb0f674D9737C72B2A63fC542361185b807` |
| 6 | MSTR | `0xec262a75e413fAfD0dF80480274532C79D42da09` | 10000 | `0x70504a6FafdbfB75fE971FAA4dD716e79aC5624c` |

Every route uses the reviewed mainnet `SinjohSimpleSwapAdapter` deployment
`0xc9F600ebaf9EE1F4a24568D2e4Af9E8df1e07D7B` (runtime code hash
`0x17b8eecc60ff9af5768240b0384e96c4e54fd8611355297e45146303294c6ac6`) with
`routeData = abi.encode(uint24(fee))` and empty guard data. Do not use its superseded v1-router
deployment. The pinned production guards are `0xDad51edC925D4CCd46c1229763F40d1F32c7480C`
for fee 500, `0xd01273Fa749BF16e333cFB85D27fD11A82D1515D` for fee 3000, and
`0xf81d21e0b51A7DD815f44682B63b7e732E0b4803` for fee 10000. Each is a
`SinjohSharedV3TwapPriceGuard` with `twapWindow = 300` seconds; its runtime hash and immutable
parameters are verified by the preflight.

## Asset integrity: the stocks are upgradeable proxies

Every approved stock is the same `BeaconProxy` bytecode behind one shared beacon
(`0xe10b6f6B275de231345c20D14Ab812db62151b00`); Robinhood can upgrade the implementation for
all of them at once. The reviewed implementation
(`0xb35490d6f9163DE4F80d88dc75c3516eb64C5aE2`, codehash pinned in
`StockRouteManifest`) has three properties the raffle depends on, all verified from source:

- **Raw balances, 18 decimals.** `balanceOf`/`transfer` move raw units; stock splits change a
  separate `uiMultiplier()` and never touch balances, so the raffle's exact-delta delivery
  and all on-chain accounting are split-proof. Display layers must show
  `raw × uiMultiplier()`.
- **No transfer fee.** Exact-amount transfers, which `_sendExactAsset` requires; a skimming
  upgrade would strand stock payouts in undeliverable credits.
- **Discretionary pause** (`paused()`, role-set, not automatic market hours). While paused,
  swaps and deliveries revert: claims stay retryable, deferred credits wait, and the
  winner's `claimFunding` WETH fallback remains available in the window tail. Nothing is
  lost; delivery is delayed.

The preflight enforces all of this every run: beacon identity, implementation codehash
(an upstream upgrade fails the gate and forces re-review), decimals, live pause state, and
a real post-swap exact-transfer probe.

## The gate is a command, not a checklist

Every mechanical precondition below is checked by `script/PreflightStockRoutes.s.sol` against live
chain state. Run it; do not re-derive it by hand.

```bash
forge script script/PreflightStockRoutes.s.sol:PreflightStockRoutes --rpc-url https://rpc.mainnet.chain.robinhood.com
```

It never broadcasts. For each of the seven certified routes it verifies the pinned guard runtime
hash, resolves the canonical pool, requires
observation cardinality at or above the guard's minimum and a full five-minute window of history,
requires the guard's immutable parameters to match the reviewed values, requires the guard's fee
tier to equal the fee the adapter will actually swap in, takes a real quote at the route's
launch-time WETH cap, and then executes that swap through the real adapter
against the real pool and requires the guard's own minimum to clear. It reports every failure in
one run rather than stopping at the first, and exits non-zero if any route fails.

`checkRoute(index, guard, amountIn)` re-checks a single route after priming, without exercising
the other six.

The route table above is generated from `script/StockRouteManifest.sol`, which is the source of
truth. Changing a route is a reviewed code change that the preflight re-checks.

### What the preflight cannot establish

- **Asset identity.** That `0xec26…da09` is the approved MSTR deployment and not a lookalike is a
  registry question. Verify it against the official Robinhood asset registry, once, by hand.
- **Sustained liquidity.** It proves one swap clears the guard's bound at one block. It says
  nothing about depth an hour later.
- **Authorization.** A pass is a mechanical result. It is not permission to deploy.

The seven routes above passed a full production-fork preflight on 2026-09-05. GOOGL at
`0x2e0847E8910a9732eB3fb1bb4b70a580ADAD4FE3` remains excluded because its pool cannot clear the
reviewed WETH bound. With `claimFunding` a later-degraded route falls back to a WETH payout rather
than losing the prize, but the launch gate must still be rerun before changing the certified set.

## Remediation

Both failures are fixed by one broadcast, fork-tested end to end in
`sinjoh-liquidity-manager/test/DeployRafflePriceGuardsMainnet.fork.t.sol`:

```bash
cd sinjoh-liquidity-manager
forge script script/DeployRafflePriceGuardsMainnet.s.sol:DeployRafflePriceGuardsMainnet --rpc-url https://rpc.mainnet.chain.robinhood.com --account sinjoh-deployer --sender 0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49 --broadcast
```

It deploys the three five-minute guards, primes every route pool below the target capacity, and
seeds an observation into each pool stuck at cardinality 1 — with escalating swap sizes, because a
V3 pool only writes an observation when a swap moves its tick, and it verifies the write happened
rather than assuming it. Re-running against healthy pools deploys fresh guards and spends nothing
else. Wait five minutes for the TWAP window to fill, then run the preflight with the three
returned guard addresses.

Priming is monotonic and normally happens once per pool and target cardinality. A new guard or a
shorter window does not require another `prime` transaction when the pool's existing
`observationCardinalityNext` is already large enough. A new/replaced pool or a later decision to
raise the target capacity does. Priming reserves capacity but does not backfill observations;
swaps must populate the buffer and the pool must still retain a full five minutes of history.

## Prize sizing

Set the raffle's immutable `maxPrize` from the shallowest selected pool, not the average pool. The
production preflight probes every route at its complete reviewed WETH input cap. The launch UI then
sets the round maximum from the lowest selected route cap and rejects any creator-entered maximum
above it. Mystery mode therefore inherits GME's lower cap, while a specific-stock raffle may use
that selected route's higher cap.

This is also where a guard's hard input bound is caught. `SinjohSharedV3TwapPriceGuard` reverts for
`amountIn > type(uint128).max`, unreachable for any WETH prize;
`SinjohV3RouteTwapPriceGuard` reverts above its reviewed per-route `maxAmountIn`, which is
reachable. Both are immutable, live in a different package from `maxPrize`, and are compared
nowhere on-chain — the preflight compares them by taking a real quote at the real maximum.
