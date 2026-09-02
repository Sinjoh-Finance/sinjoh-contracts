# Requirements Re-review

## Missing constraints added

1. **Eligibility at transfer and redemption.** Mint-only gating is insufficient for a bearer NFT backed by restricted Stock Tokens.
2. **No global loop.** Ongoing allocations use per-asset accumulators and permissionless bounded settlement.
3. **Pooled LP operations.** Per-NFT vault ownership is preserved through strategy shares; 3,000 separately managed ranges are rejected as the default.
4. **Price failure behavior.** Stale/paused feeds stop swaps and rebalances, not in-kind redemption.
5. **Seven-day Delta reward stream.** Streaming but unclaimable WETH is included in strategy NAV and exit accounting.
6. **Terminal state.** The last NFT pays no exit tax, receives dust, and closes the collection.
7. **Operational migration.** Immutable economics are separated from timelocked adapter/feed migrations and guardian de-risking.

## Wrong assumptions corrected

- Stock Tokens are issuer debt securities, not direct ownership of shares.
- Delta rewards do not currently auto-compound.
- Delta withdrawals return both pool assets; they do not automatically return the original deposit asset.
- Delta exposes v3 and v4 pools, but the publicly verified builder inspected here is a Uniswap v3 builder.
- A two-asset LP strategy is not natively a plain ERC-4626 vault.
- External marketplace royalties are not guaranteed.

## Decisions now specified

- Fixed supply 3,000, fixed-price mint, deterministic vault deployed at mint.
- Portfolio: 50% three Stock Tokens, 35% two Delta strategy shares, 15% USDG.
- Primary split: 80% treasury, 10% creator, 5% Sinjoh, 5% operations reserve.
- Secondary royalty: 5% total, split 3.5% treasuries, 0.75% creator, 0.75% Sinjoh.
- Exit tax: 3% redistributed in kind; waived for the final NFT.
- No Sinjoh performance fee; bound-token burn disabled for v1.
- Multi-step exit with permissionless processing and in-kind emergency fallback.

## Immutable choices before deployment

- Initial Stock Token, feed, Delta pool, and approved-router manifest.
- Eligibility attestation authority and policy.
- Collection economics and operations-reserve sunset.
- Exact strategy-share interface and emergency in-kind redemption semantics.
