# Simplified Yield Banks Holdings Research

## Executive Summary

- **Building:** Direct Stock Token and USDG custody plus a minimal manual adapter path for future
  Delta `$INJOH/WETH` positions.
- **Verdict:** **Build with caution** — the generic control plane is ready, but a concrete Delta
  adapter is not safe to activate from the currently verified lifecycle.
- **Top risk:** An incomplete Delta entry/exit path can strand collection backing.
- **Must decide first:** Bind the exact `$INJOH` token, Delta product, pool, conversion route, and
  full redemption lifecycle before Delta activation.
- **Watch out for:** Stock Token dividends are already reinvested through `uiMultiplier()`; no
  separate dividend claim is required.

## Risk Heatmap

| Component | Critical | High | Medium | Low |
|---|---:|---:|---:|---:|
| OpenZeppelin Contracts | 0 | 0 | 1 | 1 |
| Robinhood Stock Tokens | 1 | 1 | 0 | 0 |
| Delta Liquidity | 1 | 1 | 0 | 0 |
| **Total** | **2** | **2** | **1** | **1** |

**Critical & High, by name:**

1. **CRITICAL — Stock Tokens: restricted-holder incompatibility.**
2. **CRITICAL — Delta: incomplete entry and exit lifecycle.**
3. **HIGH — Stock Tokens: multiplier double counting.**
4. **HIGH — Delta: two-asset and streamed-reward accounting.**

## Components Researched

| Component | Version | Source found | Status |
|---|---|---|---|
| OpenZeppelin Contracts | 5.6.1 | Official GitHub release and installed source | Reused from cache (fetched 2026-08-27) |
| Robinhood Stock Tokens | unversioned | Official Robinhood Chain docs | Fresh this run |
| Delta Liquidity | unversioned | Official Delta docs and verified Blockscout source | Fresh this run |

## What a Coding Agent Must Know Before Starting

1. Stock Tokens are held directly; do not implement dividend claiming.
2. USDG is held directly; remove the ERC-4626 lending adapter.
3. Keep adapters synchronous and manually operated for the MVP.
4. Allowlist adapters by sleeve, accounting asset, address, and runtime code hash.
5. Remove canary, risk-class, audit-hash, queued-withdrawal, and generic-harvest machinery.
6. Add an operator bridge so the collection allocator can actually call sleeve adapter actions.
7. Keep the concrete Delta adapter disabled until all position lifecycle bindings are complete.

## Pre-coding Decisions Required

- No decision is required to build direct Stock Token and USDG custody or the generic adapter path.
- Delta activation later requires exact token, pool, product, route, ABI, addresses, runtime hashes,
  caps, and proportional/full-exit semantics.

## Requirements Corrections

- Replace “collect stock dividends” with “hold Stock Tokens whose multiplier reinvests dividends.”
- Replace “USDG Yield” naming with “USDG” because no lending or yield strategy is active.
- A verified position builder alone is not a complete Delta adapter lifecycle.

## What This Report Prevents

- A fake dividend-claim subsystem.
- Accidental USDG lending.
- Activating an unverified Delta zap.
- A manual operator path that exists in tests but is unreachable in the deployed topology.

Run summary: two components researched fresh and one reused from cache. `--fresh` forces a full
re-research.
