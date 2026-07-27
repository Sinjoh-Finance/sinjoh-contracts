# Sinjoh

Sinjoh is immutable launchpad infrastructure for Robinhood Chain, beginning with
Pons v1. This monorepo contains five independently deployable and auditable
Solidity packages:

| Package | Purpose |
|---|---|
| [`sinjoh-fee-router`](./sinjoh-fee-router) | Charges a 1% protocol fee on router intake, then routes the remaining assets through immutable buckets and allocations. |
| [`sinjoh-airdrop-distributor`](./sinjoh-airdrop-distributor) | Charges 1% on funding, then pushes the net assets to subject-token holders using cumulative Merkle-sum commitments. |
| [`sinjoh-liquidity-manager`](./sinjoh-liquidity-manager) | Converts one quote asset as needed, creates permanent full-range Uniswap v3/v4 liquidity, and charges 1% of LP fees collected. |
| [`sinjoh-pons-v1-adapter`](./sinjoh-pons-v1-adapter) | Collects or receives Pons v1 fees and forwards the subject token and WETH to a fixed fee router. |
| [`sinjoh-revenue-collector`](./sinjoh-revenue-collector) | Provides a stable protocol-revenue endpoint and forwards assets to a governance-selected downstream processor without charging again. |

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

## Documentation

- [`STRATEGY.md`](./STRATEGY.md): protocol boundaries and design principles
- [`DEVELOPMENT_PLAN.md`](./DEVELOPMENT_PLAN.md): delivery and release gates
- [`UI-NOTES.md`](./UI-NOTES.md): UI, indexer, keeper, and end-to-end wiring handoff
- [`TESTNET_DEPLOYMENTS.md`](./TESTNET_DEPLOYMENTS.md): verified Robinhood testnet deployments
- [`SJTEST_TESTNET_REPORT.md`](./SJTEST_TESTNET_REPORT.md): completed SJTEST test launch
- Each package's `SPEC.md`: normative behavior and security requirements

## Release state

The final Robinhood testnet sweep, including the revenue collector and all three
1% fee paths, is complete. Mainnet has not been deployed. Mainnet
activation remains gated on final immutable configuration approval, exact-state
fork rehearsal, dependency code-hash verification, independent external review,
production infrastructure, and a small-value post-deployment smoke test.
