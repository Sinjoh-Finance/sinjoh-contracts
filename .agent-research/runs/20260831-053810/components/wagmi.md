<!-- BRAINBLAST:CACHE slug=wagmi version=2.19.5 fetched=2026-08-24 -->
# Wagmi

Version: 2.19.5
Disposition: HIT — reused from cache fetched 2026-08-24
Sources: https://wagmi.sh/react/api/connectors/walletConnect and
https://wagmi.sh/react/api/createConfig

Facts: wallet-reported chain identity must gate writes; configured default chain is not proof of the
wallet's current chain. Existing WalletConnect sessions may have stale chain approvals.

Risks:
- **HIGH — A configured network can mask a wallet connected elsewhere.** Shared action code checks
  chain identity before simulation and signing.
- **MEDIUM — Stale WalletConnect sessions may omit Robinhood Chain.** UI presents reconnect/switch
  recovery rather than signing.

No unresolved question.
