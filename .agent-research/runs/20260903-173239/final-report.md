# Executive Summary

The protocol needs generic, ordered paid-mint stages so Piggy Banks can launch Alpha, Prime,
Premium, then Standard with a cascading frozen-holder allowlist. **Verdict: Build with caution.**
The top risk is SeaDrop's opaque mint callback: price and stage are not passed to the NFT. The first
immutable launch decision is the final stage schedule plus observed primary-drop fee BPS. The largest
spec gap is OpenSea's documented requirement for a final public stage, which conflicts with excluding
wallets below 10,000 $INJOH if presales do not sell out.

# Risk Heatmap

| Component | Critical | High | Medium | Low |
|---|---:|---:|---:|---:|
| SeaDrop | 1 | 2 | 1 | 0 |
| OpenSea Drops | 1 | 1 | 1 | 0 |
| OpenZeppelin Contracts | 0 | 0 | 1 | 1 |
| Robinhood Chain | 0 | 1 | 0 | 1 |
| **Total** | **2** | **4** | **3** | **2** |

Critical and high risks: opaque callback parameters; hosted public-stage conflict; lifetime wallet
stats; cross-stage batch minting; mutable OpenSea primary fee; and wrong external deployment.

# Components researched

| Component | Version | Status |
|---|---|---|
| SeaDrop | unversioned canonical deployment | Fresh this run |
| OpenSea Drops | unversioned | Fresh this run |
| OpenZeppelin Contracts | 5.6.1 | Reused from cache (fetched 2026-08-27) |
| Robinhood Chain | chain ID 4663 | Fresh this run |

# What the coding agent must know

1. Store mint stages separately from fee-weight ranges; they are independent protocol concepts.
2. Return the active stage's per-wallet minted count and supply boundary from `getMintStats`.
3. Reject any quantity that crosses the active stage boundary inside the NFT too, not only in
   SeaDrop.
4. Bind expected gross price and exact SeaDrop-net proceeds to the pending mint. Reject zero-price,
   underpriced, wrong-fee, and overpaid callbacks atomically.
5. Permit Merkle roots only when a nonempty paid stage schedule exists; retain clearing support.
6. Keep all Piggy Banks values in deployment/allowlist artifacts, never protocol constants.
7. Build the allowlist as cascading leaves from the frozen snapshot with inclusive thresholds.
8. OpenSea currently lists Robinhood Chain as supported; select it explicitly rather than accepting
   Studio's Ethereum default.

# Pre-coding decisions required

- Exact stage dates and durations: mutable before root publication but embedded in every Merkle leaf.
- Actual primary-drop fee BPS: externally controlled and must be verified in the final OpenSea setup.
- Hosted public stage: confirm omission/disablement or use a custom whitelist-only mint experience.

# Requirements corrections

- Reverse the existing Piggy Banks fee-weight ranges to match Alpha-first token IDs.
- Do not model tier eligibility as exclusive; it cascades downward.
- Do not use SeaDrop lifetime wallet stats for stage-local caps.

# What this research prevents

It prevents free or incorrectly priced Yield Banks, a batch crossing into the next tier, higher-tier
holders losing later-stage capacity, lower-balance holders entering the wrong phase, and reliance on
secondary-market fee documentation for a primary drop.

Run summary: three components researched fresh, one reused. `--fresh` forces full re-research.
