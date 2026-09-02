# Brainblast Research Report

**Run:** 20260831-162733
**Requirements:** Dynamic Delta pool discovery without per-pool manifests or governance
**Date:** 2026-08-31

## Executive Summary

- **Building:** Versioned Delta infrastructure admission with onchain pool discovery and
  pool-specific isolated execution created without per-pool governance.
- **Verdict:** Ready to build. Canonical pool identity and the live infrastructure tuple are
  source-verifiable.
- **Top risk:** A canonical pool may still contain a hostile token; manual execution and exact
  transfer/slippage checks must remain.
- **Must decide first:** Existing integrations are immutable generations; upgrades add a new
  generation rather than changing live adapters.
- **Watch out for:** Discovery is not investment approval. Capital remains manually executed.

## Risk Heatmap

| Component | Critical | High | Medium | Low |
|---|---:|---:|---:|---:|
| Robinhood Chain | 0 | 1 | 1 | 0 |
| Uniswap V3 | 0 | 1 | 2 | 0 |
| Delta position builder | 0 | 1 | 1 | 0 |
| OpenZeppelin Contracts | 0 | 0 | 1 | 1 |
| **Total** | **0** | **3** | **5** | **1** |

**Critical and High risks:**

1. **HIGH — Robinhood Chain: permissionless assets can be malicious.**
2. **HIGH — Uniswap V3: slippage and range manipulation.**
3. **HIGH — Delta builder: unversioned deployment drift.**

## Components researched

| Component | Version | Source | Status |
|---|---|---|---|
| Robinhood Chain | chain 4663 | official docs and live RPC | Fresh this run |
| Uniswap V3 | v3 plus official 2026-05-22 chain-4663 deployment | official docs/source | Reused from cache (fetched 2026-08-27), chain deployment refreshed |
| Delta position builder | unversioned live deployment | explorer and live RPC | Fresh this run |
| OpenZeppelin Contracts | 5.6.1 | installed source and official release | Reused from cache (fetched 2026-08-27) |

## What a coding agent must know before starting

1. Pin approved infrastructure tuples, not pools.
2. Validate `pool.factory()`, `token0`, `token1`, `fee`, factory `getPool`, runtime hash,
   initialization, unlocked state, and nonzero liquidity onchain.
3. Do not let discovery bypass the manual allocation operator, slippage, tick, deadline, cap, or
   owner-loss controls.
4. Keep pool accounting isolated. A common fungible sleeve spanning unrelated pools would make an
   owner's selected pool inaccurate.
5. Emit materialization/version events so the indexer and UI can discover pools without release
   manifest enumeration.
6. Approve new Delta deployments as new generations. Pause deposits and exit old generations; do
   not mutate their dependencies.

## Pre-coding decisions required

- **Immutable integration generations:** approved. New generations are additive and
  governance-controlled.
- **Pool admission:** deterministic and permissionless under an approved generation; no per-pool
  governance or manifest entry.
- **Capital execution:** remains restricted to the allocation operator/guardian controls already
  defined by the protocol.

## Requirements corrections

- Remove `deltaPools` as a release-manifest authorization list.
- Replace timelock-only per-pool registration with deterministic onchain materialization.
- Treat `$INJOH`/WETH as a featured collection choice, not a protocol constant.

## What this report prevents

- Governance and deployment work growing linearly with pool count.
- Silently trusting an indexer or UI-provided pool address.
- Repointing live custody contracts when Delta deploys a new generation.
- Treating permissionless discovery as permission to invest automatically.

Run summary: 2 components fresh, 2 reused from cache. `--fresh` forces a full re-research.
