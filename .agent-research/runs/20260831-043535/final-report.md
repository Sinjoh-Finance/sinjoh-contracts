# Yield Banks OpenSea Remediation Research

## Executive Summary

- **Building:** Safe SeaDrop primary payout and multi-asset Seaport royalty ingress for Yield Banks.
- **Verdict:** Ready to build — the implementation records both product choices explicitly and preserves the verified payout boundary.
- **Top risk:** Adding the existing general SinjohFeeRouter would silently add its fixed fee and break exact per-mint accounting.
- **Must decide first:** Declare the collection's equity custody and income model in its signed release manifest.
- **Watch out for:** ERC-2981 does not enforce secondary earnings.

## Risk Heatmap

| Component | Critical | High | Medium | Low |
|---|---:|---:|---:|---:|
| SeaDrop | 1 | 0 | 0 | 0 |
| Seaport | 1 | 1 | 0 | 0 |
| ERC-2981 | 0 | 1 | 0 | 0 |
| OpenZeppelin Contracts | 0 | 0 | 0 | 1 |
| **Total** | **2** | **2** | **0** | **1** |

## Components researched

| Component | Version | Status |
|---|---|---|
| SeaDrop | unversioned | Fresh this run |
| Seaport | unversioned | Fresh this run |
| ERC-2981 | Final | Fresh this run |
| OpenZeppelin Contracts | 5.6.1 | Reused from cache (fetched 2026-08-27) |

## What implementation must preserve

1. SeaDrop creator payout is native ETH and occurs after the NFT mint callback.
2. The exact payout must remain correlated with the pending mint tranche.
3. Secondary royalties may arrive in native ETH or any ERC-20 sale currency.
4. Royalty synchronization must be restricted to the allocation operator. The destination route remains timelock-bound and codehash-pinned, while slippage floors and deadlines are supplied fresh for each amount.
5. The royalty percentage must be collection configuration, not a source constant.
6. OpenSea configuration is operational state and must be verified separately.

## Decisions implemented

- Each release manifest must explicitly choose onchain tokenized-equity custody or an offchain custody receipt and disclose whether income appears as balance appreciation, cash distribution, or both.
- The proceeds vault is the collection-specific Sinjoh primary fee router: it preserves exact mint receipts, applies only the configured collection split, and adds no general-router fee.

## Requirements corrections

- Do not route SeaDrop proceeds through the existing general SinjohFeeRouter.
- Do not describe ERC-2981 royalties as guaranteed.
- Do not call Stock Tokens direct stock ownership or discrete dividend collection.
- Do not persist amount-specific royalty route calldata; use fresh operator-supplied execution data against timelock-bound, codehash-pinned routes.

Run summary: three components researched fresh and one reused from cache.
