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
| 2 | GOOGL | `0x2e0847E8910a9732eB3fb1bb4b70a580ADAD4FE3` | 500 | `0x778f2a0cF24E8D12fE3730C87Fe1448d47E66Add` |
| 3 | TSLA | `0x322F0929c4625eD5bAd873c95208D54E1c003b2d` | 3000 | `0xA953CA88ff430e9487c60cA34d757414f4efdA07` |
| 4 | COIN | `0x6330D8C3178a418788dF01a47479c0ce7CCF450b` | 3000 | `0x6707aeAc7D0e519B083219d27BB427364363183A` |
| 5 | AAPL | `0xaF3D76f1834A1d425780943C99Ea8A608f8a93f9` | 500 | `0x8bb3514e2204E1cDF3Ac149EFEe7Ff04D91B719f` |
| 6 | NVDA | `0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC` | 3000 | `0xC0Be1cb0f674D9737C72B2A63fC542361185b807` |
| 7 | MSTR | `0xec262a75e413fAfD0dF80480274532C79D42da09` | 10000 | `0x70504a6FafdbfB75fE971FAA4dD716e79aC5624c` |

Every route uses the reviewed mainnet `SinjohSimpleSwapAdapter` deployment
`0xc9F600ebaf9EE1F4a24568D2e4Af9E8df1e07D7B` (runtime code hash
`0x17b8eecc60ff9af5768240b0384e96c4e54fd8611355297e45146303294c6ac6`) with
`routeData = abi.encode(uint24(fee))` and empty guard data. Do not use its superseded v1-router
deployment. The route's price guard must be a `SinjohSharedV3TwapPriceGuard` deployed for the same
fee tier with `twapWindow = 300` seconds. The existing mainnet guard
`0xfdd4f594a9f7cd17fee0bbf2859f4eea3265f328` is an immutable 10000-fee, 900-second guard and is not
valid for this five-minute configuration. Fresh 500, 3000, and 10000 guards must be deployed with
the reviewed bounds only after the full testnet gate passes.

## Asset integrity: the stocks are upgradeable proxies

Every approved stock is the same `BeaconProxy` bytecode behind one shared beacon
(`0xe10b6f6B275de231345c20D14Ab812db62151b00`); Robinhood can upgrade the implementation for
all eight at once. The reviewed implementation (`0xb35490…5aE2`, codehash pinned in
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
RAFFLE_GUARD_500=0x… RAFFLE_GUARD_3000=0x… RAFFLE_GUARD_10000=0x… MAX_PRIZE=… forge script script/PreflightStockRoutes.s.sol:PreflightStockRoutes --rpc-url https://rpc.mainnet.chain.robinhood.com
```

It never broadcasts. For each of the eight routes it resolves the canonical pool, requires
observation cardinality at or above the guard's minimum and a full five-minute window of history,
requires the guard's immutable parameters to match the reviewed values, requires the guard's fee
tier to equal the fee the adapter will actually swap in, takes a real quote at the largest slot
the configured `MAX_PRIZE` can produce, and then executes that swap through the real adapter
against the real pool and requires the guard's own minimum to clear. It reports every failure in
one run rather than stopping at the first, and exits non-zero if any route fails.

`checkRoute(index, guard, amountIn)` re-checks a single route after priming, without paying for
the other seven.

The route table above is generated from `script/StockRouteManifest.sol`, which is the source of
truth. Changing a route is a reviewed code change that the preflight re-checks.

### What the preflight cannot establish

- **Asset identity.** That `0xec26…da09` is the approved MSTR deployment and not a lookalike is a
  registry question. Verify it against the official Robinhood asset registry, once, by hand.
- **Sustained liquidity.** It proves one swap clears the guard's bound at one block. It says
  nothing about depth an hour later.
- **Authorization.** A pass is a mechanical result. It is not permission to deploy.

As of the recorded block the preflight fails: AAPL, GOOGL, and RDDT sit at observation cardinality
1, which the guard rejects outright, and no five-minute guard exists yet for any fee tier. With
`claimFunding` a dead route degrades to a WETH payout rather than a lost prize, but it is still a
permanently degraded product on a fixed share of every future round.

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

Set the raffle's immutable `maxPrize` from the shallowest selected pool, not the average pool. Pass
the candidate value as `MAX_PRIZE`: the preflight derives the largest slot share the raffle can
produce — `maxPrize` split by `winnersPerRound` plus the division remainder, less both floored tax
shares — and probes every route at exactly that size. A `MAX_PRIZE` that no route can absorb fails
the gate rather than surviving to an immutable deployment.

This is also where a guard's hard input bound is caught. `SinjohSharedV3TwapPriceGuard` reverts for
`amountIn > type(uint128).max`, unreachable for any WETH prize;
`SinjohV3RouteTwapPriceGuard` reverts above its reviewed per-route `maxAmountIn`, which is
reachable. Both are immutable, live in a different package from `maxPrize`, and are compared
nowhere on-chain — the preflight compares them by taking a real quote at the real maximum.
