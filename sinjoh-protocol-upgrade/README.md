# Sinjoh governed protocol upgrade

This Foundry package implements the shared governance, treasury, routing, staking,
distribution, and post-launch funding-band system. It is a new deployment surface; it does
not mutate the storage or behavior of the currently deployed v1 contracts.

## Architecture

```text
                           +----------------------+
                           | GovernanceController |
                           +----------+-----------+
                                      |
                  +-------------------+-------------------+
                  |                   |                   |
             FeeRouterV2         YieldBasket     DynamicFundingBands
                  |                   |
                  +----------+--------+
                             |
                  SinjohStakingEngine
                             |
                       StakingEngine
```

Every mutable module inherits `Governed` and consults one immutable
`IGovernanceController`. A deployment chooses one authority model:

- `INDIVIDUAL`: an address controlled directly by one signer.
- `MULTISIG`: a contract authority such as a Safe or Sinjoh Joint.
- `TOKEN_GOVERNOR`: the execution timelock for `SinjohGovernor`.
- `IMMUTABLE`: a controller which permanently rejects mutations.

`AddressGovernanceController` requires contract code for multisig and token-governor modes,
so an EOA cannot be disclosed as either one. For token governance, bind the controller to the
OpenZeppelin `TimelockController`, not to the governor contract: queued proposals execute as
the timelock. Modules that require bootstrap configuration use an address controller first,
then the authority calls `freeze()` to atomically erase the authority and disclose immutable
mode. `ImmutableGovernanceController` is only suitable when every required setting is supplied
to constructors. Freezing is irreversible; a later guardian pause is therefore a permanent
shutdown because no authority remains to resume.

`SinjohGovernor` composes OpenZeppelin Governor, settings, simple vote counting, quorum,
proposal-guardian, and timelock modules. Use an ERC20Votes token for liquid or delegated
voting. Use `StakedVotesAdapter` over `StakingEngine` for non-delegated locked-token voting.
Voting delay and period use the vote source's ERC-6372 clock; the included staking adapter uses
timestamps, so those settings are measured in seconds. The proposal threshold is an absolute
vote amount. Calculate the desired
0.5-1% threshold from expected voting supply when deploying. Quorum is an integer percentage;
5-15 is the recommended launch range.

## Contracts

| Contract | Purpose | Main safety properties |
| --- | --- | --- |
| `FeeRouterV2` | Versioned project-fee routing | Atomic route sets, delayed activation, protected rollback target, immutable 1% fee, exact transfers, guardian or governance route pause |
| `StakingEngine` | Fixed-tier token locks | Timestamp checkpoints, automatic zero weight at unlock, exact deposits and withdrawals, withdrawals remain available while paused, tier changes apply on new or renewed locks |
| `SinjohStakingEngine` | Claim-based staking distributions | 30-minute minimum epochs, zero-weight rollover, prefunded liabilities, batched claims, executor reward caps, unclaimed sweep |
| `YieldBasket` | Allowlisted harvest-only portfolio | Per-adapter caps, token-specific reward routes, pause-preserving configuration, loss write-off/recovery, exact accounting |
| `DynamicFundingBands` | Prefunded post-launch commitments | Activation delay, fresh TWAP cadence, minimum distance, confirmation clock, immutable active terms, exact payouts, per-asset/subject commitments |

The existing `sinjoh-airdrop-distributor` remains the default standard airdrop path and does
not require recipients to stake. `SinjohStakingEngine` is a separate, optional path for
staking-driven rewards; its schedules intentionally derive eligibility and allocation weight
from `StakingEngine` checkpoints. Deployments and interfaces should present these as distinct
airdrop products rather than treating staking as a prerequisite for ordinary airdrops.
Claims use full-precision proportional allocation against each epoch's funded amount and
eligible weight; only unavoidable per-account division dust remains sweepable after expiry.
If an epoch-start checkpoint has no reward weight, permissionless execution advances the epoch
clock without creating an epoch or paying an executor. Pending rewards and their liability remain
intact for the next eligible window instead of becoming stranded.

The router's fundable actions include airdrops, baskets, raffles, bands, swap-and-send adapters,
and liquidity adapters. Every non-direct destination must implement `ISinjohFundable`; there is
no generic governance call surface.

## Accounting and fee rules

- The Fee Router removes its immutable 1% protocol fee before project routes are evaluated.
  Remainder carry makes splitting intake unable to reduce the cumulative fee. Re-activating the
  already-active configuration is rejected so a stale governance transaction cannot overwrite
  the known-good rollback target.
- The distributor keeps the existing Sinjoh service rule: a cumulative 1% fee on gross funding.
  `totalLiability[token]` tracks all unpaid net rewards and is covered by the contract balance.
- Dynamic bands charge their cumulative 1% service fee only when backing redeems. Pending,
  active, and armed bands remain fully prefunded.
- Basket principal is never harvested. Each allowlisted reward token has its own distributor and
  distribution configuration, so multi-reward adapters can route every asset independently.
  An adapter must transfer the token during the same `harvest` call, the reported amount must
  equal the measured balance delta, and its configured distributor must consume that exact amount.
  Adapter withdrawals realize losses against managed principal. Value above principal remains
  idle and non-distributable until governance calls `realizeIdleValue`. `basketValue()` exposes
  current adapter-reported assets, managed principal, and deposit-asset-denominated unrealized
  gain or loss; per-token realized yield remains available through `cumulativeRealizedYield`.
  Reconfiguration preserves an emergency adapter pause. Removing an adapter clears every reward
  route. For an irrecoverable fully paused adapter, governance can explicitly write off principal
  and later recover revived shares only as non-principal value; the adapter cannot be reapproved
  or receive a new allocation while written-off shares remain.

These fees are module-local and stack across integrations. For example, Fee Router intake routed
into the distributor or a band pays the router's 1% first and the destination module's 1% on its
own net base, leaving approximately 98.01% before any configured executor incentive and subject
to integer remainder carry.

Tokens with transfer fees, rebases during a transaction, or otherwise inexact balance movement
are rejected. Adapters and oracle implementations remain trusted integration boundaries and
must be separately reviewed and allowlisted.

## Eligibility

Version 1 deliberately selects the requested **actively locked at the beginning of the epoch**
rule. An epoch uses the timestamp immediately before the epoch begins, conservatively excluding
stake added in the opening timestamp. Individual and aggregate timestamp checkpoints include
scheduled expiries, so a position whose lock has already ended contributes zero to both the
claimable weight and the stored eligible-weight denominator even when its owner has not withdrawn.
Reward and governance weight become zero at the exact unlock timestamp. Extending an active lock
replaces its scheduled expiry; relocking an expired position reactivates weight only for the new
lock. Expiry does not retroactively erase eligibility for an epoch whose earlier snapshot found the
position actively locked. The deposited principal remains immediately withdrawable after expiry.
Users can claim up to 64 strictly increasing epoch IDs in one transaction.
Each epoch pins its own claim deadline and unclaimed-funds destination, and late execution starts
a fresh claim window.

## Dynamic-band lifecycle

```text
PENDING -> ACTIVE -> ARMED -> REDEEMED
    |          |        |
    +----------+--------+-> EXPIRED
    |
    +-> CANCELLED (governance, before activation only)
```

The qualifying range must sit wholly above or wholly below the current TWAP and satisfy the
configured distance. `observe` starts or resets the confirmation clock. While armed, a fresh
in-range TWAP must be recorded at least once per configured TWAP window; an out-of-range sample
or observation gap resets continuity. `redeem` obtains another fresh TWAP and pays only after
the uninterrupted confirmation period. Freshness requires a strictly advancing oracle
`updatedAt`, so a cached observation cannot arm and redeem a band. A self-funding creator or
governance can cancel before activation. A compatible oracle must return the timestamp through
which the TWAP was evaluated and must advance it when a later window can be evaluated even if no
trade occurred; an oracle that returns only the last swap timestamp is incompatible. Terms and
backing cannot move after activation. `committedByAsset` and
`committedBySubject` are the canonical overlap/exposure views. `totalCommitted` is a nominal
cross-asset counter and must not be treated as a common-unit valuation. For a Fee Router
`FUND_BAND` route, encode a `BandInput` template with `amount = 0`; each runtime route amount
becomes that band's exact prefunding.

## Build and test

```sh
cd sinjoh-protocol-upgrade
forge fmt --check
forge build --sizes
forge test
```

The suite includes unit, integration, 1,000-run fuzz, and 256-run stateful invariant tests.
It covers the full governor-vote-queue-timelock-execute lifecycle, cumulative fee resistance,
zero-weight staking rollover, claim solvency, multi-reward routing, harvest injection attempts,
adapter pause/write-off/recovery, atomic route rollback protection, quiet-market oracle refresh,
and prefunded band commitments.

## Deployment order

1. Select an ERC20Votes source or deploy `StakingEngine` plus `StakedVotesAdapter`.
2. Deploy an OpenZeppelin `TimelockController` with the intended execution delay.
3. Deploy `SinjohGovernor`, grant it proposer and canceller roles, grant the zero address the
   executor role if execution should be permissionless, and renounce the bootstrap admin.
4. Deploy one controller. For token governance, use `TOKEN_GOVERNOR` with the timelock address.
5. Deploy all governed protocol modules with that same controller and a pause-only guardian.
6. Propose and activate router routes, schedules, adapter/reward allowlists, and allocations
   through the selected authority.
7. If immutable operation is selected, call `AddressGovernanceController.freeze()` only after
   every required route, schedule, adapter, and allocation is configured and verified.
8. Verify contract source, publish authority disclosures and pending activation timestamps,
   exercise pause/rollback on a fork, and transfer every bootstrap role before accepting funds.

Do not deploy this package to mainnet until its concrete adapters, oracle, parameters, role
assignments, and bytecode have passed an independent security audit. No production addresses
are claimed by this package.

The implementation gates, deployment order, manifest requirements, canary, rollback, and
supporting `/portfolio` UI work are specified in
[`MAINNET_DEPLOYMENT_AND_UI_PLAN.md`](./MAINNET_DEPLOYMENT_AND_UI_PLAN.md).
