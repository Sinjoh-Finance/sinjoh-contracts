# Contributing

Contributions are welcome through GitHub issues and pull requests. Never use a
public issue to report a suspected vulnerability; follow
[`SECURITY.md`](./SECURITY.md) instead.

## Development setup

Install Foundry and the Solidity compiler required by each package. The active
Sinjoh packages pin Solidity `0.8.28` in their Foundry configuration.

Run the deterministic repository gate before opening a pull request:

```sh
./scripts/test-all.sh
node scripts/verify-provenance-map.mjs
```

Fork tests are opt-in because they require live RPC access:

```sh
SINJOH_RUN_FORK_TESTS=1 ./scripts/test-all.sh
```

## Pull requests

- Keep changes scoped to one protocol or one shared concern.
- Run `forge fmt` in every modified Foundry package.
- Add unit, fuzz, invariant, or fork coverage appropriate to the risk.
- Never move, delete, or retarget a `deploy/mainnet/*` tag.
- Never commit private keys, authenticated RPC URLs, or deployment secrets.
- Explain any runtime bytecode change and whether it affects a deployed
  generation.

Unless explicitly stated otherwise, contributions intentionally submitted for
inclusion are licensed under the Apache License 2.0 as described by section 5
of [`LICENSE`](./LICENSE). Files carrying another SPDX identifier retain that
file-level license.
