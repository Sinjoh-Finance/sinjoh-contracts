# Robinhood Chain

Version: mainnet chain ID 4663
Disposition: MISS-unversioned

Sources: https://docs.robinhood.com/chain/connecting/,
https://docs.robinhood.com/chain/contracts/, https://docs.robinhood.com/chain/

## Facts

- Mainnet is chain 4663; testnet is 46630. ETH is the native gas and SeaDrop payment asset.
- Canonical WETH is `0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73`; canonical USDG is
  `0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168`.
- Public RPC endpoints are rate-limited and not recommended for production.

## Risks

- **HIGH — Testnet/mainnet dependency mixing can target the wrong contracts.** Mitigated by making
  the release manifest mainnet-only and checking the RPC chain ID before reads or writes.
- **MEDIUM — Public RPC throttling can make monitoring incomplete.** Production requires managed,
  redundant RPC providers.

No public-source question remains unresolved.
