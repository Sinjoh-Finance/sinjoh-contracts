# Pons v2 — verified on-chain findings

Source of truth: **verified contract source on Blockscout**, chain 4663, read 2026-07-31.
The published docs at `docs.ponsfamily.com/v2` are wrong in several places (noted below).
Where docs and ABI disagree, the ABI wins.

## 2026-08-04 update: pons redeployed v2 — everything below the line describes the superseded deployment

The pause recorded below ended in a **full redeployment**, not an unpause. Sinjoh's
test launch `0xf985da537a04c35fc720fcd9539e2ba12ffb7d59d6cd86c68a1072181c07c13c`
(token `0xf032a9178071F94AFedB562F79040894F371ae7b`, block 27883694) went through a
new factory. Current addresses, all verified on Blockscout:

| Contract | Address |
|---|---|
| Launch Factory | `0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e` |
| Launch Deployer | `0x3711ceA4feaDE896C913C68F01Eda97Cb06D1A42` |
| Fee Escrow | `0xd3AFEB2a57f70eF218Aa82451c51B2fb0416Ac9e` |
| Meme Hook | `0xE5e702641Ea86F4ae6cC3cDaeD2B886f976Be044` |
| Launch Locker | `0x267444D099b10fB5Ed7c3Cc7B7c767AdcA574952` |
| Graduation Executor | `0xC7819B64A1dAECD7eC19856d026cb14EfBd89046` |
| Buyback Vault | `0x42df2a798f82289E177311362e8f5ccC45c1219c` |
| Launch Forwarder (new) | `0xe33E9E479dF8802cb0866d5d05258bEc4cF62948` |
| Factory owner (changed) | `0xFdDE5a1E3cDF791Da71E49F817D70C7ceD72CC36` |

PoolManager, PositionManager, Permit2, and WETH are unchanged. Live state:
`launchEnabled = true`, launch fee 0.0005 ETH, config 0 economics unchanged
(supply 1e27, 1% curve fee, 1.68 ETH phantom, 4.2 ETH graduation), fee policy
snapshot `(30% protocol, 50% buybackBurn, 1% hook fee, 3% max impact)`,
`maxCreatorTaxBps = 1000`. All eight pair assets re-approved with the same
economics, USDG still 6 decimals.

ABI changes against the superseded deployment:

1. **CREATE2 is back.** `TokenParams` grew a trailing `bytes32 salt`; the deployer
   uses CREATE2 namespaced per factory-authenticated initiating account, and
   `PonsV2LaunchDeployer.predictLaunchAddresses` exists again. Old blocker #1
   (non-deterministic token addresses) is resolved, though the adapter still binds
   from within the launch transaction and needs no prediction.
2. **Snipe tax.** 99% of a buy's quote leg in the launch second, decaying to zero
   across 5 seconds (owner-tunable; the curve snapshots the factory's values at
   launch). Keys on the buy's **recipient**. The factory auto-exempts the launch
   caller and `creatorFeeRecipient` — both the Sinjoh adapter — so the atomic
   developer buy is untaxed. A new `launchToken` overload takes
   `address[] snipeTaxExemptions` (max 32) for a team's bundle wallets; snipe-tax
   proceeds accrue into `quoteFeeBalance` and split like the base fee.
3. **`launchTokenFor(params, configId, pairToken, originalDeployer, exemptions)`** —
   restricted to the configured `launchForwarder` (pons's own atomic launch-and-buy
   router). Not usable by Sinjoh, but it demonstrates the singleton-launcher pattern
   the open question below contemplated.
4. **`sweepFees(uint256 minBuybackTokensOut)`** now takes a mandatory floor when a
   buyback would execute; with buyback disabled the adapter passes zero. Gating is
   unchanged (deployer may sweep while no buyback balance is pending). The curve's
   `deployer` slot **is** the creator-fee recipient: `_sweepFees` credits the
   creator amount to `deployer`, and `setCreatorFeeRecipient` reassigns `deployer`,
   so sweep rights follow the fee recipient — the 3-day timelocked protocol
   override therefore moves both payout and sweep authority. This is the v2
   analogue of v1's `feeRedirectIntact()` watch item.
5. The whitelist survives (`launchEnabled || whitelistedLaunchers[originalDeployer]`);
   only the new owner is whitelisted today. The singleton-launcher decision below is
   still open, and still cheap-now-impossible-later.

`SinjohPonsV2Adapter`, its factory, mocks, unit tests (37) and mainnet fork tests
(12, including live snipe-tax-exemption and creator-tax coverage) were re-verified
against this deployment on 2026-08-04. The superseded fee escrow at `0xbc39B650…`
holds nothing of Sinjoh's; no migration is needed.

---

## Deployment status

Every v2 address has code. The docs line "launch factory and curves not yet live" is stale.

| Contract | Address |
|---|---|
| Launch Factory (`PonsV2LaunchFactory`) | `0x7E1EAbd52Ae29598e6483F72dCf1a70b14284dB8` |
| Launch Deployer (`PonsV2LaunchDeployer`) | `0xdD89f26beA3916233d002D1189F973B78D38aA70` |
| Fee Escrow | `0xbc39B6502E1a6Ab36E4A5c5026A35F08342A0A9c` |
| Meme Hook | `0x8e99D2009D60A917e9B1c00C04C077b8c0c3a044` |
| Launch Locker | `0x28b6F0116c7F234951cf0e67319ed53863Df2197` |
| Graduation Executor | `0xbccBb394E40d718710F4275C23f9F851B680565a` |
| Graduation Guard | `0xFef36C2ca32D3eCD18C371021950d44033Bee531` |
| Buyback Vault | `0x2d6e3aA895EDa2603189c2A89679bD4279175FdB` |
| Uniswap v4 PoolManager | `0x8366a39CC670B4001A1121B8F6A443A643e40951` |
| Uniswap v4 PositionManager | `0x58daec3116aae6D93017bAAea7749052E8a04fA7` |
| Permit2 | `0x000000000022D473030F116dDEE9F6B43aC78BA3` |
| Factory owner | `0x0815A4881f9c4073a70fdF00600EbA54c5a5baAa` |

Live state: `launchEnabled = true`, `launchFee = 5e14` (0.0005 ETH),
`launchConfigCount = 1`, `maxCreatorTaxBps = 1000`, creator-fee-recipient timelock
`259200` (3 days). All dependencies wired — `LaunchDependenciesNotWired` will not fire.

`getLaunchConfig(0)` = supply `1e27`, curveFeeBps `100`, phantomQuote `1.68e18`,
graduationThreshold `4.2e18`, poolFee `0`, tickSpacing `200`, enabled `true`.
Launch fee, 1.00% trade fee and 4.2 ETH graduation are unchanged from v1, so the
UI's headline numbers carry over.

## Non-blockers (previously suspected, now disproven)

**Native ETH pairs need no approval.** `approvedPairTokens(0x0)` returns false, but the
guard is `if (pairToken != address(0) && !approvedPairTokens[pairToken]) revert
PairTokenNotApproved();`. Native launches read economics from the launch config, not
from `pairTokenEconomics`. `previewLaunchEconomics(0, 0x0)` returns a valid non-zero
pin, confirming config 0 + native is launchable today.

**No Pons permission required *while launches are enabled*.** The whitelist guard is
`if (!launchEnabled && !whitelistedLaunchers[msg.sender]) revert NotWhitelisted();` —
a bypass for when launches are globally paused. With `launchEnabled = true` anyone,
including a contract, can launch. See the pause caveat below: this flag is operational
and does move.

**Contract launchers are supported.** `originalDeployer` and the default
`creatorFeeRecipient` are both `msg.sender`, so a router that launches remains the
deployer and fee recipient. The router-owned model survives v2.

**No custom ERC-20 pair is approved yet.** Nothing is registered in
`approvedPairTokens`, so a USDG/equity pair selector has no backing asset today. That
is a Pons-side gap, not a Sinjoh one.

## v2 is live and busy

`TokenLaunched` logs from block 23551520 to head: **1042 launches**. v2 is not a
future migration target, it is where the volume already is.

Pair-asset breakdown, and the approved set (`approvedPairTokens`):

| Pair asset | Address | Dec | Launches | Approved |
|---|---|---|---|---|
| $NVDA | `0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC` | 18 | 219 | yes |
| **native ETH** | `0x0000…0000` | 18 | 195 | n/a — needs no approval |
| $SPCX | `0x4a0E65A3EcceC6dBe60AE065F2e7bb85Fae35eEa` | 18 | 139 | yes |
| $GME | `0x1b0E319c6A659F002271B69dB8A7df2F911c153E` | 18 | 119 | yes |
| $AAPL | `0xaF3D76f1834A1d425780943C99Ea8A608f8a93f9` | 18 | 109 | yes |
| $TSLA | `0x322F0929c4625eD5bAd873c95208D54E1c003b2d` | 18 | 106 | yes |
| $GOOGL | `0x2e0847E8910a9732eB3fb1bb4b70a580ADAD4FE3` | 18 | 60 | yes |
| $SPY | `0x117cc2133c37B721F49dE2A7a74833232B3B4C0C` | 18 | 48 | yes |
| **USDG** | `0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168` | **6** | 47 | yes |

Not approved despite being in our RWA presets: $COIN, $MSTR, $RDDT. WETH is not
approved either — the ETH option is `pairToken = address(0)`, not WETH.

**Only 19% of v2 launches pair against native ETH.** A native-only integration would
miss most of the market, and the ETH/USDG selector in the target design implies custom
pairs are in scope.

### USDG has 6 decimals

This is the one finding that reaches into the router. `SinjohFeeRouter` normalizes
everything to WETH and its accounting is 18-decimal throughout: `sync(asset)` accepts
only `subject` or `weth`, and `_subjectToWeth` is the single normalization route.

For a custom-pair launch, fees arrive **in the pair asset** — USDG, $NVDA, $SPY — which
is neither the subject nor WETH, so `sync` rejects it outright. Supporting custom pairs
means the router needs a general per-intake-asset normalization route rather than the
one hardcoded subject-to-WETH leg, and that route must be decimal-correct for a 6-decimal
input.

### Custom-pair developer buys need an allowance

`curve.buy` is payable and takes `quoteIn` as value for native launches, but for a
custom pair the caller must hold and approve the pair token first. An adapter doing an
atomic developer buy on a custom-pair launch would have to pull the pair asset from the
creator via `transferFrom`, which the v1 adapter security rules forbid outright ("no
allowance is granted and no `transferFrom` is used"). That rule needs an explicit,
narrow exception or custom-pair dev buys have to be dropped.

## Launches are currently paused, and that has an architectural consequence

`LaunchEnabledUpdated` history on the factory:

| Block | `launchEnabled` |
|---|---|
| 24633492 | true |
| **24672804** | **false** ← current |

Pons paused launches at block 24672804, partway through this review. While paused,
`launchToken` reverts `NotWhitelisted()` for every caller except an address in
`whitelistedLaunchers`. Only two are set: the factory owner
`0x0815A4881f9c4073a70fdF00600EbA54c5a5baAa` (block 23567980) and
`0xd48E5622a6F0d015388fBed4272a336535927fa4` (block 24363932).

**The pause is pons fixing a fault they found in their own code.** Sinjoh cannot ship
v2 launches until they resolve it, regardless of what we build. 1042 launches across
**369 distinct deployers** happened while the flag was on, so the mechanism works; the
current stop is theirs, not ours.

`SinjohPonsV2Adapter` is complete and tested against the live deployment and can sit
ready. Work continues on the launchpad-agnostic router in the meantime, which is not
blocked by pons at all.

**The consequence for our design.** The whitelist keys on `msg.sender`. Sinjoh's
per-launch adapter is a fresh CREATE2 clone for every launch, so its address cannot be
whitelisted ahead of time and the whitelist can never help us. Being launchable during
a pause would require a **singleton launcher** — one long-lived, whitelistable contract
that calls `launchToken` and passes the per-launch adapter as `creatorFeeRecipient`
(which is a stored address and need not be `msg.sender`).

That change is cheap now and impossible later, since both contracts are immutable. It
also moves `deployer` from the adapter to the singleton, which matters because
`sweepFees` accepts `msg.sender == deployer` — the singleton would need a permissionless
`sweepFees(curve)` passthrough for fee collection to keep working.

Decision required before the router is rebuilt: per-launch adapter as launcher (simpler,
cannot launch during a pause) versus singleton launcher plus per-launch adapter
(whitelistable, one more contract).

## Curve fees do not reach the escrow on their own

Trading fees accrue on the curve as `quoteFeeBalance`/`creatorTaxBalance`. They only
move to the escrow when someone calls `sweepFees`, which is gated:

```solidity
bool isOperator = msg.sender == feePolicy.feeSweepOperator();
if (!isOperator && msg.sender != deployer) revert NotFeeSweepOperator();
if (!isOperator && _requiresTrustedOperator()) revert InternalSwapRequiresOperator();
```

and `_requiresTrustedOperator()` is `buybackQuoteBalance != 0`.

So the launch deployer may sweep its own curve, but only while no buyback balance is
pending. `buybackQuoteBalance` only accumulates when `buybackEnabled` is set at launch.

**Sinjoh therefore launches with `buybackEnabled = false`, enforced in the adapter.**
Enabling it would hand the sweep to pons's own operator and end permissionless fee
arrival — the property the entire routing guarantee depends on. A `collect()` that
claimed without sweeping would have drained a usually-empty escrow while the real fees
sat on the curve indefinitely.

`graduate()` also calls `_sweepFees` internally, so a buy that crosses the graduation
threshold sweeps on its way through and the curve's own `sweepFees` then reverts
`AlreadyGraduated`. Both paths are covered by fork tests.

## A v4 TWAP price guard is not buildable for graduated pools

`SinjohSharedV3TwapPriceGuard` reads a Uniswap v3 pool's `observe()` oracle. There is
no equivalent to port to.

Uniswap v4 core removed the built-in oracle — observations moved into hooks — and the
**pons meme hook does not implement one**. Its full function list contains no
`observe`, no observations array, no cardinality, nothing historical:

```
afterAddLiquidity, afterDonate, afterInitialize, afterRemoveLiquidity, afterSwap,
beforeAddLiquidity, beforeDonate, beforeInitialize, beforeRemoveLiquidity, beforeSwap,
buybackBurnBps, buybackVault, currentFeePolicy, factory, feeEscrow, feeSweepOperator,
getHookPermissions, hookFeeBps, launches, maxInternalPriceImpactBps, owner,
pendingBuyback, pendingCreatorTax, pendingFees, poolManager, protocolFeeRecipient,
protocolFeeShareBps, registerPool
```

`StateView.getSlot0` gives spot `sqrtPriceX96` and nothing else, so a guard over a
graduated pons v2 pool could only ever compare spot against spot — which a sandwich
moves in the same transaction.

Options, none of them free:

1. **Caller-supplied floors only.** Already the fee router's posture after audit
   finding F2 added `sync(asset, minAmountOut)`, and `processBucket` always took one.
   The floor has to be computed off-chain by whoever calls, which puts the burden on
   the keeper.
2. **Route conversions through the v3 fork instead.** Works for pair assets — USDG and
   the equity tokens have v3 pools — but not for a graduated launch token, whose only
   market is its v4 pool.
3. **Ask pons to add an oracle to the hook.** Out of our control and not something to
   plan around.

The practical consequence: the liquidity manager, which is the component that consults
the guard, cannot mint into a graduated v2 pool under TWAP protection the way it does
for v3. That is a v2-only limitation; v1 launches are unaffected because they graduate
into v3 pools with working oracles.

**2026-08-04: option 1 is now built for buybacks.** `SinjohPonsV2BuybackAdapter` +
`SinjohPonsV2BuybackPriceGuard` (sinjoh-launchpad-adapters) implement the buyback
bucket as a phase-routed swap — bonding curve pre-graduation, hooked v4 pool after —
under a pure signed floor, since no on-chain quote exists in either phase. The
adapter derives everything from `factory.getLaunchedToken(token)` at swap time
(native-quote launches only), so nothing launch-specific is baked into the immutable
router config.

## Blockers and breaking changes

### 1. Token addresses are not deterministic

`PonsV2LaunchDeployer` uses plain `new PonsV2…` (CREATE, nonce-based). No salt
parameter, no CREATE2, no `Clones`. v1's `salt` argument is gone.

Consequence: the current router-first flow cannot pre-commit anything derived from the
token address. Today `use-pons-launch.ts` predicts the token, derives a v3 pool from it,
and bakes that pool into the router's immutable `configHash` *before* launching. That
sequence is impossible on v2.

### 2. There is no pool until graduation, and then it is Uniswap v4

Pre-graduation the curve is the only market. Post-graduation the pool is a v4 pool with
`fee = 0` and a mandatory pons hook, addressed by PoolId inside the singleton
PoolManager — not a CREATE2 address. Both the v3 pool derivation in
`pons-router-dependencies.ts` and the `poolInitCodeHash` in the manifest become
meaningless for v2 launches.

### 3. `launchToken` rejects a developer buy

`if (msg.value != launchFee) revert LaunchFeeNotPaid();` — exact equality. v1 accepted
`launchFee + developerBuy` and performed the first buy inside the launch. v2 has no
first-buy path; a dev buy must be a separate `curve.buy(quoteIn, minTokensOut, recipient)`
call. To keep it atomic and un-snipeable it has to be a router-mediated second call in
the same transaction.

### 4. Fees are pull-based and arrive in the pairing asset

Creator fees accrue in the shared escrow. The recipient must call `claim()` (native) or
`claimToken(token)` (ERC-20) from its own address. `SinjohFeeRouter.collectPonsFees()`
calls `IPonsV1Locker.collectFees(subject)` and is dead on v2.

Fees are always denominated in the pairing asset and never in the launch token. For a
native launch that is raw ETH. The router's `receive()` is a bare no-op and `sync(asset)`
rejects anything that is not `subject` or `weth`, so claimed ETH would sit permanently
unaccounted. A wrap-on-claim or native intake path is required.

### 5. The v1 launch call signature is gone

```solidity
// v1
launchToken(LaunchParams params, uint256 launchConfigId, uint256 dexId, bytes32 salt)
    returns (address token)
// v2
launchToken(TokenParams params, uint256 launchConfigId, address pairToken)
    payable returns (address token, address curve)
```

`TokenParams` = `(string name, string symbol, string logo, string description,
(string twitter, string telegram, string discord, string website, string farcaster) socials,
address creatorFeeRecipient, uint16 creatorTaxBps, bool buybackEnabled,
bytes32 expectedEconomics)`.

Note `creatorTaxBps` is **uint16**, not the uint256 the docs imply. `feeWallet` is gone,
replaced by `creatorFeeRecipient`. `dexId` and `salt` are gone. Two return values, not one.

`expectedEconomics` is an optional terms pin — `bytes32(0)` skips the check. It should be
set from `previewLaunchEconomics(launchConfigId, pairToken)`, because every economic term
is owner-updatable and can move between quote and execution.

### 6. Fee policy is dynamic and snapshotted per launch

`memeHook.currentFeePolicy()` is read at launch and frozen into `_launchFeePolicies[token]`.
The UI's current `protocolFeeShare == 30` equality check has no v2 equivalent; readback
must use `getLaunchFeePolicy(token)`.

## Doc errors found

The docs misstate at least four signatures. Verified versions:

- `PoolGraduated(address token, uint256 positionId, uint256 tokenAmount, uint256 pairTokenAmount)`
  — docs say `(token, pool)`.
- `LaunchSwept(address token, uint256 quoteOut, uint256 tokenOut)` — docs say `(token)`.
- `CreatorFeeRecipientChangeProposed(address token, address currentRecipient,
  address proposedRecipient, uint256 effectiveAt, uint256 expiresAt)` — docs omit
  `currentRecipient`.
- `CreatorFeeRecipientUpdated(address token, address previousRecipient, address newRecipient)`
  — docs omit `previousRecipient`.
- `Credited(address recipient, address depositor, uint256 amount)` — docs omit `depositor`.
- `CreditedToken(address recipient, address token, address depositor, uint256 amount)`
  — docs omit `depositor`.

Also undocumented: `claim()` and `claimToken(address)` each have a partial-amount
overload (`claim(uint256)`, `claimToken(address,uint256)`), and an empty claim reverts
`NoBalance()` rather than returning zero — which is what the keeper's
"revert means nothing accrued" pacing must key on.

Any v2 integration must be built against the on-chain ABI, not the docs.
