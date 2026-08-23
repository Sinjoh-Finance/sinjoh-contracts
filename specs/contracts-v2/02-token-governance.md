# Token Governance

## 1. Objective

Token Governance is an independent protocol composed of `ProjectGovernorV2` and
`ProjectTimelockV2`. Token holders create and vote on proposals; successful proposals are queued in
the Timelock, and the Timelock is the immutable controller recorded by Treasury Vaults and other
controlled modules.

The Governor and Timelock do not custody project Treasury assets and do not depend on a Treasury
Vault being enabled.

## 2. Immutable launch configuration

| Parameter | Default | Factory bounds |
| --- | ---: | ---: |
| voting delay | 1 day | 1 hour to 7 days |
| voting period | 3 days | 1 day to 14 days |
| proposal threshold | 1% of Registry `referenceSupply` | 0.1% to 10% |
| quorum | 10% of past eligible vote supply | 1% to 30% |
| timelock delay | 1 day | 6 hours to 7 days |

The clock is timestamp-based. Parameters and vote source are immutable in the first release.
Changing governance rules requires a new separately audited deployment.

Using `referenceSupply` keeps staked governance launchable before tokens are staked. A proposer
must hold enough voting power from the selected source at `clock() - 1` to meet the absolute
threshold. Quorum remains a percentage of the source's historical eligible supply.

## 3. Vote sources

The launcher selects exactly one direct `IERC5805` source:

### Liquid wallet voting

`ProjectVotesToken` is the vote source. One eligible token held at the snapshot is one vote.
Historical balances and eligible supply update automatically. The zero address, canonical burn
address, and immutable system-custody exclusions contribute zero to account votes and voting
supply.

### Staked-token voting

`ProjectStakingPoolV2` is the vote source. One token locked in an active PoS NFT position at the
snapshot is one vote. NFT mint, transfer, and burn update aggregate owner checkpoints atomically.
The Governor never enumerates NFTs and never accepts a caller-supplied token ID.

Neither source supports delegation. No votes adapter or self-delegation transaction is deployed.

## 4. Proposal lifecycle

```text
PENDING -> ACTIVE -> SUCCEEDED -> QUEUED -> EXECUTED
    |          |          |
    +----------+----------+-> DEFEATED/CANCELLED/EXPIRED
```

Rules:

1. proposer voting power is measured at `clock() - 1`;
2. proposal voting power is fixed at its snapshot;
3. voting choices are against, for, and abstain;
4. for + abstain count toward quorum, while success requires for > against;
5. every successful proposal executes through the Timelock;
6. Timelock execution is permissionless after the delay;
7. a failed execution remains queued and retryable under the Timelock's normal operation state;
8. the launcher, factory, creator, and optional guardian have no proposer, canceller, executor, or
   Timelock-admin role after launch;
9. proposal actions commit to ordered targets, native values, calldatas, and description hash.

## 5. Timelock roles

After atomic launch finalization:

- the Governor is the sole Timelock proposer and canceller;
- execution is open to any caller after an operation is ready;
- the Timelock administers itself;
- every temporary launcher/deployer admin role is renounced.

The Timelock's minimum delay is immutable for this release. No EOA or Governor call can bypass the
delay to invoke a controlled module directly.

## 6. Proposal safety and UI data

The Governor uses standard batched proposal targets and calldata. Controlled modules expose only
typed functions and enforce `msg.sender == tokenTimelock`.

The UI must simulate and decode every action, including:

- exact Treasury Vault assets, amounts, and recipients;
- Router allocation versions and affected destinations;
- Basket assets/weights/adapters being added or removed;
- Funding Band bounds, inventory, and destination;
- proposal snapshot, deadline, queue, and earliest execution timestamps.

Unknown selectors or undecodable actions are displayed as unsupported, never as benign updates.

## 7. Required views and events

Views expose immutable project binding, vote source, clock mode, threshold, quorum at a supplied
timepoint, proposal votes/state/timestamps, receipts, and Timelock operation readiness.

Events include the standard OpenZeppelin Governor and Timelock lifecycle events plus
`TokenGovernanceCreated(projectId, governor, timelock, voteSource)`.

## 8. Security invariants

1. Proposal votes always come from the immutable source at the proposal snapshot.
2. Moving or unstaking tokens after a snapshot cannot change that proposal's voting power.
3. A successful proposal cannot execute before the Timelock delay.
4. Direct calls from the Governor, voters, creator, launcher, or EOA cannot operate a controlled
   module.
5. Timelock bootstrap roles are absent after launch.
6. The canonical burn address contributes zero votes and zero quorum supply for either source.

## 9. Acceptance criteria

1. A liquid holder can propose and vote without delegation.
2. A wallet's staked vote total equals the sum of its PoS NFT amounts at the snapshot.
3. Transferring a PoS NFT after the snapshot changes only future proposal power.
4. Unstaking after the snapshot does not change the active proposal's recorded voting power.
5. For + abstain satisfy quorum, but only for > against succeeds.
6. Queue and execute fail before their respective timestamps and succeed permissionlessly after.
7. A failed queued call may be retried without re-voting.
8. Burn-address token balances and PoS ownership produce no voting power.

## 10. Out of scope

- vote delegation;
- veto councils, optimistic governance, quadratic voting, or vote multipliers;
- changing governance parameters or vote source after launch;
- replacing Token Governance with a Multisig Account;
- a platform cancellation or recovery administrator.
