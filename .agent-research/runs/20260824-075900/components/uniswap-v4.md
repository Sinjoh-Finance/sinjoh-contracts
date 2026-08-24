# Component: Uniswap v4 core

**Date checked:** 2026-08-24
**Sources:**
- Documentation index: https://developers.uniswap.org/llms.txt
- PoolManager architecture: https://developers.uniswap.org/docs/protocols/v4/concepts/poolmanager

## Facts

- The pinned local `@uniswap/v4-core` package is 1.0.2.
- Uniswap v4 uses a singleton PoolManager rather than deploying one contract per pool.
- New pools are initialized inside PoolManager and identified by a unique PoolId.
- During swaps and liquidity operations, tokens move into the PoolManager contract and final balances settle there.

## Assumptions

- The live Pons factory's `poolManager()` and `locker()` views are the authoritative graduation custody addresses for its immutable release.

## Inferences

- A Project registry cannot store a v4 pool as a normal pool address; PoolId is the pool identity while PoolManager is token custody.
- Voting, airdrop, and raffle exclusions must include both the Pons locker and the singleton PoolManager before the token's one-time exclusion finalization.

## Risks

**CRITICAL — Graduation moves supply into custody omitted by the historical Project release**

The historical GovTest token excluded its curve and adapter but not the current Pons locker or v4 PoolManager. After graduation, balances in those contracts could inflate eligible voting supply and holder eligibility. Safe launch payloads must include both addresses, and a hardened adapter must verify them from the live factory.

## Resolved questions

**Does graduation create a separate ERC-20 token or pool contract?**

No separate token is required. Uniswap v4 initializes pool state in the singleton PoolManager and identifies it by PoolId; the same launched ERC-20 can move from curve custody into locker/PoolManager custody.
