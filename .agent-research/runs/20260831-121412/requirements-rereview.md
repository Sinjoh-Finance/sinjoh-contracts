# Requirements Re-review

## Wrong assumptions

- `$INJOH` is not required by the live ladder builder; it is hard-coded in the current adapter's
  local configuration and naming.
- Adding several pool adapters to one common fungible market-making sleeve would not give owners
  isolated pool selection.

## Missing constraints

- “Any existing pool” must mean any pool that can pass deterministic factory, token, route, oracle,
  eligibility, and cap validation. Existence alone is unsafe on a permissionless chain.
- Each pool choice needs isolated accounting so one NFT does not inherit another NFT's selected
  pool exposure.

## Immutable choices

- Each pool strategy instance binds one pool, its second asset, its routes, and dependency code
  hashes. New pools must be addable after collection deployment without changing those bindings.

## Sound requirements

- Pool selection belongs to the NFT owner; execution remains manual and operator-limited.
- `$INJOH`/WETH can be the Sinjoh collection's selection without becoming a protocol default.
- Operations-reserve logic is unrelated and should be fully removed.
