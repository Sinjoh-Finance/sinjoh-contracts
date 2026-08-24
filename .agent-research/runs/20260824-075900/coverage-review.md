# Coverage Review

| Component | Auth | Install/version | Rate limits | Breaking changes | Risk | Coverage |
|---|---|---|---|---|---|---|
| @sinjoh/sdk | npm publication authority is external operator state | Local target 2.1.0; registry latest 2.0.0 | Registry availability applies | Coordinated 2.1.0 package set not yet published | Critical | Complete for release decision |
| viem | None for library; transport may require provider auth | 2.55.19 | Transport-specific | Major version constrained below 3 | Medium | Complete |
| Robinhood Chain | Public RPC none; recommended providers use keys | Mainnet chain ID 4663 | Public endpoint explicitly rate-limited | Network notices/upgrades are separate official surface | High | Complete; exact public quota is not published |
| Uniswap v4 core | None | 1.0.2 | Not applicable | Singleton custody differs materially from v3 | Critical | Complete |
| OpenZeppelin Contracts | None | 5.6.1 | Not applicable | 5.x moved customization to `_update` | Low | Complete |
| Reown / WalletConnect | Project ID plus domain allowlist | AppKit 1.7.8 transitive | APKT010 documented; numeric quota not public | WalletConnect/Reown package tree contains deprecation notices in the lockfile | High | Complete for launch gate |
| Vercel | Team/project authorization | Managed platform, unversioned | Plan-dependent | Environment behavior is documented and current | Medium | Complete |

No official source publishes the numeric Robinhood public-RPC quota, the current Reown dashboard allowlist, the final Production multisig selection, or the npm account's present authentication state. Those are explicitly treated as external configuration gates rather than guessed.
