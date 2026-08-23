# Contracts v2 implementation traceability

This is the engineering handoff from the approved specifications in
`../specs/contracts-v2/` to the greenfield implementation. It is not an independent audit or
permission to deploy.

## Protocol coverage

| Protocol | Production implementation | System evidence | UX/DevX boundary |
| --- | --- | --- | --- |
| Project token + Registry + Launcher | `ProjectVotesToken`, `ProjectRegistryV2`, `ProjectLauncherV2`, immutable deployment engine/code stores | token unit/fuzz/invariants; Registry unit/fuzz; 19 Launcher integration/E2E tests | one reviewed preset, creator-owned choices only, deterministic prediction and full preflight before signing |
| Multisig Accounts | independent `ProjectMultisigAccountV2` controller | 25 unit, 6 fuzz, 5 invariant tests; shared Treasury-controller integration | typed submit/confirm/revoke/execute workflow; no module-specific account variant |
| Token Governance | independent `ProjectGovernorV2` + `ProjectTimelockV2`, direct liquid or staked checkpoints | liquid/staked unit, fuzz, invariant, and all-module proposal-to-outcome journeys | no delegation or vote adapter; the Registry publishes Governor, Timelock, and exact vote source |
| Treasury Vaults | `ProjectTreasuryVaultV2` with exact receipts, typed sends/swaps, and Basket reservation | 26 unit, 7 fuzz, Treasury/Bands/controller/system integrations and invariants | same Treasury ABI under either governance model; complete Basket route and approval readbacks |
| Router | `ProjectRouterV2` typed route versions and exact retry escrow | 27 unit, 6 fuzz, cross-module split/recovery and system conservation suites | presets own adapters/routes; governance changes complete route versions; one-call work status |
| Staking + PoS NFT | `ProjectStakingPoolV2` + bound `ProjectPoSNFT` | 26 unit, 6 fuzz, 5 invariant tests and staked-governance/dividend E2E | stake once, receive position NFT, burn on mature unstake; no manual vote activation |
| Airdrop | `ProjectAirdropV2` + deterministic TypeScript snapshot/Merkle-sum worker | 19 unit, 5 fuzz, 5 invariant tests, shared Solidity/SDK fixture and two-provider SDK tests | holder never claims; keeper pushes and retries; attestor tooling fails closed on inconsistent history |
| Basket | `BasketManagerV2`, `BasketNFTV2`, isolated `BasketVaultV2`, ownerless ERC-4626 adapter factory | Basket/adapter unit, fuzz, invariant and funding/yield/burn E2E journeys | reviewed vault selection; infrastructure auto-materialized; due harvest/burn/retry states are readable |
| Funding Bands | `ProjectFundingBandsV2` + ownerless V3 integration factory/guard/position adapter | 16 Bands unit, 5 fuzz, production-integration unit/integration and every-destination E2E | creators choose understandable bounds/inventory/destination; no pool/oracle/adapter/tick/proof fields |
| Raffle | project-bound `ProjectRaffleV2`, release-pinned audited randomness adapter, deterministic worker SDK | 15 unit, 5 fuzz, invariant/integration, normative Merkle fixture and full keeper lifecycle tests | no winner registration/claim; creators never select randomness infrastructure; failures become retry work |
| Permanent Liquidity | project-bound `ProjectLiquidityManagerV2` with V3/V4 support and no principal exit | 21 unit, 5 fuzz, Router integration and all-module launch | reviewed deployment profile owns venue plumbing; creator chooses split/limits/cadence/fee destination only |

## Cross-system requirements

- The canonical zero and burn addresses are removed from liquid votes, eligible voting supply,
  staked position ownership, Airdrop weights, and Raffle tickets. The Pons locker, canonical pool,
  project subject, and enabled custody modules are automatically excluded where applicable.
- Creator eligibility is ordinary eligibility: the creator is neither given a bonus nor excluded
  merely for being the creator.
- Router, Treasury, Basket, Bands, Raffle, Airdrop, and Liquidity use typed project-bound funding or
  control paths. No project module exposes `delegatecall`, proxy upgrades, or generic arbitrary
  execution.
- Failed delivery remains an exact backed retryable liability. The stateful custody and two system
  invariant suites exercise cross-module conservation and control.
- The release runtime-pins every external dependency and records implementation, factory, adapter,
  guard, oracle/venue, creation-code, and core runtime hashes in a strict 63-field manifest.
- The SDK builds canonical project launch provenance only after the validated preview matches the
  post-launch Registry record; it refuses identity, governance, supply, module, config-hash, or
  address drift.

## Current automated result

- `forge fmt --check`: pass.
- `forge lint --severity high`: pass; the intentional same-transaction CREATE3 `SELFDESTRUCT`
  compiler warning is documented in `PRE_AUDIT_REVIEW.md`.
- `forge build --sizes`: pass. Tightest core margins are 1,300 bytes for the deployment engine,
  1,578 bytes for Router, and 1,861 bytes for Launcher.
- `forge test`: 442 passed, 0 failed, 1 environment-gated fork test skipped.
- `npm test --prefix sdk`: 23 passed, 0 failed.
- Release serialization/schema/verifier inventory: 63 required fields, no missing, extra, or
  duplicate field.

## External release gates still required

Implementation completion does not satisfy the external release gates. Deployment remains
fail-closed until all of the following real artifacts exist and are independently reviewed:

1. independent audit covering the complete package, SDK workers, release scripts, and selected
   external integrations, with every critical/high finding resolved;
2. target-chain fork evidence for selected ERC-4626 vaults, V3/V4/Permit2, swap routes/guards,
   Funding Bands pool/oracle behavior, and the pinned randomness adapter;
3. production-shaped all-modules testnet rehearsal with generated role and asset-flow evidence;
4. target-chain gas-limit confirmation, source verification, keeper/attestor/randomness monitoring,
   and the smallest practical canary before material funds.

`script/deploy-release.sh` requires the audit, fork, testnet, role, and asset-flow evidence paths,
their hashes, an explicit passed audit gate, exact chain ID, and every approved runtime hash before
it broadcasts anything.
