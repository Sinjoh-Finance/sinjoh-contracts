# Pons v2 — verified on-chain findings

Source of truth: **verified contract source on Blockscout**, chain 4663, read 2026-07-31.
The published docs at `docs.ponsfamily.com/v2` are wrong in several places (noted below).
Where docs and ABI disagree, the ABI wins.

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
