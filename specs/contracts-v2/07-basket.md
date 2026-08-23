# Basket

## 1. Objective

A Basket is an ERC-721 NFT backed by its own asset vault. The vault holds one or more
platform-approved yield-bearing positions. The project Treasury owns the Basket NFT at launch.
Routed fees are converted into the configured assets, yield is harvested every 24 hours or 7 days
and airdropped to holders or stakers, and principal remains locked until the NFT is burned.

## 2. Contract model

The protocol has three narrow components:

- `BasketManagerV2`: mints/burns Basket NFTs, validates configuration, coordinates funding,
  harvest, rebalance, and redemption;
- `BasketNFTV2`: ERC-721 ownership and metadata;
- one `BasketVaultV2` per token ID: custodies the Basket's assets and talks only to its configured
  adapters.

`BasketVaultV2` is the Basket's own treasury referenced in the product model. It is separate from
the project Treasury, and it can release principal only through the Basket burn lifecycle.

The NFT is the bearer ownership and redemption right. `ownerOf(tokenId)` is always the destination
for unlocked assets after tax. The initial owner for a project launch is the registered Treasury.
The first release mints at most one primary Basket to each project Treasury.

## 3. Configuration

```solidity
enum HarvestCadence { ONE_DAY, SEVEN_DAYS }
enum EligibilityMode { HOLDERS, STAKERS }
enum BurnTaxDestination { CREATOR, TREASURY, ROUTER, AIRDROP }

struct TargetAsset {
    address depositAsset;
    address yieldAdapter;
    address swapAdapter;
    address priceGuard;
    uint16 targetWeightBps;
    uint16 maxSlippageBps;
    bytes routeData;
}

struct BasketConfig {
    bytes32 projectId;
    address subject;
    address treasury;
    address airdrop;
    HarvestCadence cadence;
    EligibilityMode eligibilityMode;
    bool governanceUpdatesEnabled;
    uint16 burnTaxBps;
    BurnTaxDestination burnTaxDestination;
    uint256 burnPriceSubject;
    TargetAsset[] targets;
}
```

Rules:

- one to eight targets;
- target weights total exactly 10,000 basis points;
- deposit assets and adapters are unique and within the project's immutable approval root;
- adapter, route, and guard runtime/config hashes are frozen in the configuration version;
- cadence is exactly 24 hours or 7 days;
- staker eligibility requires the project staking module;
- burn tax is optional and capped at 5,000 basis points;
- burn tax destination is one destination in the first release;
- burn price is denominated in raw project-token units and may be zero;
- burn tax and burn price are immutable for the life of the Basket;
- the Treasury and project binding are immutable.

## 4. Platform-approved yield adapters

An adapter is bound to one Basket vault and one target asset. It exposes a narrow interface:

```solidity
interface IBasketYieldAdapter {
    function basketVault() external view returns (address);
    function depositAsset() external view returns (address);
    function deposit(uint256 assets) external returns (uint256 positionUnits);
    function totalAssets() external view returns (uint256 assets);
    function harvest(address recipient) external returns (address[] memory assets, uint256[] memory amounts);
    function withdrawPrincipal(uint256 assets, address recipient) external returns (uint256 received);
    function exitAll(address recipient) external returns (address[] memory assets, uint256[] memory amounts);
}
```

Admission requires an audited implementation, exact balance-delta behavior, a mainnet-fork deposit/
harvest/full-exit test, no caller-selected target, and an exit path that cannot redirect assets away
from the Basket vault. An adapter cannot be shared across Basket vaults.

## 5. Funding and allocation

The Basket implements `IProjectFundable.fund`. It accepts any configured input asset and allocates
the measured receipt by target weights.

For each target share:

1. if input equals the target deposit asset, no swap occurs;
2. otherwise the Basket performs the immutable guarded swap for that target;
3. it deposits the measured target asset into the bound yield adapter;
4. it records the exact deposit amount as locked principal;
5. rounding residuals remain attributed to the Basket vault and are included in the next allocation.

Funding is atomic across all target shares. If one swap/deposit fails, no principal/accounting
change is committed and the funder retains/reacquires the entire amount through transaction revert.
The Basket charges no funding fee.

## 6. Principal and yield

For each adapter:

```text
positionValue = adapter.totalAssets()
lockedPrincipal = cumulativeDeposits - principalMovedDuringRebalance
unrealizedGain = max(positionValue - lockedPrincipal, 0)
unrealizedLoss = max(lockedPrincipal - positionValue, 0)
```

Locked principal cannot be sent to holders, the Treasury, governance, creator, or an operator.
Only value explicitly returned by `adapter.harvest` or withdrawn above the adapter's remaining
principal may be classified as realized yield.

Losses reduce current Basket value but do not create a claim against future funding. Future gains
first restore the adapter to its principal high-water mark before becoming distributable yield.

## 7. Harvest and dividends

`harvest(tokenId)` is permissionless after the configured cadence has elapsed.

1. each active adapter transfers its harvestable reward/yield assets to the Basket vault;
2. the vault verifies measured deltas and prevents principal from being classified as yield;
3. each nonzero reward asset is funded into the project's Airdrop using the Basket as funder;
4. the Airdrop account uses the Basket's immutable holder/staker mode and cadence;
5. the next harvest time advances only after all yield is safely funded or recorded as a retryable
   pending distribution.

A failure for one reward asset records that asset as pending and does not reclassify or lose it.
Anyone may retry. Pending dividends are liabilities and cannot be reinvested as principal.

## 8. Governance updates and rebalancing

If `governanceUpdatesEnabled == false`, target assets/weights are immutable. If enabled, project
governance may activate a complete new target configuration drawn only from the immutable approval
root.

Rebalancing may:

- change target weights;
- add an approved target;
- remove an approved target by exiting it into the Basket vault;
- move principal from one approved target to another through guarded swaps;
- pause new allocation to a failing adapter.

Rebalancing may not send assets outside the Basket vault, change owner, change burn tax/price,
change eligibility mode, or distribute principal. Removed-target proceeds remain locked Basket
principal and must be reallocated or held idle inside the vault.

## 9. Basket transfer

Basket NFTs are transferable. A transfer moves the future redemption right but does not move vault
assets or change project/eligibility configuration. The Treasury may transfer its NFT only through
an authorized governance action. The new owner can later burn the Basket and receives unlocked
assets net of tax.

## 10. Redemption by burn

Burn is the only operation that unlocks principal. Because up to eight adapters may need exits,
redemption is resumable rather than requiring one unbounded transaction.

```text
ACTIVE -> BURNING -> BURNED
```

1. the NFT owner calls `beginBurn(tokenId)` (the Treasury uses its typed Basket function);
2. NFT transfers, new funding, rebalancing, and harvesting stop;
3. anyone may call `processBurnTarget(tokenId, targetIndex)`; returned assets remain locked in the
   Basket vault;
4. each target must either exit all assets or transfer its complete redeemable position into the
   vault under its audited exit rule;
5. when all targets are processed, the NFT owner calls `finalizeBurn`;
6. `burnPriceSubject` project tokens are pulled from the current NFT owner and burned, when nonzero;
7. for each unlocked asset, `floor(amount * burnTaxBps / 10_000)` is sent to the configured tax
   destination and the remainder to the current NFT owner;
8. all exact transfers succeed, then the NFT is burned and the vault is permanently closed.

If the owner is the project Treasury, the Treasury is both redemption recipient and burn-price
payer. Its typed finalize function grants only the exact temporary project-token allowance needed
and clears it after use. Tax destination behavior:

- `CREATOR`: exact in-kind tax to immutable project creator;
- `TREASURY`: exact in-kind tax to registered Treasury (a no-op destination when it is already
  owner, but still emitted/accounted);
- `ROUTER`: fund the registered Router for normal routing;
- `AIRDROP`: fund the registered Airdrop under the Basket's eligibility mode.

No asset leaves the Basket before finalization. A partially processed burn can be resumed by any
keeper, and NFT ownership remains visible until final settlement succeeds.

## 11. Accounting invariants

1. Every asset/position in a Basket vault belongs to exactly one token ID.
2. Locked principal can leave the vault only during successful `finalizeBurn` after NFT ownership
   validation.
3. Cumulative dividends never exceed cumulative realized yield.
4. Adapter loss cannot be charged as a dividend or silently replenished from pending dividends.
5. Rebalancing preserves total Basket ownership and sends no value outside the vault.
6. Burn taxes plus owner proceeds equal measured unlocked amounts for every asset.
7. Basket Manager, factory, keeper, and project governance cannot redirect redemption away from the
   NFT owner.

## 12. Acceptance criteria

1. Launching with Basket enabled mints the configured NFT directly to the project Treasury.
2. One-asset and multi-asset funding allocate within rounding tolerance to target weights.
3. A 24-hour Basket cannot harvest twice inside 24 hours; a 7-day Basket cannot harvest twice inside
   7 days.
4. Holder and staker dividend modes fund the matching Airdrop account.
5. A loss-making adapter distributes no principal as yield.
6. A governance rebalance changes targets without transferring value outside the Basket.
7. No owner, governance, or adapter can withdraw principal before burn finalization.
8. Burn without sufficient project-token burn price reverts without unlocking assets.
9. Successful burn destroys the NFT and sends every unlocked asset net of exact tax to the owner.
10. An interrupted multi-target burn resumes without reprocessing or double-paying a target.

## 13. Out of scope

- borrowing or leverage;
- permissionless adapter admission;
- fractional Basket NFT ownership;
- principal withdrawals without burning the NFT;
- changing burn economics after mint;
- multiple burn-tax destinations in the first release.
