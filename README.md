# Sinjoh

Sinjoh is immutable launchpad infrastructure for Robinhood Chain. Pons v1 and
Pons v2 are live integrations; Flap, Pools, and letscash.fun support remains
behind deployment-manifest gates. This monorepo contains independently
deployable and auditable Solidity packages plus offchain automation:

| Package | Purpose |
|---|---|
| [`sinjoh-fee-router`](./sinjoh-fee-router) | Charges a 1% protocol fee on router intake, then routes the remaining assets through immutable buckets and allocations. |
| [`sinjoh-airdrop-distributor`](./sinjoh-airdrop-distributor) | Charges 1% on funding, then pushes the net assets to subject-token holders using cumulative Merkle-sum commitments. |
| [`sinjoh-liquidity-manager`](./sinjoh-liquidity-manager) | Converts one quote asset as needed, creates permanent full-range Uniswap v3/v4 liquidity, and charges 1% of LP fees collected. |
| [`sinjoh-funding-bands`](./sinjoh-funding-bands) | Lets verified launch creators commit inventory to one-sided v3/v4 market-cap bands, then routes crossed WETH proceeds to the creator or a fee router. |
| [`sinjoh-pons-v1-adapter`](./sinjoh-pons-v1-adapter) | Collects or receives Pons v1 fees and forwards the subject token and WETH to a fixed fee router. |
| [`sinjoh-launchpad-adapters`](./sinjoh-launchpad-adapters) | Integrates Pons v1/v2, Flap, Pools, and letscash.fun and forwards each launchpad's actual fee assets to the launchpad-agnostic router. |
| [`sinjoh-revenue-collector`](./sinjoh-revenue-collector) | Provides a stable protocol-revenue endpoint and forwards assets to a governance-selected downstream processor without charging again. |
| [`sinjoh-treasury-vault`](./sinjoh-treasury-vault) | Custodies treasury assets under one swappable governor address, paired with a 2-of-3 joint-account control system as the Standard governance module. |
| [`sinjoh-keeper`](./sinjoh-keeper) | Automates permissionless routing and provides the isolated deterministic airdrop snapshot, attestation, and push workflow. |
| [`sinjoh-sdk`](./sinjoh-sdk) | TypeScript packages for typed ABIs, verified deployment manifests, byte-exact config codecs, deterministic Merkle trees, launch planning, and a read-only MCP agent surface. |
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

Pons's public documentation currently describes v1 and is not authoritative for
the deployed v2 ABI. Use the pinned [official Pons v2 source
commit](https://github.com/ponsdotdev/ponsfamily/commit/836f0f97f9a9569855876570d6778501c163c883)
and the verified live [factory](https://robinhoodchain.blockscout.com/address/0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e)
and [hook](https://robinhoodchain.blockscout.com/address/0xE5e702641Ea86F4ae6cC3cDaeD2B886f976Be044)
when checking v2 behavior.

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
  sinjoh-funding-bands \
  sinjoh-pons-v1-adapter \
  sinjoh-revenue-collector \
  sinjoh-raffle-rewards \
  sinjoh-randomness \
  sinjoh-launchpad-adapters \
  sinjoh-treasury-vault
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

Build and test the SDK workspace independently:

```sh
cd sinjoh-sdk
npm ci
npm run typecheck
npm test
npm run build
npm run pack:check
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
- [`sinjoh-sdk/README.md`](./sinjoh-sdk/README.md): SDK quick start, package map, safety model, and release status
- [`TESTNET_DEPLOYMENTS.md`](./TESTNET_DEPLOYMENTS.md): verified Robinhood testnet deployments
- [`SJTEST_TESTNET_REPORT.md`](./SJTEST_TESTNET_REPORT.md): completed SJTEST test launch
- Each package's `SPEC.md`: normative behavior and security requirements

## Release state

Core infrastructure is deployed on Robinhood Chain mainnet (chain `4663`) as of
2026-07-30, with funding bands following on 2026-08-15. The authoritative record
of every deployed address, runtime code hash, and third-party dependency is
[`mainnet-deployments.json`](./mainnet-deployments.json)
(`status: "core-infrastructure-deployed"`, release candidate). Pons v1 and
Pons v2 integrations are live; Flap, pools.trade, and letscash.fun support is
deployed but remains behind deployment-manifest gates. The earlier Robinhood
testnet deployments predate the hardened revision and are historical validation
data only.
