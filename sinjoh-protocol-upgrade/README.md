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

`SinjohGovernor` composes OpenZeppelin Governor, settings, simple vote counting, quorum, and
timelock modules. Token-holder treasuries use the subject token's historical wallet-balance
checkpoints directly: one token held at the proposal snapshot is one vote, with no staking or
delegation step. `TokenHolderTreasuryFactory` deploys a Governor and timelock as an alternative
governor module for the existing `SinjohTreasuryVault` governor slot. It can either create a new
vault with that module installed or create only the module for the vault's standard delayed
governor handoff. It does not create or modify the subject token.
Voting delay and period use the vote source's ERC-6372 clock; the included staking adapter uses
timestamps, so those settings are measured in seconds. The proposal threshold is an absolute
vote amount. Calculate the desired
0.5-1% threshold from expected voting supply when deploying. Quorum is an integer percentage;
5-15 is the recommended launch range. The factory rejects zero voting delay, period, proposal
threshold, or quorum and enforces a minimum one-hour execution timelock.

## Contracts

| Contract | Purpose | Main safety properties |
| --- | --- | --- |
| `FeeRouterV2` | Versioned project-fee routing | Atomic route sets, delayed activation, protected rollback target, immutable 1% fee, exact transfers, per-route failure escrow and retry, guardian or governance route pause |
| `StakingEngine` | Simple token staking | One token equals one reward unit and one vote, timestamped raw-balance checkpoints, immediate partial/full unstaking, exact transfers, unstaking while paused |
| `TokenHolderTreasuryFactory` | Token-holder governor module for Treasury Vaults | Existing subject-token checkpoints, new-vault or delayed-handoff installation, Governor-only proposing/cancelling, public timelock execution, no retained factory role |
| `SinjohStakingEngine` | Claim-based staking distributions | 30-minute minimum epochs, zero-stake rollover, prefunded liabilities, batched claims, executor reward caps, unclaimed sweep |
| `SinjohLaunchStakingEngine` | Opt-in staking airdrops for new launches | One shared sink keyed by launched token, raw active-stake snapshots, immediate unstaking, isolated router/token/asset reward accounts, zero-stake rollover |
| `YieldBasket` | Treasury-bound, allowlisted harvest-only portfolio | Exact vault-transfer registration, immutable treasury returns, per-adapter caps, token-specific reward routes, loss write-off/recovery, unsolicited-token isolation |
| `ERC4626YieldAdapter` | Basket-bound ERC-4626 integration | Exact transfers, preview compliance checks, immutable basket/vault binding, no arbitrary calls or reward claims |
| `DynamicFundingBands` | Prefunded post-launch commitments | Activation delay, fresh TWAP cadence, minimum distance, confirmation clock, immutable active terms, exact payouts, per-asset/subject commitments |

The existing `sinjoh-airdrop-distributor` remains the default standard airdrop path and does
not require recipients to stake. New launches may instead opt into `SinjohLaunchStakingEngine`.
The fee router passes the launched token as the subject, so every token has an independent raw
stake ledger even though the platform uses one shared sink. A wallet may withdraw available stake
immediately. Only its balance at a completed epoch snapshot determines that epoch's claim.

The older `StakingEngine` plus `SinjohStakingEngine` pair is a single-token governed module. It is
not the launch-platform staking feature and must not be used to route rewards for unrelated token
launches. Interfaces must present standard holder airdrops and opt-in launch staking as distinct
products rather than treating staking as a prerequisite for ordinary airdrops.
Claims use full-precision proportional allocation against each epoch's funded amount and
eligible stake; only unavoidable per-account division dust remains sweepable after expiry.
If an epoch-start checkpoint has no stake, permissionless execution advances the epoch
clock without creating an epoch or paying an executor. Pending rewards and their liability remain
intact for the next eligible window instead of becoming stranded.

The router's fundable actions include airdrops, baskets, raffles, bands, swap-and-send adapters,
and liquidity adapters. Every non-direct destination must implement `ISinjohFundable`; there is
no generic governance call surface.

## Accounting and fee rules

- The Fee Router removes its immutable 1% protocol fee before project routes are evaluated.
  Remainder carry makes splitting intake unable to reduce the cumulative fee. Re-activating the
  already-active configuration is rejected so a stale governance transaction cannot overwrite
  the known-good rollback target. A paused or reverting destination reserves only its exact route
  share in configuration-and-route-specific escrow; other routes and later intake continue.
  Reserved balances are excluded from future `sync` calls. Anyone may call `retryEscrow` after the
  route recovers, while governance may use `recoverEscrow` to redirect a permanently incompatible
  route's reservation.
- The distributor keeps the existing Sinjoh service rule: a cumulative 1% fee on gross funding.
  `totalLiability[token]` tracks all unpaid net rewards and is covered by the contract balance.
- Dynamic bands charge their cumulative 1% service fee only when backing redeems. Pending,
  active, and armed bands remain fully prefunded.
- Basket principal is never harvested. Each allowlisted reward token has its own distributor and
  distribution configuration, so multi-reward adapters can route every asset independently.
  An adapter must transfer the token during the same `harvest` call, the reported amount must
  equal the measured balance delta, and its configured distributor must consume that exact amount.
  Treasury funding uses a prepare/transfer/complete handshake that snapshots both the immutable
  treasury and basket balances. Registration succeeds only when the basket rose by at least the
  prepared amount and treasury fell by exactly that amount; excess basket tokens stay unregistered.
  Timelocks execute those calls in one proposal, while a Joint uses its self-authorized
  `executeBatch` so the same flow is atomic. The transfer-only vault never approves or calls the basket.
  Adapter withdrawals realize losses against managed principal. Measured value above principal is
  tracked separately from unsolicited deposit tokens and remains non-distributable until
  governance calls `realizeIdleValue`. Every principal withdrawal, realized gain, revived
  write-off recovery, and token recovery is forced to the immutable treasury. `basketValue()` exposes
  current adapter-reported assets, managed principal, and deposit-asset-denominated unrealized
  gain or loss; per-token realized yield remains available through `cumulativeRealizedYield`.
  Reconfiguration preserves an emergency adapter pause. Removing an adapter clears every reward
  route. For an irrecoverable fully paused adapter, governance can explicitly write off principal
  and later recover revived shares only as non-principal value. ERC-4626 positions also expose an
  explicit lossy recovery path after write-off so a preview-non-compliant vault cannot trap the
  position; exact share spend and asset receipt checks still apply. The adapter cannot be reapproved
  or receive a new allocation while written-off shares remain. Tokens that reach the basket
  outside a verified harvest remain excluded from realized yield and can be moved only through the
  governance-only `recoverNonDepositAsset`; unregistered deposit tokens have a distinct
  `sweepUnregisteredDepositAsset` path that can return only to treasury.

Protocol-fee remainder carry and outgoing exact-transfer checks are implemented once in the
internal `ProtocolAccounting` library and reused across the router, staking, distribution, basket,
and band modules.

These fees are module-local and stack across integrations. For example, Fee Router intake routed
into the distributor or a band pays the router's 1% first and the destination module's 1% on its
own net base, leaving approximately 98.01% before any configured executor incentive and subject
to integer remainder carry.

Tokens with transfer fees, rebases during a transaction, or otherwise inexact balance movement
are rejected. Adapters and oracle implementations remain trusted integration boundaries and
must be separately reviewed and allowlisted.

## Eligibility

Version 1 uses the simplest rule: **raw staked balance at the beginning of the epoch**. One staked
token is one unit of reward allocation and, through `StakedVotesAdapter`, one non-delegated vote.
There are no lock tiers, durations, multipliers, cooldowns, or expiry accounting. Users may add to
their stake or partially/fully unstake immediately. An epoch uses the timestamp immediately before
it begins, conservatively excluding stake added in the opening timestamp. Unstaking after that
snapshot does not retroactively change the completed snapshot or erase the user's claim for that
epoch. This deliberately accepts predictable-snapshot timing behavior in exchange for simple,
liquid staking; the UI and disclosures must state that tradeoff plainly.
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
raw-balance snapshots, immediate partial/full unstaking, staking custody invariants, zero-stake
rollover, claim solvency, route failure isolation/escrow/recovery, multi-reward
routing, harvest injection attempts, adapter pause/write-off/token recovery, atomic route rollback
protection, quiet-market oracle refresh, and prefunded band commitments.

## Deployment order

For token-holder Treasury Vault governance, deploy `TokenHolderTreasuryFactory` once. Call
`createTokenHolderTreasury` to create a new vault with token governance installed from genesis, or
`createTokenHolderGovernor` to produce the Governor/timelock module used in an existing vault's
normal delayed governor handoff. The subject token must already expose historical wallet-balance
votes through `IVotes`.

The staking-only deployment script is manifest-driven and deploys
`AddressGovernanceController`, `StakingEngine`, the optional `StakedVotesAdapter`, and
`SinjohStakingEngine`. Copy `deployments/staking-engine.parameters.example.json` to an untracked,
reviewed manifest, replace every zero placeholder, and run a simulation before adding
`--broadcast`:

```sh
STAKING_DEPLOYMENT_MANIFEST=/absolute/path/to/reviewed-staking-parameters.json \
DEPLOYER_PRIVATE_KEY=... \
forge script script/DeployStakingProtocol.s.sol:DeployStakingProtocol \
  --rpc-url "$ROBINHOOD_RPC_URL"
```

The script accepts only Robinhood Chain mainnet (`4663`) or testnet (`46630`), checks the
signer's address, requires a separate emergency guardian, and pins the staking token by runtime
code hash. It does not create schedules, freeze governance, or print the private key. Those are
separate reviewed actions after the canary.

The governance/yield deployment is separately gated by
`deployments/governance-yield-basket.parameters.example.json`. It accepts mainnet chain ID `4663`
only and validates the deployer, authority mode and runtime hash, final timelock roles, treasury
constructor readbacks, guardian separation, deposit asset, every adapter cap/runtime hash, and
every reward token/distributor/runtime hash and route. The manifest pins the basket's deterministic
CREATE address, and every adapter must immutably report that exact basket before broadcast. It
deploys the controller and immutable
treasury-bound basket, then returns the exact configuration calldata for execution by the declared
Joint or timelock; the deployer never receives temporary basket authority.
Basket-bound adapters may be deployed first against the manifest's predicted basket address; the
deployment reverts unless the created basket exactly matches it.

```sh
YIELD_DEPLOYMENT_MANIFEST=/absolute/path/to/reviewed-yield-parameters.json \
DEPLOYER_PRIVATE_KEY=... \
forge script script/DeployGovernanceYieldBasket.s.sol:DeployGovernanceYieldBasket \
  --rpc-url "$ROBINHOOD_RPC_URL"
```

After selecting an audited ERC-4626 vault, run the opt-in fork canary with a deliberately small
funding account. It executes deposit, valuation, full redemption, and treasury return locally:

```sh
ROBINHOOD_MAINNET_RPC_URL=... \
YIELD_CANARY_ERC4626_VAULT=0x... \
YIELD_CANARY_FUNDER=0x... \
YIELD_CANARY_AMOUNT=... \
forge test --match-contract ERC4626YieldAdapterMainnetForkTest -vv
```

1. Select an ERC20Votes source or deploy the raw-balance `StakingEngine` plus
   `StakedVotesAdapter`.
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
