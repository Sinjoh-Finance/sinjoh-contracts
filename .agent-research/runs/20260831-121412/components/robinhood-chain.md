# Component: Robinhood Chain

**Date checked:** 2026-08-31
**Version:** mainnet chain 4663
**Disposition:** MISS-fresh

**Sources:**
- https://docs.robinhood.com/chain/connecting/
- https://docs.robinhood.com/chain/contracts/
- https://robinhood.com/chain

## Facts

- Mainnet chain ID is 4663 and ETH is the gas asset.
- The official public RPC is `https://rpc.mainnet.chain.robinhood.com`; it is rate-limited and not
  recommended for production.
- Canonical WETH is `0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73`.
- Robinhood Chain is permissionless. Existence on the chain is not an endorsement or a safety
  classification for a token or pool.

## Assumptions

- An NFT owner selecting a pool expects that choice to affect only that NFT's market-making
  allocation.

## Inferences

- A pool-existence check alone cannot establish token legitimacy, liquidity quality, oracle
  availability, transfer behavior, or suitability for Yield Banks.

## Risks

**HIGH — Permissionless pool existence is not a safety boundary.** An arbitrary existing pool may
contain a malicious or unsuitable asset. Pool selection must additionally bind the canonical
factory, token contracts, routes, and price sources.

**MEDIUM — Public RPC throttling can make discovery incomplete.** Production pool discovery and
transaction construction require redundant managed RPC reads and a final preflight simulation.

## Resolved questions

**Can any deployed address or pool be treated as reviewed because it is on Robinhood Chain?**

No. Robinhood's official documentation describes the chain as permissionless and expressly does
not warrant third-party protocols listed in its ecosystem.
