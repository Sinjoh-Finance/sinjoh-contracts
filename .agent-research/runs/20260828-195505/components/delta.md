# Component: Delta Liquidity

**Date checked:** 2026-08-28
**Disposition:** MISS-unversioned

## Facts

- Delta runs on Robinhood Chain, chain ID 4663, and documents shaped LP positions and staking:
  https://deltaliquidity.app/docs
- Delta documents `DeltaPositionBuilder` at
  `0x6235cF6bd8419b34942F4EDDB39C880BD96dD700`.
- The explorer-verified builder exposes
  `mintLadder(address pool, Rung[] rungs, int24 minCurrentTick, int24 maxCurrentTick, uint256 deadline)`
  and mints ordinary Uniswap V3 position NFTs directly to `msg.sender`:
  https://robinhoodchain.blockscout.com/api?module=contract&action=getsourcecode&address=0x6235cF6bd8419b34942F4EDDB39C880BD96dD700
- The verified builder constructor binds Uniswap V3 factory
  `0x1f7d7550B1b028f7571E69A784071F0205FD2EfA` and position manager
  `0x73991a25C818Bf1f1128dEAaB1492D45638DE0D3`.
- Its source validates factory pool identity, current-tick bounds, rung ranges, token transfer caps,
  and the deadline, and refunds unused token amounts to the caller.
- Delta's documented single-asset `DeltaZap` at
  `0xC0b8eC7589ee49c53305517bFd53BEd708392294` did not expose verified source or ABI through the
  explorer API during this run and is not used by Yield Banks.

## Assumptions

- Each collection will choose and review its own `$INJOH` token, `$INJOH`/WETH pool, conversion
  routes, PriceHub feeds, adapter cap, and maximum position count.

## Inferences

- Yield Banks can implement a complete Delta ladder lifecycle without the unverified zap or stake
  manager: convert explicitly through codehash-bound routes, mint V3 NFTs through the verified
  builder, self-custody them, decrease/collect/burn through the verified position manager, and
  return WETH plus residual `$INJOH` in kind on full exit.
- Live uncollected V3 fees cannot be read exactly from the position-manager NFT alone. NAV can
  conservatively count principal plus stored owed amounts; an operator collection realizes live
  fees before distribution.

## Risks

**HIGH — activation binding mismatch**

A wrong token, pool, route, factory, manager, or builder can direct backing into the wrong market.
The constructor, deployment plan, release manifest, registry, and live verifier must all bind the
same addresses and runtime code hashes.

**MEDIUM — conservative fee valuation**

Live fees not yet crystallized into `tokensOwed` are omitted from adapter NAV until collection. This
undercounts rather than overstates backing, but operations must collect before financial reporting
that requires realized fee totals.

## Resolved questions

**Can the concrete Delta adapter be implemented without relying on an unverified Delta zap or stake
manager?**

Yes. The verified builder creates caller-owned ordinary V3 NFTs, and the standard verified position
manager supplies the complete decrease, collect, and burn lifecycle. Collection-specific economic
choices remain explicit deployment or transaction inputs rather than protocol defaults.
