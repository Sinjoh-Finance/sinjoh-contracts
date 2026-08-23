# Router

## 1. Objective

`ProjectRouterV2` accepts project revenue and executes a governance-selected allocation plan. A
route can send value, swap it, burn project tokens, add permanent liquidity, fund an airdrop, fund
a raffle, fund the treasury, or fund another validated project sink.

Each project has at most one router. It is bound to the project token, creator, Treasury Vault,
controller, and registry record at deployment. The launcher supplies up to sixteen complete initial
route sets to the constructor, so a launched Router is immediately usable and has no temporary
bootstrap administrator or post-deployment wiring step. The constructor also caps aggregate initial
route encoding so the launcher rejects configurations that would exceed the chain's initcode limit
with a clear protocol error instead of an opaque deployment failure.

## 2. Funding and accounting

The router supports attributed funding through `IProjectFundable.fund` and un-attributed receipts
through an explicit `sync(asset)` path.

For each input asset:

```text
balance(router, asset) >= pending[asset] + totalEscrowed[asset] + protocolOwed[asset]
```

`fund` verifies exact balance movement. `sync` credits only the measured surplus above all recorded
liabilities. Any caller may execute or sync; the caller gains no ownership of funds.

The router charges the existing cumulative 1% service fee on gross intake before project route
allocations. Remainder carry makes fee splitting ineffective. Protocol fee delivery is
permissionless but always goes to the immutable protocol fee recipient.

## 3. Route model

One complete route set is active per input asset.

```solidity
enum ActionType {
    SEND,
    SWAP_AND_SEND,
    BURN_PROJECT_TOKEN,
    ADD_LIQUIDITY,
    FUND_AIRDROP,
    FUND_RAFFLE,
    FUND_TREASURY,
    FUND_PROJECT_SINK
}

struct RouteAction {
    ActionType actionType;
    uint16 allocationBps;
    address recipient;
    address adapter;
    address priceGuard;
    bytes actionConfig;
}

struct RouteSet {
    uint64 version;
    address inputAsset;
    RouteAction[] actions;
}
```

Rules:

- between one and sixteen actions;
- allocations total exactly 10,000 basis points;
- each action allocation is nonzero;
- actions are processed in array order, but allocation uses cumulative per-route accounting rather
  than per-call rounding, so splitting the same total into tiny execution batches cannot bias which
  actions receive value;
- config/route data is length bounded and covered by the route-set hash;
- a route version is activated as a complete unit; partial edits are impossible;
- the prior route version remains readable for accounting and failed-route retry, but cannot receive
  new allocations after replacement.

## 4. Destinations and actions

### SEND

Transfers the input asset without conversion. The recipient may be the creator, treasury, or any
nonzero address chosen by governance. Zero/dead addresses require the burn action instead.

### SWAP_AND_SEND

Swaps the input asset through a platform-approved adapter and sends the measured output to the
fixed recipient. The action fixes input/output assets, route, adapter, price guard, and recipient.
The caller may supply a stricter minimum output but cannot change the route.

### BURN_PROJECT_TOKEN

If the input asset is the project token, it calls the token's burn function directly. Otherwise it
performs a guarded swap into the project token and burns the measured output. Sending tokens to a
dead address is not considered a protocol burn.

### ADD_LIQUIDITY

Calls the project's registered Liquidity Manager through `fund`. It cannot select a different
subject, pool, fee mode, adapter, or recipient at execution time.

### FUND_AIRDROP

Funds the project's registered Airdrop contract. Holder/staker mode is fixed in the Airdrop account;
the router cannot override it.

### FUND_RAFFLE

Funds the project's registered Raffle using its immutable prize asset/configuration.

### FUND_TREASURY

Transfers to the registered Treasury through `deposit`. If treasury basket routing is enabled, the
Treasury records the received amount as routeable; otherwise the value remains ordinary treasury
balance.

### FUND_PROJECT_SINK

Calls another contract implementing `IProjectFundable`. The sink must be registered to the same
project. Registry membership already limits this path to modules deployed and verified by the
same immutable release, so no second project-specific proof is accepted. This supports future
release-reviewed modules without permitting arbitrary calls.

## 5. Route updates

Only project governance may activate a new route set or pause or resume a versioned action.
Token-holder updates pass through the project timelock; multisig updates pass through its threshold
flow. Pausing explicitly names `(asset, routeVersion, actionIndex)`, allowing governance to stop a
broken historical action from being retried without freezing unrelated active-route work.

Activation validates the entire route before changing the active version. An invalid adapter,
recipient, project binding, allocation total, or config hash reverts without affecting the current
route. Configuration entrypoints are reentrancy guarded, so a payment recipient or integration
callback cannot modify route state in the middle of execution.

Pausing an action stops new execution for that action and escrows its allocation. Resume requires
governance. Unpaused actions remain executable.

## 6. Execution and failure isolation

`execute(asset, maxAmount, callerMinOuts, guardData)` processes at most the specified pending amount.
The batch amount is removed from pending before external execution. Each route share is then
executed in an isolated external self-call:

- success permanently settles that share;
- revert records that exact share in escrow keyed by `(asset, routeVersion, actionIndex)`;
- failure of one action does not revert successful actions;
- no failed share is recycled through the active route or counted by `sync`.

Failure capture copies only a fixed-size prefix of revert data and commits the original revert-data
length into the reason hash. A malicious destination therefore cannot defeat batch isolation by
returning an oversized revert payload.

Anyone may call `retryEscrow` using the original immutable action. Governance may recover an action
that is permanently incompatible, but only by moving its escrow into a newly activated action for
the same project and asset. Recovery cannot send to a caller-selected recipient.

## 7. Swaps

All swaps require:

1. a platform-approved adapter/runtime hash;
2. a platform-approved price guard bound to the asset pair and route hash;
3. an unexpired guard quote;
4. `minOut = max(guardMinOut, callerMinOut)`;
5. exact input allowance cleared after the call;
6. measured input decrease equal to the action amount;
7. measured output increase at least `minOut`;
8. no residual adapter allowance or unaccounted output.

Adapters may expose a narrow swap function only. They cannot make callbacks into Router
configuration or retain project funds.

## 8. Events and views

Events:

- `Funded(projectId, source, asset, gross, protocolFee, net, attributed)`;
- `RouteActivated(asset, version, routeHash)`;
- `RoutePaused(asset, version, actionIndex)` and `RouteResumed(...)`;
- `ActionExecuted(asset, version, actionIndex, amountIn, assetOut, amountOut)`;
- `ActionEscrowed(asset, version, actionIndex, amount, reasonHash)`;
- `EscrowRetried(...)` and `EscrowRecovered(...)`;
- `ProtocolFeeSent(asset, amount)`.

Views return the active route, every historical route by version, pending/escrow balances,
projected allocations for an amount, and executable/retryable work. `workStatus` returns the active
version and all asset-level work buckets in one call. `actionStatus` returns the immutable action,
pause state, cumulative allocation, and retryable escrow in one call. `isSwapApproved` lets
launchers and frontends validate a swap approval proof. `isSinkApproved` directly reports whether a
sink is a registered module of the same project; project sinks require no redundant proof or wrapper
configuration.

## 9. Invariants

1. `sum(success + escrow)` for an execution equals the net batch amount.
2. A route action can spend only its own fixed allocation.
3. Pending, escrowed, and protocol-fee balances are disjoint.
4. Replacing a route cannot alter or consume old-version escrow.
5. A direct-send or swap recipient cannot be changed during execution.
6. Total Router liabilities never exceed measured per-asset balances.
7. For a fixed route and cumulative routed amount, cumulative action allocations are independent
   of execution batch boundaries.

## 10. Acceptance criteria

1. One route set can simultaneously pay the creator, treasury, airdrop, raffle, and liquidity.
2. A reverting raffle action escrows only its share while all other shares settle.
3. A governance route update changes new allocations but not prior escrow or completed accounting.
4. A burn route provably reduces project-token total supply by the measured output.
5. A caller cannot weaken a price guard or substitute a recipient/sink.
6. A raw transfer is credited once by `sync` and cannot be credited again.
7. Service fees equal 1% of cumulative gross intake regardless of transaction splitting.
8. Every action type has a cross-module integration test against its registered destination.

## 11. Out of scope

- arbitrary call actions;
- governance-selected delegatecall plugins;
- cross-chain routes;
- best-price aggregation across unapproved exchanges;
- per-wallet route ownership.
