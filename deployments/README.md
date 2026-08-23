# Deployment control plane

This directory contains machine-readable release policy. It does not replace the
normative contract specifications or invent onchain state.

- `networks/`: RPC, explorer, finality, and broadcast policy by chain ID.
- `plans/`: allowlisted ordered deployment steps. Workflows cannot accept arbitrary
  package or script input.
- `manifests/`: current environment state. A step is completed only after finality and
  post-deployment verification.
- `forks/`: explicit live-fork certification inventories.
- `assertions/`: owner, signer, lifecycle, and configuration reads that runtime
  bytecode hashes cannot cover.
- `consumers/bindings.json`: reviewed mappings from canonical deployment paths to
  UI, Railway, and Envio contracts/environment variables.
- `schema/`: stable schemas for network, deployment, plan, and release records.

Robinhood testnet currently has `status: not-deployed` because the earlier generation
predates the hardened contracts. Do not populate addresses from historical prose. The
first current-generation rollout must build the record from finalized receipts and
measured runtime code hashes.

Mainnet's compatibility registry remains `../mainnet-deployments.json`. New tooling
validates it in place so SDK consumers are not broken. The mainnet plan is deliberately
checked in with every step blocked; a reviewed release PR unlocks only the approved
entrypoints, while signing remains offline. Future generations should be append-only
records, with the root registry generated as the current compatibility view.

`publish-promotion.yml` converts one finalized deployment registry into an
attested, immutable consumer artifact. Downstream repositories and platforms
must import or render that artifact; they do not become independent address
authorities. A candidate artifact rehearses the exact generation while the
current production generation stays active. A separately approved active
artifact performs the consumer cutover.
