<!-- BRAINBLAST:CACHE slug=uniswap-v3-v4 version=v3-unversioned-v4-core-1.0.2 fetched=2026-08-27 -->
# Uniswap v3 and v4 concentrated liquidity

Version: v3 unversioned; v4 core 1.0.2
Disposition: MISS-new
Primary sources: https://docs.uniswap.org/concepts/protocol/concentrated-liquidity and https://docs.uniswap.org/contracts/v3/guides/providing-liquidity/mint-a-position

## Verified facts

- Concentrated-liquidity providers choose a price range. Narrower in-range liquidity is more capital efficient, but an out-of-range position becomes inactive, earns no fees, and is held entirely in one asset.
- Uniswap v3 positions are ERC-721 tokens managed through `INonfungiblePositionManager`.
- The official v3 minting guide warns that zero minimum token amounts in production create a front-running/slippage vulnerability. Minimums and deadlines must be derived from protected quotes.
- The repository pins Uniswap v4 core 1.0.2 through the existing v4 dependency tree.
- Delta advertises v3 and v4 pools, but the verified `DeltaPositionBuilder` inspected in this run targets the v3 factory and v3 nonfungible position manager.

## Assumptions and inferences

- Sinjoh v1 should integrate only the verified v3 builder path. A separate audited adapter should be required before enabling Delta v4 or the unverified ladder manager.
- Strategy accounting must include both current token amounts and uncollected fees, not an LP-token spot balance.

## Risks

- **HIGH — Slippage and range manipulation.** Weak minimum amounts, deadlines, or TWAP/oracle checks can turn deposits and rebalances into extractable value.
- **MEDIUM — Position-NFT custody.** The strategy must safely receive, track, collect from, and close each ERC-721 position; losing the token ID or approvals can strand backing.
- **MEDIUM — Out-of-range drift.** A position may stop earning and become concentrated in the weaker asset.

## Unresolved

- Unresolvable from public sources: a versioned Delta-to-Uniswap-v4 adapter with verified source. V4 should remain disabled until one is reviewed.
