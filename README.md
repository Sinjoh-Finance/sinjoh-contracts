# Sinjoh Contracts

[![CI](https://github.com/Sinjoh-Finance/sinjoh-contracts/actions/workflows/ci.yml/badge.svg)](https://github.com/Sinjoh-Finance/sinjoh-contracts/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](./LICENSE)

Solidity contracts, integration tests, deployment records, and provenance for
the Sinjoh protocols on Robinhood Chain (chain ID `4663`). Each protocol is an
independent Foundry package with pinned compiler settings and its own tests.

> **Release status:** public source release under the Apache License 2.0.
> Deployment provenance is verified, but publication is not an independent
> security audit. Review [`AUDITS.md`](./AUDITS.md) before relying on deployed
> or source code.

## Packages

| Package | Purpose |
| --- | --- |
| [`sinjoh-fee-router`](./sinjoh-fee-router) | Immutable fee collection, normalization, allocation, and sink routing. |
| [`sinjoh-revenue-collector`](./sinjoh-revenue-collector) | Stable protocol-revenue endpoint with a governance-selected processor. |
| [`sinjoh-airdrop-distributor`](./sinjoh-airdrop-distributor) | Default standard cumulative Merkle-sum holder distributions; no staking required. |
| [`sinjoh-liquidity-manager`](./sinjoh-liquidity-manager) | Permanent full-range Uniswap v3/v4 liquidity management. |
| [`sinjoh-funding-bands`](./sinjoh-funding-bands) | Creator-funded, one-sided v3/v4 market-cap bands and settlement. |
| [`sinjoh-raffle-rewards`](./sinjoh-raffle-rewards) | Holder raffles, round accounting, and prize delivery. |
| [`sinjoh-randomness`](./sinjoh-randomness) | Onchain verification of ECVRF proofs. |
| [`sinjoh-treasury-vault`](./sinjoh-treasury-vault) | Treasury custody and joint-account governance modules. |
| [`sinjoh-pons-v1-adapter`](./sinjoh-pons-v1-adapter) | Pons v1 fee forwarding. |
| [`sinjoh-launchpad-adapters`](./sinjoh-launchpad-adapters) | Pons v1/v2, Flap, pools.trade, and letscash.fun integrations. |
| [`sinjoh-protocol-upgrade`](./sinjoh-protocol-upgrade) | Source-only governed fee routing, optional staking-driven claim distributions, yield baskets, and dynamic funding bands. |
| [`sinjoh-integration`](./sinjoh-integration) | Cross-package and production-behavior integration tests. |
| [`sinjoh-contracts-v2`](./sinjoh-contracts-v2) | Greenfield integrated v2 contracts; not deployed and does not modify legacy packages. |

The packages compose through copied interfaces and ordinary calls or asset
transfers; they do not import one another's implementations.

Greenfield specifications for the next integrated deployment generation are in
[`specs/contracts-v2`](./specs/contracts-v2/README.md). They do not modify or migrate the deployed
contracts listed above.

## Build and test

Requirements:

- Foundry
- the pinned Solidity compiler (`0.8.28`)

Run the deterministic package suites:

```sh
./scripts/test-all.sh
```

The script runs formatting checks and tests for every Foundry package. Tests
whose names contain `.fork.` are excluded unless `SINJOH_RUN_FORK_TESTS=1` is
set. Fork tests also require the RPC variables documented by their owning
package.

## Deployment provenance

The complete local, testnet, mainnet, signing, finality, and cross-repository
promotion workflow is in [RELEASE_OPERATIONS.md](./RELEASE_OPERATIONS.md).

[`mainnet-deployments.json`](./mainnet-deployments.json) is the address and
runtime-hash registry. [`DEPLOYMENT_PROVENANCE.md`](./DEPLOYMENT_PROVENANCE.md)
documents the verification method. Every known mainnet generation has an
annotated `deploy/mainnet/*` tag; those tags must never be moved or deleted.

All 72 source-verifiable deployment contracts are published on Robinhood Chain
Blockscout with successful creation-bytecode matches and no changed-bytecode
results. See [`BLOCKSCOUT_VERIFICATION.md`](./BLOCKSCOUT_VERIFICATION.md) and
the machine-readable
[`blockscout-verification.json`](./blockscout-verification.json).

History filtering changes commit IDs even when source trees are byte-identical.
[`deployment-provenance.json`](./deployment-provenance.json) records both the
original `sinjoh-legacy` commit and its rewritten commit in this repository.

## Security

Treat every deployment manifest as untrusted until its runtime code hash has
been checked against the chain. Never deploy from an uncommitted worktree: the
Forge broadcast `commit` field records `HEAD`, not the content of local edits.

Security reports should be sent privately as described in
[`SECURITY.md`](./SECURITY.md). Do not open a public issue for a suspected
vulnerability.

The repository's audit status and the limits of its provenance evidence are
recorded in [`AUDITS.md`](./AUDITS.md).

## Repository lineage

This repository was history-filtered from private tag
`provenance/pre-reorganization-2026-08-18` in
`Sinjoh-Finance/sinjoh-legacy`. See [`MIGRATION.md`](./MIGRATION.md) for the
scope and verification contract.

## Contributing and license

Contributor setup, testing, and provenance rules are documented in
[`CONTRIBUTING.md`](./CONTRIBUTING.md).

Sinjoh-owned work is licensed under the [Apache License 2.0](./LICENSE).
Third-party and vendored components retain the licenses identified by their
file-level SPDX declarations and accompanying license files; see
[`NOTICE`](./NOTICE).
