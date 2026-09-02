# Component Inventory

| Component | Type | Version | Role | Confidence |
|---|---|---|---|---|
| Delta Liquidity | Other | unversioned | Creates Delta stakes and shaped LP positions on Robinhood Chain and distributes trading fees. | High |
| Robinhood Chain | Blockchain | unversioned; chain ID 4663 | EVM execution and settlement network for all collection, Stock Token, and Delta contracts. | High |
| Robinhood Stock Tokens and REST metadata API | API | unversioned | Provides ERC-20 stock exposure, corporate-action multipliers, token metadata, and trading-halt data. | High |
| Chainlink Data Feeds on Robinhood Chain | Other | unversioned | Supplies multiplier-adjusted Stock Token prices, heartbeats, and L2 sequencer status. | High |
| Uniswap v3 and v4 concentrated liquidity | Other | v3 unversioned; v4 core 1.0.2 | Underlying concentrated-liquidity systems exposed by Delta. The verified Delta position builder inspected in this run mints Uniswap v3 position NFTs. | High |
| ERC-4626 | Other | EIP-4626 | Standardizes fungible strategy shares used to represent pooled Delta and reserve strategies. | High |
| OpenZeppelin Contracts | SDK | 5.6.1 | Supplies ERC-721, clone, token-safety, access-control, and reentrancy primitives used by Sinjoh V2. | High |
