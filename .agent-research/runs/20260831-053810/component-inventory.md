# Component inventory

| Component | Type | Version | Role | Confidence | Disposition |
|---|---|---:|---|---|---|
| OpenSea SeaDrop | API / contracts | unversioned deployed instance | Primary mint and payout | Explicit | MISS-unversioned |
| OpenSea Seaport | contracts | 1.6 deployed instance | Secondary sales | Explicit | MISS-unversioned |
| Robinhood Chain | Blockchain | mainnet chain 4663 | Execution network | Explicit | MISS-unversioned |
| Robinhood Stock Tokens | contracts | unversioned beacon deployment | Dividend-oriented sleeve assets | Explicit | MISS-unversioned |
| Paxos USDG | contracts | unversioned EIP-1967 deployment | Stable-asset sleeve | Explicit | MISS-unversioned |
| Delta v3 | contracts | unversioned verified deployment | $INJOH/WETH LP sleeve | Explicit | MISS-unversioned |
| Chainlink feeds | contracts | unversioned per feed | USD NAV | Explicit | MISS-unversioned |
| OpenZeppelin Contracts | SDK | 5.6.1 | ERC-721, access, clones, safety | Explicit | HIT |
| Viem | SDK | UI 2.55.19 / SDK 2.55.10 | Reads, simulation, calldata, receipts | Explicit | HIT |
| Wagmi | SDK | 2.19.5 | Wallet connection | Explicit | HIT |
| Envio HyperIndex | Infra | 3.2.1 | Event indexing | Explicit | HIT |
| Uniswap v3/v4 | contracts | v3 unversioned / v4 core 1.0.2 | Concentrated-liquidity semantics | Implied | HIT |

Versions were taken from repository lockfiles or, for deployed contracts, treated as unversioned and
bound by address, runtime code hash, and active implementation hash.
