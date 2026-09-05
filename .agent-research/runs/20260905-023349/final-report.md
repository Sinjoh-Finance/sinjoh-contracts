# Brainblast Research Report

**Run:** 20260905-023349  
**Requirements:** Restore Flap and letscash.fun launches and prove stock-raffle binding and payout on Robinhood Chain.
**Date:** 2026-09-05

## Executive Summary

- **Building:** Synchronized production pins and live fork canaries for stock raffles across launchpads.
- **Verdict:** Ready to build — the live configuration is understood and the safety guard should remain fail-closed.
- **Top risk:** Upgradeable upstream launchpads can retain an address while changing versioned behavior or tuple selectors.
- **Must decide first:** Do not remove the commitment; approve only the exact `v5.21.2` state after the end-to-end fork passes.
- **Watch out for:** CI must provide the validated archive RPC under every environment alias consumed by registered tests.

## Risk Heatmap

| Component | Critical | High | Medium | Low |
| --- | ---: | ---: | ---: | ---: |
| Flap Portal | 1 | 0 | 0 | 1 |
| @letscashfun/sdk | 1 | 1 | 0 | 0 |
| Robinhood Chain | 0 | 0 | 1 | 0 |
| **Total** | **2** | **1** | **1** | **1** |

**Critical & High, by name:**

1. **CRITICAL — Flap Portal — Mutable upstream version can stop every Flap launch:** stale reviewed commitments reject all launches until compatibility is proven and pins are synchronized.
2. **CRITICAL — @letscashfun/sdk — Proxy upgrade silently changes all launch selectors:** proxy-only checks stay green while old tuple calls revert.
3. **HIGH — @letscashfun/sdk — A normal salt-search miss can abort a launch:** bounded vanity search must advance only on a contract-level miss.

## Components Researched

| Component | Version | Source found | Status |
| --- | --- | --- | --- |
| Flap Portal | v5.21.2 | https://docs.flap.sh/flap/developers/token-launcher-developers/robinhood-integration-guide.md | Fresh this run |
| @letscashfun/sdk | 0.5.0 | https://registry.npmjs.org/@letscashfun%2Fsdk/0.5.0 | Fresh this run |
| Robinhood Chain | 4663 | https://docs.robinhood.com/chain/connecting/ | Fresh this run |

## What a Coding Agent Must Know Before Starting

1. Keep the Portal commitment check fail-closed; never substitute a dynamic read immediately before signing.
2. The new reviewed commitment is `0xd11206f76d4086d0aab6f96707b25806347b07d7ef45197bf15699765ef975d3`.
3. The Portal remains `0x26605f322f7fF986f381bB9A6e3f5DAb0bEaEb09`, the Tax Token V3 implementation remains `0x7777C8743C88B3aff3cf262135beF2c8b2e83333`, the proxy runtime hash is unchanged, and native quote configuration remains `(1, 25, 25, 0, 0)`.
4. Update UI launch/metadata checks and Solidity production scripts/tests in the same release.
5. A passing acceptance test must launch through the live Portal, bind the router and raffle, produce taxable revenue, fund the raffle, commit/draw, and pay a winner.
6. The fork runner must export the selected RPC as `SINJOH_RPC_PRIMARY` in addition to the other canonical aliases.
7. The current letscash.fun tuple appends `uint256 supply`; use zero for standard supply, and pin implementation `0x40250b4C73FC30f8F6ad077744B0124B3f111C28` with runtime hash `0xc420573f11b2c4fab419118e0e6fc167cc3902c62a3e41fd4495c5db0ea30532`.
8. Salt mining must retry exhausted bounded windows while propagating non-contract RPC failures.

## Pre-coding Decisions Required

- **Approve exact Portal commitment** — immutable for each launch attempt but mutable in source after a reviewed upstream upgrade. Use only `0xd11206f76d4086d0aab6f96707b25806347b07d7ef45197bf15699765ef975d3` for the current reviewed state.

## Requirements Corrections

- Add synchronized upstream configuration pins and current-state lifecycle canaries to the definition of launch readiness.
- Treat stock route construction and raffle binding as separate required fail-closed gates.

## What This Report Prevents

- Disabling the safety check merely to restore launches.
- Updating only the UI or only the contracts canary and leaving production inconsistent.
- Trusting a stable proxy address while its active implementation has changed every launch selector.
- Mistaking an RPC issue for an upstream Portal version change.
- Reporting a launch as successful before the raffle is bound and payout-capable.

Run summary: 3 components fresh, 0 reused. Re-run with `--fresh` to force a full re-research.
