# Requirements re-review

## Missing constraints now made explicit

- Primary OpenSea mint payment is native ETH on Robinhood Chain, not an ERC-20 WETH transfer. The
  proceeds vault receives native net payout and manual allocation later wraps only backing as needed.
- Secondary creator earnings are optional marketplace behavior for this custom ERC-721; ERC-2981 is
  a signal, not enforcement.
- Stock Token income is represented by multiplier-aware balance appreciation, not a separate cash
  dividend arriving in the protocol.
- Production release is Robinhood Chain mainnet only until separately reviewed testnet dependencies
  are supplied.

## Corrected assumptions

- Checking proxy runtime code alone does not identify USDG or Stock Token behavior. Active EIP-1967
  implementation and beacon implementation hashes are now required.
- A single public-drop hash did not cover payers, signers, token-gated stages, or fee recipients. The
  release commitment now covers every enumerable mint authorization path.
- Deploying the NFT directly to a contract timelock prevented OpenSea Studio ownership. Deployment now
  uses a wallet-controlled `openSeaManager`, then a two-step handoff to the timelock.

## Pre-coding / pre-deployment decisions

- Choose each collection's supply, prices, proceeds splits, default allocation weights, royalty rate,
  eligible Stock Tokens, eligibility policy, roles, and operator limits. None are inferred here.
- Provide reviewed live swap routes, feeds, Delta pool, $INJOH address, and exact code hashes.
- Obtain legal review for Stock Token holder eligibility and public disclosures.

## Immutable choices

Collection supply, economic splits, sleeve policy caps, royalty recipient/rate, dependency bindings,
and deterministic deployment salts are fixed by deployment. A new collection/factory version is the
safe route for changing them.
