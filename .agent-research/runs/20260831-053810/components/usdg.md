# Paxos USDG on Robinhood Chain

Version: unversioned EIP-1967 proxy deployment
Disposition: MISS-unversioned

Sources: https://docs.robinhood.com/chain/contracts/,
https://eips.ethereum.org/EIPS/eip-1967

## Facts

- Canonical USDG is `0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168`.
- The live address is an EIP-1967 proxy. Runtime code at the proxy is insufficient to identify the
  active implementation.

## Risks

- **HIGH — Proxy implementation drift can change asset behavior without changing the USDG address.**
  Mitigated by manifest binding and live verification of both proxy and implementation code hashes.

No public-source question remains unresolved.
