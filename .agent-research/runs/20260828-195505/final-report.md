# Simplified Yield Banks Holdings Research

## Executive Summary

- **Building:** Direct Stock Token and USDG custody plus a manual, self-custodied Delta
  `$INJOH/WETH` ladder adapter.
- **Verdict:** **Build with caution** — the complete lifecycle is verified and implementable; each
  production collection must still supply and review its exact market bindings.
- **Top risk:** A mismatched Delta token, pool, route, or runtime hash can direct backing into the
  wrong market.
- **Must decide first:** Pin the collection-specific `$INJOH` token, pool, feeds, routes, position
  limit, and allocation cap in the reviewed deployment plan.
- **Watch out for:** Live V3 fees are conservatively omitted from NAV until collected.

## Risk Heatmap

| Component | Critical | High | Medium | Low |
|---|---:|---:|---:|---:|
| OpenZeppelin Contracts | 0 | 0 | 1 | 1 |
| Robinhood Stock Tokens | 1 | 1 | 0 | 0 |
| Delta Liquidity | 0 | 1 | 1 | 0 |
| **Total** | **1** | **2** | **2** | **1** |

**Critical & High, by name:**

1. **CRITICAL — Stock Tokens: restricted-holder incompatibility.**
2. **HIGH — Stock Tokens: multiplier double counting.**
3. **HIGH — Delta: activation binding mismatch.**

## Components Researched

| Component | Version | Source found | Status |
|---|---|---|---|
| OpenZeppelin Contracts | 5.6.1 | Official GitHub release and installed source | Reused from cache (fetched 2026-08-27) |
| Robinhood Stock Tokens | unversioned | Official Robinhood Chain docs | Fresh this run |
| Delta Liquidity | unversioned | Official Delta docs and verified Blockscout source | Fresh this run |

## What a Coding Agent Must Know Before Starting

1. Stock Tokens are held directly; do not implement dividend claiming.
2. USDG is held directly; do not implement lending.
3. Keep all strategy actions synchronous and manually operated.
4. Bind adapters and every integration by exact address and runtime code hash.
5. Use the verified Delta builder to mint caller-owned ordinary V3 position NFTs.
6. Self-custody, decrease, collect, and burn those NFTs through the bound position manager.
7. Return residual WETH and `$INJOH` in kind on complete exit.
8. Keep collection market selection and transaction rungs/slippage values configurable.

## Pre-coding Decisions Required

- The contract lifecycle needs no additional product decision.
- Production activation requires exact token, pool, feeds, routes, addresses, runtime hashes,
  maximum positions, cap, and operator-loss policy in the collection's reviewed inputs.

## Requirements Corrections

- Replace “collect stock dividends” with direct custody of multiplier-rebasing Stock Tokens.
- Replace “USDG Yield” naming with “USDG.”
- Use the verified ladder builder and standard V3 lifecycle, not the unverified zap or staking path.

## What This Report Prevents

- A fake dividend-claim subsystem.
- Accidental USDG lending.
- Reliance on an unverified Delta zap or staking contract.
- Hard-coded pool selection, ladder geometry, allocation percentages, or slippage.
- A position that cannot be completely decreased, collected, burned, and returned in kind.

Run summary: two components researched fresh and one reused from cache. `--fresh` forces a full
re-research.
