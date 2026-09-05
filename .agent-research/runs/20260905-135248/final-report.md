# Pons stock-pair expansion

## Executive Summary

Sinjoh can expose all 53 canonical Pons-approved stocks for token launches immediately. Twenty-six
stocks also have a direct WETH conversion route that passed the complete raffle preflight at 0.01
WETH on 2026-09-05. **Verdict: Ready to build with deployment gates.** The top risk is freezing a
stale or non-executable route into an immutable raffle. The first irreversible decision is the
raffle's stock/adapter/guard route set. The biggest remaining product gap is protocol-owned stock
inventory for the 27 assets without a ready direct guarded route.

## Risk Heatmap

| Component | Critical | High | Medium | Low |
|---|---:|---:|---:|---:|
| Pons V2 Factory | 0 | 1 | 1 | 0 |
| Robinhood registry/tokens | 0 | 1 | 1 | 0 |
| Pons V3 routes | 0 | 2 | 1 | 0 |
| **Total** | **0** | **4** | **3** | **0** |

High risks: stale launch allowlists; upgradeable stock-token behavior; immutable raffle routes that
cannot execute; guard/adapter fee-tier mismatch.

## Inventory and capability

- **53/53 stocks:** launch pair support. The factory approval is the gate, not market liquidity.
- **26/53 stocks:** WETH-funded fixed-stock raffle support now, subject to a deployment-time live
  preflight at the actual maximum per-slot prize.
- **1/53 additional stock (GOOGL):** funded route exists; deploy and preflight a fee-100 guard.
- **26/53 remaining stocks:** direct stock funding works at the ERC-20 payout layer, but automatic
  WETH conversion needs a new route or reserved protocol inventory.

The full canonical address and route inventory is in `asset-inventory.md`.

## What the coding agent must know

1. The Pons V2 launch adapters are already generic. Remove the UI's stale hand-curated pair list
   as an authority and populate from the factory's complete approval history, with a pinned
   fallback snapshot.
2. Keep asset identity address-first. Labels and tickers are display metadata only.
3. Raise both raffle implementations' stock-reward ceiling from 16 to 64, update tests/ABIs, and
   deploy a new immutable implementation/factory generation before configuring more than 16.
4. Add all 26 passing routes to the certified manifest for fixed-stock raffles. Until the new
   raffle generation is deployed, keep mystery-stock creation at 16 or fewer routes.
5. Add fee-100 guard deployment and preflight support, then add GOOGL only after the deployed guard
   passes live checks.
6. Re-run the preflight immediately before every raffle-generation deployment. A 2026-09-05 pass
   is evidence, not permanent certification.
7. Build inventory reservation as a separate custody/operations milestone: reserve exact output
   before accepting a buy or creating a raffle, release on cancellation/failure, and replenish only
   through authorized acquisition.

## Pre-coding decisions

- The new raffle ceiling is 64, leaving room for the current 53 stocks without an unbounded loop.
- Existing raffle generations remain unchanged; the higher-cap implementation is a new generation.
- Market routes and stock inventory are separate fulfillment providers behind one availability
  decision. WETH fallback remains an execution-failure path, not the normal support definition.

## What this research prevents

It prevents treating Pons approval as proof of liquidity, shipping a 53-item UI against a 16-item
immutable contract limit, using a pool at a fee tier the guard does not price, and accepting a
raffle whose promised stock cannot be reserved or bought.

Run summary: 3 components researched fresh, 0 reused from cache. `--fresh` forces a full re-check.

