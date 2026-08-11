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
struct Normalization {
    AssetRef asset;
    Route route;
    address priceGuard;
    uint128 maxAmountInPerCall;
}
Normalization[] normalizations;   // replaces `Route subjectToWeth`
```

Every router bucket likewise includes an immutable `priceGuard` and
`maxAmountInPerCall`; WETH identity and native unwrap buckets use a zero guard,
while other ERC-20 outputs require one.

`sync(asset)` accepts any asset with a configured normalization route and converts it
to WETH through that route; WETH itself passes through with no route, as today. The
subject keeps its route under the same mechanism, so this is a generalization of the
existing behaviour rather than a new code path.

**Decimals.** USDG is a 6-decimal asset. Nothing downstream of normalization changes,
because every route outputs 18-decimal WETH and all router accounting is denominated
in the output. The decimal exposure is confined to the route's caller floor and
immutable amount-aware price guard. Both receive the raw input amount, so their quote
logic must preserve the input token's actual scale. A guard that assumes 18-decimal
inputs would misprice a USDG leg by twelve orders of magnitude.

The caller floor is only an additional constraint. Because anyone may call `sync`,
the router always enforces the immutable guard's quote and takes the stricter of the
two values; a caller cannot sandwich the full pending balance by supplying a weak
floor.

The intake set is not hardcoded. The adapter reads `approvedPairTokens` at launch and
refuses a pair the factory has not approved, so the supported list tracks Pons without
a Sinjoh redeploy.

## Ordering

The 2026-08 redeployment restored CREATE2 launches: `TokenParams.salt` derives the
token and curve addresses, namespaced per initiating account — which is the adapter,
so the adapter must exist before the launch addresses are predictable either way.
The ordering below therefore stays as designed, and the router still learns the
subject from `bind` inside the launch transaction rather than from a prediction.

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

### `SinjohFlapAdapter`

One predictable adapter clone launches exactly one native-quote Flap Tax Token V3
through Robinhood Portal V6. The supported profile is deliberately narrow:

- `TOKEN_TAXED_V3`, `V2_MIGRATOR`, `DEX0`, and the standard LP-fee profile;
- native quote only, with extensions and permit data disabled;
- 100% of the post-Flap creator allocation goes to the adapter (`mktBps = 10_000`),
  and the adapter is also the permanent integrator commission receiver;
- burn, dividend, and LP-side allocations are zero, so no creator revenue bypasses
  the Sinjoh router.

The Portal deploys the token as an EIP-1167 CREATE2 clone. `predictSubject(salt)`
reproduces that address from the pinned Portal, Tax Token V3 implementation, and salt;
launch refuses an occupied prediction or a returned token that differs from it. The
adapter also commits to `portalConfigHash()`, which covers the Portal proxy bytecode,
reported version, and native-quote configuration, then reads the created token and
TaxProcessor back before binding the router.

Flap's native-quote TaxProcessor pays both marketing and integrator commission as raw
native currency. Its `dispatch()` is permissionless, so value may arrive before a
keeper calls `collect()`. Collection therefore dispatches and wraps the adapter's
entire native balance into the router's configured WETH, not merely the current call's
balance delta. `receive()` intentionally performs no work because Flap caps receiver
callbacks and converts failed native transfers into protocol-owned value.

`feeRoutingIntact()` monitors all mutable upstream boundaries: token, Portal owner,
quote/WETH identity, marketing receiver, commission receiver and bps, distribution,
and Flap fee rate. It is an operational alarm, not a substitute for the launch-time
validation.

The router needs no subject normalizer for this path: the only intake asset is the
router's WETH. `collect()` wraps, `forward(WETH)` transfers, and `router.sync(WETH)`
applies the normal Sinjoh protocol fee and allocation policy.

Robinhood testnet deployment is prepared by
`script/DeploySinjohFlapTestnet.s.sol`. It pins all live dependency code hashes,
deploys the adapter factory and mutually named router/adapter clones, predicts the
required `7777` token address, launches, and verifies the resulting fee route. A
developer buy is optional through `FLAP_DEVELOPER_BUY_WEI`; a non-zero buy requires
`FLAP_MIN_DEVELOPER_BUY_OUT`.

Robinhood mainnet preparation, pinned dependencies, fork acceptance gates, and the
non-broadcast infrastructure/canary scripts are recorded in
`FLAP_MAINNET_PREPARATION.md`.

### `SinjohPonsV2Adapter`

Pinned to launch factory `0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e`, fee escrow
`0xd3AFEB2a57f70eF218Aa82451c51B2fb0416Ac9e`, and canonical WETH (the 2026-08
redeployment; the original factory at `0x7E1EAbd5…` is paused and superseded).

- `launch(TokenParams params, uint256 launchConfigId, address pairToken, uint256 devBuy, uint256 minTokensOut, address[] snipeTaxExemptions)`
  — requires `params.creatorFeeRecipient == address(this)`, requires
  `params.expectedEconomics == factory.previewLaunchEconomics(launchConfigId, pairToken)`
  so owner-updatable terms cannot move between quote and execution, sends exactly
  `launchFee`, then performs the developer buy. The launch window carries a snipe
  tax (99% decaying across 5s at current settings); the factory auto-exempts the
  adapter, so the developer buy clears untaxed, and `snipeTaxExemptions` (max 32)
  declares the creator's additional bundle wallets. Exemption keys on the buy's
  `recipient`.
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

### `SinjohPonsV2BuybackAdapter` and `SinjohPonsV2BuybackPriceGuard`

The buyback route for pons v2 launches: one singleton `ISinjohSwapAdapter` that
converts a router's WETH bucket share into the launch token, plus the signed-floor
guard `processBucket` consults. Pinned to the same launch factory and WETH as the
launch adapter, plus the Uniswap v4 PoolManager
`0x8366a39CC670B4001A1121B8F6A443A643e40951` (cross-checked against
`factory.poolManager()` at construction) and the factory's immutable meme hook.

- Routes carry no data. The adapter reads `factory.getLaunchedToken(assetOut)` at
  swap time — the factory's immutable per-launch record — so a router config
  written before the launch existed can never disagree with what deployed. Phase
  `NotGraduated` buys on the bonding curve (`buy{value}` after unwrapping WETH);
  phase `PoolCreated` swaps the graduated v4 pool through `unlock`, rebuilding the
  factory's own pool key (native currency0, snapshotted `poolFee`/`tickSpacing`,
  meme hook); `Swept`/`Rescued` revert `NoMarket` — during `Swept` anyone may call
  the factory's permissionless `createGraduatedPool` to open the market.
- Native-quote launches only. A custom-pair launch trades in its pair asset, which
  the WETH bucket input cannot reach without a second conversion leg; the UI keeps
  the bucket blocked for custom pairs.
- A crossing buy near the graduation threshold is clamped and refunded by the
  curve; the adapter refuses the partial fill (`UnexpectedBalance`) because the
  router debits the full input and the floor was signed for it. Callers retry
  smaller or wait for the pool.
- The guard is pure signed floor (`SinjohPonsV2BuybackFloor`, five-minute maximum
  validity, same digest shape as the Flap guards). Unlike Flap there is no
  on-chain quote to cross-check: the curve exposes no quote view and the meme hook
  implements no oracle, and quoting v4 requires the unlock flow, which cannot run
  from a view context. The keeper's signer is the sole floor authority, which is
  the documented posture for graduated v2 pools.

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

### `SinjohPoolsTradeInstantAdapter`

pools.trade is Uniswap Labs' launchpad on Robinhood Chain — the open-source
liquidity-launcher stack. Contract sourcing, launch mechanics, and fee flow are
recorded in `POOLS-TRADE-FINDINGS.md`; all shapes below are taken from verified
on-chain source at the deployed commits.

The instant shape has no curve and no graduation: one launcher `multicall`
mints a fixed 1B-supply UERC20 and LPs it single-sided into a hookless
native-ETH v4 pool, permanently locked in the FeeSplitter. Creator revenue is
40% of the position's native LP fees, attributed to the launch's position
tokenId in the UERC20BeneficiaryVault and claimable only by the owner of the
transferable "FEEB" ERC-721.

- `launch(name, symbol, metadata, distributionSalt, developerBuy, minTokensOut)`
  — snapshots `positionManager.nextTokenId()`, multicalls
  `createToken(recipient = launcher)` + `distributeToken(strategy, feeBeneficiary = adapter)`,
  requires the returned token to equal `predictSubject(name, symbol)` (exact:
  the UERC20 CREATE2 salt is `(name, symbol, decimals, launcher, graffiti)`
  and the graffiti hashes the adapter), reads back both custody facts — the
  position locked in the FeeSplitter and the FEEB NFT minted to the adapter —
  binds the router, then performs the developer buy against the fresh pool by
  swapping the v4 singleton directly. The pool is live from the launch call,
  so the buy is un-front-runnable, and there is no launch fee and no snipe-tax
  mechanic to route around.
- `collect()` — `feeSplitter.collectFees([tokenId])` then
  `vault.claim(tokenId, 0, 0)`, wrapping the claimed native to WETH. Neither
  step reverts on zero accrual, so no error absorption exists on this path;
  any upstream revert is real and propagates.
- `intakeAssets()` — `[WETH]`. The subject is never a fee asset.
- `feeRoutingIntact()` — the two custody facts above, re-read. Neither has a
  legitimate way to change: the splitter has no withdrawal path and the
  adapter never transfers the FEEB NFT (its transferability is this stack's
  `transferCreatorFeeRecipient` analogue, and the adapter exposes no path to
  it).

The same bytecode serves the deployed no-creator-fee strategy variant
(`beneficiaryVault() == 0`), pinned by a second factory deployment: the launch
works identically, no FEEB NFT exists, `collect()` is a permanent no-op, and
`intakeAssets()` is empty. Nothing is ever owed, and the adapter says so
rather than pretending otherwise.

### `SinjohPoolsTradeLBPAdapter`

The auction shape: a ContinuousClearingAuction runs price discovery in any
currency (native or ERC20), then permissionless migration moves the raise and
a reserved LP supply into a v4 pool at the clearing price. Creator revenue is
three streams, and the adapter is the named recipient of all of them:

1. the non-LP raise share, swept to `recipient` at migration;
2. the migrated LP position NFTs, minted to `positionRecipient`, whose fees
   `collect` pulls with a zero-liquidity `DECREASE_LIQUIDITY` + `TAKE_PAIR`
   plan for as long as the pool trades;
3. unsold auction tokens, swept by `tokensRecipient` after the auction ends
   (tolerating exactly `AuctionIsNotOver()` and `CannotSweepTokens()`).

A failed migration refunds the raise and reserve to `recipient` — the adapter
— so the failure path also lands in the router, with `migrationFailed`
recorded so interfaces stop waiting for a pool.

- `launch(LBPLaunchParams)` — typed auction economics (blocks, floor, steps,
  brackets, pool fee/spacing/hook, position definitions) with every recipient
  forced to the adapter and per-position `overridePositionRecipient` refused
  outright. Side allocations ride the same multicall: optional
  `(recipient, amount)` splits through the pinned TokenSplitter, and optional
  merkle legs `(amount, merkleRoot, owner, endTime)` through the pinned
  MerkleClaimFactory, each deploying and funding one of Uniswap's audited
  merkle distributors atomically with the launch. Side totals must sum to
  `totalSupply - auctionAmount`; merkle legs are salted per index so identical
  legs cannot CREATE2-collide, and a leg's `owner` (who may withdraw unclaimed
  tokens after `endTime`) must not be the adapter — unclaimed airdrop supply
  is the creator's, not creator fees, and must stay outside the fee route. The
  deployed auction is predicted through the CCA factory's own `getAddress` and
  read back — token, currency, `tokensRecipient = adapter`,
  `fundsRecipient = strategy`, and strategy registration — before the router
  bind.
- `migrate()` — wraps the strategy's permissionless `migrate`, records the
  minted position tokenIds (all its — overrides were refused), and resolves
  the real pool key from `getPoolAndPositionInfo`, which settles the
  hookless-fallback ambiguity (a zero-hook launch migrates to the
  strategy-hooked key when the hookless pool was front-initialized).
  `registerPositions` recovers a migration executed directly on the strategy,
  verifying ownership and the committed pool per id.
- `intakeAssets()` — `[subject, WETH]` for a native auction,
  `[subject, currency]` otherwise. The subject is a real fee asset here
  (unsold tokens, token-side LP fees, reserve refunds), so the router needs a
  subject normalization route, as with pons v1.

The adapter's factory keeps a one-shot subject registry
(`adapterForSubject`), written by the clone inside its launch transaction —
the lookup the buyback route uses to resolve launch-configured pool keys.

### `SinjohPoolsTradeBuybackAdapter` and `SinjohPoolsTradeBuybackPriceGuard`

One singleton `ISinjohSwapAdapter` converts a router's WETH bucket share into
any pools.trade launch token. Routes carry no data; the key derivation is read
on-chain at swap time per shape: an LBP launch resolves through the factory
registry to its adapter's recorded `Migrated` key (native-quote only — a
custom-currency pool reverts `UnsupportedPair`), and anything else derives the
static instant key (native currency0, pinned fee/spacing, no hook) and
confirms the pool exists via a slot0 `extsload`. Unmigrated and
failed-migration LBP launches revert `NoMarket`.

The guard is the pure signed floor (`SinjohPoolsTradeBuybackFloor`,
five-minute maximum validity, same digest shape and signer as the Flap and
pons v2 guards). As there, no on-chain quote exists to cross-check: instant
pools are hookless v4 with no oracle, LBP pools may carry launch-chosen hooks
that implement none, and quoting v4 requires the unlock flow, which cannot
run from a view context. A `GatedSwapHook`-gated pool reverts inside the hook
until its gatekeeper approves swaps; callers treat that as no market yet.

### `SinjohPoolsTradeSellAdapter` and `SinjohPoolsTradeSubjectPriceGuard`

The normalization route for LBP launches, whose intake includes the subject
itself. The router's `sync(subject, floor)` needs a sell-direction swap and an
amount-aware guard — and normalization guards receive **no caller data**, so
signed floors cannot serve there; the minimum must come from on-chain state.

The sell adapter is one singleton for every launch: it resolves the market the
same way the buyback adapter does (LBP registry first, static instant key with
a slot0 existence read otherwise), sells the subject exact-in on v4, and
delivers WETH. A native-quote pool wraps (`routeData` empty); a
custom-currency pool hops currency-to-WETH through the pinned SwapRouter02
(`routeData` = the abi-encoded v3 fee tier), mirroring the pons v2
pair-buyback route in reverse. ERC20 settlement uses the singleton's
sync-transfer-settle sequence.

The guard prices the subject leg at the v4 pool's **spot** (slot0 via
view-safe `extsload`) under an immutable haircut — a deliberately weaker
oracle than the v3 TWAP guards, because v4 keeps no observations and quoting
v4 properly requires the unlock flow, which cannot run from a view context.
Three compensations, stated rather than hidden: the haircut bounds acceptable
slippage, the router's `maxAmountInPerCall` bounds the value one manipulated
call can touch, and the router requires a nonzero caller floor on every
normalization sync, which the keeper derives from a simulated execution. A
custom-currency launch composes the deployed shared v3 TWAP guard's
`quoteAtTwap` for the currency leg and requires the route's v3 tier to equal
the shared guard's tier, so the priced route and the executed route cannot
diverge. Failed-migration and pre-migration launches quote `NoMarket`, which
is correct: no pool exists, and the (worthless) subject refund of a failed
migration is the one asset knowingly left unsyncable.

Deployment, in order: `script/DeployPoolsTradeMerkleClaimFactory.s.sol`
deploys Uniswap's MerkleClaimFactory — which Uniswap has not deployed on
Robinhood Chain — as the byte-identical upstream artifact (vendored in
`script/artifacts/`, hash-asserted before broadcast) through the canonical
CREATE2 deployer with a zero salt, so the address
`0x0C8B3e001C8DbBDbe15089c887C9323E097F0a15` is a pure function of the
artifact and reproducible by anyone; then
`script/DeployPoolsTradeAdapterFactories.s.sol` deploys the three adapter
factories (instant creator-fee, instant no-fee, LBP) with all eight upstream
dependencies pinned by code hash; then
`script/DeployPoolsTradeBuybackInfrastructure.s.sol` deploys the buyback
singleton and guard against the already-deployed LBP factory; then
`script/DeployPoolsTradeNormalizationInfrastructure.s.sol` deploys the sell
adapter and subject price guard the same way.

pools.trade watch items, monitored rather than deferred: the CCA factory's
`protocolFeeController()` is zero today but mutable (a future controller
takes a cut of raises), and Uniswap rotates strategy deployments with
versions — the launcher address itself changed once between v3.0.0 and
v3.2.0. If Uniswap later publishes its own canonical MerkleClaimFactory at a
different address, existing launches are unaffected (each distributor is a
standalone contract) and new adapter factory deployments should repin.

### `SinjohLetsCashAdapter`

One predictable clone owns the creator-fee stream of one native-quote
letscash.fun vNext launch. The upstream factory requires
`TokenParams.creator == msg.sender`, so the adapter cannot proxy the launch
without replacing the human creator on-chain. The supported flow is therefore:

1. predict and deploy the adapter and router;
2. the creator calls `launchWithFeeSplit` directly with the adapter as the sole
   recipient and 10,000 shares;
3. the creator calls `adapter.activate(token, poolId, configId)`.

Activation validates the factory config identity, immutable hook module, native
quote, non-self-burn mode, token provenance, pool id, exact upstream fee terms,
and the sole adapter recipient before binding the router. It deliberately does
not re-check the factory's mutable global/config enabled switches after launch:
an owner pause between an EOA's two transactions must not strand fees already
assigned to the adapter. An EOA needs two transactions; a smart account may
batch them. The second call is safe to retry until confirmed and cannot activate
a launch routed anywhere else.

The vNext hook's `claim(poolId)` pays raw ETH to its recorded creator. The
permissionless adapter claims, wraps its entire ETH balance to WETH, and forwards
WETH through the standard router seam. Treasury, raffle, airdrop, wallet, and
other allocations are consequently the same router configuration used by the
other launchpads.

Fee ownership is deliberately one-way. letscash.fun permits only the current
creator recipient to call `updateCreator`, and this adapter exposes no arbitrary
call or update path. Once the launch records the adapter, neither the original
creator nor Sinjoh can redirect that stream. A self-burn launch is rejected
because its native letscash.fun burner recipient can never be redirected. This
does not restrict buybacks or burns configured downstream through the Sinjoh
router.

Only native-quote configs are supported. Although the current factory also
contains token-quote configs, they are outside this adapter's ETH-only profile.
The factory is upgradeable, so activation verifies post-launch immutable token
and hook state rather than trusting proxy behavior alone. The hook and pool
custody are immutable dependencies pinned by address and runtime code hash.

### `SinjohLetsCashBuybackAdapter` and `SinjohLetsCashBuybackPriceGuard`

The buyback adapter converts router WETH to the letscash.fun subject in its
native Uniswap v4 pool. Route data is exactly `abi.encode(configId)`; the adapter
reconstructs the pool key from the current config and requires the immutable
hook registry to contain the resulting pool id with matching fee economics.
It unwraps WETH, settles the native side inside the PoolManager unlock callback,
and returns the measured token output under the router's caller and guard floors.

The guard accepts a five-minute signed, amount-aware floor bound to chain,
guard, router, subject, assets, amount, and route-data hash. The keeper reads the
buyback adapter's own slot0 quote, applies the configured slippage bound, and
signs the floor. The quote accounts for the hook fee but intentionally leaves
price impact to the slippage allowance and the swap's enforced minimum.
Keeper manifests cap that allowance at 2,000 bps and must use conservative
per-call amounts; the signature authenticates a current same-pool observation
but does not turn slot0 into an independent oracle.

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

## Factory deployment

The v1 and v2 factories are deployed separately so each Forge script remains below
the EIP-170 runtime-size limit. Both scripts refuse the wrong chain or deployer, pin
every immutable upstream dependency by current code hash, and verify the factory
readbacks plus the implementation's initialization lock before returning.

```sh
DEPLOYER_PRIVATE_KEY=... forge script \
  script/DeployPonsV1LaunchAdapterFactory.s.sol:DeployPonsV1LaunchAdapterFactory \
  --rpc-url https://rpc.mainnet.chain.robinhood.com --broadcast

DEPLOYER_PRIVATE_KEY=... forge script \
  script/DeployPonsV2AdapterFactory.s.sol:DeployPonsV2AdapterFactory \
  --rpc-url https://rpc.mainnet.chain.robinhood.com --broadcast

forge script \
  script/DeployPoolsTradeMerkleClaimFactory.s.sol:DeployPoolsTradeMerkleClaimFactory \
  --rpc-url https://rpc.mainnet.chain.robinhood.com \
  --account sinjoh-deployer --broadcast

forge script \
  script/DeployPoolsTradeAdapterFactories.s.sol:DeployPoolsTradeAdapterFactories \
  --rpc-url https://rpc.mainnet.chain.robinhood.com \
  --account sinjoh-deployer --broadcast

POOLS_TRADE_LBP_FACTORY=0x... forge script \
  script/DeployPoolsTradeBuybackInfrastructure.s.sol:DeployPoolsTradeBuybackInfrastructure \
  --rpc-url https://rpc.mainnet.chain.robinhood.com \
  --account sinjoh-deployer --broadcast

SINJOH_LETSCASH_QUOTE_SIGNER=0x... forge script \
  script/DeployLetsCashInfrastructure.s.sol:DeployLetsCashInfrastructure \
  --rpc-url https://rpc.mainnet.chain.robinhood.com \
  --account sinjoh-deployer --broadcast
```

## Robinhood Chain mainnet dependencies

| Contract | Address |
|---|---|
| letscash.fun factory proxy | `0x5bd1Fbe78a78fe8236fa00CF48fbEBA74ae34661` |
| letscash.fun current vNext hook | `0x75A54357D9C78a2Db19004a5FDc76c50F9242AEC` |
| pons v2 launch factory | `0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e` |
| pons v2 launch deployer | `0x3711ceA4feaDE896C913C68F01Eda97Cb06D1A42` |
| pons v2 fee escrow | `0xd3AFEB2a57f70eF218Aa82451c51B2fb0416Ac9e` |
| pons v2 launch locker | `0x267444D099b10fB5Ed7c3Cc7B7c767AdcA574952` |
| pons v2 meme hook | `0xE5e702641Ea86F4ae6cC3cDaeD2B886f976Be044` |
| pons v2 buyback vault | `0x42df2a798f82289E177311362e8f5ccC45c1219c` |
| pons v2 graduation executor | `0xC7819B64A1dAECD7eC19856d026cb14EfBd89046` |
| pons v2 launch forwarder (pons's own atomic router) | `0xe33E9E479dF8802cb0866d5d05258bEc4cF62948` |
| superseded v2 factory (paused at block 24672804) | `0x7E1EAbd52Ae29598e6483F72dCf1a70b14284dB8` |
| Uniswap v4 PoolManager | `0x8366a39CC670B4001A1121B8F6A443A643e40951` |
| Uniswap v4 PositionManager | `0x58daec3116aae6D93017bAAea7749052E8a04fA7` |
| WETH | `0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73` |
| pons v1 launch factory (legacy) | `0xA5aAb3F0c6EeadF30Ef1D3Eb997108E976351feB` |
| pons v1 locker (legacy) | `0x736D76699C26D0d966744cAe304C000d471f7F35` |
| pools.trade LiquidityLauncher v3.2.0 | `0x0000FffFBE8efE702c8703aE3477FF5dE3d319C0` |
| pools.trade UERC20Factory v2.0.0 | `0x000000e200088D55C39a11F609E5F667729ad49b` |
| pools.trade InstantLaunchStrategy (creator fee) | `0x23f8209572b4a1C2AD88A42749E830791Fb027f1` |
| pools.trade InstantLaunchStrategy (no creator fee) | `0xAD44D55E7f8337C3cE113fBb591486E85be104b2` |
| pools.trade FeeSplitter (creator fee) | `0xeFF166AAf189323c58dc27eD1206EB2C37FaACDf` |
| pools.trade FeeSplitter (no creator fee) | `0x222D6d4f1ce59b0d48D5505114eC8Addc90A4359` |
| pools.trade UERC20BeneficiaryVault | `0xd35E9CA72F64C7F93BE30fad67524323396B36D7` |
| pools.trade CompoundingClaimRecipient | `0xf9526Dd3361fe0ba6b7a99533ed471D3E808E99a` |
| pools.trade LBPStrategy v3.1.1 | `0x05d552391067389EE44fec3924157ed33F976000` |
| pools.trade CCA factory | `0x000000001F26a0044BaA66024e7b6599c61963F8` |
| pools.trade InitializerHook | `0xD462a559337859369EF271814851A18F496ba000` |
| pools.trade TokenSplitter v3.2.0 | `0x4F5E3FBb9745358A92Da5674305FAb8D2B8a73cE` |
| pools.trade UniversalRouterStrategy | `0x1242c9439d589cAE85E121B1f79f2aF51e91DCEE` |
| pools.trade MerkleClaimFactory (Sinjoh's byte-identical deployment of the upstream artifact) | `0x0C8B3e001C8DbBDbe15089c887C9323E097F0a15` |
| Uniswap v4 UniversalRouter | `0x8876789976dEcBfCbBbe364623C63652db8C0904` |
| superseded pools.trade launcher v3.0.0 (legacy) | `0x00004c4ccc709Ef590F7C81102C0689F0263D4e9` |

All v2 shapes in this spec are taken from verified on-chain source, not from
`docs.ponsfamily.com/v2`, which misstates at least six event signatures. See
`PONS-V2-FINDINGS.md`.
