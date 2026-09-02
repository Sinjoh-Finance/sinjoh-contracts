# Robinhood Stock Tokens and metadata API

Version: unversioned
Disposition: MISS-unversioned
Primary source: https://docs.robinhood.com/chain/stock-tokens/

## Verified facts

- Stock Tokens are tokenised debt securities issued by Robinhood Assets (Jersey) Limited. They do not give legal or beneficial ownership of the referenced shares.
- They are ERC-20 tokens with 18 decimals. Only Authorized Participants can direct primary minting and burning with the issuer; other users rely on secondary venues.
- Stock Tokens use ERC-8056 `uiMultiplier()` for dividends, splits, and other corporate actions. Raw token balances and total supply remain fixed while the display/economic multiplier changes.
- Onchain Chainlink feeds are already adjusted for the multiplier. Applying `uiMultiplier()` again to an onchain feed double-counts the adjustment.
- The Robinhood REST price is the raw referenced-asset price and is not multiplier-adjusted. A consumer using it must apply the current multiplier exactly once.
- Stock Token onchain price feeds operate 24/5. During corporate actions an oracle may pause; staleness remains the primary safety check.
- The metadata API base is `https://api.robinhood.com/rhj/`. Documented endpoints include `/assets`, `/prices/{symbol}`, and `/corporate-actions`. The published rate limit is 60 requests per second; prices are cached for 15 seconds and corporate actions for one hour.
- The offering documents state that Stock Tokens are not registered under U.S. securities laws and cannot be offered, sold, or delivered in the United States or to or for U.S. persons. Additional jurisdiction restrictions apply.

## Assumptions and inferences

- An unrestricted transferable NFT with a bearer redemption claim on Stock Tokens could bypass the Stock Token eligibility restrictions even if the initial mint is gated.
- Mint, transfer, and redemption therefore need eligibility enforcement unless counsel approves a different structure or the Stock Token sleeve is removed.
- The REST API is suitable for metadata and halt context, not for trustless onchain settlement.

## Risks

- **CRITICAL — Jurisdiction and securities restrictions.** A globally transferable 3,000-NFT collection backed by Stock Tokens is not launchable as described without legal analysis and an eligibility/transfer-control design.
- **HIGH — Multiplier double-counting.** Mixing REST prices, onchain feeds, and ERC-8056 without a single valuation convention silently corrupts NAV and swap limits.
- **HIGH — 24/5 and corporate-action pauses.** Weekend or paused feeds make automated rebalancing unsafe; stale data must halt price-dependent operations while preserving in-kind exit.
- **MEDIUM — Issuer and instrument risk.** NFT owners have exposure to a debt security and its issuer, not direct shareholder rights.

## Unresolved

- Unresolvable from public sources: the definitive eligible-jurisdiction policy for this specific NFT wrapper. Product counsel and the current prospectus must decide it.
