# Sinjoh

Sinjoh is immutable launchpad infrastructure for Robinhood Chain. Pons v1 remains
the live integration; Pons v2 support is built behind deployment-manifest gates for
its forthcoming testnet and mainnet contracts. This monorepo contains seven independently deployable and auditable
Solidity packages plus the offchain automation package:

| Package | Purpose |
|---|---|
| [`sinjoh-fee-router`](./sinjoh-fee-router) | Charges a 1% protocol fee on router intake, then routes the remaining assets through immutable buckets and allocations. |
| [`sinjoh-airdrop-distributor`](./sinjoh-airdrop-distributor) | Charges 1% on funding, then pushes the net assets to subject-token holders using cumulative Merkle-sum commitments. |
| [`sinjoh-liquidity-manager`](./sinjoh-liquidity-manager) | Converts one quote asset as needed, creates permanent full-range Uniswap v3/v4 liquidity, and charges 1% of LP fees collected. |
| [`sinjoh-pons-v1-adapter`](./sinjoh-pons-v1-adapter) | Collects or receives Pons v1 fees and forwards the subject token and WETH to a fixed fee router. |
| [`sinjoh-revenue-collector`](./sinjoh-revenue-collector) | Provides a stable protocol-revenue endpoint and forwards assets to a governance-selected downstream processor without charging again. |
| [`sinjoh-keeper`](./sinjoh-keeper) | Automates permissionless routing and provides the isolated deterministic airdrop snapshot, attestation, and push workflow. |
| [`sinjoh-raffle-rewards`](./sinjoh-raffle-rewards) | Pays holders by lottery: hourly VRF draws with a pre-reserved WETH prize and optional per-slot swaps into an approved mystery stock. |
| [`sinjoh-randomness`](./sinjoh-randomness) | Verifiable randomness from an ECVRF proof checked on-chain, for a chain with no VRF deployment. |
| [`sinjoh-indexer`](./sinjoh-indexer) | Projects factory and protocol events through one dynamically registered Envio indexer. |

The packages do not import one another's implementations. Composition uses copied
interfaces and ordinary asset transfers. Each package has its own Foundry
configuration, tests, specification, and deployment scripts.

## Fee and tax boundaries

For Pons v2 launches, the creator may choose a market-level creator tax of zero or 1 to 5,000
basis points (0.01% to 50%). The launch transaction enforces both Sinjoh's 5,000-bps ceiling and
the selected factory's live `maxCreatorTaxBps()`; the lower cap wins. This is Pons market
accounting, not an ERC-20 fee-on-transfer tax, so ordinary wallet transfers remain untaxed.

These separate charges must not be presented as one "trade tax":

- Pons v1 currently launches each token into a 1%-fee Uniswap V3 pool. That LP fee is charged by the
  pool on swaps and split upstream by Pons.
- Pons v2 may additionally assess the creator's immutable launch-time trade tax. Its initial
  recipient is either the creator directly or that launch's `SinjohFeeRouter`.
- The Sinjoh fee router charges 1% when collected launch-fee revenue enters Sinjoh accounting. It
  does not intercept or tax users' trades.
- The liquidity manager charges 1% only from LP fees when they are collected, never from LP
  principal or wallet transfers.
- The raffle charges 1% on prize-pool funding and may also apply its separately configured,
  immutable payout tax to a winning prize. Neither is a token trading tax.

See the [Pons v2 protocol documentation](https://docs.ponsfamily.com/v2).

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
  sinjoh-revenue-collector \
  sinjoh-raffle-rewards \
  sinjoh-randomness
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

Validate the Envio indexer independently:

```sh
cd sinjoh-indexer
npm ci
npm run typecheck
npm test
```

## Documentation

- [`STRATEGY.md`](./STRATEGY.md): protocol boundaries and design principles
- [`DEVELOPMENT_PLAN.md`](./DEVELOPMENT_PLAN.md): delivery and release gates
- [`UI-NOTES.md`](./UI-NOTES.md): UI, indexer, keeper, and end-to-end wiring handoff
- [`INFRASTRUCTURE.md`](./INFRASTRUCTURE.md): provisioned cloud resources, runtime variables, and remaining credential gates
- [`SELF-AUDIT.md`](./SELF-AUDIT.md): pre-audit review of the raffle and randomness packages
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
