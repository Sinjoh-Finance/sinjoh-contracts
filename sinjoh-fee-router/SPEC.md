# SinjohFeeRouter

An immutable, per-subject contract that accepts a bounded set of fee assets, charges a 1% protocol fee exactly once, and assigns the remainder to as many as eight asset buckets.

The router does not claim from launchpads. A launchpad can nominate it directly only
when delivery requires no authorized call from the recipient. All other upstream
collection semantics require a separately specified adapter that transfers value to
the router.

## Supported launchpad shape

| Requirement | Consequence if unmet |
|---|---|
| The creator-fee recipient can be an arbitrary address | A direct router integration is impossible |
| Fees are pushed to that address as ETH or a supported ERC-20 | Otherwise a launchpad-specific claim adapter is required |
| Every configured conversion has an immutable route and price guard | Otherwise that conversion is disabled and value remains pending |

pons v1 requires the separately specified `SinjohPonsV1Adapter`: the locker transfers
fees to its redirect, but only an authorized identity can trigger collection. pons
v2 uses a different pull escrow and is outside this contract’s first-release scope.
The pons v1 launch deployer or factory can repoint future fees away from the adapter;
router immutability applies only after assets reach the router.

## Deployment

`SinjohFeeRouterFactory` deploys EIP-1167 clones with CREATE2. One router serves one subject token.

The predicted address derives from:

```text
factory address
implementation address
creator
user salt
keccak256(canonical encoded Config)
```

It intentionally does not derive from the subject token, so it can be predicted before that token exists.

```solidity
function predictAddress(
    address creator,
    bytes32 salt,
    Config calldata config
) external view returns (address);
```

Deployment and initialization are atomic in the factory transaction. A clone is never left uninitialized. If a third party deploys the same `(creator, salt, config)`, the result is the same initialized router and grants that party no authority.

## Configuration

```solidity
enum AssetKind {
    NATIVE,
    FIXED_ERC20,
    SUBJECT
}

struct AssetRef {
    AssetKind kind;
    address token; // zero unless FIXED_ERC20
}

struct Conversion {
    AssetRef input;
    address adapter;
    address priceGuard;
    bytes routeData;
    uint128 maxAmountInPerCall;
    uint48 minInterval;
}

struct Allocation {
    address destination;
    uint16 bps;
    bool isSink;
    bool creatorMayRepoint;
    bytes sinkConfig;
}

struct Bucket {
    AssetRef output;
    uint16 bps;
    Conversion[] conversions;
    Allocation[] allocations;
}

struct Config {
    address creator;
    address protocolFeeRecipient;
    address weth;
    AssetRef[] intakeAssets;
    Bucket[] buckets;
}
```

Limits:

- at most 4 intake assets;
- at most 8 buckets;
- at most 4 conversions per bucket, with one unique entry per configured intake
  asset that the bucket can process;
- at most 16 allocations per bucket;
- each `routeData` and `sinkConfig` is at most 1,024 bytes;
- the canonical encoded `Config` is at most 16,384 bytes;
- intake assets and bucket outputs must be unique after resolving the subject;
- bucket bps sum to 10,000;
- each bucket’s allocation bps sum to 10,000;
- protocol fee is the constant 100 bps;
- zero destinations are forbidden;
- native ETH cannot be sent to the burn address;
- a sink must have a nonzero destination and immutable configuration hash;
- every non-identity conversion must have a nonzero adapter and price guard.

Factory tests must deploy the maximum-size valid configuration under Robinhood's
transaction gas limit. A configuration that cannot be initialized in one atomic
factory transaction is invalid; it must not leave a partially initialized clone or
data contract.

`weth` is a chain-specific immutable used only by the configured unwrap adapter and deployment assertions. On Robinhood Chain mainnet it is:

```text
0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73
```

## Binding

```solidity
function bind(address subject) external; // onlyCreator, once
```

Binding:

- requires nonzero deployed code;
- resolves every `SUBJECT` asset reference;
- rejects any resulting duplicate asset;
- is irreversible;
- is required before synchronization or routing.

Assets may arrive before binding and remain unaccounted. No inference is made from balances.

## Asset support

The first release supports:

- native ETH;
- explicitly configured standard ERC-20s with stable balances;
- WETH through the canonical configured address.

Unsupported:

- rebasing tokens;
- fee-on-transfer tokens;
- tokens whose `transfer`/`transferFrom` changes balances by an unexpected amount;
- ERC-777-style callback assumptions;
- arbitrary assets sent by mistake.

Unsupported assets have no recovery path. Interfaces must warn before direct transfers.

## Accounting model

For every supported asset the router maintains both detailed ledgers and an aggregate:

```text
totalLiability[asset]
  = protocolOwed[asset]
  + sum(bucketInputOwed[bucket][asset])
  + sum(walletOwed[recipient][asset])
  + sum(sinkOwed[allocationId][asset])

balance(router, asset) >= totalLiability[asset]
```

The sums are an invariant definition, not an on-chain loop. Every ledger transition updates `totalLiability[asset]` in constant time.

The unaccounted intake at synchronization is:

```text
unaccounted = balance(router, asset) - totalLiability[asset]
```

If `balance < totalLiability`, synchronization reverts with `Insolvent(asset)`. Invariant and fuzz tests must prove this is unreachable for supported assets.

Any unsolicited transfer of a supported asset is treated as new intake on the next synchronization. It is charged once and routed under the immutable policy.

## Synchronization and protocol fee

```solidity
function sync(address asset) external returns (uint256 gross, uint256 fee);
```

`sync`:

1. resolves and verifies that `asset` is a configured intake asset;
2. computes unaccounted intake from the balance/liability difference;
3. advances an asset-scoped fee remainder and calculates the incremental fee so
   cumulative protocol fees always equal `floor(cumulativeGross * 100 / 10_000)`;
4. adds the fee to `protocolOwed[asset]`;
5. advances a bounded modulo-10,000 allocation remainder and credits each bucket
   from a repeating 10,000-unit cycle containing exactly `bps` slots for each
   bucket;
6. increases `totalLiability[asset]` by `gross`;
7. emits the complete accounting transition.

Nothing is charged during a swap, allocation, retry, claim, or receipt from another internal ledger. Value is charged exactly once when it crosses from unaccounted balance into liabilities.

Protocol fees remain in kind:

```solidity
function sendProtocolFee(address asset, uint256 amount) external;
```

The function is permissionless but always sends to the immutable protocol fee recipient. Failure affects only that call and leaves the liability unchanged.

`amount` must be nonzero and no greater than `protocolOwed[asset]`.
On success, `protocolOwed` and `totalLiability` decrease by the exact balance decrease.

## Immutable conversion routes

Callers never supply a pool, path, hook, adapter, or route bytes.

Each `(bucket, inputAsset)` pair is either:

- identity: input already equals the bucket output;
- configured with one immutable adapter, price guard, and route data;
- unsupported, in which case its input stays pending.

The adapter interface is copied:

```solidity
interface ISinjohSwapAdapter {
    function swap(
        address assetIn,
        address assetOut,
        uint256 amountIn,
        uint256 minAmountOut,
        bytes calldata routeData
    ) external payable;
}
```

The router measures its own balance delta and never trusts the adapter’s return value.

The guard interface is copied:

```solidity
interface ISinjohPriceGuard {
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

An implementation may use:

- a sufficiently initialized Uniswap v3 TWAP with a maximum spot/TWAP deviation;
- a verified v4 hook oracle;
- Chainlink feeds with sequencer, staleness, and decimal checks;
- an EIP-712 quote signed by an immutable signer with nonce and expiry.

If no trustworthy guard exists, the conversion must not be configured. A notional cap or caller-supplied minimum is not a price guard.

## Bucket processing

```solidity
function processBucket(
    uint8 bucketId,
    address inputAsset,
    uint256 amountIn,
    uint256 callerMinOut,
    bytes calldata guardData
) external returns (uint256 amountOut);
```

Rules:

1. `amountIn` must equal `min(pending bucket input, maxAmountInPerCall)`.
2. A caller cannot choose a smaller tranche or exceed the immutable maximum.
3. The immutable minimum interval must have elapsed.
4. For identity conversion, output equals input.
5. Otherwise the guard supplies `guardMinOut` and expiry.
6. The enforced minimum is `max(guardMinOut, callerMinOut)`; a caller may be stricter, never weaker.
7. Adapter approval is exact and reset to zero after use.
8. The router measures input spent and output received.
9. Unexpected input spend or insufficient output reverts the entire bucket call.
10. On success, the detailed and aggregate input liabilities decrease by exact input spent.
11. Output is credited across allocations and both detailed and aggregate output liabilities increase by exact output received.

Destination allocations use the same repeating 10,000-unit cycle. Transaction
boundaries therefore cannot change the result, each full cycle exactly matches
the configured basis points, and every output unit is immediately deliverable.
Within a partial cycle, allocations follow immutable configuration order.

Each bucket is processed in a separate transaction. A failed conversion cannot block a different bucket.

## Wallet allocations

When bucket output is credited to a wallet allocation, the current destination is snapshotted:

```text
walletOwed[destination][asset] += amount
```

Repointing affects future credits only. It cannot confiscate amounts already owed to the old destination.

```solidity
function repointWallet(uint8 bucketId, uint8 allocationId, address newDestination)
    external; // onlyCreator
```

Only allocations marked `creatorMayRepoint` and not marked `isSink` can be changed. Every change emits old and new destinations.

Wallet value is delivered separately:

```solidity
function sendWallet(address recipient, address asset, uint256 amount) external;
```

The call is permissionless and can only send the named recipient’s own liability to that recipient. A revert leaves it pending and affects no other allocation.

`amount` must be nonzero and no greater than `walletOwed[recipient][asset]`.
On success, `walletOwed` and `totalLiability` decrease by the exact balance decrease.

## Sink allocations

Sinks use the atomic funding convention:

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

```solidity
function fundSink(uint8 bucketId, uint8 allocationId, uint256 amount) external;
```

`amount` must be nonzero and no greater than the selected
`sinkOwed[allocationId][asset]`.

For ERC-20:

1. the router grants the immutable sink an exact temporary allowance;
2. the sink pulls during `fund`;
3. the allowance is reset;
4. the router verifies the exact balance decrease and `received == amount`.

For native ETH, the router calls with `msg.value == amount`.

On success, `sinkOwed` and `totalLiability` decrease by the exact transferred amount. Failure reverts only this sink-dispatch transaction and leaves both unchanged. There is no automatic fallback or reassignment.

## Native ETH and WETH

WETH is not implicitly unwrapped. A bucket targeting native ETH configures a dedicated immutable unwrap conversion:

- only the canonical configured WETH may enter;
- `withdraw(amount)` is called on WETH;
- output must equal input exactly;
- no price oracle is required for the 1:1 unwrap.

The Universal Router and WETH are distinct contracts.

## Public execution and liveness

`sync`, `processBucket`, `sendWallet`, `fundSink`, and `sendProtocolFee` are permissionless.

Version one does not reimburse callers and holds no gas reserve. Pending-work views and events allow creators, recipients, holders, and keepers to decide what to execute.

Lack of a caller delays processing but cannot redirect value.

## Mutability

Frozen at initialization:

- creator;
- protocol fee and recipient;
- intake assets;
- bucket assets and bps;
- allocation bps and sink flags;
- sink destinations and configuration;
- adapters, guards, routes, caps, and intervals;
- WETH address.

Set once:

- subject, through `bind`.

Mutable:

- future destination of explicitly repointable wallet allocations only.

There is no owner, upgrade path, arbitrary call, sweep, fallback recipient, or rescue function.

## Security requirements

- Reentrancy guard on every state-changing external entrypoint that makes external calls.
- Checks-effects-interactions; a failed external operation must revert its local liability transition.
- Exact temporary allowances; no standing adapter or sink allowance.
- Balance-delta verification for every adapter and sink operation.
- Chain-ID and dependency-code-hash assertions in deployment scripts.
- Canonical config encoding and duplicate-asset checks after subject binding.
- No `delegatecall`.
- No caller-selected target, route, hook data, or safety downgrade.

## Required tests

1. Liability sum never exceeds actual balance for any supported asset.
2. Aggregate `totalLiability` always equals the sum of detailed liabilities.
3. Every received unit is either unaccounted or in exactly one liability ledger.
4. A synchronized unit cannot be charged twice.
5. Donations of supported assets are charged once.
6. Unsupported and fee-on-transfer assets cannot corrupt accounting.
7. Caller minimum below guard minimum cannot weaken execution.
8. Sandwich/manipulated spot outside guard tolerance reverts.
9. One bucket failure does not affect another bucket’s callable state.
10. Repointing cannot move accrued wallet liabilities.
11. Sink failure leaves allowance zero and liability unchanged.
12. CREATE2 front-running cannot seize initialization authority.
13. Fork tests use Robinhood mainnet pons v1 pools and canonical Uniswap deployments.

## Robinhood Chain mainnet dependencies

| Contract | Address |
|---|---|
| WETH | `0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73` |
| Universal Router | `0x8876789976decbfcbbbe364623c63652db8c0904` |
| Permit2 | `0x000000000022D473030F116dDEE9F6B43aC78BA3` |
| Uniswap v3 QuoterV2 | `0x33e885ed0ec9bf04ecfb19341582aadcb4c8a9e7` |
| Uniswap v4 Quoter | `0x8dc178efb8111bb0973dd9d722ebeff267c98f94` |
| pons v1 locker | `0x736D76699C26D0d966744cAe304C000d471f7F35` |
| pons v1 factory | `0xA5aAb3F0c6EeadF30Ef1D3Eb997108E976351feB` |

pons v2 addresses must not be added until deployed bytecode and completed audits are available.
