# Component: Robinhood Chain

**Date checked:** 2026-09-03
**Version:** mainnet chain ID `4663`
**Sources:**
- Network and RPC details: https://docs.robinhood.com/chain/connecting/
- Deployment guide: https://docs.robinhood.com/chain/deploy-smart-contracts/

## Facts

- Robinhood Chain mainnet is EVM-compatible, uses ETH for gas, and has chain ID `4663`.
- The official public RPC is `https://rpc.mainnet.chain.robinhood.com` and is rate-limited; Robinhood
  recommends a managed provider for production traffic.
- Standard Solidity/Foundry deployments are supported.

## Assumptions

- The already deployed SeaDrop address remains available at launch.

## Inferences

- The storage-based OpenZeppelin reentrancy guard is chain-compatible and does not require
  assumptions about transient-storage support.

## Risks

**LOW — Public RPC throttling**

The public RPC is suitable for verification and tests but should not be the production application's
only RPC endpoint.

## Resolved questions

**Is standard Solidity execution supported?** Yes; the official guide states the chain is EVM-compatible.

**Auth, install, rate limits, and changes**

Onchain writes authenticate with transaction signatures. No SDK is required. The public RPC is
explicitly rate-limited; no numeric quota is published on the checked page.
