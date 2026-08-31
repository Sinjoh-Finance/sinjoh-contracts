# Component: Robinhood Chain

**Date checked:** 2026-08-31
**Version:** chain 4663
**Disposition:** MISS-fresh

## Sources

- https://docs.robinhood.com/chain/contracts/
- https://docs.robinhood.com/chain/connecting/
- https://docs.robinhood.com/chain/
- live JSON-RPC at https://rpc.mainnet.chain.robinhood.com

## Facts

- The official mainnet chain ID is 4663 and the official public RPC is
  `https://rpc.mainnet.chain.robinhood.com`.
- The public RPC is rate-limited and the documentation recommends a production provider.
- Canonical WETH is `0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73`.
- Robinhood Chain is permissionless. Contract or pool existence is therefore not an endorsement.

## Assumptions

- None. Network identity and WETH were read from the official documentation and live chain.

## Inferences

- Production discovery must use redundant RPC providers and revalidate identity in the execution
  transaction. An indexer result alone is not an authorization boundary.

## Risks

**HIGH — Permissionless assets can be malicious.** A canonical factory can host a pool containing a
hostile ERC-20. Pool discovery may be permissionless, but execution must retain exact-transfer,
runtime-identity, slippage, deadline, and manual-operator checks.

**MEDIUM — Public RPC throttling can hide discovery results.** Production pool enumeration cannot
depend on the public endpoint alone.

## Resolved questions

**Does a pool need to be present in a Sinjoh manifest to prove it exists?**

No. Existence and immutable identity are available directly from the canonical factory and pool.
The manifest only needs to pin the trusted infrastructure generation.
