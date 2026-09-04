# Brainblast Research Report

**Run:** 20260903-221002
**Requirements:** OpenSea-only, sequential fixed-price Piggy Banks launch with public tier rotation
**Date:** 2026-09-03

## Executive Summary

- **Building:** A configurable mint policy that assigns an immutable token-ID range, price,
  inventory counter, and wallet counter to every collection-defined tier.
- **Verdict:** Build with caution — the contract model is sound, but OpenSea's single public stage
  requires an owner transaction at every public-tier boundary.
- **Top risk:** A missed public-stage rotation pauses minting; enabling another SeaDrop route can
  make the route ambiguous because SeaDrop's NFT callback omits its selected mint parameters.
- **Must decide first:** Keep the launch manager as NFT owner through the initial public rotation,
  or delay launch enough to schedule every update through the 24-hour timelock.
- **Watch out for:** The existing NFT already pins the superseded policy; production requires a new
  factory and collection deployment before configuring OpenSea.

## Risk Heatmap

| Component | Critical | High | Medium | Low |
|---|---:|---:|---:|---:|
| OpenSea SeaDrop | 0 | 2 | 1 | 0 |
| Robinhood Chain | 0 | 0 | 0 | 1 |
| OpenZeppelin Contracts | 0 | 0 | 0 | 1 |
| **Total** | **0** | **2** | **1** | **2** |

High risks:

1. **HIGH — Ambiguous concurrent routes:** production must keep public, token-gated, signed,
   payer, and allowlist routes from overlapping.
2. **HIGH — Timed public rotation:** OpenSea exposes one public stage, so every transition must be
   submitted and verified before its window begins.

## Components researched

| Component | Version | Source found | Status |
|---|---|---|---|
| OpenSea SeaDrop | 1.0 / `368b005` | Official repository, release, and support docs | Fresh this run |
| Robinhood Chain | chain ID 4663 | Official documentation | Fresh this run |
| OpenZeppelin Contracts | 5.6.1 | Local package and official release | Fresh this run |

## What a coding agent must know before starting

1. `mintSeaDrop` receives only minter and quantity; it never receives the selected route or tier.
2. The four allowlist windows must be mutually exclusive so time identifies exactly one tier.
3. After those windows, exactly one SeaDrop public configuration may be active.
4. A public configuration identifies a tier only when price, wallet cap, fee, and fee-recipient
   restriction uniquely match that tier's immutable policy terms.
5. Each tier has its own minted count, wallet count, and contiguous token-ID range. These counters
   persist across the tier's allowlist and every later public reopening.
6. `getMintStats` returns tier-local counts to SeaDrop; the collection independently enforces the
   collection-wide maximum.
7. The collection accepts non-sequential tier token IDs, prevents duplicate IDs, and keeps
   `mintedSupply` as a count.
8. OpenSea-hosted allowlist CSVs may produce a different root from the repository's independent
   reference tree. Record and verify the root OpenSea actually installs; never substitute a root.

## Pre-coding and launch decisions required

1. Use four initial allowlist stages and one rotating public stage; do not add a custom gateway.
2. Keep all alternate SeaDrop mint paths and payers empty in the production manifest.
3. Resolve the NFT-owner timing choice before broadcast: the current 24-hour timelock cannot execute
   next-day stage rotations unless they were scheduled at least 24 hours earlier.
4. Transfer NFT ownership to the **new collection's** verified timelock immediately after the
   Standard public configuration is installed if the launch manager performs the initial rotation.
   Do not reuse the superseded collection's timelock address.

## Requirements corrections

- Do not make later tiers depend on earlier sellout.
- Do not lower the price of unsold Alpha, Prime, or Premium inventory.
- Do not infer a tier from collection-global minted supply.
- Do not use an allowed-payer gateway: mutually exclusive windows make it unnecessary.
- Treat OpenSea's 365-day public-stage maximum as an operational renewal date, not a permanent
  onchain sale.

## What this report prevents

- Selling an Alpha, Prime, or Premium token at the Standard price.
- Locking unsold higher-tier inventory permanently.
- Blocking a later tier because an earlier tier did not sell out.
- Double-minting or crossing a tier's token-ID range.
- Handing a successor the abandoned gateway design.

Run summary: 3 components researched fresh, 0 reused from cache. `--fresh` forces a complete rerun.
