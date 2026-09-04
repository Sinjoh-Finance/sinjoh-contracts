# Coverage review

| Component | Auth/authority | Version/install | Limits | Breaking changes | Risk covered |
|---|---|---|---|---|---|
| SeaDrop | NFT owner configures the pinned implementation; SeaDrop alone mints | Unversioned canonical deployment | Leaf wallet and cumulative supply limits | Callback omits stage parameters | Yes |
| OpenSea Drops | Connected collection owner publishes | Unversioned hosted service | Presale wallet lists and hosted public final stage | Fees and UI behavior are external | Yes |
| OpenZeppelin Contracts | Existing `Ownable2Step` and contract roles | 5.6.1 local source | Application-defined | 5.x `_update` hook verified | Yes |
| Robinhood Chain | Factory registry and collection roles | Chain ID 4663 | RPC/provider dependent | Deployment reorg risk | Yes |

All required coverage areas are addressed. OpenSea's whitelist-only hosted configuration remains an
external launch-time decision, not a source-code assumption.
