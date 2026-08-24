# Staking and Proof of Stake NFT

## 1. Objective

When staking is enabled, the project deploys one `ProjectStakingPoolV2` and one `ProjectPoSNFT`.
Token holders lock project tokens in the pool. Each stake mints one PoS NFT representing the exact
position. Burning the NFT after its lock expires returns the position's tokens.

The pool also provides automatic historical staked-balance checkpoints for staker-only airdrops and
optional staked-token governance.

## 2. Position model

```solidity
struct Position {
    uint128 amount;
    uint64 createdAt;
    uint64 unlockAt;
}
```

Rules:

- one `stake` call creates one position and one NFT;
- position amount is fixed; adding stake creates another NFT;
- only standard non-rebasing project tokens are accepted;
- lock duration is one immutable project value chosen at launch;
- first-release factory bounds are 1 day to 365 days;
- the position cannot unlock before `unlockAt`;
- unstaking is full-position only and burns the NFT;
- staking charges no protocol fee.

## 3. Staking

```solidity
function stake(uint256 amount, address recipient) external returns (uint256 tokenId);
```

The pool measures its subject-token balance before/after transfer and requires the increase to equal
`amount`. It stores the position, mints the NFT to `recipient`, updates aggregate current/historical
stake for `recipient`, and updates total-staked checkpoints atomically.

Recipient must be nonzero, must not be the canonical burn address
`0x000000000000000000000000000000000000dEaD`, and must be able to receive ERC-721 safely when it is
a contract. A user may stake for another wallet; the recipient owns the position and its
eligibility.

## 4. PoS NFT ownership and transfer

The PoS NFT is transferable. Ownership determines who may unstake and who receives future
stake-based voting/airdrop weight.

On every NFT transfer, the staking pool atomically moves the position amount from the prior owner's
aggregate checkpoint to the new owner's checkpoint. The transfer does not move the locked ERC-20;
it moves the right to redeem that position.

Transfer rules:

- zero-address transfer occurs only during burn;
- transfer to the canonical burn address reverts; destroying a position requires the defined
  matured `unstake` flow rather than stranding its NFT;
- the staking pool is the only minter and burner;
- approvals follow ERC-721;
- a transfer at timestamp `t` affects snapshots at/after `t`, never an earlier snapshot;
- metadata exposes subject, raw amount, created time, unlock time, and current unlock status.

## 5. Unstaking

```solidity
function unstake(uint256 tokenId, address recipient) external returns (uint256 amount);
```

The caller must own or be approved for the NFT. The current time must be at least `unlockAt`.
Execution order is checks, delete position/update owner and total checkpoints, burn NFT, then exact
token transfer to the nonzero recipient under reentrancy guard.

Unstaking remains available when other project modules or new staking are paused. There is no
governance confiscation, early unlock fee, cooldown, or emergency extension of the lock.

## 6. Historical eligibility and votes

The pool directly implements the required timestamp-based vote/snapshot interface:

```solidity
function balanceOfStake(address owner) external view returns (uint256);
function getPastStake(address owner, uint256 timepoint) external view returns (uint256);
function getPastTotalStaked(uint256 timepoint) external view returns (uint256);
function getVotes(address owner) external view returns (uint256);
function getPastVotes(address owner, uint256 timepoint) external view returns (uint256);
function getPastTotalSupply(uint256 timepoint) external view returns (uint256);
```

`getVotes == balanceOfStake` and `getPastVotes == getPastStake`. The pool uses automatic raw stake;
delegation is unavailable. One locked token equals one vote and one staker-airdrop weight unit.

Historical lookup at a current/future timepoint reverts according to the standard vote interface.
Multiple positions owned by the same wallet are aggregated.

## 7. Solvency

```text
balance(pool, subject) == totalActiveStake
totalActiveStake == sum(amount for every live PoS NFT)
```

The pool rejects raw token transfers from its accounting. A permissionless `recoverSurplus` may
return only measured balance above `totalActiveStake` to the project Treasury; it can never reduce
position backing.

## 8. Events and views

Events:

- `PositionCreated(tokenId, funder, owner, amount, unlockAt)`;
- `PositionTransferred(tokenId, from, to, amount)` in addition to ERC-721 `Transfer`;
- `PositionRedeemed(tokenId, owner, recipient, amount)`;
- `SurplusRecovered(amount, treasury)`.

Views return position data, aggregate current/past stake, positions owned by a wallet through an
indexer-friendly event surface, and global backing/active totals. Core contracts do not enumerate
all token IDs on-chain.

## 9. Invariants

1. Every live PoS NFT maps to exactly one nonzero position.
2. Every position is fully backed by pool subject-token balance.
3. Owner aggregate checkpoints equal the sum of live position amounts owned at each checkpoint.
4. NFT transfer changes aggregate weight once without changing total stake.
5. NFT burn reduces owner and total weight by the redeemed amount exactly once.
6. Governance and guardian roles cannot withdraw position backing or delay matured redemption.

## 10. Acceptance criteria

1. Staking 100 tokens mints one NFT reporting amount 100 and the exact unlock time.
2. Burning before unlock reverts; burning at/after unlock returns exactly 100 tokens and destroys
   the NFT.
3. Transferring a position moves current voting/airdrop weight to the new owner and preserves prior
   snapshots.
4. A wallet with three NFTs has voting weight equal to their summed raw amounts.
5. No separate votes adapter or delegation transaction is required for staked governance.
6. Pausing new stakes does not pause transfers or matured unstaking.
7. Surplus recovery cannot make the pool balance lower than active stake.
8. Staking for, or transferring a PoS NFT to, the canonical burn address reverts, and it never
   contributes staked voting or Airdrop weight.

## 11. Out of scope

- partial position withdrawals;
- increasing an existing position;
- lock multipliers, tiers, or reward boosts;
- liquid staking tokens;
- slashing;
- staking rewards stored in the pool (rewards use Airdrop V2).
