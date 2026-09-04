# Component: OpenSea SeaDrop

**Date checked:** 2026-09-03
**Version:** SeaDrop 1.0 (`seadrop-1.0`, commit `368b005`)
**Sources:**
- Release and deployed address: https://github.com/ProjectOpenSea/seadrop/releases/tag/seadrop-1.0
- Canonical implementation: https://raw.githubusercontent.com/ProjectOpenSea/seadrop/main/src/SeaDrop.sol
- Required NFT callback: https://raw.githubusercontent.com/ProjectOpenSea/seadrop/main/src/interfaces/INonFungibleSeaDropToken.sol
- Allowlist stages: https://support.opensea.io/en/articles/8867054-define-your-allowlists
- Drop schedule: https://support.opensea.io/en/articles/8867049-prepare-your-drop-schedule

## Facts

- SeaDrop 1.0 is deployed at `0x00005EA00Ac477B1030CE78506496e8C2dE24bf5`.
- Allowlist leaves bind the minter to `MintParams`, including price, dates, wallet limit, stage
  index, stage supply, fee, and fee-recipient restriction.
- SeaDrop validates the proof and exact `msg.value`, then invokes only
  `mintSeaDrop(address minter,uint256 quantity)` on the NFT. The callback does not include the
  chosen `MintParams` or stage index.
- SeaDrop calls `getMintStats(minter)` before minting and trusts the three returned counters to
  enforce wallet and stage limits.
- OpenSea Studio supports up to five sequential presale stages with stage-specific price, allowlist,
  duration, and per-wallet limit; only one presale stage is active at a time.
- OpenSea exposes one public stage, it follows the presales, and its configured duration is capped
  at 365 days.
- SeaDrop pays the creator payout after the NFT callback returns and emits `SeaDropMint` only after
  the mint and payout complete.
- Onchain calls confirmed nonempty code for `0x00005EA00Ac477B1030CE78506496e8C2dE24bf5`
  on Robinhood Chain and code hash
  `0x53e4b9339cf624803c9a7d0195576cca5b917920813508d86b3eb93dcbabeb5c`.

## Assumptions

- OpenSea will continue using the documented SeaDrop 1.0 callback ABI for the configured address.

## Inferences

- Because the four allowlist windows never overlap, the NFT callback can identify their immutable
  policy tier from the current time without a custom payer or mint gateway.
- After the allowlists, the policy can identify the one active public tier by requiring SeaDrop's
  live price, wallet cap, fee, and fee-recipient restriction to uniquely match one immutable tier.
- Reconfiguring the single public stage rotates OpenSea minting among unsold tiers while preserving
  each tier's original token-ID range, inventory counter, price, and wallet counter.

## Risks

**HIGH — Simultaneously active SeaDrop routes are ambiguous to the NFT callback**

The production configuration must keep allowlist windows mutually exclusive and must not enable
token-gated, signed, payer, or an early public route. The release verifier checks those sets and
rejects drift; after transfer, the timelock controls future changes.

**HIGH — Public rotation requires correctly timed owner transactions**

OpenSea exposes only one public stage. Missing a scheduled rotation leaves minting paused after the
old window expires. Each transaction must be verified onchain before its window begins.

**MEDIUM — Stage counters must remain tier-scoped**

Returning collection-global counts would recreate sellout gating. The policy returns tier-local
minted counts and capacity while the collection separately enforces the 3,333 maximum.

## Resolved questions

**Can SeaDrop identify the selected allowlist tier in `mintSeaDrop`?**

No. The official interface supplies only minter and quantity.

**Can the selected OpenSea-only schedule avoid a gateway?**

Yes. The allowlist windows are sequential, and after them there is only one live public stage. The
policy therefore has one unambiguous tier for every valid mint time.

**Auth, install, rate limits, and changes**

Authorization is onchain through NFT configuration. There is no network API rate limit or SDK
installation involved. SeaDrop 1.0 is the sole tagged release; the integration is pinned to its
deployed contract address and ABI.
