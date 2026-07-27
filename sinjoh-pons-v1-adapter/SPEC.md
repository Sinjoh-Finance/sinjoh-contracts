# SinjohPonsV1Adapter

A minimal, immutable integration adapter that receives pons v1 fees and forwards
the resulting subject token and WETH to one `SinjohFeeRouter`. It can also expose
permissionless collection when the pons locker owner has approved the adapter as a
fee collector.

The adapter exists because pons v1 transfers fees to its configured recipient only
when an authorized identity calls the locker. A router that is merely configured as
the recipient cannot originate that call. Configuring this adapter as the pons fee
redirect makes fee assets arrive at the immutable forwarding boundary, but the live
v1 locker does not automatically authorize the redirect address to initiate
collection.

It performs no accounting, conversion, allocation, or protocol-fee charging.

## Deployment

Instances are EIP-1167 clones created through `CREATE2` and initialized atomically
by a factory.

```solidity
struct Config {
    address subject;
    address router;
}
```

Factory and implementation constructor immutables:

```solidity
constructor(address ponsLocker, address weth, uint256 chainId);
```

Requirements:

- deployment chain ID is Robinhood Chain mainnet (`4663`);
- locker and WETH addresses have code and match deployment-script code hashes;
- subject and router are nonzero contracts;
- subject differs from WETH;
- initialization happens in the factory transaction;
- initializer cannot be called twice;
- predicted addresses include factory, implementation, creator, subject, router,
  user salt, and chain ID in their derivation.

The factory emits all derivation inputs. A deployment script must compare the
factory's predicted address with the actual result.

The adapter may be deployed only after the subject token exists. The pons launch
deployer or factory then calls the verified locker's `setFeeRedirect` flow to make
the adapter the resolved fee recipient. This configures payout only. The locker
owner must separately call its collector-approval flow if permissionless
adapter-triggered collection is required. Both upstream settings are outside Sinjoh
and must be verified on-chain before the integration is considered active. The pons
launch deployer or factory can later change that redirect again. The adapter cannot
prevent or reverse such a change.

## Immutable state

After initialization, the adapter stores:

- subject token;
- router;
- pons v1 locker;
- canonical WETH;
- deployment chain ID.

There is no owner, operator, upgrade, rescue, arbitrary call, or mutable recipient.

## Collect

```solidity
function collect() external;
```

`collect()` has no Sinjoh caller restriction and calls only:

```solidity
ponsLocker.collectFees(subject);
```

The call succeeds only if the pons locker recognizes the adapter as an approved fee
collector. Setting the adapter as fee redirect alone is insufficient on the live
Robinhood testnet locker. Without collector approval, the launch deployer or pons
automation must call the locker directly; payout still arrives at the adapter and
remains permissionlessly forwardable.

Rules:

1. require the deployment chain ID;
2. enter a reentrancy guard;
3. record subject and WETH balances before the call;
4. call the immutable locker with the immutable subject;
5. record balances after the call;
6. emit measured deltas for both assets.

The adapter ignores upstream return values. A locker revert rolls back the entire
call. Receiving zero of one or both assets is valid if the locker succeeds.

`collect()` does not forward. Keeping collection and forwarding as separate
entrypoints lets one asset make progress if the other token later becomes
non-transferable.

pons automation may also call the locker directly. In that case assets arrive at
the adapter without `collect()`, and the forwarding path remains available.

## Forward

```solidity
function forward(address asset) external returns (uint256 amount);
```

`forward()` is permissionless.

Rules:

1. `asset` must equal the immutable subject or WETH;
2. enter a reentrancy guard;
3. read the adapter's full balance of that asset;
4. return zero without an external call if the balance is zero;
5. transfer the full balance to the immutable router with `SafeERC20`;
6. verify the adapter's balance decreased by exactly `amount`;
7. emit the asset, amount, router, and caller.

The adapter does not call `router.sync()`. Forwarding and router accounting remain
separate failure domains. Anyone may call `sync(asset)` on the router afterward.

Direct transfers of subject or WETH to the adapter are forwarded by the same
permissionless function. Unsupported assets are stranded; there is deliberately no
generic sweep because that would create an arbitrary-token execution surface.

Fee-on-transfer, rebasing, ERC-777-style callback, and otherwise nonstandard subject
or WETH implementations are unsupported.

## Accounting boundary

The adapter has no internal value liabilities. Its complete intended balance is
observable as:

```text
balance(adapter, subject)
balance(adapter, WETH)
```

The 1% Sinjoh protocol fee is charged exactly once, later, when the router's
`sync(asset)` converts the forwarded, previously unaccounted balance into router
liabilities.

The adapter must never take a fee or mark an amount as already charged.

## Activation checklist

An integration is active only after an operator verifies:

1. adapter bytecode and immutable configuration;
2. router subject binding equals the adapter subject;
3. router intake assets include subject and WETH;
4. the pons locker's resolved fee recipient for the subject is the adapter;
5. either an on-chain adapter `collect()` succeeds or the launch deployer/pons
   automation successfully collects directly into the adapter;
6. permissionless forwarding and router synchronization succeed for both assets.

The user interface must not label the integration active before all six checks pass.
After activation, an indexer must monitor `FeeRedirectUpdated` and the live
`feeRedirects(subject)` value. If the redirect stops resolving to the adapter, the
interface must immediately mark future fee flow as inactive; value already held by
Sinjoh remains governed by its immutable policy.

## Events

```solidity
event Collected(
    address indexed subject,
    uint256 subjectAmount,
    uint256 wethAmount,
    address indexed caller
);

event Forwarded(
    address indexed asset,
    address indexed router,
    uint256 amount,
    address indexed caller
);
```

## Security requirements

- Exact immutable locker, subject, WETH, and router targets.
- No caller-supplied calldata, target, recipient, or amount.
- Atomic clone initialization.
- Reentrancy guard on `collect()` and `forward()`.
- Pre/post balance-delta verification.
- No allowance is granted and no `transferFrom` is used.
- No payable function and no native-ETH receipt path.
- No fallback, `delegatecall`, upgrade, rescue, or self-destruct path.
- Chain-ID and dependency-code-hash assertions in deployment scripts.

## Required tests

1. Uninitialized clones cannot be seized.
2. Reinitialization reverts.
3. CREATE2 prediction matches deployment and cannot be front-run to change config.
4. `collect()` calls only the immutable pons locker and subject.
5. A caller cannot change locker, subject, router, or calldata.
6. Unauthorized upstream configuration makes `collect()` revert without state.
7. Direct locker collection into the adapter remains forwardable.
8. WETH forwarding succeeds even if subject forwarding fails, and vice versa.
9. Unsupported assets cannot be forwarded.
10. Zero-balance forwarding performs no token call.
11. Reentrancy cannot redirect or duplicate a transfer.
12. Forwarding does not charge a Sinjoh fee.
13. Router `sync()` charges forwarded value exactly once.
14. Robinhood mainnet fork tests cover the canonical pons v1 locker and a real
    subject-token fee flow.
15. Redirect-monitor fixtures mark the integration inactive after upstream
    repointing without affecting already-forwarded value.

## Robinhood Chain mainnet dependencies

| Contract | Address |
|---|---|
| pons v1 locker | `0x736D76699C26D0d966744cAe304C000d471f7F35` |
| pons v1 factory | `0xA5aAb3F0c6EeadF30Ef1D3Eb997108E976351feB` |
| WETH | `0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73` |

pons v2 is not supported by this adapter.
