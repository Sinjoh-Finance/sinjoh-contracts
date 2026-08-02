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
executes direct Robinhood Chain v3 swaps and WETH unwrapping.

## Deployment and binding

`SinjohFeeRouterFactory` deploys EIP-1167 clones with CREATE2. Initialization is
atomic. The historical `deploy` path derives its address from the creator, salt,
and canonical config.

Launchpad-mediated launches use `predictLaunchpadAddress` and
`deployForLaunchpad`. Their clone address depends only on the creator and user
salt, which breaks the otherwise circular dependency between the router
configuration and the adapter it names. Reusing a salt with a different
configuration reverts.

## The launchpad boundary

**The router contains no launchpad-specific code.** It knows one address:

```solidity
address public launchpadAdapter;
```

The router never calls it and never inspects it. The address grants exactly one
right — to bind the subject, once:

```solidity
function bind(address newSubject) external;   // creator or launchpadAdapter
```

Everything launchpad-specific — how a token is launched, how fees are claimed,
which asset they arrive in, what the launch parameters look like — lives behind
`ISinjohLaunchpadAdapter` in `sinjoh-launchpad-adapters`. **Supporting a new
launchpad means writing an adapter. It does not mean changing this contract.**

`bind` is delegable to the adapter because a launchpad may not produce a
predictable token address. Some launchpads create tokens dynamically, so nothing
derived from the address can be committed before the launch lands; the adapter
learns the address in the launch transaction and binds there.

A zero `launchpadAdapter` is valid and means only the creator may bind, which is
correct for a launch the creator performs themselves.

Fees arrive by plain transfer. Adapters wrap native value before forwarding, so
intake is uniformly ERC-20 and every balance is measured the same way;
`sync(address(0))` reverts `NativeIntakeUnsupported`.

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
    address priceGuard;
    uint128 maxAmountInPerCall;
    Allocation[] allocations;
}

struct Normalization {
    AssetRef asset;
    Route route;
    address priceGuard;
    uint128 maxAmountInPerCall;
}

struct Config {
    address creator;
    address protocolFeeRecipient;
    address weth;
    address launchpadAdapter;
    Normalization[] normalizations;
    Bucket[] buckets;
}
```

`normalizations` replaces the former single `subjectToWeth` leg. Fees do not
always arrive as the subject token: a launchpad that pairs a launch against a
quote asset pays fees in that asset instead, and that asset may not be 18
decimals. `sync` accepts any asset with a configured route and converts it to
WETH through that route; WETH itself passes through with no route.

## Synchronizing

```solidity
function sync(address asset) external returns (uint256 gross, uint256 fee);
function sync(address asset, uint256 minAmountOut) external returns (uint256 gross, uint256 fee);
```

**The one-argument form is WETH-only.** WETH needs no conversion, so there is
nothing for a floor to protect and requiring one would be noise on the most
common call a keeper makes. Every other asset is swapped, so every other asset
must use the two-argument form with a nonzero caller floor. Supplying a floor
for WETH is allowed but ignored because no swap occurs.

The refusal distinguishes its causes — `NativeIntakeUnsupported` for the zero
address, `UnsupportedAsset` when no route is configured, and
`NormalizationFloorRequired` only when a route exists and the caller omitted the
floor — so a caller is not sent to fix the wrong thing.

The floor is denominated in WETH, the swap's output, but must be derived from the
input asset's own decimals. A 6-decimal quote asset read as 18 decimals misprices
by twelve orders of magnitude.

The caller floor is not the router's trust boundary: `sync` is permissionless,
so an attacker could always supply a weak value. Each normalization therefore
stores an immutable `priceGuard`. The router asks it for an amount-aware minimum
for at most `maxAmountInPerCall` of the unaccounted balance and executes with the
stricter of the guard quote and the caller floor. Excess balance remains
unaccounted for later bounded calls, so a donation cannot permanently exceed a
guard's supported amount. Zero or expired guard quotes fail closed.

For the shared `ISinjohPriceGuard` interface, normalization supplies its input
asset as both `subject` and `assetIn`. This deliberately binds the guard to the
pair actually being swapped: a USDG-to-WETH normalization remains guardable even
though the launched subject token is not one side of that pair.

Decimals are confined to the route. Every route outputs 18-decimal WETH and all
downstream accounting is denominated in the output, so nothing after
normalization changes. The exposure is the route's `minAmountOut` and the price
guard, both of which must be computed in the input asset's own scale — a
6-decimal input read as 18 decimals misprices by twelve orders of magnitude.

Rules:

- one to eight buckets;
- zero to eight normalizations (zero is valid for a WETH-only intake);
- one to sixteen allocations per bucket;
- bucket basis points total 10,000;
- every bucket’s allocation basis points total 10,000;
- WETH output uses an empty identity route;
- every other output uses a deployed adapter;
- every ERC-20 output other than WETH uses a deployed immutable price guard;
- native unwrap and WETH identity buckets use no guard and enforce exact value;
- every bucket has a nonzero immutable per-call input cap;
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

`asset` must be WETH or any bound configured normalization asset. Non-WETH intake
swaps to WETH first. The protocol fee and all bucket shares are then denominated
in WETH. Shares use house-monotone D'Hondt apportionment over lifetime cumulative
totals, so splitting one sync into smaller calls cannot change any bucket's
cumulative entitlement and no entitlement ever needs to decrease. Exact priority
ties go to the earlier configured entry.

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

`inputAsset` must be WETH. Any nonzero amount up to both the bucket’s pending WETH
and immutable `maxAmountInPerCall` may be processed. The immutable bucket route either keeps WETH or produces the
configured output. ERC-20 swaps execute against the stricter of the immutable
guard quote and `callerMinOut`; zero and expired quotes fail closed. WETH
identity needs no guard, and native unwrap requires at least exact one-to-one
output. The router verifies exact WETH spend and measures the actual output
balance increase. Allocations use the same house-monotone cumulative
apportionment, so caller-selected processing tranches cannot redirect rounding
value.

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
