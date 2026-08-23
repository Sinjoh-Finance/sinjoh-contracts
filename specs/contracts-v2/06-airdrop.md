# Airdrop

## 1. Objective

`ProjectAirdropV2` accepts reward assets and distributes each epoch proportionally to eligible
project participants. A project selects holder mode or staker mode. Holders do not need to connect
a wallet or submit a claim; a keeper pushes verified payments.

## 2. Eligibility modes

```solidity
enum EligibilityMode { HOLDERS, STAKERS }
```

Mode is immutable for one Airdrop instance.

### Holder mode

Weight is the eligible project-token wallet balance at the epoch snapshot.

### Staker mode

Weight is the wallet's aggregate active stake represented by PoS NFTs at the epoch snapshot. The
worker reconstructs ownership from staking/NFT events and verifies totals against the staking
pool's historical checkpoints.

For both modes:

```text
entitlement(holder) = floor(epochAmount * holderWeight / totalEligibleWeight)
```

The creator participates under the same rule when it has eligible weight. There is no creator
bonus and the creator is not automatically excluded.

## 3. Exclusions

Every epoch excludes:

- the zero address and canonical burn address
  `0x000000000000000000000000000000000000dEaD`;
- the Airdrop contract;
- the project token contract;
- the canonical project liquidity pool or PoolManager/position custody addresses configured at
  launch;
- launch curves, liquidity lockers, vesting/escrow custody, treasury, Router, staking pool, Raffle,
  Funding Bands, Basket vaults, and other predicted protocol custody addresses;
- Pons locker `0xda4bCee76B29EFEc9697Fcf663601c2042043968`.

The effective set is immutable for the Airdrop deployment and included in its configuration hash.
In staker mode, protocol contracts cannot own eligible PoS NFTs unless they are explicitly allowed
at launch; the Treasury is excluded by default.

## 4. Why snapshots use a committed tree

ERC-20 and ERC-721 contracts cannot enumerate all historical owners on-chain. A reference indexer
therefore reconstructs the deterministic snapshot and an immutable attestor commits an independent,
direction-aware Merkle-sum root for each epoch.

The attestor can misweight or omit a wallet. It cannot commit more epoch entitlement than the
Airdrop has funded, replace an epoch root, pay an excluded address, redirect a proof to another
recipient, or make total payments exceed liabilities.

The UI/operator must publish the full leaf/proof artifact for independent recomputation. Replacing
the attestor requires a new Airdrop deployment; project governance cannot silently rotate it.

## 5. Funding accounts

Each `(projectId, funder, rewardAsset)` has isolated accounting so Router, Treasury, Basket, and
Bands funding cannot spend one another's balance.

```text
accountId = keccak256(abi.encode(projectId, funder, rewardAsset, eligibilityMode))
```

`fund` measures exact receipt, charges the existing cumulative 1% service fee, and increases the
account's distributable funding by the net amount. Native currency and standard ERC-20 reward
assets are supported. Fee-on-transfer/rebasing assets are rejected.

The first funding fixes:

- maximum push batch size;
- minimum snapshot confirmations;
- epoch cadence (on-demand, 24 hours, or 7 days);
- eligibility mode and immutable exclusion hash;
- division-dust destination (Treasury, next epoch, or original funder).

Later funding must match the canonical account config hash.

## 6. Epoch commitments

Each commitment includes:

```solidity
struct EpochCommitment {
    uint64 epochId;
    uint64 snapshotBlock;
    bytes32 snapshotBlockHash;
    bytes32 rootHash;
    uint256 rootSum;
    uint256 epochAmount;
    uint256 totalEligibleWeight;
}
```

Rules:

1. epoch IDs and snapshot blocks strictly increase;
2. the chain-specific L2 block number/hash interface validates snapshot finality;
3. commitment is within the chain's verifiable block-hash window;
4. root hash/sum, epoch amount, and total eligible weight are nonzero;
5. epoch amount is no greater than uncommitted funded balance;
6. root sum is no greater than `epochAmount`; any difference is explicit integer-division dust;
7. a root is immutable after commitment;
8. the same snapshot cannot fund two epochs for the same account unless their assets/accounts differ.

If eligible weight is zero, no epoch is committed; funding rolls forward.

## 7. Automatic push delivery

```solidity
function push(
    bytes32 accountId,
    uint64 epochId,
    Leaf[] calldata leaves,
    Proof[] calldata proofs
) external;
```

Anyone may submit a bounded batch. Each leaf commits `(accountId, epochId, snapshotBlock, holder,
amount)`. The contract verifies the independent epoch proof and pays that holder at most once for
the epoch.

Transfer failure records the holder's exact retryable credit and continues the batch through an
isolated self-call. Anyone may retry, but payment can only reach the proven holder. Payment requires
no signature or wallet transaction from the holder.

Processing a valid leaf increments `settledEntitlement` exactly once whether its transfer succeeds
or becomes a retryable credit. An epoch can finalize only when `settledEntitlement == rootSum`.
The finalizer sends only `epochAmount - rootSum` integer-division dust to the configured destination.
A keeper cannot skip a leaf and sweep its entitlement. Retryable credits remain payable after
finalization, and finalization does not affect any later independent epoch.

## 8. Basket dividend integration

Each Basket reward account uses the Basket as `funder` and the project's Airdrop as sink. The
Basket's 24-hour or 7-day harvest cadence is also the Airdrop account cadence. A harvest transfers
only realized yield and then makes it available for the next snapshot epoch.

Holder/staker mode is selected in the Basket configuration and must match the funded Airdrop
account. The Basket cannot change eligibility by supplying different runtime config.

## 9. Solvency and events

```text
balance(airdrop, asset) >=
    uncommittedFunding(asset)
  + committedUnpaid(asset)
  + retryableCredits(asset)
  + protocolOwed(asset)
```

Events:

- `AccountConfigured(accountId, funder, asset, mode, configHash)`;
- `Funded(accountId, asset, gross, fee, net)`;
- `EpochCommitted(accountId, epochId, snapshotBlock, rootHash, rootSum, epochAmount)`;
- `PaymentSucceeded(accountId, epochId, holder, amount)`;
- `PaymentDeferred(accountId, epochId, holder, amount, reasonHash)`;
- `CreditDelivered(holder, asset, amount)`;
- `EpochFinalized(accountId, epochId, divisionDust, destination)`.

## 10. Required worker checks

1. reconstruct transfers/PoS ownership in strict block/log order;
2. verify snapshot hashes through at least two independent RPC endpoints;
3. cross-check holder-mode supply or staker-mode total against on-chain historical values;
4. apply the immutable complete exclusion set;
5. sort unique holders and compute every nonzero raw-unit proportional amount with checked
   arithmetic;
6. publish complete leaves/proofs and a deterministic artifact hash;
7. push every nonzero leaf and retry transfer failures;
8. reconcile aggregate payments against on-chain liabilities before finalization.

## 11. Acceptance criteria

1. A holder with 10% of eligible weight receives 10% of the distributable epoch amount, subject
   only to integer flooring.
2. The same proportional test passes using aggregate PoS NFT stake in staker mode.
3. The creator receives its proportional amount when eligible.
4. The canonical LP and Pons locker receive zero even when they hold project tokens.
5. The canonical burn address receives zero and its balance is removed from total eligible weight.
6. Holders receive pushed payments without signatures or claim transactions.
7. A reverting recipient cannot block other recipients and retains an exact retryable credit.
8. A falsified weight, sibling sum, direction, account, epoch, or recipient proof reverts.
9. An attestor cannot commit entitlements above account funding or replace a committed root.
10. The 1% service fee is correct on cumulative gross funding despite split deposits.
11. Basket harvest integration creates the correct holder/staker account and cadence.
12. An epoch cannot finalize until every committed leaf is paid or converted into the proven
    holder's retryable credit; only division dust can leave through the dust destination.

## 12. Out of scope

- NFT collection holders other than project PoS positions;
- opt-in manual claims as the primary user flow;
- mutable eligibility mode for an existing account;
- sybil detection or identity weighting;
- rebasing/fee-on-transfer reward assets.
