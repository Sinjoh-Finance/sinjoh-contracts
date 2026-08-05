# Testnet-first stock reward rollout

All stock-reward infrastructure and the complete keeper-driven raffle lifecycle must pass on
Robinhood Chain testnet (`46630`) before any mainnet deployment is authorized. Testnet deployment
does not authorize a later mainnet broadcast.

## Testnet is a controlled mirror

The Robinhood asset registry currently lists the approved AAPL, COIN, GME, GOOGL, MSTR, NVDA,
RDDT, and TSLA deployments only on mainnet (`4663`). Their mainnet contracts have no code at the
same addresses on testnet. A token on testnet with a matching name or symbol is not evidence that
it is an approved Robinhood Stock Token.

Use eight clearly named, test-only ERC-20 mirrors for the end-to-end test. They exercise selection,
accounting, decimals, swaps, delivery, retry, indexing, and keeper reconciliation; they do not
validate the identity or liquidity of the production assets. Record every mirror token, pool,
adapter, guard, factory, randomness adapter, raffle factory, and raffle address in a new testnet
deployment manifest before enabling the keeper.

Verified testnet dependencies as of 2026-08-01:

| Dependency | Address | Runtime code hash |
|---|---|---|
| WETH | `0x37E402B8081eFcE1D82A09a066512278006e4691` | `0xa7f01c02394c333cc82f3236a0212384759ac2b0a4b982db822e3ff691e6567d` |
| Pons V3 factory | `0xFECCB63CD759d768538458Ea56F47eA8004323c1` | `0x2b8f65119f8e463cf1391bb1e6484aa0abb829214c5d3d2ff9d2736381824ab6` |
| Pons V3 router | `0x1b32F47434a7EF83E97d0675C823E547F9266725` | `0xac3b33c22775c9671078d06575f1c25cf98f3c607fe11b454f3d75ebf19622ae` |

The testnet router uses the deadline-bearing Uniswap V3 router ABI. Use the immutable per-route
`SinjohUniswapV3SwapAdapter`, not the mainnet `SinjohSimpleSwapAdapter`, and activate each adapter
only after its canonical factory pool exists.

## Five-minute guards

Deploy one `SinjohSharedV3TwapPriceGuard` for each fee tier `500`, `3000`, and `10000`. All three
must use:

- `twapWindow = 300` seconds;
- `maxSpotDeviationBps = 1000`;
- `maxOutputSlippageBps = 750`;
- `validityPeriod = 300` seconds; and
- `comparisonAmount = 1 ether`.

The chain-locked deployment script is
`../sinjoh-liquidity-manager/script/DeployRafflePriceGuardsTestnet.s.sol`. It checks chain ID
`46630`, the expected deployer, and the V3 factory runtime hash before broadcasting.

```sh
cd sinjoh-liquidity-manager
DEPLOYER_PRIVATE_KEY=... forge script \
  script/DeployRafflePriceGuardsTestnet.s.sol:DeployRafflePriceGuardsTestnet \
  --rpc-url https://rpc.testnet.chain.robinhood.com \
  --broadcast
```

The five-minute window is intentionally less manipulation-resistant than the old fifteen-minute
window. The guard still fails closed when the pool lacks five minutes of history or when spot is
more than 10% from the TWAP, and the swap still requires at least 92.5% of the TWAP output.

## Priming lifecycle

`prime(tokenA, tokenB, cardinality)` calls the V3 pool's monotonic
`increaseObservationCardinalityNext`. For a given pool and target capacity, this is normally a
one-time transaction. It must be called again only when:

- a new pool replaces or supplements the old pool;
- the desired target cardinality is higher than the pool's existing
  `observationCardinalityNext`; or
- a fresh testnet deployment starts after the network or pool state is reset.

Changing guard addresses or shortening the TWAP window does not erase pool observations and does
not require re-priming a pool that already has sufficient capacity. Priming also does not backfill
history: swaps must subsequently initialize observations, and at least 300 seconds of usable
history must exist before the five-minute guard can quote. Size cardinality from measured swap
frequency, then verify `observe([300, 0])`; do not assume that cardinality `2` is sufficient.

## Release gate

Complete these steps in order on testnet:

1. Deploy the eight explicitly test-only stock mirrors.
2. Create and fund their WETH V3 pools across the same `500`/`3000`/`10000` fee-tier mix intended
   for production.
3. Deploy and activate one immutable V3 swap adapter per route.
4. Deploy the three five-minute shared guards.
5. Prime every selected pool once to its measured target cardinality, then generate ordinary small
   swaps until every pool retains at least five minutes of history.
6. Run the route preflight until it passes. It replaces what used to be three separate manual
   steps — confirming cardinality, confirming a full window of history, taking a live quote, and
   executing a guarded swap on every route — and reports every remaining failure in one run:

   ```bash
   RAFFLE_GUARD_500=0x… RAFFLE_GUARD_3000=0x… RAFFLE_GUARD_10000=0x… MAX_PRIZE=… forge script script/PreflightStockRoutes.s.sol:PreflightStockRoutes --rpc-url https://rpc.testnet.chain.robinhood.com
   ```

   The manifest it checks pins the **mainnet** route set, so on testnet either point
   `StockRouteManifest.routes()` at the mirrors for the run or use `checkRoute` per mirror. Do not
   edit the mainnet addresses to make a testnet run pass.
7. Deploy the randomness adapter with
   `sinjoh-randomness/script/DeployEcvrfRandomnessTestnet.s.sol`, then deploy the raffle factory
   with `sinjoh-raffle-rewards/script/DeployRaffleRewardsFactoryTestnet.s.sol`. Create the immutable
   eight-route raffle and run funding, commit, randomness, automatic keeper claim, stock delivery,
   forced delivery failure, durable-credit retry, expiry, and restart reconciliation.
8. Confirm the indexer agrees with on-chain balances and liabilities for WETH and every stock.

Mainnet remains a separate release gate. Re-resolve the official asset registry, pools, depths,
runtime hashes, and prize sizing immediately before deployment; testnet success cannot substitute
for those checks.
