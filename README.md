# Sinjoh

Sinjoh is immutable launchpad infrastructure for Robinhood Chain, beginning with
Pons v1. This monorepo contains five independently deployable and auditable
Solidity packages plus the offchain automation package:

| Package | Purpose |
|---|---|
| [`sinjoh-fee-router`](./sinjoh-fee-router) | Charges a 1% protocol fee on router intake, then routes the remaining assets through immutable buckets and allocations. |
| [`sinjoh-airdrop-distributor`](./sinjoh-airdrop-distributor) | Charges 1% on funding, then pushes the net assets to subject-token holders using cumulative Merkle-sum commitments. |
| [`sinjoh-liquidity-manager`](./sinjoh-liquidity-manager) | Converts one quote asset as needed, creates permanent full-range Uniswap v3/v4 liquidity, and charges 1% of LP fees collected. |
| [`sinjoh-pons-v1-adapter`](./sinjoh-pons-v1-adapter) | Collects or receives Pons v1 fees and forwards the subject token and WETH to a fixed fee router. |
| [`sinjoh-revenue-collector`](./sinjoh-revenue-collector) | Provides a stable protocol-revenue endpoint and forwards assets to a governance-selected downstream processor without charging again. |
| [`sinjoh-keeper`](./sinjoh-keeper) | Automates permissionless routing and provides the isolated deterministic airdrop snapshot, attestation, and push workflow. |

The packages do not import one another's implementations. Composition uses copied
interfaces and ordinary asset transfers. Each package has its own Foundry
configuration, tests, specification, and deployment scripts.

## Clone

The repository vendors the exact official Uniswap and OpenZeppelin releases used
by the contracts, so one clone is sufficient:

```sh
git clone <repository-url>
```

## Test

Run each package independently:

```sh
for package in \
  sinjoh-fee-router \
  sinjoh-airdrop-distributor \
  sinjoh-liquidity-manager \
  sinjoh-pons-v1-adapter \
  sinjoh-revenue-collector
do
  (cd "$package" && forge fmt --check && forge test)
done
```

Live fork tests require the relevant Robinhood RPC environment variables.

The keeper has its own strict TypeScript suite:

```sh
cd sinjoh-keeper
npm ci
npm run typecheck
npm test
npm run build
```

## Documentation

- [`STRATEGY.md`](./STRATEGY.md): protocol boundaries and design principles
- [`DEVELOPMENT_PLAN.md`](./DEVELOPMENT_PLAN.md): delivery and release gates
- [`UI-NOTES.md`](./UI-NOTES.md): UI, indexer, keeper, and end-to-end wiring handoff
- [`TESTNET_DEPLOYMENTS.md`](./TESTNET_DEPLOYMENTS.md): verified Robinhood testnet deployments
- [`SJTEST_TESTNET_REPORT.md`](./SJTEST_TESTNET_REPORT.md): completed SJTEST test launch
- Each package's `SPEC.md`: normative behavior and security requirements

## Release state

The earlier Robinhood testnet sweep, including the revenue collector and all three
1% fee paths, completed successfully. The source now includes cumulative
fee/allocation accounting and deterministic router tranches; because the contracts
are immutable, that hardened revision must receive fresh testnet deployments and a
new end-to-end sweep before it becomes the release candidate. Mainnet has not been
deployed.
