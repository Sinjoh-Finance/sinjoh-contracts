<!-- BRAINBLAST:CACHE slug=uniswap-v3-v4 version=v3-unversioned-v4-core-1.0.2 fetched=2026-08-27 -->
# Uniswap v3/v4 concentrated liquidity

Version: v3 unversioned / v4 core 1.0.2
Disposition: HIT — reused from cache fetched 2026-08-27
Sources: https://docs.uniswap.org/concepts/protocol/concentrated-liquidity and
https://docs.uniswap.org/contracts/v3/guides/providing-liquidity/mint-a-position

Facts: v3 positions are ERC-721s; an out-of-range position becomes single-sided and stops earning;
production mints require protected nonzero minimums and deadlines.

Risks:
- **HIGH — Weak minimums/ranges permit slippage or manipulation.** Adapter calldata includes explicit
  per-rung floors, tick bounds, and deadline.
- **MEDIUM — Position custody mistakes can strand backing.** The adapter tracks only accepted manager
  NFTs and tests full exit.
- **MEDIUM — Out-of-range drift changes exposure and fee generation.** This is visible performance
  risk and requires manual monitoring/rebalancing.

Unresolved: no reviewed Delta v4 path; v4 remains disabled.
