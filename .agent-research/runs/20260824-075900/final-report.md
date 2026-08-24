# Brainblast Research Report

**Run:** 20260824-075900
**Requirements:** Make the canonical Pons + Project V2 wallet launch path Production-ready, including post-graduation custody safety.
**Date:** 2026-08-24

## Executive Summary

- **Building:** One atomic wallet-signed Pons token and Project V2 launch that remains governance-safe after Uniswap v4 graduation.
- **Verdict:** Blocked — source fixes pass, but the required SDK package is unpublished and external Production configuration/canaries remain incomplete.
- **Top risk:** Graduation moves supply into the Pons locker and singleton PoolManager; omitting either before one-time exclusion finalization distorts voting and holder eligibility.
- **Must decide first:** Confirm the final Production owner and the exact hardened-release deployment sequence before any ownership or immutable binding transaction.
- **Watch out for:** Robinhood's public RPC is explicitly rate-limited and not recommended for Production.

## Risk Heatmap

| Component | Critical | High | Medium | Low |
|---|---:|---:|---:|---:|
| @sinjoh/sdk | 1 | 0 | 0 | 0 |
| viem | 0 | 0 | 1 | 0 |
| Robinhood Chain | 0 | 1 | 0 | 0 |
| Uniswap v4 core | 1 | 0 | 0 | 0 |
| OpenZeppelin Contracts | 0 | 0 | 0 | 1 |
| Reown AppKit / WalletConnect | 0 | 1 | 0 | 0 |
| Vercel | 0 | 0 | 1 | 0 |
| **Total** | **2** | **2** | **2** | **1** |

**Critical & High, by name:**

1. **CRITICAL — Uniswap v4 core — Graduation custody omission:** locker and PoolManager balances become eligible if not finalized as exclusions.
2. **CRITICAL — @sinjoh/sdk — Required 2.1.0 package is not published:** clean remote builds cannot resolve the dependency.
3. **HIGH — Robinhood Chain — Production defaults to a public rate-limited RPC:** availability can fail independently of contract correctness.
4. **HIGH — Reown — Production wallet connections require external domain allowlisting:** code cannot prove dashboard state.

## Components researched

| Component | Version | Source found | Status |
|---|---|---|---|
| @sinjoh/sdk | 2.1.0 target; 2.0.0 registry latest | https://registry.npmjs.org/@sinjoh%2fsdk | Fresh this run |
| viem | 2.55.19 | https://viem.sh/docs/contract/simulateContract | Fresh this run |
| Robinhood Chain | unversioned, chain 4663 | https://docs.robinhood.com/chain/connecting/ | Fresh this run |
| Uniswap v4 core | 1.0.2 | https://developers.uniswap.org/docs/protocols/v4/concepts/poolmanager | Fresh this run |
| OpenZeppelin Contracts | 5.6.1 | https://docs.openzeppelin.com/contracts/5.x/api/token/erc20 | Fresh this run |
| Reown AppKit / WalletConnect | 1.7.8 transitive | https://docs.reown.com/appkit/faq | Fresh this run |
| Vercel | unversioned | https://vercel.com/docs/deployments/environments | Fresh this run |

## What a coding agent must know before starting

1. Uniswap v4 pools are PoolId-addressed state in a singleton PoolManager, so registry pool identity and token custody are different concepts.
2. The immutable Pons token exclusion finalizer must receive the adapter, predicted curve, live locker, and live PoolManager in one sorted unique custody set.
3. The adapter should independently read `locker()` and `poolManager()` from the live Pons factory and reject their omission.
4. SDK assembly must validate custody before encoding, then verify the exact `to`, `data`, and `value`; simulation is a separate, non-persistent check.
5. GovTest is historical evidence for the single-token architecture, not a graduation-safety canary.
6. Publish `@sinjoh/sdk`, `@sinjoh/abis`, and `@sinjoh/deployments` 2.1.0 together before relying on Vercel.
7. Configure provider-backed Production RPC, Reown domains, and final ownership outside source control, then run wallet-signed canaries.

## Pre-coding decisions required

- **Immutable custody identity:** Pin the current Pons locker `0x1006fA85294A9c38AA4214d52c86CC970Ddc5647` and PoolManager `0x8366a39CC670B4001A1121B8F6A443A643e40951`, while having the adapter verify both against live factory views.
- **Release authority:** Confirm the final multisig before ownership transfer or one-time factory/release binding.
- **RPC architecture:** Choose a provider and abuse/quota policy for Production reads and simulation.

## Requirements corrections

- GovTest's exact historical payload omitted post-graduation custody and must not be labeled Production-safe.
- The public Robinhood RPC is a fallback/testing endpoint, not a Production availability plan.
- Preview configuration and health do not prove Production environment parity.
- Local SDK tarballs do not unblock Vercel; public package publication is required.

## What this report prevents

- Governance quorum and holder rewards being inflated by tokens held in the graduated v4 pool system.
- A Production deploy failing at dependency installation despite passing local tests.
- Wallet connection failing only after promotion because the Production origin was never allowlisted.
- Launch prediction and simulation becoming intermittently unavailable under a public-RPC quota.

Run summary: 7 components were researched fresh and 0 were reused. Re-run with `--fresh` to force full research again.
