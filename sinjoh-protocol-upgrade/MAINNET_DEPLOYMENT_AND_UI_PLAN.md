# Sinjoh Staking Engine mainnet and UI plan

Status: planning only. This document does not claim a production deployment or authorize one.

## Product boundary

Sinjoh has two separate reward products:

- `sinjoh-airdrop-distributor` is the default standard airdrop path. Recipients do not need to
  stake and the existing launch UI continues to use it.
- The Sinjoh Staking Engine protocol is the optional staking-reward path. `StakingEngine` holds
  locks and writes voting/reward checkpoints; `SinjohStakingEngine` funds schedules, closes
  epochs, and serves claims from those checkpoints.

UI, documentation, manifests, and analytics must preserve that distinction. Ordinary airdrops
must never be labeled as requiring a stake.

## Mainnet decisions required

Deployment parameters are immutable or economically significant. Record an explicit approval
for every item below before preparing a broadcast transaction:

| Decision | Required record |
| --- | --- |
| Staking token | Checksummed address, decimals, symbol, runtime code hash, and token-behavior review |
| Lock tiers | Duration, reward-weight BPS, governance-weight BPS, and active state for each tier |
| Authority | Individual bootstrap, multisig, or token governor; final timelock and signer policy |
| Guardian | Pause-only address, response procedure, and confirmation it differs from routine operators |
| Protocol revenue | Fee-recipient address and accounting owner |
| Reward schedules | Reward token, interval, claim period, permissionless setting, executor incentive, and unclaimed destination |
| Eligibility semantics | Approval that checkpoint weight at epoch start is eligible, including stake still deposited after its unlock time until withdrawal |
| Fee composition | Approval that router-to-staking funding charges 1% in each module, leaving about 98.01% before executor incentives |
| Unclaimed funds | Destination and sweep policy; every epoch pins the destination active when it is closed |
| Immutable mode | Whether and when to freeze; freezing is irreversible and a later guardian pause cannot be resumed |

The authority, guardian, revenue recipient, staking token, and tier table belong in a reviewed
parameter manifest, not only in shell environment variables.

## Security and release gates

All gates are mandatory for a production broadcast:

1. An independent smart-contract audit covers the exact source commit and production parameter
   manifest. Every critical or high finding is closed or accepted in writing.
2. A clean build reproduces the published bytecode. `forge fmt --check`, `forge build --sizes`,
   the repository-wide test script, 1,000-run fuzz tests, and 256-run invariants pass.
3. Exact-transfer behavior of every selected staking and reward token is verified. Fee-on-transfer,
   rebasing-during-transfer, or other inexact tokens are rejected.
4. Every concrete TWAP oracle advances its evaluation timestamp on a later valid window even when
   no intervening trade occurred. An implementation that reports only the last swap time fails the
   compatibility test.
5. A Robinhood Chain mainnet fork rehearsal uses chain ID 4663 and current onchain state. It
   exercises stake, increase, extend, epoch funding, late execution, claims, sweeping, pause,
   zero-weight epoch rollover, withdrawals while paused, basket adapter write-off/recovery, and
   every governance transition.
6. The deployment script is simulated without broadcast and its decoded constructor arguments,
   role grants, expected addresses, and runtime hashes match the signed manifest.
7. A testnet or isolated canary completes one entire small-value lifecycle before mainnet funding.
8. The UI preview reads the same finalized block from direct RPC and its indexed source, and the
   balances, liabilities, schedules, epochs, claims, and positions reconcile.
9. Explorer verification, canonical deployment records, SDK ABI provenance, monitoring, incident
   owners, and the UI rollback flag are ready before enabling the public surface.

## Deployment implementation

Add a Foundry deployment script and a machine-readable parameter manifest to this package. The
script must refuse to proceed when the chain ID, token code, controller mode, guardian, fee
recipient, or tier/schedule constraints differ from the reviewed manifest. It must emit a dry-run
summary without printing a private key.

Deploy and configure in this order:

1. Deploy the chosen governance controller. Use an address controller during bootstrap when
   routes or schedules require post-constructor configuration.
2. Deploy `StakingEngine` with the staking token and reviewed lock tiers.
3. Deploy `StakedVotesAdapter` if governance will use locked, non-delegated voting weight.
4. If token governance is selected, deploy/configure the timelock and `SinjohGovernor`, grant
   proposer/canceller/executor roles, and remove bootstrap administration.
5. Deploy `SinjohStakingEngine` with the same controller, guardian, `StakingEngine`, and protocol
   fee recipient.
6. Create reviewed reward schedules. Configure `FeeRouterV2` staking-reward routes with
   `FUND_AIRDROP` and canonical `abi.encode(scheduleId)` route data.
7. Exercise a small-value canary: stake, fund, close, claim, extend, pause, withdraw while paused,
   resume, and sweep an intentionally expired dust epoch.
8. Transfer or renounce every bootstrap role. Freeze only after all configuration and verification
   is complete and only if the approved authority model is immutable.

No production route should accept material funding until the canary has reconciled:

```text
contract reward-token balance >= totalLiability[token]
pending rewards + unpaid epoch rewards = totalLiability[token]
gross funding - cumulative protocol fees - executor payouts - claims - sweeps = liability
```

## Deployment records and SDK publication

After a successful broadcast:

1. Add transaction hashes, block numbers, constructor arguments, runtime code hashes, authority,
   guardian, and source commit to the canonical `mainnet-deployments.json` and provenance files.
2. Verify source on the configured Robinhood Chain explorer and independently compare deployed
   runtime bytecode with the clean build.
3. Regenerate `@sinjoh/abis` from the exact contracts commit. Publish
   `stakingEngineAbi`, `sinjohStakingEngineAbi`, and any selected governance ABI with provenance.
4. Regenerate the SDK deployment manifest from the canonical contracts record. The UI must consume
   those addresses or mechanically verify that its local manifest matches them.
5. Publish the eligibility rule, lock tiers, schedule parameters, authority mode, fee stacking,
   claim deadlines, unclaimed destinations, and executor incentives beside the addresses.

## Supporting UI work

The implementation belongs on the existing `codex/sinjoh-v2-overhaul` UI branch. Keep it behind a
preview-only `NEXT_PUBLIC_ENABLE_STAKING_ENGINE=true` flag until every release gate passes. The
flag defaults off; turning it off is the first UI rollback action. Do not add a sixth top-level
navigation destination.

### Contract configuration

Extend the UI manifest with separately named, code-hash-pinned entries:

- `stakingEngine`: position, lock, and checkpoint contract.
- `sinjohStakingEngine`: reward schedule, epoch, and claim contract.
- `stakedVotesAdapter`, governance controller, governor, and timelock when deployed.

The feature must remain hidden unless both core addresses and both expected runtime code hashes
are present and live bytecode matches. A mismatch fails closed and must never offer a transaction.

### Portfolio experience

Add a **Staking** workspace to `/portfolio` with:

- connected-wallet stake amount, tier, unlock time, reward weight, and voting weight;
- stake, increase, extend, and withdraw actions, with approval/permit handling where supported;
- withdrawals available while protocol funding/execution is paused;
- active reward schedules grouped by reward token;
- claimable amounts, epoch end, claim deadline, and unclaimed destination;
- batch claim selection capped at 64 strictly increasing epoch IDs;
- clear states for not staked, not eligible at epoch start, already claimed, expired, paused, and
  unreadable chain data;
- links to explorer transactions and source/parameter disclosures.

All state-changing user actions are wallet-signed. Each action first checks runtime hashes,
simulates the exact contract call, displays the decoded effect, submits through the connected
wallet, waits for the configured finality, and then invalidates the affected reads.

### Operator and public disclosure experience

Do not expose governance controls as ordinary portfolio actions. Add an authenticated operator
surface inside the existing token workspace (keep `/manage` unlisted during the current UI
cutover) for:

- schedule creation and updates;
- funding status, pending rewards, liability coverage, next close time, and executor incentive;
- permissionless `executeEpoch` when due;
- claim-window progress and permissionless sweep after expiry;
- Fee Router route status and the effective stacked-fee preview.

Public token/build pages should show read-only schedules, tiers, eligibility, governance authority,
fees, claim deadlines, and verified addresses. Label the existing standard airdrop surface
**Standard Airdrops** and the optional path **Staking Rewards**.

### Data and automation

Index these events from the deployment block:

- `Staked`, `StakeIncreased`, `LockExtended`, `Withdrawn`, and `TierSet`;
- `ScheduleCreated`, `ScheduleUpdated`, `Funded`, `EpochExecuted`, `EmptyEpochSkipped`, `Claimed`,
  and `UnclaimedSwept`;
- controller changes, pauses, and Fee Router configuration activation.

Direct RPC remains the source of truth for transaction preparation and claimability. Indexed data
may accelerate history and discovery but must be reconciled to the same finalized block before it
is presented as final. A keeper may simulate and submit permissionless `executeEpoch` calls after
the due, funding, and eligible-weight checks pass; it must never sign a user's stake, claim,
withdrawal, or approval.

## Rollout and rollback

Roll out in four stages:

1. Local and fork tests with fixture-only UI data.
2. Vercel preview connected to testnet/canary contracts, with feature flag on for reviewers only.
3. Mainnet read-only preview after deployment and bytecode verification.
4. Public wallet actions after indexer reconciliation, canary completion, monitoring, and final
   release approval.

If an issue appears, disable the UI feature flag, pause new funding and epoch execution, and remove
or pause Fee Router staking routes. Preserve claims for already funded epochs and withdrawals from
`StakingEngine`; neither action is pause-gated. These contracts are not proxies, so a contract bug
requires a reviewed replacement deployment and route migration rather than an in-place upgrade.

## Go-live evidence

The release owner should publish one checklist containing the audited source commit, test output,
parameter manifest hash, deployment transactions, verified addresses and runtime hashes, role
state, canary transactions, liability reconciliation, SDK release, UI preview, monitoring links,
rollback owner, and final approval. Until that checklist is complete, the package remains
source-only and the existing standard airdrop deployment remains the default production path.
