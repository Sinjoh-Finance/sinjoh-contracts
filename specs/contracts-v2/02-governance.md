# Governance

## 1. Objective

Every project chooses one governance model at launch. That authority governs the treasury and may
update the project's router, basket, treasury basket-routing policy, and post-launch funding bands.
No delegation feature is included.

## 2. Supported modes

### Multisig

The first release uses a 2-of-3 `ProjectJointV2`:

- exactly three unique nonzero signers;
- two confirmations required;
- seven-day proposal expiry;
- confirmations may be revoked before execution;
- signer replacement requires a self-call approved by the threshold;
- batch execution is atomic;
- the multisig may hold native gas but is not the project treasury.

An audited external multisig may be admitted by a later factory version, but the v2 launcher does
not accept an arbitrary unverified authority implementation.

### Token holder

The launcher deploys a `ProjectGovernorV2` and `ProjectTimelockV2`. The timelock is the executor
recognized by every governed module.

Default launch parameters:

| Parameter | Default | Factory bounds |
| --- | ---: | ---: |
| voting delay | 1 day | 1 hour to 7 days |
| voting period | 3 days | 1 day to 14 days |
| proposal threshold | 1% of Registry `referenceSupply` | 0.1% to 10% of `referenceSupply` |
| quorum | 10% of past eligible vote supply | 1% to 30% |
| timelock delay | 1 day | 6 hours to 7 days |

The clock is timestamp-based for both liquid and staked voting. Parameters are immutable in the
first release; changing governance rules requires a future separately audited deployment.

Using `referenceSupply` keeps a staked-governance launch usable even though no tokens are staked in
the launch transaction. A proposer must later hold enough liquid tokens or active stake for the
selected source to meet the same absolute threshold. Quorum remains a percentage of the historical
eligible supply reported by that vote source.

## 3. Vote sources

Vote source is selected once at launch.

### Liquid wallet voting

The project token is the direct vote source. One eligible token held at the proposal snapshot is
one vote. Historical balances and eligible supply are automatic; no delegation or adapter exists.
Tokens held by the zero address, canonical burn address, or immutable system-custody exclusions
contribute zero to both account voting power and eligible voting supply.

### Staked-token voting

The project staking pool is the direct vote source. One project token locked in an active PoS NFT
position at the proposal snapshot is one vote. The staking pool aggregates all positions currently
owned by a wallet and exposes current/historical owner balances and total staked supply.

The PoS NFT is the position receipt. The Governor does not enumerate NFTs and does not trust a
caller-provided token ID. NFT mint, transfer, and burn automatically update owner checkpoints.
The staking protocol rejects positions or NFT transfers to the canonical burn address, so it cannot
acquire staked votes or increase the staked-voting denominator.

## 4. Proposal lifecycle

```text
PROPOSED -> ACTIVE -> SUCCEEDED -> QUEUED -> EXECUTED
     |          |          |
     +----------+----------+-> DEFEATED/CANCELLED/EXPIRED
```

Rules:

1. proposer votes are measured at `block.timestamp - 1`;
2. proposal votes are fixed at the proposal snapshot;
3. voting choices are against, for, and abstain;
4. quorum counts for + abstain, while success requires for > against;
5. successful proposals must pass through the timelock;
6. timelock execution is permissionless after the delay;
7. the launcher/factory has no proposer, canceller, or admin role after deployment;
8. proposal execution failures retain the queued operation for a normal retry where supported by
   the timelock.

## 5. Governed capabilities

The authority may call only explicit module functions. Expected capabilities are:

| Module | Governed operations |
| --- | --- |
| Treasury | send assets, execute guarded swap, set/disable basket route, operate/transfer/burn owned Basket NFT |
| Router | activate a complete route version, pause route, recover permanently failed route escrow |
| Basket | change target weights/assets within the immutable platform approval set, pause adapter, harvest config |
| Funding Bands | create and fund a new eligible band, cancel a pending unfunded/eligible band |
| Registry | publish allowed operational metadata/canonical pool update |

Governance cannot mint project tokens, alter historical votes, seize PoS positions, unlock Basket
principal without burning the NFT, redirect an existing airdrop entitlement, replace a raffle root,
or withdraw permanent liquidity.

## 6. Proposal safety and UI data

Every governed function must expose typed calldata in its ABI and emit old/new config hashes. The
Governor itself may use standard batched targets/calldata, but governed modules do not expose a
generic executor.

The UI must simulate proposals and render:

- exact assets, amounts, and recipients for treasury sends;
- route allocation changes and affected destinations;
- basket assets/weights being added or removed;
- band bounds, inventory, and destination;
- earliest queue and execution timestamps.

Unknown selectors or undecodable proposal actions are displayed as unsupported, not as a benign
configuration update.

## 7. Emergency behavior

An optional project guardian may pause swaps, new allocations, and new band funding. The guardian
cannot resume, transfer funds, change configuration, cancel votes, or block matured unstaking and
already-earned distributions. Governance resumes paused paths.

Token governance cannot be replaced by multisig, or vice versa. Loss of governance availability
does not create a recovery super-admin.

## 8. Required views and events

Views:

- governance mode, executor, vote source, clock mode;
- proposal threshold/quorum at a supplied timepoint;
- current/past votes for an account;
- proposal state and all lifecycle timestamps;
- timelock operation readiness.

Events include standard proposal/vote/timelock events plus `GovernanceCreated(projectId, mode,
executor, voteSource)` and `EmergencyPathPaused(module, selector, guardian)`.

## 9. Acceptance criteria

1. A liquid holder can vote without any prior delegation transaction.
2. A wallet's staked vote total equals the sum of its PoS NFT amounts at the proposal snapshot.
3. Transferring a PoS NFT after the snapshot does not move votes for that proposal; it changes
   future snapshot power exactly once.
4. Unstaking after a proposal snapshot does not change that proposal's recorded voting power.
5. A successful proposal cannot execute before the timelock delay.
6. Neither the Governor nor an EOA can bypass the timelock to call a governed module.
7. The multisig cannot execute with one confirmation or duplicate a signer confirmation.
8. No delegate or delegate-by-signature flow can assign votes to another wallet.
9. Guardian pause cannot transfer assets or prevent matured position redemption.
10. Project tokens held by the canonical burn address produce zero liquid votes and are excluded
    from quorum supply; the address cannot own a PoS position or acquire staked votes.

## 10. Out of scope

- vote delegation;
- veto councils;
- optimistic governance;
- vote locking multipliers or quadratic voting;
- changing governance mode or vote source after launch.
