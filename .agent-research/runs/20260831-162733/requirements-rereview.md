# Requirements Re-review

## Sound

- Pool-specific manifest entries and governance approvals are unnecessary for deterministic pool
  identity.
- Infrastructure upgrades should add a new version instead of mutating existing adapters.
- Manual capital execution remains the correct final gate for user-selected pools.

## Wrong assumptions corrected

- The previous report treated “admitted pool” as synonymous with “manifest-listed pool.” It is not.
- A canonical-factory check proves pool identity, not token safety, liquidity, or price quality.

## Missing constraints now explicit

- Pool discovery and capital execution are separate states.
- Every execution rechecks the active infrastructure version and exact factory/pool relationship.
- A future incompatible Delta deployment requires a new adapter generation.
- The public RPC cannot be the only production discovery/indexing provider.

## Immutable choices

- Existing adapter instances retain their original factory, position manager, builder, routes, and
  runtime bindings. They are exited, not rewritten.

## Unresolved questions

None. The implementation must fail closed for pools that cannot satisfy the active adapter
generation's token-pair and accounting requirements while still permitting owners to discover and
request canonical pools without a manifest edit.
