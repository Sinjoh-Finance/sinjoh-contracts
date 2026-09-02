# Coverage review

| Component | Auth / authority | Version / install | Limits | Breaking-change surface | Risk covered |
|---|---|---|---|---|---|
| SeaDrop | NFT owner configures; SeaDrop alone mints | address + code hash | stage caps | mutable config | yes |
| Seaport | signed orders; OpenSea settings owner-controlled | address + code hash | order-specific | optional royalties | yes |
| Robinhood Chain | wallet signatures / RPC credentials | chain 4663 | public RPC throttled | network/address drift | yes |
| Stock Tokens | eligibility external; ERC-20 onchain | beacon + implementation | legal restrictions | multiplier / implementation | yes |
| USDG | ERC-20 onchain | proxy + implementation | n/a | implementation upgrade | yes |
| Delta v3 | allocation operator; sleeve-bound adapter | address + code hashes | position cap | route/dependency drift | yes |
| Chainlink feeds | read-only | address + code hash | freshness bound | feed replacement | yes |
| OpenZeppelin | contract roles | 5.6.1 lock | n/a | library upgrades | yes |
| Viem | connected account | pinned workspace versions | provider limits | ABI/client changes | yes |
| Wagmi | connected wallet | 2.19.5 | connector limits | stale sessions | yes |
| Envio | hosted deploy credentials | 3.2.1 | provider/log limits | config/codegen | yes |
| Uniswap v3/v4 | operator approvals | pinned dependencies | ranges/positions | v4 intentionally disabled | yes |

All components cover authority, version identity, operational limits, breaking-change surface, and at
least one risk. No research question was left without either a source-backed answer or an explicit
public-source limitation.
