# SinjohFeeRouter

An immutable per-launch router with one accounting asset: WETH.

## Data flow

1. The launched token and WETH arrive at the router.
2. All newly received launched tokens swap once into WETH.
3. The router charges 1% in WETH.
4. Net WETH is split across at most eight configured buckets.
5. A bucket either:
   - keeps WETH;
   - unwraps WETH to native ETH;
   - swaps WETH once into the launched token;
   - swaps WETH once into another ERC-20 or tokenized RWA.
6. The bucket output is divided among wallets and sink contracts.
7. Wallet liabilities are sent directly. Sink liabilities fund the airdrop
   distributor or liquidity manager.
8. The launch UI does not offer burn allocations for RWA buckets.

The router does not deploy per-launch adapters or guards. A shared adapter
executes direct Pons v3 swaps and WETH unwrapping.

## Deployment and binding

`SinjohFeeRouterFactory` deploys EIP-1167 clones with CREATE2. Initialization is
atomic. The predicted address depends on the creator, salt, and canonical config,
so the router can be installed as the Pons fee wallet before the token exists.

After the launch confirms, the creator calls:

```solidity
function bind(address subject) external;
```

Binding is one-time, requires deployed token code, and enables routing.

## Configuration

```solidity
enum AssetKind {
    NATIVE,
    FIXED_ERC20,
    SUBJECT
}

struct AssetRef {
    AssetKind kind;
    address token;
}

struct Route {
    address adapter;
    bytes routeData;
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
    Route route;
    Allocation[] allocations;
}

struct Config {
    address creator;
    address protocolFeeRecipient;
    address weth;
    Route subjectToWeth;
    Bucket[] buckets;
}
```

Rules:

- one to eight buckets;
- one to sixteen allocations per bucket;
- bucket basis points total 10,000;
- every bucket’s allocation basis points total 10,000;
- WETH output uses an empty identity route;
- every other output uses a deployed adapter;
- route and sink configuration bytes are bounded;
- resolved bucket outputs must be unique;
- native ETH cannot use the burn address.

## Accounting

For each asset:

```text
balance(router, asset) >= totalLiability[asset]
```

Detailed liabilities are:

- `protocolOwed[asset]`;
- `bucketInputOwed[bucket][WETH]`;
- `walletOwed[recipient][asset]`;
- `sinkOwed[allocation][asset]`.

New intake is the balance above existing liability. Launched-token liabilities
created by buyback buckets therefore cannot be mistaken for new fee intake.

```solidity
function sync(address asset) external returns (uint256 gross, uint256 fee);
```

`asset` must be the bound subject or WETH. Subject intake swaps to WETH first.
The protocol fee and all bucket shares are then denominated in WETH. The last
bucket receives integer-division dust so every unit is assigned immediately.

## Bucket processing

```solidity
function processBucket(
    uint8 bucketId,
    address inputAsset,
    uint256 amountIn,
    uint256 callerMinOut,
    bytes calldata unused
) external returns (uint256 amountOut);
```

`inputAsset` must be WETH. Any nonzero amount up to the bucket’s pending WETH
may be processed. The immutable bucket route either keeps WETH or produces the
configured output. The router verifies exact WETH spend and measures the actual
output balance increase. The last allocation receives integer-division dust.

Each bucket is independent. A failed asset swap does not block WETH sends,
airdrops, buybacks, native ETH, LP, or another asset bucket.

## Delivery

```solidity
function sendProtocolFee(address asset, uint256 amount) external;
function sendWallet(address recipient, address asset, uint256 amount) external;
function fundSink(uint8 bucketId, uint8 allocationId, uint256 amount) external;
```

All three are permissionless and can only deliver existing liabilities to their
configured destination. A failed call leaves the liability pending.

Sink funding uses an exact temporary ERC-20 allowance, or `msg.value` for native
ETH. The router checks its exact balance decrease and the sink’s reported
receipt.

The liquidity manager receives WETH. Its configuration swaps approximately 50%
into the launched token and adds the pair as permanent LP.

## Mutability

Frozen at initialization:

- protocol fee recipient;
- WETH and shared routes;
- buckets, assets, percentages, and sink configuration;
- all non-creator destinations.

Set once:

- launched token via `bind`.

Optionally mutable:

- future credits for allocations explicitly marked `creatorMayRepoint`.

Repointing never moves liabilities already credited to an old wallet.

## Public execution

`sync`, `processBucket`, `sendProtocolFee`, `sendWallet`, and `fundSink` are
permissionless. The UI and keeper can run the same short sequence:

```text
collect -> sync subject -> sync WETH -> process buckets -> deliver liabilities
```

## Required verification

- all received value is either unaccounted or represented by one liability;
- subject normalization happens before fee charging and bucket splitting;
- direct WETH intake uses the identical fee and split path;
- WETH, native ETH, buyback, arbitrary token, wallet, airdrop, burn, and LP
  configurations are covered;
- RWA burn is rejected by shared UI/server validation;
- partial bucket processing works;
- failed buckets and sinks are isolated;
- repointing cannot move accrued value;
- factory prediction equals deployment;
- router, adapter, and sink balances reconcile after a complete run.
