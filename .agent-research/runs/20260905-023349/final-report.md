# Brainblast Research Report

**Run:** 20260905-023349  
**Requirements:** Restore reviewed Flap launches and prove stock-raffle binding and payout on Robinhood Chain.  
**Date:** 2026-09-05

## Executive Summary

- **Building:** A synchronized production pin and live fork canary for Flap-backed stock raffles.
- **Verdict:** Ready to build — the live configuration is understood and the safety guard should remain fail-closed.
- **Top risk:** Flap's mutable version can invalidate every launch until all reviewed pins are updated together.
- **Must decide first:** Do not remove the commitment; approve only the exact `v5.21.2` state after the end-to-end fork passes.
- **Watch out for:** CI must provide the validated archive RPC under every environment alias consumed by registered tests.

## Risk Heatmap

| Component | Critical | High | Medium | Low |
| --- | ---: | ---: | ---: | ---: |
| Flap Portal | 1 | 0 | 0 | 1 |
| Robinhood Chain | 0 | 0 | 1 | 0 |
| **Total** | **1** | **0** | **1** | **1** |

**Critical & High, by name:**

1. **CRITICAL — Flap Portal — Mutable upstream version can stop every Flap launch:** stale reviewed commitments reject all launches until compatibility is proven and pins are synchronized.

## Components Researched

| Component | Version | Source found | Status |
| --- | --- | --- | --- |
| Flap Portal | v5.21.2 | https://docs.flap.sh/flap/developers/token-launcher-developers/robinhood-integration-guide.md | Fresh this run |
| Robinhood Chain | 4663 | https://docs.robinhood.com/chain/connecting/ | Fresh this run |

## What a Coding Agent Must Know Before Starting

1. Keep the Portal commitment check fail-closed; never substitute a dynamic read immediately before signing.
2. The new reviewed commitment is `0xd11206f76d4086d0aab6f96707b25806347b07d7ef45197bf15699765ef975d3`.
3. The Portal remains `0x26605f322f7fF986f381bB9A6e3f5DAb0bEaEb09`, the Tax Token V3 implementation remains `0x7777C8743C88B3aff3cf262135beF2c8b2e83333`, the proxy runtime hash is unchanged, and native quote configuration remains `(1, 25, 25, 0, 0)`.
4. Update UI launch/metadata checks and Solidity production scripts/tests in the same release.
5. A passing acceptance test must launch through the live Portal, bind the router and raffle, produce taxable revenue, fund the raffle, commit/draw, and pay a winner.
6. The fork runner must export the selected RPC as `SINJOH_RPC_PRIMARY` in addition to the other canonical aliases.

## Pre-coding Decisions Required

- **Approve exact Portal commitment** — immutable for each launch attempt but mutable in source after a reviewed upstream upgrade. Use only `0xd11206f76d4086d0aab6f96707b25806347b07d7ef45197bf15699765ef975d3` for the current reviewed state.

## Requirements Corrections

- Add synchronized upstream configuration pins and current-state lifecycle canaries to the definition of launch readiness.
- Treat stock route construction and raffle binding as separate required fail-closed gates.

## What This Report Prevents

- Disabling the safety check merely to restore launches.
- Updating only the UI or only the contracts canary and leaving production inconsistent.
- Mistaking an RPC issue for an upstream Portal version change.
- Reporting a launch as successful before the raffle is bound and payout-capable.

Run summary: 2 components fresh, 0 reused. Re-run with `--fresh` to force a full re-research.
