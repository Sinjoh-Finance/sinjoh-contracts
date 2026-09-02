# Yield Vaults research requirements

Source plan: `YIELD-VAULTS.md`

## Product

Launch one collection of exactly 3,000 ERC-721 NFTs on Robinhood Chain. Every NFT is a bearer redemption claim on its own isolated treasury. The treasury must be able to:

- hold approved Robinhood Stock Tokens;
- earn LP trading fees through Delta;
- hold approved yield-strategy shares where this improves the product without obscuring custody;
- receive an equal share of routed collection and project-token fees;
- travel with the NFT on transfer; and
- release its full net value only when the NFT is burned.

## Collection economics

- Creator chooses the collection's immutable economic configuration at launch.
- Funding sources may include primary mint proceeds, NFT secondary-market fees, newly launched bound-token creator fees, and explicitly approved external contributions.
- Funding enters in WETH or another approved input asset, is allocated across stocks, Delta LP strategies, and reserves, and is attributed equally to all live NFTs.
- Redemption may require burning a fixed amount of the bound project token.
- Redemption charges a cashout tax that benefits the remaining live NFTs.
- The last-NFT terminal state must be explicitly defined.

## Architecture constraints

- Funding must not loop over 3,000 NFTs.
- Per-token accounting must be exact, auditable, and transferable with `tokenId`.
- Every NFT must have a deterministic vault address and isolated accounting/custody.
- Delta positions, stock balances, pending fee allocations, unclaimed rewards, and net redemption value must be visible per NFT.
- Delta integrations, stock-token contracts, swap routes, price feeds, and yield adapters must be allowlisted and guarded.
- The design must define settlement, harvesting, compounding, rebalancing, emergency exit, partial failure, and final redemption.
- No creator, keeper, or platform operator may withdraw NFT backing to an arbitrary recipient.

## User-facing outcome

Pitch a collection in which every NFT is a transferable, growing onchain portfolio: it owns Stock Token exposure, earns real trading fees by supplying Delta liquidity, receives protocol revenue, and can be redeemed only by destroying the NFT.
