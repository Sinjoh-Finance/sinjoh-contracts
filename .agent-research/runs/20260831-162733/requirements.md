# Yield Banks dynamic Delta pool admission

Yield Bank NFT owners must be able to select an existing canonical Delta/Uniswap V3 pool without
Sinjoh adding that pool to a release manifest or asking governance to approve the individual pool.

The protocol must:

- pin and source-verify Delta infrastructure generations rather than enumerating pools;
- validate pool identity from the approved factory onchain;
- keep each selected pool's accounting isolated;
- allow a new Delta deployment generation to be approved by collection governance without
  mutating existing adapters or positions;
- preserve manual investment execution, loss limits, deadlines, slippage limits, emergency exits,
  and owner-controlled allocation changes;
- expose dynamic pool discovery and materialization consistently in contracts, SDK, indexer, API,
  keeper, UI, deployment schemas, and documentation;
- fail closed when a pool is not compatible with an approved integration generation.

No pool-specific release-manifest entry or pool-specific governance transaction may be required.
