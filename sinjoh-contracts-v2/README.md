# Sinjoh Contracts v2

Greenfield implementation of the integrated Sinjoh v2 protocol specifications in
[`../specs/contracts-v2`](../specs/contracts-v2/README.md).

This package does not modify, migrate, or import the implementations of deployed v1 contracts.
OpenZeppelin Contracts 5.6.1 is imported from the repository's pinned vendored dependency.

## Implemented protocols

| Protocol | Status |
| --- | --- |
| Shared project interfaces and identity | implemented |
| `ProjectVotesToken` | implemented |
| Staking + PoS NFT | implemented |
| Multisig Accounts | implemented |
| Token Governance | implemented |
| Treasury Vaults | implemented |
| Registry | implemented |
| Router | implemented |
| Airdrop | implemented |
| Basket | implemented |
| Funding Bands | implemented |
| Raffle | implemented |
| Liquidity | implemented |
| Launcher | implemented |

## Verification

```sh
forge fmt --check
forge build --sizes
forge test
```

Token Governance is deployed atomically as one `ProjectTimelockV2` that creates and permanently
binds its `ProjectGovernorV2`. The Governor is the sole proposer/canceller, execution is open only
for mature scheduled operations, and role/delay mutation is disabled. Controlled modules authorize
the Timelock address directly. Liquid voting reads `ProjectVotesToken`; staked voting reads
`ProjectStakingPoolV2`. Neither path requires delegation.

`ProjectTreasuryVaultV2` uses the same controller ABI with either independent governance model. It
provides exact native/ERC-20 accounting, guarded proof-approved swaps, optional policy-based Basket
reservations with permissionless keeper execution, and typed Basket NFT management without a
generic arbitrary-call surface. Frontends and keepers can read complete route status and verify an
exact swap approval on-chain.

`ProjectRegistryV2` is an append-only canonical discovery layer. One record tells clients which
governance workflow and modules are enabled, resolves every explicit address without bytecode
probing, and supports only controller-authored UI metadata revisions. It has no project control,
asset custody, deployment, recovery, or generic execution authority.

`ProjectRouterV2` accepts exact attributed or synced revenue, carries the cumulative 1% fee
remainder, and executes constructor-initialized or governance-versioned typed routes. Cumulative
allocation prevents micro-batch bias; failed and paused shares remain exact versioned escrow for
permissionless retry while their route is active or governance re-keying from a superseded route
into an active same-asset action. Its work/action and
approval views are designed for direct keeper and frontend consumption.

`ProjectAirdropV2` creates immutable per-funder reward accounts and pushes holder- or staker-mode
payments without recipient claims. EIP-712 epoch commitments are permissionlessly relayed, while
on-chain checkpoints and direction-aware weight/amount Merkle sums verify every proportional leaf.
Failed recipients and dust destinations become exact retryable credits; one-call account/epoch
status and proof/hash helpers support frontends, workers, and independent artifact verification. A
defective commitment can be closed by its original funder or project Treasury after 30 days,
returning only the unpaid remainder to that account's uncommitted funding.

`BasketManagerV2`, `BasketNFTV2`, and each isolated `BasketVaultV2` implement locked yield baskets.
Funding follows a complete proof-approved input/target route matrix, realized yield is harvested on
the selected daily or weekly cadence into the matching Airdrop account, and failed downstream
delivery remains exactly retryable. Optional governance updates perform an atomic in-vault
rebalance. If the Airdrop permanently rejects a dividend asset, the project controller can redirect
that exact pending amount to Treasury before reconfiguration or burn. Principal can leave only
through resumable NFT burn settlement, with an optional exact
project-token burn price and in-kind tax. The per-Basket Vault is a deterministic clone of one
audited implementation so the launch is both address-predictable and EVM-size compliant.

`ERC4626BasketYieldAdapter` is the first production-shaped Basket adapter. Each instance is
permanently bound to one Basket Vault and one reviewed ERC-4626 vault, exposes a release-stable
runtime hash, exposes the concrete vault as its approval source, clears exact approvals, harvests
only value above recorded principal, and permits a
full exit only back to its bound Basket Vault. For the standard creator flow, the Launcher predicts
and deploys these adapters from an ownerless deterministic factory in the same transaction as the
project; creators select release-root-approved ERC-4626 vaults and never deploy, bind, approve, or exclude an
adapter manually. Pre-reviewed custom adapters remain available as an advanced launch path.

`ProjectFundingBandsV2` lets the project controller atomically commit Treasury-held project tokens
to post-launch market-cap bands whenever the current verified cap is below a band's lower bound.
It holds the canonical position NFT, requires an advancing sustained-price observation before
permissionless settlement, charges the cumulative 1% quote fee exactly once, and delivers through
seven typed destinations. Failed delivery remains fully backed and retryable; governance recovery
can only select another allowed same-project destination. Fixed reference supply prevents token
mints or burns from moving band boundaries. The standard launch path derives time-weighted market
cap from the canonical Uniswap V3 pool and atomically deploys its project-bound guard and position
adapter from one ownerless deterministic factory; the release preset supplies the reviewed TWAP,
quote-price, and approval settings, so creators never deploy or bind integrations or enter contract
plumbing. Preflight returns every predicted address before the wallet prompt.

`ProjectRaffleV2` preserves the current audited Raffle's ticket, reservation, randomness, payout,
tax, expiry, and solvency behavior while replacing its post-deployment binding step with one atomic
project-verified initialization. Router and Funding Bands use the standard typed funding interface;
zero, burn, Raffle, subject, and launch-custody addresses are excluded from eligibility. Winners
never register or claim: keepers submit proofs and failed payouts remain exact backed credits, even
when a hostile token returns oversized revert data. Frozen settings and concise status views give
launchers, frontends, and workers a predictable integration surface.
The immutable release pins the audited randomness adapter and records its runtime hash. Launch
presets use a zero placeholder, so creators never select, enter, or verify randomness infrastructure;
the deployment engine inserts the approved adapter automatically.
The SDK supplies the complete worker path: strict event-history replay, two-provider snapshot
reconciliation, deterministic ticket-tree construction, winner-proof submission, credit retries,
and timed-out-round closure. These operational details stay out of creator and holder interfaces.
The immutable attestor remains trusted to commit an honest, exhaustive ticket root: on-chain proof
verification binds payouts to that root but cannot prove that the off-chain root omitted no holder.

`ProjectLiquidityManagerV2` binds the existing permanent-liquidity design to one canonical Registry
project and accepts the same attributed funding ABI as Router and Funding Bands. Each funding source
has an isolated immutable account, guarded swaps can only create or increase its one full-range
position, and principal has no withdrawal, transfer, approval, burn, rescue, governance, or generic
call path. Position fees retain creator, Treasury, recycle, and funder modes with cumulative 1%
protocol accounting. Integration profiles are reviewed off-chain; the first funder supplies and
permanently freezes the venue, adapter, guard, hook, route, and pool parameters for only its isolated
account. One-call status views and permissionless retry/mint/collect flows keep later operations out
of contract plumbing. The SDK hydrates frozen account configuration from reviewed pool profiles and
product-level choices;
the Router atomically fills canonical creator/Treasury fee recipients during launch and later route
updates, so applications never predict or encode those addresses themselves.

`ProjectLauncherV2` validates, predicts, deploys, initializes, verifies, and registers a complete
project in one creator transaction. Module addresses remain stable while launch settings are edited;
Registry separately commits the exact final configuration hash. An ownerless deployment engine and
immutable chunked creation-code stores keep runtime and initcode under EVM limits without proxies or
retained project authority. Router destinations, Treasury Basket policy, Basket NFT ownership,
ERC-4626 adapters, governance vote source, and custody exclusions are materialized automatically.
The all-modules
integration launch currently uses about 40.7M gas with a 50M regression ceiling; the target-chain
limit must be confirmed in deployment rehearsal.

The one-time release flow is invoked through `script/deploy-release.sh`; the raw Foundry broadcast
script is not the supported entrypoint. Preflight refuses a dirty tree, wrong chain, missing
audit/fork/testnet evidence, or mismatched external runtime hash, runs every local verification
gate, and only then broadcasts. The deployment script independently verifies release wiring,
implementations, adapters, external dependencies, and module creation-code bindings before writing
a schema-backed chain-specific manifest under `deployments/`. See
[`deployments/README.md`](deployments/README.md).

The framework-neutral TypeScript package in `sdk/` generates typed ABIs directly from the Foundry
artifacts. It exposes launch prediction/preflight, project discovery, typed governance-action
encoding, and one-call pending-work helpers for the UI and keeper surfaces. Funding Band helpers
accept human-readable USD bounds, validate simple destination choices, compose the mandatory atomic
Treasury-prefund + band-create batch, and encode that same batch for either Multisig Accounts or
Token Governance. Solidity and TypeScript share canonical calldata fixtures so generated
integrations cannot silently drift from contracts.
After launch, `buildProjectLaunchManifest` cross-checks the exact validated preview against the
Registry readback and emits canonical JSON-safe provenance for publication or signing. It never
asks an operator to re-enter deployed project addresses.

The complete specification-to-code and release-gate handoff is
[`security/IMPLEMENTATION_TRACEABILITY.md`](security/IMPLEMENTATION_TRACEABILITY.md).
