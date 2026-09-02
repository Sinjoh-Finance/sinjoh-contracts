# Component: Uniswap V3 core/periphery model

**Date checked:** 2026-08-31
**Version:** v3-core 1.0.1
**Disposition:** MISS-fresh

**Sources:**
- https://github.com/Uniswap/v3-core/blob/main/contracts/interfaces/IUniswapV3Factory.sol
- https://github.com/Uniswap/v3-core/blob/main/contracts/interfaces/pool/IUniswapV3PoolImmutables.sol
- https://github.com/Uniswap/v3-periphery/blob/main/contracts/interfaces/INonfungiblePositionManager.sol
- https://docs.uniswap.org/contracts/v3/guides/providing-liquidity/mint-a-position

## Facts

- V3 factory pool identity is `(tokenA, tokenB, fee)` and `getPool` returns zero when no such pool
  exists.
- A pool permanently exposes its factory, `token0`, `token1`, fee, and tick spacing.
- Each position-manager token is an ERC-721 whose position record includes token0, token1, fee,
  ticks, liquidity, and tokens owed.
- Official minting guidance requires an already-created, initialized pool and warns that zero
  minimum amounts are vulnerable to front-running.

## Assumptions

- Yield Banks will continue using the reviewed V3 deployment rather than silently switching to V4.

## Inferences

- A pool can be admitted deterministically by checking its factory lookup, immutable token pair,
  fee, tick spacing, runtime hash, routes, and price sources.
- Owner-specific choice requires pool-specific accounting shares or per-token position custody;
  it cannot be represented truthfully by one common market-making share token.

## Risks

**HIGH — Missing slippage, tick, or deadline constraints enables value extraction.** Every entry,
withdrawal, and rebalance must retain nonzero minima, current-tick bounds, and a short deadline.

**HIGH — Thin or manipulable pools can produce severe losses.** Factory authenticity does not
prove liquidity depth or a reliable external price. Admission needs reviewed price feeds and caps.

**MEDIUM — Tick-spacing or position-identity mismatch can revert or misattribute custody.** The
adapter must verify the minted position's tokens, fee, owner, liquidity, and pool factory identity.

## Resolved questions

**Can an existing V3 pool be identified without a hard-coded token symbol?**

Yes. The canonical identity is the two token addresses plus fee, verified against the factory's
`getPool` result and the pool's immutable fields.
