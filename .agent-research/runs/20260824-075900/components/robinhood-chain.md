# Component: Robinhood Chain

**Date checked:** 2026-08-24
**Sources:**
- Connecting to Robinhood Chain: https://docs.robinhood.com/chain/connecting/
- Deploying smart contracts: https://docs.robinhood.com/chain/deploy-smart-contracts/

## Facts

- Robinhood Chain mainnet is an Arbitrum L2 with chain ID 4663 and ETH as the gas token.
- The official public RPC is `https://rpc.mainnet.chain.robinhood.com`.
- Robinhood's documentation says the public endpoints are rate-limited and not recommended for Production.
- The docs recommend a provider such as Alchemy and say archive endpoints are required for historical reads and indexing.

## Assumptions

- The production operator will provision a keyed provider and apply origin/quota controls before launch.

## Inferences

- Public-RPC success during local tests is not a Production availability guarantee.
- Browser prediction and simulation can fail intermittently under public rate limits even when contracts are correct.

## Risks

**HIGH — Production currently defaults to a non-production public RPC**

The app defaults browser reads to an endpoint Robinhood explicitly labels rate-limited and not recommended for Production. Provision and verify a production provider or a rate-limited server relay before enabling the live launch path.

## Resolved questions

**Is the public RPC the recommended Production endpoint?**

No. Robinhood recommends provider-backed endpoints for Production and archive endpoints for historical access.
