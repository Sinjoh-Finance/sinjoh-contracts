# SinjohFundingBands

An immutable, creator-controlled inventory ladder for verified Robinhood Chain launches.
A recognized launch creator commits subject tokens to as many as ten one-sided
concentrated-liquidity positions above the launch price. As demand trades through a
position, the committed subject inventory converts into the pool's quote currency. Once
the position has fully crossed, anyone can settle it and deliver the proceeds to either
the creator or a bound `SinjohFeeRouter`.

`SinjohFundingBands` deploys inventory. `SinjohLiquidityManager` remains responsible for
deploying ongoing revenue flow into permanent full-range liquidity.

## First-release scope

- Robinhood Chain mainnet, chain ID `4663`.
- Canonical Uniswap v3 and v4 deployments.
- Launch profiles for Pons v1 (v3), Pons v2 (v4), pools.trade (v4), and letscash.fun
  (v4).
- Canonical WETH or native ETH as the pool quote currency.
- Native ETH collected from v4 is wrapped into canonical WETH.
- One verified creator account and one band set per launched subject.
- Between one and ten immutable bands per account.
- Creator-only registration and funding.
- Permissionless settlement and proceeds delivery.

For Pons v2, registration and funding are available only after the canonical
launch record reaches `GraduationPhase.PoolCreated`; before graduation there is
no Uniswap v4 pool in which to place a funding band. A launch UI may persist an
offchain draft, but that draft is not committed inventory.

A launch profile is not production-supported until its deployed factory, pool identity,
hook behavior, and creator records pass Robinhood mainnet fork tests. Sharing the
canonical PoolManager does not imply hook compatibility.

## Launch verification

The creator cannot nominate an arbitrary token or pool. Each supported launchpad has an
immutable verifier that resolves:

```solidity
enum Venue {
    UNISWAP_V3,
    UNISWAP_V4
}

struct VerifiedLaunch {
    address creatorAtLaunch;
    address subject;
    Venue venue;
    address quoteAsset;     // WETH or address(0) for native ETH
    address pool;           // v3 pool; zero for v4
    uint24 poolFee;
    int24 tickSpacing;
    address hooks;          // zero for v3
    bytes32 poolId;         // zero for v3
    uint256 launchSupply;
}
```

Registration requires:

- `msg.sender == creatorAtLaunch`;
- the launch record comes from an immutable supported verifier;
- the subject and pool match the canonical launchpad record;
- the pool resolves through the canonical Uniswap factory or `PoolKey`;
- quote currency is canonical WETH or native ETH;
- the pool is initialized;
- launch supply is nonzero;
- the subject is a standard, fixed-balance ERC-20;
- the deployment chain ID is `4663`.

The launch creator is snapshotted permanently. Later launchpad creator or fee-recipient
changes do not transfer control of the Funding Bands account.

Pons v2's launch record does not retain the token's original configured supply.
After verifying the factory record and the token's factory, deployer, and curve
self-attestation, its profile snapshots the current ERC-20 `totalSupply()` at
registration. Any voluntary holder burn before registration therefore reduces
the market-cap denominator used for that account.

Supported verifier addresses are frozen when `SinjohFundingBands` is deployed. Supporting
another launchpad requires a new deployment.

## Band configuration

```solidity
enum Destination {
    CREATOR,
    FEE_ROUTER
}

struct BandConfig {
    uint128 lowerMarketCapUsdE8;
    uint128 upperMarketCapUsdE8;
    Destination destination;
    address feeRouter; // zero for CREATOR
}
```

Rules:

- There must be between one and ten bands.
- `lowerMarketCapUsdE8 < upperMarketCapUsdE8`.
- Bands are ordered by increasing market cap and cannot overlap.
- Gaps are allowed.
- Every lower boundary must be above the validated current market cap.
- Tick-spacing rounding cannot collapse two economic boundaries onto one usable tick.
- Destination is immutable per band.
- `CREATOR` resolves permanently to `creatorAtLaunch` and requires a zero `feeRouter`.
- `FEE_ROUTER` requires a deployed router whose `creator()` and `subject()` match the
  verified launch, whose runtime code hash matches the manager's immutable audited
  Sinjoh Fee Router clone hash, and whose intake assets include both WETH and the subject.

Per-band destinations allow some bands to pay the creator while others feed buybacks,
burns, liquidity, or another immutable policy through a router.

## Market-cap conversion

Registration snapshots:

- launch supply;
- subject-token decimals;
- ETH/USD oracle answer and timestamp;
- requested USD market-cap boundaries;
- effective WETH-denominated boundaries after tick rounding.

The oracle is immutable and its round must be positive, complete, and no older than the
protocol maximum.

Each USD market-cap range is converted once into a token/WETH range:

```text
tokenUsdPrice = marketCapUsd / launchSupply
tokenWethPrice = tokenUsdPrice / ethUsdPrice
```

The position remains fixed in token/WETH terms afterward. It is not repositioned when
ETH/USD changes. Events and views expose the requested USD boundaries, the snapshotted
ETH/USD value, the effective WETH boundaries, and the usable Uniswap ticks. Interfaces
must disclose that the band's live USD equivalent changes with ETH/USD after registration.

Address ordering is handled internally. For subject-as-token0 pools, increasing subject
value moves toward higher ticks. For subject-as-token1 and native-ETH v4 pools, it moves
toward lower ticks. Callers never provide or interpret raw ticks.

## Registration

```solidity
function create(
    address subject,
    uint8 profileId,
    BandConfig[] calldata bands,
    bytes calldata launchData,
    bytes calldata guardData
) external returns (bytes32 accountId);
```

`launchData` and `guardData` are each capped at 1,024 bytes. `guardData` carries the
profile-specific reference-price evidence required to prove every lower boundary is
above the current market during registration.

Registration:

1. resolves the canonical launch and creator;
2. verifies `msg.sender` is the launch creator;
3. snapshots supply and ETH/USD;
4. converts market caps to usable ticks;
5. validates the current spot and manipulation-resistant reference price are below every
   band;
6. freezes all configuration;
7. emits every requested and effective boundary.

Registration may occur without immediately funding every band.

## Funding

```solidity
struct BandFunding {
    uint8 bandId;
    uint128 amount;
}

function fund(
    address subject,
    BandFunding[] calldata funding,
    bytes calldata guardData
) external returns (uint256 totalReceived);
```

Rules:

- Only the snapshotted creator may fund.
- A call contains between one and ten unique band IDs.
- Every amount is nonzero.
- Exact balance-delta accounting is required.
- Fee-on-transfer and rebasing tokens are unsupported.
- Direct token transfers create no credit and are stranded.
- Funding and position mint or increase happen atomically.
- A band may receive later deposits only while both the guarded reference and pool spot
  remain below its economic lower boundary.
- Once price enters or passes a band, that band can never receive more inventory.
- Deposited inventory cannot be withdrawn, reassigned, or moved to another band.
- Callers cannot provide a pool, ticks, recipient, hook, route, or PositionManager.
- Approvals are exact and reset to zero after execution.

The first successful funding creates one position for the band. Later funding increases
that same position. A band never accumulates multiple position NFTs. Token rounding
residuals remain attributed to that band and cannot be withdrawn before settlement.

## Position custody

The manager holds every position NFT. It accepts an NFT only:

- from the canonical v3 or v4 PositionManager;
- while an internal mint expectation is active;
- for the band currently being funded.

There is no function capable of transferring or approving a position, decreasing an
active band before settlement, changing ticks or destination, withdrawing committed
inventory, or making an arbitrary external call.

## Settlement guard

```solidity
function settle(
    address subject,
    uint8 bandId,
    bytes calldata guardData
) external;
```

Settlement is permissionless. A launch-profile-specific guard must prove:

- pool spot has crossed the economic upper boundary;
- a manipulation-resistant reference price has also crossed it;
- the observation is fresh;
- the pool is unlocked and initialized;
- the position's principal is entirely quote currency at the validated price.

The v3 profile uses canonical pool observations and a bounded TWAP. Each v4 profile must
use the launchpad hook's verified observation mechanism or another immutable
manipulation-resistant reference. A generic spot-only v4 profile is forbidden. If a
launchpad cannot provide a safe reference, its profile cannot be activated.

Settlement then:

1. removes 100% of the band's liquidity;
2. collects all principal and accumulated LP fees;
3. burns or closes the empty position;
4. measures actual subject, native ETH, and WETH received;
5. wraps native ETH into canonical WETH;
6. charges the protocol fee on realized WETH;
7. credits net WETH and subject-denominated LP fees or rounding residuals to the immutable
   destination;
8. marks the band permanently settled.

If price reverses before the guard passes, the band remains active and may convert back
toward subject tokens. At a valid settlement boundary, subject principal must be zero.
Any subject received therefore consists of LP fees or rounding residuals, is delivered in
kind, and is not included in realized WETH.

## Protocol fee

The Funding Bands protocol fee is exactly 100 basis points of cumulative realized WETH
per band:

```text
cumulativeFee = floor(cumulativeRealizedWeth * 100 / 10_000)
incrementalFee = cumulativeFee - previouslyChargedFee
```

This prevents transaction splitting or multiple collection legs from reducing the fee.

No Funding Bands fee is charged on deposited subject tokens, unrealized position value,
subject-denominated LP fees, rounding residuals, or delivery retries.

For a router destination, Funding Bands credits 99% of realized WETH to the router. A
later `router.sync(WETH)` treats delivery as new router intake and charges the router's
separate 1% service fee. The combined effective protocol fee is therefore 1.99% of the
original gross WETH.

## Liabilities and delivery

Settlement never depends on the recipient accepting an immediate transfer.

```solidity
function sendProceeds(
    address subject,
    uint8 bandId,
    address asset,
    uint256 amount
) external;

function sendProtocolFee(uint256 amount) external;
```

Both functions are permissionless but use fixed destinations. Band proceeds can only go
to that band's creator or router. Protocol fees can only go to the immutable protocol-fee
recipient. Router delivery does not call `sync()`; synchronization remains a separate
permissionless operation and failure domain.

For every held asset:

```text
totalLiability[asset]
  = sum(bandProceedsOwed[band][asset])
  + protocolOwed[asset]

balance(manager, asset) >= totalLiability[asset]
```

Position principal held by Uniswap is excluded from liquid liabilities. Every transfer
uses measured balance deltas. A failed delivery changes no liability and cannot block
another band.

## Band lifecycle

```text
CONFIGURED
    |
    | first successful funding
    v
ACTIVE  <---- later funding allowed only before lower boundary
    |
    | guarded upper-bound crossing
    v
SETTLED
    |
    | permissionless proceeds delivery
    v
DELIVERED
```

A configured but unfunded band that reaches its lower boundary becomes permanently
unfundable. A settled band cannot be reopened or reused.

## Hook compatibility

Before activating any v4 launch profile, fork tests must prove:

1. third-party one-sided position mint succeeds;
2. position increase succeeds;
3. full decrease and collection succeed;
4. empty-position closure succeeds;
5. required hook data is supplied correctly;
6. native and ERC-20 settlement deltas are correct;
7. no hook state transition can redirect proceeds;
8. guard observations remain valid across relevant hook states;
9. the hook cannot make an active position irrecoverable under documented behavior.

Pons v2, pools.trade, and letscash.fun each require an independent profile and test suite.

## Security requirements

- Reentrancy guard around every external-call entry point.
- Account-scoped and band-scoped accounting.
- Exact transfer and settlement balance deltas.
- Immutable chain ID, WETH, PositionManagers, PoolManager, factory, oracle, Fee Router
  runtime hash, profiles, and protocol recipient.
- Exact allowances reset after use.
- No owner, upgrade, admin, pause, rescue, or arbitrary call.
- No caller-selected pool, ticks, hook, verifier, destination, or price source.
- Maximum ten bands bounds storage, loops, and settlement work.
- Canonical contracts asserted by chain ID and deployment-time code hash.
- ETH/USD snapshot rejects stale, negative, or incomplete oracle rounds.
- Unsolicited NFTs and direct token transfers cannot create ownership credit.
- Standard ERC-20 subject tokens only.
- Every irreversible funding interface requires explicit acknowledgement.

## Required tests

1. Non-creator registration and funding revert.
2. A launchpad creator change does not change the snapshotted controller.
3. An arbitrary pool or counterfeit launch record cannot register.
4. Between one and ten bands succeed; zero or eleven bands revert.
5. Unordered, overlapping, collapsed, or below-market ranges revert.
6. USD-to-WETH conversion handles token ordering and token decimals.
7. Stale, negative, or incomplete ETH/USD rounds revert.
8. ETH/USD movement after creation does not move stored ranges.
9. Exact initial funding mints one one-sided position per funded band.
10. Later funding increases the existing position.
11. Funding after the lower boundary is entered reverts.
12. One band cannot spend another band's inventory or residual.
13. Deposited inventory cannot be withdrawn or reassigned.
14. Fee-on-transfer funding reverts without credit.
15. Direct transfers cannot be attributed to a creator or band.
16. Spot-only manipulation cannot satisfy the settlement guard.
17. Settlement before the validated upper crossing reverts.
18. Valid settlement removes all liquidity and closes the position.
19. Native ETH proceeds are wrapped into canonical WETH.
20. The protocol receives exactly 1% of cumulative realized WETH.
21. Splitting collection or delivery cannot reduce the protocol fee.
22. Subject-denominated LP fees are delivered in kind without a Funding Bands fee.
23. Failed creator or router delivery preserves liabilities.
24. Router delivery cannot target a router bound to another creator or subject.
25. No NFT transfer, approval, partial decrease, rescue, or arbitrary call exists.
26. Aggregate liabilities always equal detailed liabilities.
27. Liquid liabilities never exceed liquid balances.
28. Maximum-sized creation and funding fit Robinhood Chain's transaction gas limit.
29. Robinhood mainnet fork tests cover Pons v1, Pons v2, pools.trade, and letscash.fun.
30. Every supported v4 hook passes the compatibility suite.

## Out of scope

- Web UI.
- Keeper and indexer integration.
- Mainnet deployment or activation.
- Arbitrary user-created Uniswap pools.
- Non-WETH or non-native quote currencies.
- Moving USD-pegged ranges after ETH/USD changes.
- Rebalancing active positions.
- Editing or cancelling bands.
- Withdrawing committed subject inventory.
- Selling with market orders.
- Implementing buyback-and-burn logic inside Funding Bands.
- Supporting a launchpad profile before its live contracts and hooks pass fork
  verification.

## Rollback model

Before mainnet deployment, rollback is a source-code revert. After deployment there is no
upgrade or administrative rollback. A defective deployment must be abandoned and
replaced. Inventory already committed to an active band remains governed by that
deployment and cannot be rescued.
