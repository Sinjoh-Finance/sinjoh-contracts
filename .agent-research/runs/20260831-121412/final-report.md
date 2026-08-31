# Brainblast Research Report

**Run:** 20260831-121412
**Requirements:** Source-verified owner-selectable Delta V3 pools with isolated Yield Bank accounting
**Date:** 2026-08-31

## Executive Summary

- **Building:** A pool-neutral Delta V3 strategy layer where each Yield Bank owner can select one
  admitted pool without sharing that selected exposure with unrelated owners.
- **Verdict:** Build with caution. The implementation and live canary pass; production activation
  remains intentionally blocked until the exact `$INJOH` token, pool, feeds, routes, thresholds,
  and hashes exist in a completed release manifest.
- **Top risk:** Proxy implementations and pool state can change after review.
- **Must decide first:** Every pool needs a separate restricted sleeve and adapter plus an
  independent, manifest-bound price reference.
- **Watch out for:** Pool existence proves identity, not token suitability, liquidity, oracle
  integrity, or future code stability.

## Risk Heatmap

| Component | Critical | High | Medium | Low |
|---|---:|---:|---:|---:|
| Robinhood Chain | 0 | 1 | 1 | 0 |
| Delta V3 builder | 0 | 1 | 1 | 0 |
| Uniswap V3 | 0 | 1 | 1 | 0 |
| **Total** | **0** | **3** | **3** | **0** |

**High risks:** permissionless pool admission, unversioned deployment/proxy drift, and thin or
manipulable pool pricing.

## Components researched

| Component | Version | Source found | Status |
|---|---|---|---|
| Robinhood Chain | 4663 | official chain documentation and live RPC | Fresh this run |
| Delta V3 builder | unversioned live deployment | explorer source and live RPC | Fresh this run |
| Uniswap V3 | v3-core 1.0.1 | official documentation and source | Fresh this run |

## Verified implementation facts

1. The builder at `0x6235cF6bd8419b34942F4EDDB39C880BD96dD700` reports factory
   `0x1f7d7550B1b028f7571E69A784071F0205FD2EfA`, position manager
   `0x73991a25C818Bf1f1128dEAaB1492D45638DE0D3`, and WETH
   `0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73`.
2. Its exact `mintLadder` struct order and return value were matched to the source. The adapter
   consumes returned IDs and re-verifies position owner, pool identity, pair, fee, and liquidity.
3. One pool-specific adapter and restricted sleeve isolate each admitted pool. `$INJOH` is not
   hard-coded in the adapter or owner-selection model.
4. Release verification checks the builder, manager, factory, factory `getPool`, pool identity,
   fee, tick spacing, nonzero liquidity, unlocked state, routes, adapter, sleeve, strategy registry,
   allocator bindings, caps, and runtime hashes.
5. WETH and USDG are EIP-1967 proxies. Their active implementations and implementation hashes are
   bound separately from the proxy runtime.
6. Pool-TWAP pricing requires minimum liquidity, observation age/cardinality, spot/TWAP deviation,
   a separately reviewed WETH/USD source, and an independent manifest-bound reference source.
7. Owner rebalance loss is checked across the total oracle-valued portfolio. A paused-state,
   oracle-independent in-kind guardian exit exists for risk reduction.
8. An NFT with an active dynamic Delta allocation must rebalance out before the oracle-free burn
   path. The API, indexer, SDK, and UI use the canonical active pool field.
9. The live fork minted, tracked, valued, and completely exited a real position through the
   deployed builder.

## Pre-coding and activation decisions

- **Pool isolation model:** separate restricted sleeve and adapter for every admitted Delta pool.
- **Admission authority:** collection timelock registration after deterministic validation.
- **Price authority:** no same-pool TWAP may be the sole material-price source.
- **Activation inputs:** exact paired token, pool, fee, tick spacing, route pair, direct/reference
  feeds, minimum liquidity, caps, loss limits, source provenance, and hashes.

## Requirements corrections

- `$INJOH` is a future collection input, not an adapter constant.
- “Any existing Delta pool” means any separately reviewed and registered pool, not arbitrary UI
  address entry.
- The operations reserve and its fee leg were removed because they were not requested.
- Stock Tokens represent economic exposure through standard ERC-20s and multiplier-adjusted prices;
  they are not direct legal ownership of the referenced security or a separate dividend cash leg.

## Residual external condition

No `$INJOH` token or `$INJOH`/WETH pool address was provided. No value was guessed. The generic
protocol implementation is complete, but a production collection cannot activate that sleeve until
those deployed facts and independent price inputs pass the same-block manifest verifier and fork
test. This is an explicit release gate rather than an assumption embedded in code.

Run summary: 3 components researched fresh, 0 reused. `--fresh` forces a full re-research.
