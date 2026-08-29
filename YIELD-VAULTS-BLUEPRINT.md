# Yield Vaults Protocol Blueprint

> **Superseded for implementation:** The primary-sale, supply, escrow, refund, mint,
> transfer-lock, and sale-state sections in this document are no longer canonical.
> Use `YIELD-BANKS-DEVELOPMENT-PLAN.md`, version 2.0, for the authoritative Yield Banks
> development plan. This file is historical context only; none of its sale, portfolio,
> strategy, supply, or naming defaults are implementation requirements.

Version: 1.0

Date: 2026-08-27

Status: Superseded historical source material

Network: Robinhood Chain, chain ID 4663

Supply: Superseded; Yield Banks uses an immutable positive maximum configured per collection

Supersedes: `YIELD-VAULTS-IRONED.md` for engineering decisions

## 1. Protocol definition

Yield Vaults is a collection protocol in which every ERC-721 token is permanently bound to a deterministic treasury account. The treasury owns shares of three collection sleeves:

1. Core Stock Token Sleeve
2. Market-Making Sleeve
3. USDG Yield Sleeve

The sleeves own the underlying Stock Tokens, Delta LP positions, USDG, lending receipts, and future approved strategy positions. Strategy adapters may evolve, but the NFT's ownership, fee rights, portfolio categories, and redemption rights do not.

The holder can transfer the NFT with its entire treasury or burn it to receive the treasury assets. No holder, creator, keeper, guardian, or platform administrator can withdraw backing without burning the NFT.

## 2. Final architecture decisions

These decisions are settled for v1:

| Decision | v1 rule |
|---|---|
| Collection size | Exactly 3,000 NFTs after sale success |
| Sale | Fixed-price, all-or-refund sale in WETH |
| Initial backing | Positive basis-point share configured immutably per collection |
| Creator allocation | Basis-point share configured immutably per collection |
| Sinjoh allocation | Basis-point share configured immutably per collection |
| Operations reserve | Basis-point share configured immutably per collection |
| Portfolio weights | Positive Core, Market-Making, and USDG Yield weights configured immutably per collection and totaling 100% |
| NFT treasury | One deterministic minimal-proxy account per token ID |
| Treasury assets | Sleeve shares plus temporary WETH/USDG and approved distributions |
| Ongoing revenue | Equal per-live-NFT share accounting with no 3,000-token loop |
| Exit tax | 5% in the same assets, redistributed to remaining NFTs |
| Final NFT | No exit tax; receives all distributor dust and closes collection |
| Performance fee | None for Sinjoh in v1 |
| Strategy evolution | New immutable adapters may be registered and activated inside an existing sleeve |
| Core upgradeability | No proxies or delegatecalls in NFT, account, distributor, or sleeve-share contracts |
| External integrations | Address, runtime code hash, asset, oracle, limits, and adapter version pinned |
| Redemption | Atomic transfer of sleeve shares; strategy unwrapping is separate and cannot block NFT redemption |

### Why redemption transfers sleeve shares

The NFT must never become unredeemable because a lending market is illiquid, a Delta range cannot be closed, an oracle is stale, or an integration is paused.

Burning therefore transfers the NFT account's sleeve-share tokens and liquid assets. Those shares remain enforceable claims on their sleeves. The holder may unwrap them afterward through each sleeve. An optional `burnAndUnwrap` router may provide convenience, but the core burn path never calls an external strategy.

## 3. System topology

```text
                                      GLOBAL PROTOCOL
                       +-------------------------------------------+
                       | YieldVaultProtocolRegistry                |
                       | StrategyRegistry                          |
                       | PriceHub                                  |
                       | Versioned implementation/codehash catalog |
                       +--------------------+----------------------+
                                            |
                                            v
                                   COLLECTION FACTORY
                                            |
              +-----------------------------+-----------------------------+
              |                                                           |
              v                                                           v
    YieldVaultCollection                                           CollectionTimelock
    - immutable economics                                          - delayed policy changes
    - sale state                                                   - strategy activation
    - live supply                                                  - constituent migration
    - mint/burn coordinator                                        - never receives backing
              |
       +------+----------------+------------------+-------------------+
       |                       |                  |                   |
       v                       v                  v                   v
 YieldVaultNFT        YieldVaultDistributor   SaleEscrow       OperationsReserve
       |                       |                  |                   |
       | tokenId              | lazy claims      | WETH until       | non-backing funds
       v                       |                  | sale success      |
 YieldVaultAccount <-----------+                  +-------------------+
       |
       +---------------------+-------------------------+
       |                     |                         |
       v                     v                         v
 CoreSleeve shares      MarketMaking shares       USDGYield shares
       |                     |                         |
       v                     v                         v
 Stock Tokens           Delta adapter(s)           Idle USDG
 approved swaps         Delta/Uniswap LP           Lending adapters
 corporate actions      WETH rewards               Future USDG strategies
```

## 4. Ownership model

Ownership is layered and explicit:

| Asset or right | Onchain owner | Economic beneficiary |
|---|---|---|
| ERC-721 | Holder wallet | Holder wallet |
| Token treasury account | Bound permanently to token ID | Current ERC-721 holder |
| Sleeve-share tokens | Token treasury account or distributor pending settlement | Current ERC-721 holder |
| Stock Tokens | Core Sleeve | Core Sleeve shareholders pro rata |
| Delta position NFT | Market-Making Sleeve or its bound adapter | Market-Making Sleeve shareholders pro rata |
| USDG lending receipt | USDG Yield Sleeve or its bound adapter | USDG Yield Sleeve shareholders pro rata |
| Pending collection revenue | Distributor custody with per-token accounting | Token ID, not the current wallet address |
| Operations reserve | OperationsReserve contract | Not NFT backing |

An ERC-721 transfer changes only `ownerOf(tokenId)`. It does not move treasury assets. The deterministic account remains bound to the same token ID, so settled and unsettled value follows the NFT automatically.

## 5. Contract catalog

### 5.1 Global contracts

#### `YieldVaultProtocolRegistry`

- Append-only discovery registry for factories, collections, sleeves, and approved implementation versions.
- Stores deployment provenance and runtime code hashes.
- Owns no backing and performs no arbitrary calls.
- Deprecation hides an integration from new use but never deletes historical records.

#### `StrategyRegistry`

- Catalogs reviewed strategy adapters.
- Records adapter implementation, runtime code hash, sleeve category, accounting asset, liquidity mode, risk class, audit hash, and status.
- Registration alone does not authorize a collection to use an adapter.
- A collection timelock must separately activate it under collection-specific caps.

#### `PriceHub`

- Provides normalized 18-decimal USD quotes.
- Validates feed decimals, positive answer, heartbeat, staleness, corporate-action pause, and configured deviation limits.
- Supports Chainlink feeds, pool TWAP comparison, and an explicit operational circuit breaker.
- Is never used to calculate the 5% exit tax; the tax is applied directly to each asset amount.
- Feed failure pauses only price-dependent deposits, swaps, and rebalances.

#### `YieldVaultCollectionFactory`

- Deploys one version-pinned collection system.
- Predicts all deterministic addresses before deployment.
- Validates configuration bounds and implementation code hashes.
- Registers the resulting collection atomically.
- Cannot modify a deployed collection.

### 5.2 Collection contracts

#### `YieldVaultCollection`

The central coordinator. It stores immutable economics and controls only typed lifecycle operations.

Responsibilities:

- sale creation, mint accounting, sale success/failure;
- deterministic account creation;
- NFT mint, transfer-state, and burn authorization;
- initial portfolio allocation;
- revenue-source authorization;
- live-supply accounting;
- atomic redemption and terminal close;
- collection-specific sleeve policy and adapter activation through timelock;
- collection metadata and status views.

It must not expose arbitrary `call`, `delegatecall`, arbitrary recipient, or rescue functions for backing.

#### `YieldVaultNFT`

- ERC-721 with token IDs `1..3000`.
- Mint and burn callable only by `YieldVaultCollection`.
- Transfers disabled until sale success.
- Transfers disabled while the token is being burned.
- EIP-2981 royalty receiver is the collection revenue router.
- `tokenURI` exposes token ID, account address, collection state, and renderer output without Robinhood marks.

#### `YieldVaultAccount`

- Minimal-proxy treasury for exactly one token ID.
- Initialized once with collection address, NFT address, and token ID.
- Receives approved sleeve shares and temporary liquid assets.
- Can approve exact amounts only to collection-approved sleeves during allocation.
- Can release assets only to the snapshotted holder and distributor during a collection-controlled burn.
- Cannot execute arbitrary calls or pay an administrator.
- Maximum tracked treasury assets: eight.

#### `SaleEscrow`

- Receives every mint payment in WETH.
- Records payment and payer by token ID.
- Before sale success, no creator, Sinjoh, operations, or strategy transfer is allowed.
- On manual allocation, releases the collection-configured primary allocations.
- On failed sale, returns 100% of WETH to the recorded payer as the NFT is canceled.
- Owns no funds after success or complete refund.

#### `YieldVaultDistributor`

- Holds sleeve shares and approved assets awaiting per-token settlement.
- Maintains an accumulator per distribution asset and debt per token ID.
- Receives ongoing revenue allocations and exit-tax assets.
- Settles one token or a bounded batch.
- Never loops over total collection supply.
- Maximum distribution assets: eight, matching account tracking.

#### `CollectionRevenueRouter`

- Receives WETH or approved contribution assets from authenticated revenue sources.
- Applies the immutable split associated with the source type.
- Isolates failed legs as retryable escrow rather than blocking successful legs.
- Sends the NFT portion through the portfolio allocator and then to the distributor.
- Uses exact balance-delta accounting and clears every temporary allowance.

#### `OperationsReserve`

- Explicitly not NFT backing.
- Receives the collection-configured primary and ongoing operations allocation.
- Pays disclosed audits, automation, and capped keeper bounties through its own multisig policy.
- After the primary-reserve sunset, anyone may sweep unused primary reserves to `CollectionRevenueRouter` for 100% NFT distribution.

#### `CollectionTimelock`

- Minimum seven-day delay for adapter activation, allocation-cap changes, feed migrations, and constituent replacement.
- Cannot change fixed supply, primary split, revenue split, portfolio category weights, exit tax, bearer ownership, or redemption destination.
- Cannot transfer backing to itself or another administrator.

### 5.3 Sleeve contracts

Every sleeve is an ERC-20 share token. A token treasury owns sleeve shares; the sleeve owns underlying assets or adapter shares.

#### `CoreStockTokenSleeve`

- Category weight is configured immutably per collection.
- Holds up to three active Stock Tokens.
- Launch target: equal weights inside the sleeve unless the manifest specifies another immutable launch allocation.
- Supports timelocked constituent replacement when an issuer deprecates a token or liquidity/feed quality fails.
- Normal redemption can return constituents in kind.
- Optional USDG redemption is available only with valid feeds, protected routes, and user-provided minimum output.

#### `MarketMakingSleeve`

- Category weight is configured immutably per collection.
- Owns approved Delta strategy-adapter shares or Delta/Uniswap position NFTs.
- V1 enables at most two strategies and one active position per strategy.
- Accounts for principal inventory, uncollected trading fees, claimed WETH, and streamed but not yet claimable rewards.
- Harvest and rebalance are permissionless but policy-guarded.
- Share redemption may return underlying assets when liquid; holders can always retain the share claim when an adapter is exit-only.

#### `USDGYieldSleeve`

- Category weight is configured immutably per collection.
- Accounting and deposit asset is USDG `0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168`.
- Implements ERC-4626 when all normal deposits and redemptions are expressed in USDG.
- Deploys USDG into the configured lending adapter; any plain USDG balance is transient transaction liquidity.
- Initial maximum exposure to any single lending adapter: 10% of total collection portfolio value.
- Initial canary cap for a new adapter: 2% of total collection portfolio value.
- Supports synchronous and queued withdrawal adapters without blocking NFT burn.

## 6. Strategy adapter framework

### 6.1 Principle

Adapters are isolated custody modules, not upgradeable plugins executed inside sleeve storage. Sleeves call adapters normally; they never `delegatecall` them.

Every adapter is:

- bound to one sleeve;
- bound to one accounting asset or an explicit multi-asset inventory;
- immutable or versioned by deploying a new contract;
- registered with a runtime code hash;
- capped by the sleeve;
- unable to select an arbitrary recipient;
- able to return assets only to its bound sleeve;
- paused independently; and
- removable by exiting into the sleeve, not by changing its implementation in place.

### 6.2 Adapter states

```text
UNREGISTERED
     |
     v
REGISTERED -----> REJECTED
     |
     | collection proposal + 7-day delay
     v
CANARY (hard allocation cap)
     |
     | observation period + explicit activation
     v
ACTIVE
  |      |
  |      +-----------------> DEPOSIT_PAUSED
  |                              |
  +------------------------------+
                 |
                 v
             EXIT_ONLY
                 |
                 v
              RETIRED
```

No state transition can re-enable an adapter whose runtime code hash no longer matches its registration.

### 6.3 Adapter interface

The implementation may refine names, but every adapter must provide equivalent behavior:

```solidity
interface IStrategyAdapter {
    enum LiquidityMode { SYNCHRONOUS, QUEUED }

    function sleeve() external view returns (address);
    function accountingAsset() external view returns (address);
    function liquidityMode() external view returns (LiquidityMode);
    function positionAssets() external view returns (address[] memory);
    function totalManagedAssets() external view returns (uint256);

    function deposit(uint256 assets, uint256 minPositionUnits, bytes calldata data)
        external
        returns (uint256 positionUnits);

    function withdraw(uint256 assets, address receiver, uint16 maxLossBps, bytes calldata data)
        external
        returns (uint256 assetsReturned);

    function requestWithdraw(uint256 assets, bytes calldata data)
        external
        returns (bytes32 requestId);

    function claimWithdraw(bytes32 requestId, address receiver)
        external
        returns (uint256 assetsReturned);

    function harvest(bytes calldata data)
        external
        returns (address[] memory assets, uint256[] memory amounts);

    function exitAll(address receiver, uint16 maxLossBps, bytes calldata data)
        external
        returns (address[] memory assets, uint256[] memory amounts);
}
```

Rules:

- `receiver` must equal the bound sleeve.
- `totalManagedAssets` is an accounting view, not an oracle.
- Sleeve NAV is independently calculated from actual balances and approved price sources.
- Loss is reported, not hidden by reverting forever. A principal impairment must trigger policy limits and exit-only state without permanently trapping withdrawals.
- Every deposit, withdrawal, and harvest validates exact token movements.

### 6.4 Initial adapters

#### `USDGLendingAdapter`

- Bound to the configured USDG lending venue.
- Implements the venue's actual receipt-token, interest, loss, and withdrawal behavior.
- Validates `asset() == USDG`.
- Never treats `previewRedeem` as a price oracle.
- If the venue uses ERC-4626, supports its deposit limits, liquidity checks, and full exit without assuming every lender is ERC-4626.

#### `DeltaV3StrategyAdapter`

- Uses the verified Delta position builder at `0x6235cF6bd8419b34942F4EDDB39C880BD96dD700`.
- Creates and owns the resulting Uniswap v3 position NFT, then stakes it through the configured Delta staking lifecycle.
- Implements the configured increase, decrease, collect, stake, reward-claim, stream, unstake, and close calls.
- Every mint/rebalance uses nonzero minimum amounts, a deadline, approved pool, oracle/TWAP agreement, and maximum price impact.
- Tracks streamed WETH rewards separately from claimable WETH.
- Requires complete contract addresses and ABIs for every Delta dependency before implementation is considered complete.

## 7. Core interfaces

### 7.1 Sleeve interface

```solidity
interface IYieldVaultSleeve {
    enum RedemptionMode { ACCOUNTING_ASSET, IN_KIND, QUEUED }

    function category() external view returns (bytes32);
    function accountingAsset() external view returns (address);
    function totalAssetsUsd18() external view returns (uint256 value, uint48 pricedAt);
    function activeStrategyCount() external view returns (uint256);

    function deposit(
        uint256 assets,
        address receiver,
        uint256 minShares,
        bytes calldata data
    ) external returns (uint256 shares);

    function redeem(
        uint256 shares,
        address receiver,
        address owner,
        RedemptionMode mode,
        uint256 minimumOutput,
        bytes calldata data
    ) external returns (address[] memory assets, uint256[] memory amounts);
}
```

### 7.2 Eligibility policy

```solidity
interface IEligibilityPolicy {
    function canMint(address account, bytes calldata proof) external view returns (bool);
    function canReceiveNFT(address account, bytes calldata proof) external view returns (bool);
    function canReceiveRestrictedShares(address account, bytes calldata proof)
        external
        view
        returns (bool);
    function canRedeem(address account, bytes calldata proof) external view returns (bool);
}
```

If Stock Tokens are active, the policy cannot be disabled while any restricted sleeve exposure remains.

### 7.3 Revenue receiver

```solidity
interface IYieldVaultFundable {
    function fund(
        bytes32 collectionId,
        address sourceAsset,
        uint256 amount,
        bytes32 sourceType,
        bytes calldata sourceData
    ) external returns (uint256 received);
}
```

The router authenticates the caller and source type. It never trusts a caller-supplied split or destination.

## 8. Configuration model

### 8.1 Immutable collection configuration

```text
collectionId
factoryVersion
creator
sinjohFeeRecipient
operationsReserve
WETH
USDG
mintPriceWeth
maxSupply = 3000
saleDeadline
saleSuccessSupply = 3000
primaryBackingBps = 8000
primaryCreatorBps = 1000
primarySinjohBps = 500
primaryOperationsBps = 500
secondaryRoyaltyBps = 500
royaltyTreasuryShareBps = 7000 of royalty
royaltyCreatorShareBps = 1500 of royalty
royaltySinjohShareBps = 1500 of royalty
projectRevenueNftBps = 8000
projectRevenueCreatorBps = 1000
projectRevenueSinjohBps = 500
projectRevenueOperationsBps = 500
exitTaxBps = 500
coreSleeveWeightBps = 5000
marketMakingSleeveWeightBps = 3500
usdgYieldSleeveWeightBps = 1500
collectionTimelock
guardian
renderer
boundToken
boundTokenBurnAmount = 0 in v1
```

Every basis-point group must total exactly 10,000 during construction.

### 8.2 Mutable but bounded policy

The timelock may change only:

- active adapter selection inside a sleeve;
- per-adapter allocation cap within immutable collection maxima;
- approved pool or Stock Token constituent after a complete exit from the old position;
- price feed and swap route when the replacement passes the same asset/category constraints;
- keeper profitability threshold and capped bounty;
- pause state;
- renderer metadata implementation if the ownership and financial facts remain sourced from core contracts.

It may never change top-level category weights for this collection.

## 9. State machines

### 9.1 Collection state

```text
DEPLOYED
   |
   v
SALE_ACTIVE ----------------------> SALE_FAILED
   |                                    |
   | 3,000 paid mints                   | refunds completed
   v                                    v
SALE_SUCCESS                        CANCELED
   |
   | seed portfolio created
   v
ACTIVE <----------------------> INVESTMENT_PAUSED
   |
   | liveSupply reaches zero
   v
CLOSED
```

- NFT transfers, ongoing fee distribution, and redemption begin only at `ACTIVE`.
- A guardian may move `ACTIVE` to `INVESTMENT_PAUSED`.
- `INVESTMENT_PAUSED` still permits settlement, NFT transfers, NFT burn, sleeve-share transfer, and sleeve exit.

### 9.2 Token state

```text
UNMINTED -> SALE_LOCKED -> ACTIVE -> BURNING -> BURNED
                    \
                     -> REFUNDED  (sale failure only)
```

The `BURNING` state exists only during one non-reentrant transaction. There is no long-lived exit state in the core protocol.

### 9.3 Sleeve state

```text
UNINITIALIZED -> ACTIVE -> DEPOSIT_PAUSED -> EXIT_ONLY -> CLOSED
                    |            ^              ^
                    +------------+--------------+
                         guardian/timelock
```

Exit capability cannot be paused by the same role that pauses deposits.

## 10. Complete fund flows

### 10.1 Mint during sale

```text
Buyer
  | fixed WETH price
  v
SaleEscrow
  | records payer, tokenId, configured backing liability, and configured recipient liabilities
  v
YieldVaultCollection
  | creates deterministic account
  v
YieldVaultNFT mints SALE_LOCKED token
```

Rules:

1. Payment is measured by balance delta and must equal the fixed price.
2. Account is deployed before NFT mint.
3. No part of the payment leaves escrow before sale success.
4. Pre-success NFTs cannot transfer, burn for backing, or approve operators.

### 10.2 Sale success

When paid mint count reaches 3,000:

1. Collection records `finalizedSupply = 3000` and permanently closes minting.
2. The proceeds vault releases the configured creator, Sinjoh, and OperationsReserve shares only during manual allocation.
3. The configured backing share is wrapped and allocated across the three sleeves using the collection's immutable configured weights.
4. The exact sleeve shares received are divided equally across all 3,000 token IDs through distributor accumulators.
5. Rounding dust remains accounted in the distributor and ultimately belongs to the final live NFT.
6. Anyone may call `settle(tokenId)` to move the three sleeve-share balances into its deterministic account.
7. Collection becomes `ACTIVE` even if some token IDs have not settled because their distributor claims are already productive and transferable with the token ID.

If feeds are closed or stale at sale success, seed WETH remains fully accounted in SaleEscrow/allocator escrow until guarded sleeve deposits can execute. NFTs become transferable only after the seed claims are recorded. Allocation legs are independently retryable.

### 10.3 Sale failure

If the deadline expires before 3,000 paid mints:

1. Collection enters `SALE_FAILED`.
2. Strategy allocation is forbidden because no backing left escrow.
3. Current holder calls `refund(tokenId)`; because transfers were disabled, holder and recorded payer are the same.
4. NFT is burned and 100% of the fixed WETH price returns to the payer.
5. After all minted tokens are refunded, collection enters `CANCELED`.

No creator, Sinjoh, or operations payment is earned by a failed sale.

### 10.4 Ongoing revenue

```text
Approved source
      |
      v
CollectionRevenueRouter
      |
      +--> creator / Sinjoh / OperationsReserve by immutable source split
      |
      v
PortfolioAllocator
      | configured immutable weights totaling 100%
      v
Sleeve deposits
      | measured shares
      v
YieldVaultDistributor
      | accumulator per sleeve-share token
      v
settle(tokenId) -> YieldVaultAccount
```

Revenue source types:

| Source | NFT share | Creator | Sinjoh | Operations |
|---|---:|---:|---:|---:|
| Sinjoh secondary royalty | 70% of royalty | 15% | 15% | 0% |
| Bound-project-token revenue | configured backing share | configured creator share | configured Sinjoh share | configured operations share |
| Approved voluntary contribution | 100% | 0% | 0% | 0% |
| Exit tax | 100% to remaining NFTs | 0% | 0% | 0% |

External marketplaces may not enforce EIP-2981 royalties. Forecasts and UI must label royalties as realized, not guaranteed.

### 10.5 NFT transfer

1. NFT must be `ACTIVE`.
2. Recipient must pass `canReceiveNFT`.
3. No account asset or distributor balance moves.
4. Settled sleeve shares remain in the deterministic account.
5. Unsettled accumulator claims remain keyed to token ID.
6. New owner immediately holds the complete bearer claim.

### 10.6 Delta harvest and rebalance

1. Anyone may call the keeper entrypoint.
2. Strategy verifies state, minimum elapsed time, expected value recovered, and bounty profitability.
3. PriceHub verifies fresh feeds, corporate-action state, pool TWAP agreement, and deviation limits.
4. Adapter collects fees/rewards to its sleeve.
5. Delta's documented fee is measured from actual output.
6. Sleeve compounds according to its fixed strategy allocation.
7. Exact approvals are cleared.
8. Keeper receives a capped bounty from OperationsReserve, never from strategy principal.

A rebalance is permitted only after the range has remained outside policy for the configured delay. V1 favors wide ranges and low churn.

### 10.7 USDG lending

1. USDGYieldSleeve deposits USDG into the configured lending adapter.
2. Plain USDG remains only while a deposit or withdrawal is in progress.
3. Adapter receipt tokens remain in the adapter or sleeve as specified by the reviewed implementation.
4. Interest increases USDGYieldSleeve share value.
5. If liquidity becomes unavailable, new deposits pause and the adapter becomes queued or exit-only.
6. NFT burn remains available because it transfers USDGYieldSleeve shares rather than forcing a USDG withdrawal.

### 10.8 NFT burn and redemption

The core redemption is one atomic transaction:

1. Verify caller owns the NFT and snapshot the beneficiary.
2. Settle every pending distribution asset for the token ID.
3. Snapshot the account's tracked asset balances.
4. If `liveSupply > 1`, calculate `tax = balance * 500 / 10_000` for each asset.
5. Mark token burning, burn the NFT, and decrement `liveSupply`.
6. Transfer each tax amount to the distributor and accrue it using the new live supply.
7. Transfer each remaining balance to the beneficiary.
8. Close the deterministic account permanently.

No oracle, swap, lending withdrawal, Delta call, or LP unwind occurs.

When `liveSupply == 1`:

1. Distributor settles the last token's claims and sweeps all distribution dust into its account.
2. Exit tax is zero.
3. NFT burns and every tracked asset transfers to the beneficiary.
4. Collection state becomes `CLOSED`.

### 10.9 Sleeve unwrapping after burn

After receiving sleeve shares, the former NFT holder may:

- keep or transfer the shares;
- redeem Core Sleeve shares for Stock Tokens in kind;
- redeem Market-Making Sleeve shares through available strategy liquidity;
- redeem USDGYieldSleeve shares for USDG when `maxWithdraw` permits; or
- join a withdrawal queue for an illiquid strategy.

An optional stateless UI router may combine burn and sleeve redemption atomically. If any sleeve redemption fails, the whole convenience transaction reverts and the NFT remains unburned.

## 11. Distributor accounting

The distributor uses `RAY = 1e27` precision.

For distribution asset `a`:

```text
accPerLiveNftRay[a]
debtRay[tokenId][a]
totalReceived[a]
totalSettled[a]
```

When `amount` is received for `n = liveSupply`:

```text
indexIncrease = floor(amount * RAY / n)
accPerLiveNftRay[a] += indexIncrease
allocated = floor(indexIncrease * n / RAY)
dust += amount - allocated
```

For one token:

```text
pendingRay = accPerLiveNftRay[a] - debtRay[tokenId][a]
claimable = floor(pendingRay / RAY)
debtRay[tokenId][a] += claimable * RAY
```

Updating debt by the claimed whole-token amount, rather than setting it to the full accumulator, preserves the token's fractional entitlement.

At mint, debt is initialized to the then-current accumulator so new NFTs cannot claim old revenue. In the required all-or-refund sale, ordinary ongoing distributions begin only after all 3,000 NFTs exist.

### Distributor solvency invariant

For every asset:

```text
actual balance >= total allocated but unsettled claims + tracked dust
```

Every accrue operation measures actual received balance. A caller cannot increase the accumulator by reporting an amount that was not transferred.

## 12. Sleeve share accounting

### 12.1 General rule

Shares represent pro-rata ownership of all sleeve inventory, including:

- idle accounting asset;
- adapter shares or receipts;
- underlying positions;
- uncollected fees;
- claimed rewards;
- streamed rewards that are earned but not yet claimable; and
- realized losses.

No sleeve promises a non-decreasing share price.

### 12.2 Deposit

```text
shares = assetsValueUsd18 * totalSupply / totalAssetsUsd18
```

If `totalSupply == 0`, use seeded virtual assets/shares or a reviewed minimum-liquidity mechanism. User-supplied `minShares` protects against price and donation manipulation.

### 12.3 In-kind redemption

For liquid inventory asset `x`:

```text
amountOut[x] = balance[x] * sharesBurned / totalSupplyBefore
```

Strategy positions that cannot synchronously split remain represented by residual sleeve shares or a queued claim. NFT redemption never assumes synchronous sleeve redemption.

## 13. Oracle and market safety

### 13.1 Stock Token valuation

- Use the multiplier-adjusted onchain Chainlink feed exactly once.
- Never apply ERC-8056 `uiMultiplier()` again to that adjusted feed.
- Robinhood REST prices are metadata and halt context only; contracts do not trust them for settlement.
- Reject nonpositive, stale, or paused answers.
- Stock Token feeds are treated as 24/5. Weekend price-dependent operations stop.
- In-kind transfer and NFT burn do not require a price.

### 13.2 Delta range safety

- Approved pool and canonical tokens only.
- Nonzero minimum token amounts and deadline on every position operation.
- Chainlink/reference price and pool TWAP must agree within policy.
- Current tick must be inside configured bounds when minting.
- Range widths, tick spacing, and maximum position value are policy-capped.
- Out-of-range status is reported separately from yield.

### 13.3 Circuit breakers

PriceHub returns explicit failure reasons. Strategy actions fail closed for:

- stale feed;
- corporate-action pause;
- excessive reference/TWAP deviation;
- missing sequencer/chain-health confirmation;
- unsupported asset;
- price age outside heartbeat plus grace; or
- emergency guardian pause.

These conditions cannot stop NFT transfer, settlement, core burn, or in-kind sleeve-share delivery.

## 14. Authority model

| Actor | Allowed | Forbidden |
|---|---|---|
| NFT holder | Transfer NFT; settle; burn; redeem received sleeve shares | Withdraw account assets without burning; select arbitrary strategies |
| Anyone/keeper | Settle; process revenue legs; harvest/rebalance within policy; execute expired reserve sweep | Choose arbitrary pool, route, asset, amount, or recipient |
| Creator | Receive immutable revenue share; propose policy action | Withdraw backing; change holder economics; bypass timelock |
| Sinjoh | Receive immutable fee; publish reviewed global adapter entries | Activate adapter for a collection unilaterally; seize backing |
| CollectionTimelock | Activate reviewed adapters; set bounded caps; migrate feeds/constituents | Change supply, category weights, fee splits, exit tax, or beneficiary rules |
| Guardian | Pause deposits/rebalances; place adapter exit-only; trigger de-risk to sleeve | Transfer backing to any external recipient; resume a retired adapter |
| Operations multisig | Spend non-backing reserve and pay capped keepers | Spend treasury backing or distributor assets |

Recipient address rotation for creator, Sinjoh, and operations uses two-step propose/accept. Rotating a recipient changes only where its future non-backing allocation goes.

## 15. Strategy adoption process

Adding USDG lending or another strategy follows the same process:

1. Deploy a new immutable adapter bound to the target sleeve.
2. Verify source and publish compiler settings, runtime code hash, ABI, audit hash, and external dependency addresses.
3. Register the adapter globally as `REGISTERED`.
4. Collection timelock proposes activation with allocation cap, loss limit, and data hash.
5. Wait at least seven days.
6. Re-check runtime code hash, underlying asset, proxy implementation/admin if any, oracle, and withdrawal behavior.
7. Activate in `CANARY` with no more than 2% total collection exposure.
8. Observe at least one complete deposit, interest/fee accrual, partial withdrawal, full withdrawal, pause, and failure-recovery cycle.
9. Timelock may promote to `ACTIVE` within the immutable sleeve maximum.
10. Any mismatch places the adapter directly into `EXIT_ONLY`.

New strategies inside the existing three categories do not change NFT accounts or distributor assets. A completely new risk category requires a new collection version; v1 holders cannot be silently opted into a different category.

## 16. Failure handling

### 16.1 Revenue leg failure

- Successful split legs remain complete.
- Failed NFT allocation leg is escrowed by asset, sleeve, route version, and amount.
- Anyone may retry after the failure condition clears.
- Timelock may recover only into another current portfolio sleeve or liquid reserve, never an arbitrary recipient.

### 16.2 Strategy loss

- Sleeve reports lower NAV and share price.
- New deposits into impaired adapter pause automatically at configured loss threshold.
- Guardian can set exit-only.
- Withdrawals realize the actual loss subject to holder `maxLossBps` or return the sleeve share unchanged.
- No `principal must be restored` invariant is allowed to create a permanent freeze.

### 16.3 Adapter or protocol pause

- Core NFT transfer, settlement, and burn continue.
- Sleeve shares remain the holder's claim.
- New deposits stop.
- Harvest, withdrawal, claim, and de-risk functions remain available where safe.

### 16.4 Bad or stale oracle

- Price-dependent actions stop.
- No stale value is silently reused as current.
- Dashboard labels NAV stale with last valid update.
- In-kind operations continue.

### 16.5 Unsupported token behavior

Fee-on-transfer, rebasing, callback-bearing, blacklistable, or nonstandard tokens are rejected unless a dedicated reviewed adapter explicitly accounts for their behavior. Every supported treasury and distribution asset must pass exact balance-delta tests.

### 16.6 Unsolicited tokens

Unsolicited tokens are not counted as backing. They are quarantined. A timelocked action may accept them into a sleeve only if they pass the normal asset review; otherwise they remain immovable or are sent to a predefined non-backing recovery recipient that can never be the administrator for supported backing assets.

## 17. Existing Sinjoh V2 reuse and required changes

### 17.1 Reuse these patterns

- OpenZeppelin ERC-721, `Clones`, `SafeERC20`, reentrancy protection, and exact balance deltas.
- `BasketVaultV2` deterministic clone initialization and bounded tracked-asset concepts.
- `BasketVaultV2` Merkle/codehash approval pattern for adapters and swaps.
- `ProjectRouterV2` versioned routes, isolated action execution, retryable escrow, and liability accounting.
- Existing TWAP price-guard and swap-adapter interfaces where their binding rules match.
- Append-only deployment manifests, provenance verification, Foundry invariant tests, SDK ABI generation, and fork rehearsal.

### 17.2 Do not reuse these contracts directly

`BasketManagerV2` and `BasketVaultV2` solve a different product:

- one primary Basket NFT per project instead of 3,000;
- one adapter instance bound to one basket vault;
- harvested yield routed to dividend/airdrop sinks instead of compounding sleeve shares;
- optional manager-driven allocation replacement;
- principal-restoration assumptions that can freeze a lossy strategy; and
- multi-step target unwinding during burn.

Yield Vaults should reuse the safety techniques, not extend those storage layouts into a different protocol.

### 17.3 Project-token revenue integration

The deployed `ProjectRouterV2` validates `FUND_PROJECT_SINK` recipients as registered modules of the same project. A separate Yield Vaults collection is not automatically a valid V2 sink.

Therefore:

- new project launches should use a successor router action such as `FUND_YIELD_VAULT_COLLECTION`, validated against `YieldVaultProtocolRegistry` and the bound `projectId`;
- external fee sources that support direct recipients may fund `CollectionRevenueRouter` directly; and
- existing immutable V2 projects require a reviewed successor revenue bridge or governance-mediated treasury route. The blueprint must not pretend direct cross-project routing already works.

## 18. Metadata, SDK, and dashboard

### 18.1 Required token view

For any token ID, the SDK/indexer exposes:

- complete NFT, account, collection, distributor, sleeve, adapter, asset, pool, feed, and position addresses;
- owner;
- settled sleeve shares;
- pending sleeve shares;
- pro-rata underlying assets by sleeve;
- current and stale NAV timestamps;
- cumulative realized revenue;
- Delta position range and in-range status;
- uncollected, claimed, and streaming rewards;
- estimated sleeve redemption outputs;
- 5% tax estimate by asset; and
- collection and strategy pause states.

### 18.2 Dynamic artwork

Artwork may derive from composition, backing growth, cumulative fees, and range status. Robinhood marks must not appear in artwork, metadata, iconography, or contract attributes. Public copy says “Stock Tokens,” not “stocks” or “tokenized equities.”

### 18.3 Indexer

All state changes emit indexed events. The indexer can rebuild state from genesis and must compare indexed liabilities with onchain balances. UI must never hide an unsupported route; a configuration visible in the UI must be executable end to end through SDK encoding, server validation, wallet simulation, and onchain execution.

## 19. Gas and scaling constraints

- No transaction loops over 3,000 NFTs.
- `settle(tokenId)` loops over at most eight distribution assets.
- `settleBatch` has a hard maximum of 20 token IDs.
- Core burn loops over at most eight account assets.
- Each sleeve supports at most eight adapters; v1 limits are lower.
- Seed capital is invested once per sleeve, not once per NFT.
- Ongoing revenue is invested once per sleeve and lazily settled.
- Account clones use deterministic minimal proxies.
- External call return data and route configuration are size-capped.
- Keeper operations expose a maximum executable amount and process bounded work.

## 20. Security invariants

The implementation and invariant suite must continuously prove:

1. `mintedSupply <= 3000` always.
2. Successful sale implies `mintedSupply == finalizedSupply == 3000`.
3. Before sale success, SaleEscrow balance covers every refundable mint payment.
4. No sale fee is released before success.
5. Every live token ID has exactly one deterministic account.
6. An account can never be initialized twice or rebound to another token ID.
7. Account backing can leave only during failed-sale refund or NFT burn.
8. NFT transfer does not change account or pending distributor balances.
9. Distributor actual balance covers all unsettled claims and tracked dust per asset.
10. An accumulator increases only after measured asset receipt.
11. A burned or refunded token can never settle future revenue.
12. Exit tax is exactly 5% per asset when more than one NFT remains.
13. Exit tax is zero for the final NFT.
14. Exit tax denominator is the live supply after the burned NFT is removed.
15. The final NFT receives all remaining distributor dust.
16. Core burn calls no strategy, swap, pool, lending market, or oracle.
17. No privileged role can choose an arbitrary backing recipient.
18. Adapter receiver is always its bound sleeve.
19. Adapter runtime code hash must match its registered hash before deposits.
20. Pausing deposits cannot pause core NFT redemption.
21. All temporary ERC-20 allowances return to zero.
22. Every swap and position operation respects route, deadline, minimum output, and price policy.
23. Sleeve total supply and pro-rata claims remain internally solvent after deposits, yield, loss, donations, and redemptions.
24. ERC-721 transfers use standard ownership semantics without a separate protocol transfer registry or attestation gate.
25. Collection top-level weights and economics cannot change after deployment.

## 21. Test blueprint

### 21.1 Unit tests

#### Collection and sale

- deterministic collection/account addresses;
- exact 3,000 cap and token-ID range;
- fixed-price payment and inexact receipt rejection;
- transfer lock during sale;
- no early fee release;
- success only at 3,000;
- complete refund path and double-refund prevention;
- recipient rotation and reserve sunset;
- invalid basis-point configuration rejection.

#### NFT and account

- mint, transfer, approvals, burn, and metadata states;
- one-time account initialization;
- account cannot call arbitrary targets;
- unsupported asset rejection;
- maximum tracked assets;
- only typed collection release;
- reentrancy from ERC-721 receiver and token callbacks.

#### Distributor

- index creation across varying amounts;
- fractional entitlement preservation;
- dust tracking;
- settlement before/after transfer;
- bounded batch behavior;
- supply changes after burns;
- terminal sweep;
- fake amount without transfer rejection;
- insolvency protection.

#### Sleeves

- first deposit and donation/inflation attack;
- share mint/burn rounding directions;
- in-kind redemption;
- realized yield and loss;
- constituent and adapter caps;
- pause/exit-only behavior;
- queued USDG withdrawal behavior.

#### Adapters

- only bound sleeve;
- only bound recipient;
- exact allowance clearing;
- exact asset and receipt movements;
- source/pool/asset binding;
- codehash mismatch;
- slippage/deadline/TWAP/oracle failures;
- partial/full exit;
- reward accounting;
- loss and illiquidity handling.

#### Redemption

- settle then burn;
- exact per-asset 5% tax;
- no oracle/strategy call;
- tax redistributed to remaining token IDs;
- final NFT zero tax and dust sweep;
- malicious token reentrancy;
- repeated burn rejection.

### 21.2 Fuzz tests

- arbitrary sequences of mint, sale success/failure, distribute, settle, transfer, and burn;
- arbitrary revenue and tax amounts near rounding boundaries;
- arbitrary live-supply reductions from 3,000 to zero;
- arbitrary sleeve gains and losses;
- arbitrary adapter state transitions;
- arbitrary feed ages and price deviations;
- arbitrary batch sizes at and above limits.

### 21.3 Stateful invariants

Implement a handler that continuously performs:

```text
fund -> distribute -> settle -> transfer -> harvest -> loss -> pause -> burn
```

and asserts all 25 security invariants after every operation.

### 21.4 Integration tests

- full 3,000-mint sale finalization within Robinhood Chain gas limits using bounded settlement;
- project-token fee source to revenue router;
- royalty source to distributor;
- Core Sleeve swap and in-kind redemption;
- USDGYieldSleeve with an ERC-4626 lending mock and queued mock;
- MarketMakingSleeve with a Uniswap v3/Delta position mock;
- strategy canary, activation, pause, exit-only, and retirement;
- core burn while every external strategy is reverting;
- SDK transaction encoding and emitted-event decoding.

### 21.5 Fork tests

On Robinhood Chain testnet and then pinned mainnet forks:

- WETH `0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73` behavior;
- USDG `0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168` behavior;
- selected Stock Token contracts and Chainlink feeds;
- selected pools and liquidity;
- Delta position builder `0x6235cF6bd8419b34942F4EDDB39C880BD96dD700`;
- weekend/stale feed behavior;
- corporate-action pause behavior;
- position mint, fee collect, range exit, rebalance, and full close;
- RPC failover and event-index replay.

### 21.6 Release tests

- compiler and dependency lock verification;
- deployment-manifest schema validation;
- runtime codehash verification for every external integration;
- deterministic address prediction versus deployed result;
- Blockscout source verification;
- UI/SDK route parity;
- wallet simulation for every visible action;
- post-deploy canary and balance/liability reconciliation.

Coverage target: 100% of reachable branches in core custody, accounting, sale, and redemption contracts. External adapters require complete happy, revert, partial, stale, loss, and recovery coverage.

## 22. Proposed source layout

```text
sinjoh-contracts-v2/src/yield-vaults/
├── YieldVaultTypes.sol
├── YieldVaultProtocolRegistry.sol
├── YieldVaultCollectionFactory.sol
├── YieldVaultCollection.sol
├── YieldVaultNFT.sol
├── YieldVaultAccount.sol
├── SaleEscrow.sol
├── YieldVaultDistributor.sol
├── CollectionRevenueRouter.sol
├── OperationsReserve.sol
├── StrategyRegistry.sol
├── PriceHub.sol
├── interfaces/
│   ├── IYieldVaultAccount.sol
│   ├── IYieldVaultCollection.sol
│   ├── IYieldVaultFundable.sol
│   ├── IYieldVaultSleeve.sol
│   ├── IStrategyAdapter.sol
│   └── IPriceHub.sol
├── sleeves/
│   ├── BaseSleeve.sol
│   ├── CoreStockTokenSleeve.sol
│   ├── MarketMakingSleeve.sol
│   └── USDGYieldSleeve.sol
├── adapters/
│   ├── USDGLendingAdapter.sol
│   └── DeltaV3StrategyAdapter.sol
└── libraries/
    ├── YieldVaultIds.sol
    ├── DistributionMath.sol
    ├── SleeveAccounting.sol
    └── IntegrationBinding.sol
```

Tests mirror this tree under `sinjoh-contracts-v2/test/yield-vaults/`, with unit, fuzz, invariant, integration, and fork directories.

## 23. Implementation sequence

### Phase 0: launch prerequisites

- confirm initial three Stock Tokens and feeds;
- obtain the complete Delta LP, staking, reward, streaming, and exit dependencies;
- resolve the Robinhood Chain operational health circuit breaker;
- freeze collection economics and manifest schema.

### Phase 1: core custody and sale

- types and interfaces;
- protocol registry and factory;
- NFT, deterministic account, SaleEscrow, collection state machine;
- fixed-price 3,000 sale success/failure;
- atomic sleeve-share burn path using mock sleeve tokens.

Exit criterion: sale and redemption invariants pass under arbitrary stateful fuzzing with all strategy calls forced to revert.

### Phase 2: distribution and revenue

- accumulator distributor;
- portfolio allocation;
- revenue router and operations reserve;
- secondary royalty and direct contribution flows;
- successor project-token revenue bridge design.

Exit criterion: exact solvency and tax redistribution from 3,000 NFTs down to the final NFT.

### Phase 3: sleeves

- BaseSleeve accounting;
- CoreStockTokenSleeve;
- MarketMakingSleeve;
- USDGYieldSleeve;
- PriceHub and market-state hooks.

Exit criterion: gain, loss, donation, pause, in-kind, queued, and terminal cases pass.

### Phase 4: adapters

- selected USDG lending adapter;
- DeltaV3StrategyAdapter with staking and reward streaming;
- strategy registry and canary lifecycle.

Exit criterion: full fork rehearsal and independent adapter audit.

### Phase 5: product integration

- SDK types, reads, writes, and manifest validation;
- indexer and proof-of-backing API;
- mint, portfolio, revenue, strategy, transfer, and burn UI;
- dynamic metadata renderer;
- monitoring and keeper service.

Exit criterion: every UI-visible configuration executes end to end through SDK encoding, server validation, wallet simulation, onchain execution, and browser QA.

### Phase 6: release

- testnet 3,000-token load rehearsal;
- independent full-system audit;
- mainnet deployment manifest and source verification;
- capped strategy canaries before full allocation;
- production balance/liability monitor;
- incident runbooks and guardian rehearsal.

## 24. Deployment manifest

The collection release manifest records complete addresses and code hashes for:

- factory and implementation version;
- collection, NFT, account implementation, SaleEscrow, distributor, revenue router, operations reserve, and timelock;
- each sleeve and adapter;
- WETH, USDG, every Stock Token, every price feed, every pool, every router, every position manager, and the Delta builder;
- creator, Sinjoh, operations, guardian, and timelock recipients;
- compiler, optimizer, source commit, dependency lock hashes, audit hashes, and deployment transaction hashes;
- all immutable economic parameters and policy caps.

The SDK refuses to operate against a collection whose manifest code hashes do not match onchain runtime code.

## 25. Acceptance criteria

The protocol is ready for production only when all are true:

1. A successful collection always contains exactly 3,000 funded NFTs.
2. A failed sale refunds every buyer 100% and pays no launch fee.
3. Every token ID has a deterministic isolated account and exact pending accounting.
4. One seed allocation and one revenue allocation can serve all 3,000 NFTs without a supply-sized transaction.
5. Adding a USDG lending adapter requires no NFT or account migration.
6. Every new adapter passes registration, timelock, canary, cap, pause, exit-only, and retirement flows.
7. NFT burn succeeds while every external protocol, oracle, and adapter is reverting.
8. Burn transfers exact net assets and redistributes exact tax assets.
9. The final NFT receives all residual value and closes the collection.
10. No privileged path can transfer backing to an arbitrary recipient.
11. The proof-of-backing view reconciles distributor liabilities, account balances, sleeve shares, and underlying positions.
12. Complete addresses and verified code hashes are published for every onchain dependency.
13. NFT transfers use standard ERC-721 ownership semantics without a separate protocol transfer gate.
14. Independent audits find no unresolved critical or high-severity issue.
15. UI, SDK, contracts, keepers, indexer, and release manifest pass route-parity and recovery rehearsals.

## 26. Explicitly out of scope for v1

- holder-selected per-NFT strategy weights;
- leverage, borrowing against NFT treasuries, or recursive lending;
- one directly managed Delta range per NFT;
- guaranteed yield or principal protection;
- unrestricted transfer of Stock Token-backed claims;
- more than three portfolio sleeve categories;
- performance fees;
- cross-chain treasury positions;
- arbitrary account execution;
- governance that can rewrite collection economics;
- automatic conversion of every redemption into WETH.

These require a new collection version or a separately approved product, not a silent upgrade to this collection.

## 27. Founder-level product summary

Each of the 3,000 NFTs owns shares in three permanent portfolio sleeves. The sleeves can adopt better lending markets, LP systems, and approved Stock Token constituents over time without migrating the NFTs. Collection revenue buys more sleeve shares for every live token. The account and its pending claims follow the NFT on transfer. Burning the NFT atomically releases its share assets and leaves 5% for the remaining collection.

The ownership system is permanent. The earning engines are modular. External failures can reduce value, but they cannot give an operator custody or trap the NFT's core redemption right.
