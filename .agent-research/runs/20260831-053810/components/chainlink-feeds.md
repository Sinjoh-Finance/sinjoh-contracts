# Chainlink-compatible Stock Token feeds

Version: unversioned per-feed deployments
Disposition: MISS-unversioned

Sources: https://docs.robinhood.com/chain/stock-tokens/,
https://docs.robinhood.com/chain/stock-token-apis/

## Facts

- Robinhood documents onchain Chainlink prices as multiplier-adjusted.
- Correct reads must reject nonpositive, incomplete, future, or stale rounds and normalize decimals.

## Risks

- **HIGH — Stale or invalid price acceptance corrupts deposits, NAV, or rebalance limits.** PriceHub
  fails closed on freshness, round completeness, sign, timestamp, and decimal normalization.
- **MEDIUM — Feed-address drift can silently price the wrong asset.** Activation requires each feed's
  address and runtime hash plus asset/feed binding tests.

No public-source question remains unresolved.
