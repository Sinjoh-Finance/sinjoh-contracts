# SinjohLiquidityManager

An immutable sink that accepts one configured quote asset, swaps a fixed bounded share into a subject token, and mints or increases a full-range Uniswap position that can never be withdrawn or transferred.

The manager is standalone. An EOA, treasury, or `SinjohFeeRouter` can fund it without importing another Sinjoh contract.

## Safety model

For each account:

```text
accountId = keccak256(abi.encode(funder, subject))
```

The account owns:

- immutable pool and execution configuration;
- pending quote-asset credit;
- pending subject-token credit;
- one permanent position identifier once minted;
- fee credits that have not yet been delivered.

Global token balances are never treated as ownership. The manager maintains `totalLiability[asset]` in constant time alongside detailed account credits and fee liabilities.

## Atomic funding interface

```solidity
interface ISinjohSink {
    function fund(
        address subject,
        address asset,
        uint256 amount,
        bytes calldata config
    ) external payable returns (uint256 received);
}
```

`msg.sender` is the funder.

For ERC-20 funding:

1. `msg.value` must be zero;
2. the manager records its balance before the transfer;
3. it calls `safeTransferFrom(msg.sender, address(this), amount)`;
4. it records the balance after the transfer;
5. `received` must equal `amount`.

For native ETH:

- `asset == address(0)`;
- `msg.value == amount`;
- `received == amount`.

Every successful receipt increases both `pendingQuote[accountId]` and
`totalLiability[asset]` by `received`.

A separate token transfer is never attributed to a funder and cannot be referenced by `fund`. Unsupported direct transfers are stranded.

Fee-on-transfer and rebasing tokens are unsupported.

## First-fund registration

The first successful `fund()` for an account decodes and freezes:

```solidity
enum Venue {
    UNISWAP_V3,
    UNISWAP_V4
}

enum FeeMode {
    CREATOR,
    TREASURY,
    RECYCLE,
    FUNDER
}

struct Config {
    Venue venue;
    address quoteAsset;
    uint24 poolFee;
    int24 tickSpacing;
    address hooks;              // zero for v3
    address swapAdapter;
    address priceGuard;
    bytes swapRouteData;
    uint16 quoteSwapBps;        // fixed share of each mint notional
    uint16 maxMintSlippageBps;
    uint128 minNotionalPerMint;
    uint128 maxNotionalPerMint;
    uint48 minMintInterval;
    FeeMode feeMode;
    address feeRecipient;       // required for CREATOR/TREASURY
}
```

Requirements:

- `asset == quoteAsset`;
- subject and quote asset differ;
- `swapRouteData.length` is nonzero and at most 1,024 bytes;
- `quoteSwapBps` is between 4,500 and 5,500;
- `maxMintSlippageBps` is bounded by a protocol constant;
- minimum notional is nonzero and no greater than maximum;
- v3 requires zero hook and non-native quote;
- v4 requires the exact hook from the intended `PoolKey`;
- swap adapter, guard, and route data are nonzero/nonempty unless subject credit can arrive without a swap in a later supported version;
- fee recipient is nonzero when required.

The manager stores `configHash = keccak256(canonicalConfigEncoding)`.

Every later funding call must provide configuration with the same hash. This keeps the router-to-sink call stateless while preventing a later caller from changing the account.

## Pool resolution

Pool identity is derived from immutable configuration, but existence is read from canonical contracts.

### Uniswap v3

The manager calls the configured canonical factory:

```solidity
factory.getPool(token0, token1, poolFee)
```

It does not hard-code or reproduce the pool init-code hash.

### Uniswap v4

The manager constructs the sorted `PoolKey`:

```solidity
PoolKey({
    currency0: min(subject, quoteAsset),
    currency1: max(subject, quoteAsset),
    fee: poolFee,
    tickSpacing: tickSpacing,
    hooks: hooks
})
```

and derives `PoolId = keccak256(abi.encode(poolKey))`.

Native ETH is represented by the zero address and therefore sorts as `currency0`.

Registration and funding may occur before initialization. `mint()` reverts with `PoolNotInitialized` and leaves account credit untouched until the pool exists.

## Full-range position

The only allowed ticks are:

```text
tickLower = TickMath.minUsableTick(tickSpacing)
tickUpper = TickMath.maxUsableTick(tickSpacing)
```

Callers cannot provide ticks.

The first mint creates one position NFT for the account. Later mints increase that same position. The account never accumulates an unbounded NFT set.

The manager implements `IERC721Receiver` and accepts a safe-minted NFT only:

- from the configured canonical v3 PositionManager;
- while an internal `expectingPosition` flag is set;
- for the account currently being minted.

Pons' v3 PositionManager directly mints rather than safe-minting. The manager
supports both behaviors, but after every v3 mint it requires the canonical
PositionManager's `ownerOf(tokenId)` to equal the manager. All unsolicited safe
transfers revert. V4 ownership is fixed by the canonical PositionManager action's
recipient and checked in live integration tests.

## Guarded swap

Callers do not choose a pool, path, adapter, route, or swap share.

For a requested mint notional:

```text
quoteToSwap = notional * quoteSwapBps / 10_000
quoteLiquidityBudget = notional - quoteSpent
```

The immutable adapter executes the immutable route. The immutable price guard
returns the minimum acceptable output and expiry for either direction of its
bound subject/quote pair. The liquidity manager uses quote-to-subject; the fee
router may use the same oracle boundary for subject-to-quote normalization.

```solidity
interface ISinjohPriceGuard {
    function validatePoolPrice(
        address subject,
        address assetIn,
        address assetOut,
        uint160 venueSqrtPriceX96
    ) external view;

    function minimumOutput(
        address subject,
        address assetIn,
        address assetOut,
        uint256 amountIn,
        bytes32 routeHash,
        bytes calldata guardData
    ) external view returns (uint256 minOut, uint48 validUntil);
}
```

The manager calls `validatePoolPrice` before the swap and again before minting.
The guard rejects both the anchor-pool spot and the target venue's supplied spot
when either lies outside its configured TWAP deviation.

The v3 executor fixes router, factory, pool, input, output, and fee in constructor
immutables and exposes only `exactInputSingle`. The v4 executor fixes a hookless
PoolKey, authenticates the PoolManager unlock callback, requires exact input
settlement, and sends output only to its caller. Both require canonical
`abi.encode(uint160(sqrtPriceLimitX96))` route data and retain no swap balances.

The caller may supply a stricter minimum, never a weaker one:

```text
enforcedMinOut = max(guardMinOut, callerMinOut)
```

The manager verifies its own quote-asset decrease and subject-token balance increase. Adapter return values are ignored.

The measured quote amount spent must equal `quoteToSwap`; otherwise the call reverts.
It decreases both `pendingQuote[accountId]` and
`totalLiability[quoteAsset]`. The measured subject amount received increases both
`pendingSubject[accountId]` and `totalLiability[subject]`.

Approvals are exact and reset to zero after execution.

## Minting

```solidity
function mint(
    address funder,
    address subject,
    uint256 notional,
    uint256 callerMinOut,
    bytes calldata guardData
) external returns (uint256 tokenId, uint128 liquidity);
```

`mint()` is permissionless.

`guardData` is capped at 1,024 bytes.

Rules:

1. resolve the account and verify it is registered;
2. verify the pool is initialized;
3. verify the immutable minimum interval;
4. require `minNotional <= notional <= maxNotional`;
5. require `notional <= pendingQuote`;
6. validate pool spot state through the guard;
7. swap the fixed quote share under the enforced minimum;
8. read the post-swap pool price;
9. compute the maximum full-range liquidity supported by no more than the requested
   notional’s remaining quote budget and the account’s subject credit;
10. compute `amount0Desired` and `amount1Desired` for that liquidity;
11. set minimum amounts from `maxMintSlippageBps`;
12. mint or increase through the canonical PositionManager;
13. measure actual token amounts spent and reduce only this account’s credits and
    the matching `totalLiability` entries;
14. leave all rounding residuals credited to the same account.

The contract never uses a global token balance as `amountDesired`.
The quote value consumed by the swap plus the quote value supplied to liquidity
must never exceed `notional`.

### v3 backend

The v3 backend uses canonical `NonfungiblePositionManager.mint` for the first position and `increaseLiquidity` thereafter.

It passes:

- full-range usable ticks;
- exact account-owned desired amounts;
- computed `amount0Min` and `amount1Min`;
- a short immutable maximum deadline window.

### v4 backend

The v4 backend uses canonical `PositionManager.modifyLiquidities` actions and Permit2 settlement.

The manager does **not** implement a custom `PoolManager.unlockCallback`. A future custom PoolManager backend would be a different contract and audit scope.

Actions include exact settlement and sweep of excess native ETH back into the same account ledger. No excess is left unattributed.

## Hook compatibility

A v4 hook can:

- reject liquidity;
- require hook data;
- alter fees or accounting;
- impose permission checks;
- behave differently as mutable hook state changes.

Before a v4 configuration is offered, integrators must verify the deployed hook bytecode and fork-test:

1. third-party full-range mint;
2. position increase;
3. zero-liquidity fee collection;
4. required hook data;
5. quote/subject settlement;
6. behavior after every relevant hook state transition.

pons v2 is not supported until its final hook is deployed, verified, audited, and passes these tests.

## Permanent custody

There is no function capable of:

- decreasing principal liquidity;
- burning the position;
- transferring the position;
- approving another NFT operator;
- withdrawing pending funded principal;
- sweeping account credit;
- arbitrary external calls.

The PositionManager may be called only through hard-coded mint/increase and zero-liquidity fee-collection selectors.

Funding is an irreversible contribution. If a pool never initializes or a hook never permits liquidity, the account’s credit remains pending forever. Interfaces must require explicit acknowledgement before funding a pre-pool account.

## Position fees

```solidity
function collect(address funder, address subject) external;
```

Fee collection is permissionless and always uses the zero-liquidity collection path:

- v3: `collect` without decreasing liquidity;
- v4: `DECREASE_LIQUIDITY` with zero liquidity plus `TAKE_PAIR`.

The manager measures actual received amounts. It charges no fee on funding or
position principal. For each collected asset globally, it carries fee remainders
across every account and collection so cumulative protocol fees always equal
`floor(cumulativeGrossAmount * 100 / 10_000)`. Only the net amount follows the
account's configured fee mode, and splitting collection calls or fragmenting
fees across accounts cannot reduce the fee.

Disposition:

| Mode | Accounting |
|---|---|
| `RECYCLE` | credit quote/subject proceeds back to the same account for a later mint |
| `FUNDER` | snapshot fees into `feeOwed[funder][asset]` |
| `CREATOR` | snapshot fees into `feeOwed[feeRecipient][asset]` |
| `TREASURY` | snapshot fees into `feeOwed[feeRecipient][asset]` |

Every measured fee receipt increases `totalLiability[asset]` by the gross amount.
The detailed liabilities are the net fee-mode credit plus the protocol fee.

Delivery is separate:

```solidity
function sendFee(address recipient, address asset, uint256 amount) external;
function sendProtocolFee(address asset, uint256 amount) external;
```

It is permissionless and can send only the recipient’s own liability to that recipient.
Successful delivery decreases both `feeOwed[recipient][asset]` and
`totalLiability[asset]`. A transfer failure changes neither value and cannot block
collection for another account.

`sendProtocolFee` is also permissionless but can deliver only to the immutable
`protocolFeeRecipient`. The collector receives the fee in kind.

When the funder is a `SinjohFeeRouter`, `FUNDER` sends fees back to that router. They become new router intake only when its `sync()` observes them and charges its 1% fee.

## Accounting invariants

For every asset:

```text
totalLiability[asset]
  = sum(accountPendingQuote denominated in asset)
  + sum(accountPendingSubject denominated in asset)
  + sum(feeOwed denominated in asset)
  + protocolOwed[asset]

balance(manager, asset) >= totalLiability[asset]
```

Position principal is held in the external Uniswap position and is not part of the manager’s liquid balance.

The sums define the invariant; execution uses the constant-time aggregate and never
enumerates accounts or recipients. Every external operation uses pre/post balance
deltas. A returned amount is informational only.

## Native ETH

- v3 accounts cannot use native ETH; use canonical WETH.
- v4 accounts may use native ETH as the quote currency.
- every payable entrypoint verifies exact `msg.value`;
- unexpected ETH reverts;
- v4 excess ETH is swept back and credited to the same account and aggregate
  liability;
- there is no gas reserve or caller reimbursement.

## ERC-8056

All pool math and accounting uses raw token units. `uiMultiplier()` is not called by core execution.

Interfaces may read ERC-8056 separately for display, but failure or a future draft change cannot block funding, minting, or fee collection.

## Mutability

Frozen on first successful funding:

- venue and canonical backend;
- subject and quote asset;
- pool fee, tick spacing, and hook;
- route, adapter, price guard, and route data;
- fixed swap share;
- mint slippage, notional, interval, and deadline limits;
- fee mode and recipient.

Nothing is mutable afterward. There is no owner, admin, upgrade, rescue, or arbitrary-call role.

## Security requirements

- Reentrancy guard around every entrypoint that makes an external call.
- Exact allowances, reset after use.
- Balance-delta verification on funding, swapping, minting, and collecting.
- Account-scoped accounting; never spend another account’s credit.
- Canonical PositionManager and factory addresses asserted by chain ID and code hash.
- Price guard validates both output and pre-execution spot deviation.
- No caller-selected hook, route, tick, recipient, or safety parameter.
- Subject and quote tokens must be standard, non-rebasing ERC-20s unless quote is native v4 ETH.
- Protocol fee recipient is immutable, nonzero, and cannot equal the manager.

## Required tests

1. Front-running a separate ERC-20 transfer cannot create funding credit.
2. Fee-on-transfer funding reverts without changing credit.
3. Two funders for the same subject never share credits, position IDs, or fees.
4. One account cannot spend global balances belonging to another.
5. Manipulated spot state and weak caller minimums revert.
6. Mint slippage minima are enforced on both assets.
7. Residual quote and subject amounts remain correctly credited.
8. Only one position is minted per account; later calls increase it.
9. Every withdrawal, decrease, burn, transfer, approval, and arbitrary-call attempt is impossible.
10. Hook rejection leaves account credits unchanged.
11. Fee collection cannot decrease principal liquidity.
12. Native ETH excess returns to the same account ledger.
13. Protocol fees are exactly 1% of cumulative gross LP fees collected, cannot be
    reduced by transaction splitting, and never touch principal.
14. Invariant: liquid liabilities never exceed liquid balances.
15. Invariant: aggregate liabilities equal account, recipient-fee, and protocol-fee liabilities.
16. Robinhood mainnet fork tests cover canonical v3 and v4 PositionManagers.

## Robinhood Chain mainnet dependencies

| Contract | Address |
|---|---|
| WETH | `0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73` |
| v3 NonfungiblePositionManager | `0x73991a25c818bf1f1128deaab1492d45638de0d3` |
| v3 factory | `0x1f7d7550b1b028f7571e69a784071f0205fd2efa` |
| v4 PositionManager | `0x58daec3116aae6d93017baaea7749052e8a04fa7` |
| v4 PoolManager | `0x8366a39cc670b4001a1121b8f6a443a643e40951` |
| v4 StateView | `0xf3334192d15450cdd385c8b70e03f9a6bd9e673b` |
| Universal Router | `0x8876789976decbfcbbbe364623c63652db8c0904` |
| Permit2 | `0x000000000022D473030F116dDEE9F6B43aC78BA3` |
