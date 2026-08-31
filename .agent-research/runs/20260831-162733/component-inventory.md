# Component Inventory

| Component | Type | Version | Role | Confidence |
|---|---|---|---|---|
| Robinhood Chain | Blockchain | chain 4663 | Hosts Yield Banks and the live liquidity infrastructure | High |
| Uniswap V3 deployment on chain 4663 | Blockchain | canonical deployment dated 2026-05-22 | Defines factories, pools, swaps, and position NFTs | High |
| Delta position builder | Other | unversioned live deployment | Mints the manually selected V3 position ladder | High |
| OpenZeppelin Contracts | SDK | 5.6.1 | Supplies ownership, reentrancy, token, and utility primitives | High |

Inventory was derived from the current requirement and repository lock/dependency state. The user
requested continuous execution, so research proceeded without an inventory pause.
