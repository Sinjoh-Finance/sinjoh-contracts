# Sinjoh launchpad adapters

A launchpad-agnostic seam between `SinjohFeeRouter` and any launchpad.

The router already delegates swaps to `ISinjohSwapAdapter`, payouts to `ISinjohSink`,
and slippage floors to `ISinjohPriceGuard`. The launchpad is the one dependency that
was compiled into the router instead, as `launchPonsToken` and `collectPonsFees`
calling `IPonsV1LaunchFactory` and `IPonsV1Locker` directly. Pons v2 changes the launch
signature, the fee delivery model, and the fee asset at once, and none of those
changes can reach an immutable deployed router. This spec removes the launchpad from
the router entirely.

After this change the router knows exactly one thing about launchpads: a single
address that is allowed to bind its subject and feed it assets.

## Model

One adapter instance per launch, deployed as an EIP-1167 clone through a
per-launchpad factory. The adapter is the launchpad-side identity: it is the launch
deployer and the creator-fee recipient. Value it receives is forwarded to exactly one
immutable router.

```
creator ──> LaunchpadAdapterFactory ──> adapter (clone)
                                          │
                                          ├─ launch()    ──> launchpad
                                          ├─ collect()   <── launchpad fees
                                          └─ forward()   ──> SinjohFeeRouter
```

This is the `SinjohPonsV1Adapter` shape generalized, with the launch call moved inside
the adapter so the router never encodes a launchpad's calldata.

### Why the adapter and not the router

v2's fee escrow credits balances to a recipient and requires that recipient to call
`claim()` itself. Whatever address is named as `creatorFeeRecipient` must be able to
originate a call. An adapter can. A passive address cannot, which is why merely
nominating the router would strand every fee in the escrow forever.

Making the adapter the recipient also isolates the launchpad's failure domain. A
launchpad that changes its claim semantics, pauses, or reverts affects one clone, not
the router that holds the accounting.

## `ISinjohLaunchpadAdapter`

```solidity
interface ISinjohLaunchpadAdapter {
    /// @notice The router that receives everything this adapter forwards.
    function router() external view returns (address);

    /// @notice The launched token, or zero before launch.
    function subject() external view returns (address);

    /// @notice Assets this adapter is permitted to forward. Fixed at launch.
    function intakeAssets() external view returns (address[] memory);

    /// @notice Pulls whatever the launchpad currently owes into this adapter.
    /// Permissionless. An upstream "nothing accrued" condition is a no-op.
    /// Returns one amount per entry of `intakeAssets()`, in that order.
    function collect() external returns (uint256[] memory amounts);

    /// @notice Forwards this adapter's full balance of `asset` to the router.
    /// Permissionless. Returns zero without an external call on a zero balance.
    function forward(address asset) external returns (uint256 amount);
}
```

`collect()` and `forward()` stay separate entrypoints, as in the v1 adapter, so one
asset can make progress when the other becomes non-transferable. Neither charges a
fee; the 1% protocol fee is still charged exactly once, later, by `router.sync(asset)`.

`collect()` returns an array rather than a fixed pair. pons v2 pays a single quote
asset; pons v1 pays both the subject token and WETH out of its v3 position. A fixed
arity would encode one launchpad's asset model into the interface every other
launchpad has to satisfy — the second implementation is where that shows up, so it is
worth getting right before the first deployment.

Launch is deliberately **not** in this interface. Launch parameters are irreducibly
launchpad-specific — v1 takes `(LaunchParams, launchConfigId, dexId, salt)`, v2 takes
`(TokenParams, launchConfigId, pairToken)` — and forcing them through a common
`bytes` blob would recreate the arbitrary-calldata surface the v1 adapter spec
forbids. Each adapter exposes its own typed `launch(...)`, and each factory validates
that adapter's parameters against its own pinned launchpad.

## Router changes

`RouterTypes.Config` gains one field:

```solidity
address launchpadAdapter;   // may bind the subject and is a trusted intake source
```

and the router:

1. drops `launchPonsToken`, `collectPonsFees`, `ponsLaunchFactory`, `ponsLocker`, the
   `IPonsV1` import, and the three Pons-specific errors;
2. accepts `bind(subject)` from `creator` **or** `launchpadAdapter`;
3. gains native-ETH intake (below).

Nothing else in the router's accounting changes. `sync`, buckets, allocations, sinks,
the protocol fee, and the solvency invariant are untouched.

### Native intake

v2 fees arrive as the pairing asset, never as the launch token. For a native launch
that is raw ETH, delivered by `payable(msg.sender).call{value: amount}("")` with full
gas. The current router has a bare `receive() payable {}` and a `sync` that rejects
anything that is not `subject` or `weth`, so claimed ETH would sit permanently
unaccounted and outside `totalLiability`.

The adapter therefore wraps before forwarding: `collect()` claims native, calls
`WETH.deposit()`, and `forward(WETH)` sends WETH. For a native launch the router's
asset set stays `{subject, weth}` and its accounting is unchanged.

Wrapping happens in `collect()` after the escrow call returns, never inside
`receive()`. The escrow holds a `nonReentrant` lock across the transfer, and doing
work inside the callback would couple our adapter to that lock for no benefit.

### Generalized normalization

Only 19% of live v2 launches pair against native ETH. The rest pair against USDG or an
approved equity token, and their fees arrive in that asset — neither `subject` nor
`weth`, so today's `sync` rejects them outright.

`RouterTypes.Config` therefore replaces the single `subjectToWeth` leg with a set of
normalization routes keyed by intake asset:

```solidity
struct Normalization { address asset; Route route; }
Normalization[] normalizations;   // replaces `Route subjectToWeth`
```

`sync(asset)` accepts any asset with a configured normalization route and converts it
to WETH through that route; WETH itself passes through with no route, as today. The
subject keeps its route under the same mechanism, so this is a generalization of the
existing behaviour rather than a new code path.

**Decimals.** USDG is a 6-decimal asset. Nothing downstream of normalization changes,
because every route outputs 18-decimal WETH and all router accounting is denominated
in the output. The decimal exposure is confined to the route's `minAmountOut` and to
the price guard, both of which must be computed in the input asset's own scale. A
guard that assumes 18-decimal inputs would misprice a USDG leg by twelve orders of
magnitude, so the guard takes the input decimals explicitly rather than inferring them.

The intake set is not hardcoded. The adapter reads `approvedPairTokens` at launch and
refuses a pair the factory has not approved, so the supported list tracks Pons without
a Sinjoh redeploy.

## Ordering

v2 token addresses are **not** deterministic — `PonsV2LaunchDeployer` uses plain
`new PonsV2…` with no salt and no CREATE2 — so nothing derived from the token address
can be committed before the launch. Both the router and the adapter are CREATE2
clones, so both are predictable without it.

1. predict adapter address from (adapterFactory, creator, userSalt);
2. predict router address from (routerFactory, creator, userSalt);
3. deploy the router with `launchpadAdapter` = predicted adapter;
4. deploy the adapter bound to the router;
5. creator calls `adapter.launch(...)`; the adapter launches, receives the token, calls
   `router.bind(token)`, performs the developer buy, and forwards the bought tokens to
   the creator.

Step 5 is one transaction, so the developer buy cannot be front-run.

**Neither salt may reference the other address.** The router's config names the adapter,
so an adapter salt that included the router would make each address depend on the other.
Both therefore derive from `(creator, userSalt)` alone — the router factory already does
this via `_ponsDerivedSalt`, and the adapter factory mirrors it.

Breaking the cycle costs the salt-level guarantee that an adapter is bound to the right
router, so two checks replace it:

- `adapterFactory.deploy` is creator-only. An open deploy would let anyone claim the
  predicted clone and initialize it against a router of their choosing.
- `adapter.launch` reads `router.launchpadAdapter()` and reverts unless it is the
  adapter itself. Even a seized adapter cannot launch into a router that did not name
  it, because that router would reject its `bind` anyway.

The router's immutable config must no longer contain a predicted pool. On v2 there is
no pool until graduation, and a graduated pool is a Uniswap v4 PoolId inside a
singleton PoolManager rather than a CREATE2 address. Subject-to-WETH route data is
resolved at first `sync` instead of pinned at deploy, which is a router-side change
tracked separately.

## Developer buy

v2's `launchToken` reverts unless `msg.value == launchFee` exactly, so v1's
launch-with-first-buy is gone. The adapter performs it as a second call in the same
transaction:

```solidity
curve.buy{ value: quoteIn }(quoteIn, minTokensOut, creator);
```

`minTokensOut` is supplied by the caller and must be non-zero when `quoteIn` is
non-zero. v2 clamps oversized buys and refunds the difference, so the adapter measures
its own balance delta and forwards any refund to the creator rather than trusting the
quote.

That form works for a native launch, where `quoteIn` is sent as value. A custom-pair
launch requires the caller to already hold and approve the pair asset, so the adapter
must pull it from the creator. This is a deliberate, narrow exception to the standing
"no allowance is granted and no `transferFrom` is used" rule, bounded as follows:

- the counterparty is the immutable `creator` and nothing else;
- the amount is exactly the developer-buy amount named in the same call;
- it is reachable only from `launch`, which is one-shot and creator-only;
- the pulled balance is asserted by pre/post delta, and the adapter approves the curve
  for exactly that amount and resets the allowance to zero before returning;
- any clamp refund is returned to the creator in the same transaction.

Outside `launch` the adapter holds no allowance and can pull nothing. The exception
buys atomic, un-front-runnable developer buys on every pair asset; without it,
custom-pair creators would have to buy in a second transaction with an open window in
between.

## Adapters

### `SinjohPonsV2Adapter`

Pinned to launch factory `0x7E1EAbd52Ae29598e6483F72dCf1a70b14284dB8`, fee escrow
`0xbc39B6502E1a6Ab36E4A5c5026A35F08342A0A9c`, and canonical WETH.

- `launch(TokenParams params, uint256 launchConfigId, address pairToken, uint256 devBuy, uint256 minTokensOut)`
  — requires `params.creatorFeeRecipient == address(this)`, requires
  `params.expectedEconomics == factory.previewLaunchEconomics(launchConfigId, pairToken)`
  so owner-updatable terms cannot move between quote and execution, sends exactly
  `launchFee`, then performs the developer buy.
- `collect()` — `escrow.claim()` for a native launch, `escrow.claimToken(pairToken)`
  for a custom pair, then wraps native to WETH. Treats the escrow's `NoBalance()`
  revert as "nothing accrued", so a keeper poll on an idle launch is not an error.
- `intakeAssets()` — `[WETH]` for a native launch, `[pairToken]` otherwise. The launch
  token is never a fee asset in v2.

Supported pair assets are whatever `approvedPairTokens` reports, plus native. As of
2026-07-31 that is USDG (6 decimals) and seven equity tokens — $NVDA, $SPCX, $GME,
$AAPL, $TSLA, $GOOGL, $SPY — all 18 decimals. $COIN, $MSTR and $RDDT appear in our RWA
presets but are **not** approved on v2, and WETH is not an approved pair: the ETH
option is `pairToken == address(0)`. The adapter validates against the live mapping
rather than a pinned list, so approvals and revocations take effect without a Sinjoh
redeploy, and the UI must read the same mapping rather than assuming the RWA preset
list is launchable.

A custom-pair launch reads its own `phantomQuote` and `graduationThreshold` from
`pairTokenEconomics(pairToken)`, denominated in that asset's decimals, not from the
launch config. The adapter re-reads `decimals()` at launch and refuses a pair whose
scale no longer matches the approved value, mirroring the factory's own
`_requireDecimals` check — an upgradeable quote asset can change its scale after
approval, and the curve prices against the stored figure for its entire life.

Never exposes `transferCreatorFeeRecipient`. The adapter's role as recipient is
permanent; exposing the handoff would make the routing guarantee revocable.

`creatorTaxBps` is `uint16` and capped by the factory at `maxCreatorTaxBps` (currently
1000). The adapter passes it through and lets the factory enforce the ceiling rather
than duplicating a value that Pons can change.

### `SinjohPonsV1LaunchAdapter`

Pinned to launch factory `0xA5aA…1feB`, locker `0x736D…7F35`, and canonical WETH.

**pons v1 is the live launchpad**, not a legacy path — `launchEnabled` is true and it
is taking thousands of launches while v2 is paused by pons for a fault in their own
code. A v1 adapter with a real launch entrypoint is therefore what makes the
generalized router adoptable at all.

- `launch(LaunchParams params, uint256 launchConfigId, uint256 dexId, bytes32 salt)` —
  requires `params.feeWallet == address(this)`, sends at least `launchFee`, and
  forwards v1's first-buy output to the creator. v1 performs the first buy inside
  `launchToken` and delivers it to the fee wallet, so there is no separate curve call
  and no slippage floor to supply; the developer buy rides along in `msg.value`.
- `collect()` — `locker.collectFees(subject)`. The locker authorizes the launch
  deployer and the resolved recipient, and the adapter is both because it performed the
  launch. Treats `NoFeesToCollect()` as "nothing accrued".
- `intakeAssets()` — `[subject, WETH]`. v1 pays fees in both pool assets, so the router
  needs a subject-to-WETH normalization route as well as accepting WETH directly.
- `feeRedirectIntact()` — v1 lets the launch deployer repoint fees away from this
  adapter. Sinjoh's guarantee begins where value arrives, so interfaces must watch this
  and mark future fee flow inactive the moment it stops resolving here.

#### The already-deployed `SinjohPonsV1Adapter` cannot serve this role

Those instances are immutable EIP-1167 clones with no launch entrypoint, and their
`collect()` returns nothing, so they cannot satisfy `ISinjohLaunchpadAdapter` and
cannot be made to. They stay outside the interface. That costs nothing: launches
already using them are bound to the pre-existing router implementation, which predates
this seam entirely and is unaffected by any of it.

## Security requirements

Carried forward from the v1 adapter spec, all still binding:

- exact immutable launchpad, subject, WETH, and router targets;
- no caller-supplied calldata, target, or recipient anywhere;
- atomic clone initialization, non-reinitializable;
- reentrancy guard on `launch`, `collect`, and `forward`;
- pre/post balance-delta verification on every forward;
- no allowance granted and no `transferFrom`, except the developer-buy pull described
  above: creator-only, exact-amount, `launch`-only, delta-asserted, allowance reset to
  zero before return;
- no fallback, `delegatecall`, upgrade, rescue, or self-destruct path;
- chain-ID and dependency-code-hash assertions in deployment scripts;
- unsupported assets are stranded rather than sweepable.

New for v2:

- `launch` is callable exactly once and only by the creator;
- the economics pin is mandatory, not optional;
- a developer-buy refund is forwarded to the creator, never retained;
- native value may enter only through `collect`; a bare `receive()` accepts ETH but
  grants no accounting claim on it.

## Required tests

1. Uninitialized clones cannot be seized; reinitialization reverts.
2. CREATE2 prediction matches deployment for both adapter and router, and cannot be
   front-run to change either binding.
3. `launch` reverts when `creatorFeeRecipient` is not the adapter.
4. `launch` reverts when the economics pin does not match the factory preview.
5. `launch` sends exactly `launchFee` and reverts on any other value.
6. A second `launch` on the same adapter reverts.
7. Developer buy delivers tokens to the creator, and a clamped buy forwards the refund.
8. `collect` treats `NoBalance()` as a no-op rather than a failure.
9. Native claim is wrapped to WETH before forwarding; the router's asset set is unchanged.
10. WETH forwarding succeeds when subject forwarding fails, and vice versa.
11. Zero-balance forwarding performs no external call.
12. Reentrancy cannot redirect or duplicate a transfer.
13. Forwarding charges no Sinjoh fee; `router.sync()` charges forwarded value once.
14. The router accepts `bind` from the adapter and from the creator, and from nobody else.
15. Robinhood mainnet fork tests covering a real v2 launch, curve buy, curve sell,
    fee accrual, claim, forward, and sync end to end.
16. A fork test that graduates a launch and confirms fee flow survives the transition
    from curve to v4 pool.
17. `launch` reverts on a pair token the factory has not approved, and on an approved
    pair whose `decimals()` no longer matches its recorded scale.
18. The developer-buy pull moves exactly the named amount from the creator, leaves zero
    residual allowance, and cannot be reached outside `launch`.
19. A USDG-paired launch (6 decimals) accrues, claims, forwards, normalizes and syncs
    to the correct 18-decimal WETH amount, with a guard floor computed in USDG scale.
20. An equity-paired launch does the same for an 18-decimal pair asset, confirming the
    decimal handling is not accidentally native-only.

## Robinhood Chain mainnet dependencies

| Contract | Address |
|---|---|
| pons v2 launch factory | `0x7E1EAbd52Ae29598e6483F72dCf1a70b14284dB8` |
| pons v2 fee escrow | `0xbc39B6502E1a6Ab36E4A5c5026A35F08342A0A9c` |
| pons v2 launch locker | `0x28b6F0116c7F234951cf0e67319ed53863Df2197` |
| pons v2 meme hook | `0x8e99D2009D60A917e9B1c00C04C077b8c0c3a044` |
| Uniswap v4 PoolManager | `0x8366a39CC670B4001A1121B8F6A443A643e40951` |
| Uniswap v4 PositionManager | `0x58daec3116aae6D93017bAAea7749052E8a04fA7` |
| WETH | `0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73` |
| pons v1 launch factory (legacy) | `0xA5aAb3F0c6EeadF30Ef1D3Eb997108E976351feB` |
| pons v1 locker (legacy) | `0x736D76699C26D0d966744cAe304C000d471f7F35` |

All v2 shapes in this spec are taken from verified on-chain source, not from
`docs.ponsfamily.com/v2`, which misstates at least six event signatures. See
`PONS-V2-FINDINGS.md`.
