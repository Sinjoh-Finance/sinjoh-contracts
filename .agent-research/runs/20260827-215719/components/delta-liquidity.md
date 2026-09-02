# Delta Liquidity

Version: unversioned
Disposition: MISS-unversioned
Primary source: https://deltaliquidity.app/docs

## Verified facts

- Delta has two products: Stakes and Pools. Stakes accept one token or ETH plus a token, create the underlying LP, and stream WETH rewards to stakers over seven days.
- Delta staking does not currently auto-compound. Rewards must be claimed and redeposited.
- Stake withdrawals have no Delta timelock or exit penalty and return both pool assets in their current proportions; Delta does not automatically swap them back to the deposit asset.
- Delta Pools expose Uniswap v3 and v4 concentrated-liquidity positions. An out-of-range position is entirely in one asset and earns no fees until price returns to range.
- Delta charges 1% of claimed fees and no fee on principal, deposits, or withdrawals.
- Delta publishes these Robinhood Chain addresses:
  - VaultFactory: `0x68EDc4948F60D21c4a7Dcbb8Ed4500cE6D0b153c`
  - VaultFarmFactory: `0x2bdA3FeB985d812a5932fe59eD4D8627BA3A10d1`
  - DeltaZap: `0xC0b8eC7589ee49c53305517bFd53BEd708392294`
  - TwapOracle: `0xA26cB1b06AAE9E58D5DBCCE40f7fC38c0aced62C`
  - DeltaPositionBuilder: `0x6235cF6bd8419b34942F4EDDB39C880BD96dD700`
  - DeltaLadderManager v3: `0x5cA6214227D1195c4b7b4B96847b8966c688295D`
- Blockscout exposed verified source for `DeltaPositionBuilder` only. It is Solidity 0.8.26 and mints Uniswap v3 `INonfungiblePositionManager` NFTs directly to `msg.sender` using caller-supplied nonzero minimum amounts and a deadline. It clears approvals and refunds residual assets.
- The verified builder creates positions but does not expose increase, decrease, collect, or rebalance functions.
- No authenticated API or documented rate limit is involved in the onchain contracts. Delta did not publish a versioned SDK, complete ABI bundle, or changelog in the inspected documentation.

## Assumptions and inferences

- A per-NFT vault can directly own a position minted through `DeltaPositionBuilder` if it implements ERC-721 receipt and token approval logic.
- The safer v1 integration is a Sinjoh-owned strategy wrapper that uses the verified builder for entry and the canonical Uniswap v3 position manager for lifecycle management. The unverified Delta stake/farm contracts should not be made immutable dependencies yet.
- Because rewards stream for seven days and do not auto-compound, a vault must track claimed, claimable, and still-streaming WETH separately.

## Risks

- **CRITICAL — Core contracts are not source-verified.** The stake factory, farm factory, zap, TWAP oracle, and ladder manager lack publicly verified source/ABI at the addresses inspected. Their custody and upgrade behavior cannot be independently validated for an immutable collection integration.
- **HIGH — Rewards are not automatically compounded.** Seven-day streaming plus manual claiming can produce accounting mistakes at redemption unless streamed rewards are included or exits wait/transfer the claim.
- **HIGH — Direct per-NFT positions do not scale operationally.** Rebalancing as many as 3,000 separate ranges would impose high gas, keeper, and failure-management overhead.
- **MEDIUM — Range and inventory risk.** Out-of-range positions stop earning fees and become one-sided, so advertised yield is neither fixed nor guaranteed.

## Unresolved

- Unresolvable from public sources: the complete verified ABI/source and upgrade controls for the stake/farm/zap/manager path. The official docs and the published Blockscout addresses were checked.
- Unresolvable from public sources: a formal Delta protocol release version and changelog.
