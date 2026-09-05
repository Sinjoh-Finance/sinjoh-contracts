# Coverage Review

| Component | Auth / access | Version | Limits | Breaking changes | Risk | Result |
| --- | --- | --- | --- | --- | --- | --- |
| Flap Portal | Permissionless onchain calls | Live `v5.21.2` | Gas and contract guards | Version drift found; launch ABI/config to be lifecycle-tested | Covered | Complete |
| Robinhood Chain | Authenticated archive RPC for CI | Chain `4663` | Public RPC is rate-limited | No chain-level breaking change found | Covered | Complete |

There is no package installation step for either onchain component. Flap does not publish a rate-limit for contract calls; normal gas and RPC-provider constraints apply. No public changelog entry for `v5.21.2` was found, so compatibility must be established from live state and the forked end-to-end proof.
