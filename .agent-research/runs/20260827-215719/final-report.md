# Yield Vaults External-Integration Research

## Executive Summary

**Building:** A 3,000-piece bearer NFT collection in which each token has an isolated treasury holding Stock Tokens, USDG, and shares of collection-level Delta LP strategies.

**Verdict:** **Blocked for production launch; ready for specification and prototype.**

**Top risk:** Stock Tokens are restricted issuer debt securities. An unrestricted transferable NFT backed by them can defeat the underlying eligibility restrictions.

**Must decide first:** Accept transfer/redeem eligibility gating approved by counsel, or remove Stock Tokens from the portfolio.

**Biggest specification gap:** Most published Delta stake/farm/zap/manager addresses lack verified source and a complete published ABI, so they are unsafe immutable dependencies until Delta provides reviewable materials.

## Risk Heatmap

| Component | Critical | High | Medium | Low |
|---|---:|---:|---:|---:|
| Delta Liquidity | 1 | 2 | 1 | 0 |
| Robinhood Chain | 0 | 1 | 2 | 0 |
| Stock Tokens/API | 1 | 2 | 1 | 0 |
| Chainlink feeds | 0 | 2 | 0 | 0 |
| Uniswap v3/v4 | 0 | 1 | 2 | 0 |
| ERC-4626 | 0 | 2 | 0 | 0 |
| OpenZeppelin Contracts | 0 | 0 | 1 | 1 |
| **Total** | **2** | **10** | **7** | **1** |

### Critical and high risks

- **Delta core contracts are not source-verified.** The stake/farm/zap/manager custody and upgrade model cannot be independently validated.
- **Stock Token jurisdiction and securities restrictions** conflict with unrestricted bearer-NFT transferability.
- Delta rewards require explicit harvest/compound and seven-day-stream accounting.
- Three thousand direct LP positions are operationally expensive; pooled strategy shares are required for a practical default.
- Production RPC, feed staleness, corporate-action pauses, and the missing published sequencer-health address require fail-closed automation.
- REST/onchain/multiplier mixing can silently double-count Stock Token corporate actions.
- Concentrated-liquidity slippage/range manipulation must be guarded.
- ERC-4626 inflation and the two-asset LP semantic mismatch require an explicit wrapper design.

## Components researched

| Component | Version | Status |
|---|---|---|
| Delta Liquidity | unversioned | Fresh this run |
| Robinhood Chain | unversioned; chain ID 4663 | Fresh this run |
| Robinhood Stock Tokens/API | unversioned | Fresh this run |
| Chainlink feeds | unversioned | Fresh this run |
| Uniswap v3/v4 | v3 unversioned; v4 core 1.0.2 | Fresh this run |
| ERC-4626 | EIP-4626 | Fresh this run |
| OpenZeppelin Contracts | 5.6.1 | Fresh this run |

## What the coding agent must know

1. Use one deterministic vault per token ID but pool Delta operations behind transferable strategy shares.
2. V1 should use the verified Delta v3 position builder `0x6235cF6bd8419b34942F4EDDB39C880BD96dD700`; keep unverified Delta stake/farm/zap/manager paths disabled.
3. Delta charges 1% of claimed fees, streams stake rewards over seven days, does not auto-compound, and returns both assets on withdrawal.
4. Use `accPerLiveNft` indices and per-token debt for O(1) fee attribution. Settle individually or in bounded batches.
5. Price Stock Tokens from multiplier-adjusted onchain feeds exactly once. REST prices are metadata-only in contract decisions.
6. Stale or paused price data must stop swaps and rebalances while leaving in-kind exits possible.
7. A Delta LP wrapper must define a single accounting asset plus an explicit two-asset in-kind emergency redemption; do not misrepresent it as plain ERC-4626.
8. Clone initialization binds chain ID, factory, collection, and token ID and must be one-time.
9. No keeper, creator, guardian, or timelock action may select an arbitrary backing recipient.
10. Public product language must use “Stock Tokens,” disclose issuer-debt exposure, and avoid Robinhood marks in NFT art and metadata.

## Pre-coding decisions required

1. **Eligibility model (immutable legal effect):** counsel-approved transfer/redeem gating, or remove Stock Tokens.
2. **Initial asset manifest:** three Stock Tokens, two Delta v3 pools, feeds, routers, and maximum slippage/range policies.
3. **Delta materials:** obtain source/ABI/audit/upgrade documentation or constrain v1 to the verified builder plus canonical Uniswap v3 lifecycle.
4. **Share interface:** strict single-asset ERC-4626 wrapper with an extension, or custom ERC-20 strategy shares with explicit pro-rata/in-kind redemption.
5. **Oracle circuit breaker:** establish a Robinhood Chain sequencer-health source or approved alternative.

## Requirements corrections

- Replace “stocks” with “Stock Tokens” in public copy and disclose that they are not direct shares.
- Replace one LP position per NFT with per-NFT ownership of pooled strategy shares.
- Add transfer/redeem eligibility, 24/5 feed behavior, streaming-reward accounting, in-kind exit, and terminal last-NFT behavior.
- Separate immutable economics from constrained, timelocked external-component migrations.

## What this research prevents

- Launching an unrestricted wrapper around restricted financial instruments.
- Making unverified Delta contracts permanent custody dependencies.
- Double-counting corporate actions in NAV.
- Claiming automatic compounding when it is not provided.
- A 3,000-position keeper/gas architecture.
- Permanent redemption lock when an oracle or external adapter fails.

Run summary: seven components researched fresh, zero reused from cache. Passing `--fresh` would force the same full re-research. No deterministic `facts.yaml` rule was authored because the critical issues do not match the supported checker and test templates.
