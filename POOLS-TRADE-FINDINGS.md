# pools.trade findings

On-chain research for the `SinjohPoolsTrade` adapter family, sourced from the
sample token `0xd3D5bE6558F84e628EE091B511Df92b4e461a53b` (UNIPEG, "Unicorn
Pegasus"). Scope: **the full protocol surface** — every launch option the stack
supports is in scope for the first release; nothing is deferred.

## What pools.trade is

pools.trade is **Uniswap Labs' own launchpad on Robinhood Chain** (chain id 4663,
the same chain as Pons and Flap). It went live 2026-08-05 16:00 UTC — the broken
UI is launch-day breakage, not abandonment. The contracts are Uniswap's
open-source **liquidity-launcher** stack:
<https://github.com/Uniswap/liquidity-launcher> (MIT, audited, `docs/audit/` +
whitepaper in-repo), with the auction leg provided by Uniswap's
**continuous-clearing-auction** repo:
<https://github.com/Uniswap/continuous-clearing-auction>. Everything below is
verified on Blockscout and cross-checked against those repos at the deployed
commits.

There are two launch shapes, both live and both in scope:

1. **Instant launch** — no curve, no graduation. Mints a fixed-supply UERC20 and
   immediately LPs the entire supply single-sided into a **hookless native-ETH
   Uniswap v4 pool**; the LP position is permanently locked in a `FeeSplitter`.
   Trading is live from the launch transaction.
2. **LBP auction launch** — a **ContinuousClearingAuction** (CCA) price-discovery
   phase in any currency (native or ERC20), then permissionless migration of the
   raise + reserved supply into a v4 pool at the clearing price. 67 launches in
   the first day; this is the whitepaper's headline mechanism.

## Contract addresses (Robinhood Chain mainnet)

Current stack (v3.2.0 launcher, commit `dd8769cd45c0e9450e928513ee129b0af74f7f32`;
LBP v3.1.1, commit `5ef0262b8e191360a212aac864a525dcf7a06605`):

| Contract | Address | Notes |
|---|---|---|
| LiquidityLauncher v3.2.0 | `0x0000FffFBE8efE702c8703aE3477FF5dE3d319C0` | entry point; `multicall` of `createToken` / `depositToken` / `distributeToken` / `distributeWithNative` |
| UERC20Factory v2.0.0 | `0x000000e200088D55C39a11F609E5F667729ad49b` | CREATE2 token deploys; OpenZeppelin-audited; chain-invariant address |
| InstantLaunchStrategy (creator-fee) | `0x23f8209572b4a1C2AD88A42749E830791Fb027f1` | pins FeeSplitter `0xeFF1…ACDf` + UERC20BeneficiaryVault |
| InstantLaunchStrategy (no-creator-fee) | `0xAD44D55E7f8337C3cE113fBb591486E85be104b2` | pins FeeSplitter `0x222D…4359`; 100% of fees compound; no beneficiary vault |
| FeeSplitter (creator-fee) | `0xeFF166AAf189323c58dc27eD1206EB2C37FaACDf` | locks instant-launch positions; 40% native → vault, 60% native + 100% token → compounding |
| FeeSplitter (no-creator-fee) | `0x222D6d4f1ce59b0d48D5505114eC8Addc90A4359` | 100% native + 100% token → compounding |
| UERC20BeneficiaryVault | `0xd35E9CA72F64C7F93BE30fad67524323396B36D7` | creator-fee escrow; mints transferable "FEEB" ERC-721 per launch; fallbacks: native → `0x2aC03e14…82F8`, token → `0xdead` |
| CompoundingClaimRecipient | `0xf9526Dd3361fe0ba6b7a99533ed471D3E808E99a` | permissionlessly compounds fee share back into the locked position |
| LBPStrategy v3.1.1 | `0x05d552391067389EE44fec3924157ed33F976000` | is itself a valid v4 hook address (fallback hook role) |
| ContinuousClearingAuctionFactory | `0x000000001F26a0044BaA66024e7b6599c61963F8` | LBPStrategy's pinned `initializerFactory`; `protocolFeeController()` = zero (no protocol fee on raises today, but mutable — watch it) |
| InitializerHook | `0xD462a559337859369EF271814851A18F496ba000` | gates pool init to the LBPStrategy; salt `0x…2dcb` |
| UniversalRouterStrategy | `0x1242c9439d589cAE85E121B1f79f2aF51e91DCEE` | runs a caller-supplied UR route so launch + first buy fit in one tx |
| TokenSplitter v3.2.0 | `0x4F5E3FBb9745358A92Da5674305FAb8D2B8a73cE` | splits one distribution across N recipients without custody |
| Uniswap v4 PoolManager | `0x8366a39CC670B4001A1121B8F6A443A643e40951` | same singleton Pons v2 graduates into |
| Uniswap v4 PositionManager | `0x58daec3116aae6D93017bAAea7749052E8a04fA7` | mints launch LP positions; `tokenId` keys all fee flow |
| UniversalRouter | `0x8876789976dEcBfCbBbe364623C63652db8C0904` | what live swap traffic uses |
| Permit2 | `0x000000000022D473030F116dDEE9F6B43aC78BA3` | canonical |

Legacy stack — what the sample token actually used (v3.0.0, superseded; do not
integrate): launcher `0x00004c4ccc709Ef590F7C81102C0689F0263D4e9`, early
unverified InstantLaunchStrategy `0x60D73b21cDf2EA846ab3d58699BBbb8F29d72491`,
plain BeneficiaryVault `0x587D2fDDDF14F6f84022b51e8c3a473eB88C4544`. UNIPEG came
through a third-party front end ("launchproof.fun") on that old launcher
(tickSpacing 60); every launch sampled on the v3.2.0 launcher uses the current
parameters below.

USUPERC20Factory (Superchain token variant) is **not** deployed on Robinhood
Chain — Base/Unichain only — so UERC20 is the only token factory in scope.

All core contracts deploy through the deterministic CREATE2 proxy
(`0x4e59b4…956C`); launcher, UERC20Factory, and TokenSplitter addresses are
chain-invariant, strategies and periphery are per-chain.

## Common launch plumbing (both shapes)

One `multicall` on the launcher composes:

1. `createToken(factory, name, symbol, decimals, initialSupply, recipient=launcher, tokenData)`
   — `tokenData = abi.encode(UERC20Metadata{string description, string website, string image, bytes extraData})`.
   The launcher stamps `graffiti = keccak256(abi.encode(msg.sender))` — the
   **adapter**, when the adapter initiates. Alternatively `depositToken(token, amount)`
   pulls an existing ERC20 via Permit2 (existing-token flow, also in scope).
2. `distributeToken(token, Distribution{strategy, amount, configData}, salt)` —
   the launcher approves the strategy, which pulls the tokens; distribution salts
   are namespaced `keccak256(abi.encode(msg.sender, salt))`, i.e. by the adapter.
3. optionally `distributeWithNative(UniversalRouterStrategy, configData, salt, nativeAmount)`
   — dev buy in the same transaction (below).

**Token address prediction is exact** (resolves the old open question 3):
`UERC20Factory.getUERC20Address(name, symbol, decimals, creator, graffiti)` is a
view over `CREATE2(salt = keccak256(abi.encode(name, symbol, decimals, creator, graffiti)))`
where `creator` is the **launcher** (it is the factory's `msg.sender`) and
`graffiti` derives from the adapter. `predictSubject()` parity with the Flap
adapter is a single staticcall. Consequence: the same (name, symbol) from the
same adapter collides — each adapter clone is one-shot anyway, so this only
means launch must treat "prediction occupied" as fatal, exactly like Flap.

**Graffiti is also an authority**: `UERC20BeneficiaryVault` lets the address
hashed in the token's graffiti register an unregistered position's beneficiary
NFT asynchronously. With the adapter as the launcher-caller, that authority is
the adapter itself — a nice belt-and-suspenders, but InstantLaunchStrategy
registers synchronously at launch so it should never be needed.

## Shape 1 — InstantLaunchStrategy

Verified against live launches (tx `0x3cb9c0e0…b406` et al.) and on-chain reads
of `0x23f8…27f1`: `initialTick() = 198050`, immutable.

The strategy, atomically: requires supply exactly `1_000_000_000e18` and 18
decimals; initializes pool key
`{currency0: native(0), currency1: token, fee: 2500, tickSpacing: 25, hooks: 0}`
at tick 198050; mints one single-sided position spanning `[-160100, 198050]`
holding the full supply (dust burned to `0xdead`); registers
`configData = abi.encode(InstantLaunchConfig{address feeBeneficiary})` with the
beneficiary vault (mints the FEEB ERC-721 for the position's `tokenId` to the
beneficiary); transfers the LP NFT to the FeeSplitter permanently. `tokenId` is
`positionManager.nextTokenId()` at launch.

Fee flow (splits verified via `getSplits()`):

- `FeeSplitter.collectFees(uint256[] tokenIds)` — **permissionless** — collects
  accrued v4 LP fees and pushes 40% of **native ETH** to the vault attributed to
  `tokenId`; 60% native + 100% token-side to `CompoundingClaimRecipient`.
- `vault.claim(tokenId, min0, min1)` — callable **only by the FEEB NFT owner** —
  pays the attributed native ETH to the caller. Zero-accrual claim is a no-op
  payout, not a revert.

The **no-creator-fee variant** `0xAD44…04b2` (FeeSplitter `0x222D…4359`,
`beneficiaryVault = 0`) is identical except `configData` is ignored (still must
be non-empty), no FEEB NFT exists, and 100% of all fees compound into the locked
position. There is no creator revenue, so there is nothing for Sinjoh to route —
but it is a supported launch option: the adapter takes the strategy choice as a
launch parameter, and for this variant `collect()` and `forward()` are permanent
no-ops with `intakeAssets() = []`. Both strategy addresses are pinned immutably;
the choice is validated at launch, not caller-supplied calldata.

## Shape 2 — LBPStrategy + ContinuousClearingAuction

`configData = abi.encode(MigratorParameters, bytes initializerParams)`.

```solidity
struct MigratorParameters {
    address token;                       // must equal the launched token
    address currency;                    // auction currency; address(0) = native, or any ERC20
    uint64  migrationBlock;              // must be strictly after the auction endBlock
    uint128 reservedTokenAmountForLP;    // supply held back by the strategy for the v4 position(s)
    address recipient;                   // gets non-LP raise share + post-migration dust + failure refunds
    address positionRecipient;           // default owner of the minted v4 LP position(s)
    PoolParameters poolParameters;       // fee (static or DYNAMIC_FEE_FLAG), tickSpacing, hook
    bytes positionDefinitions;           // abi-encoded PositionDefinition[] (weighted ranges, per-position recipient overrides)
    bytes lpAllocationSchedule;          // abi-encoded LiquidityAllocationBracket[] (raise → LP budget, piecewise by amount, mps)
}
```

`initializerParams` decodes (in the CCA factory) to:

```solidity
struct AuctionParameters {
    address currency;                // must match MigratorParameters.currency
    address tokensRecipient;         // receives unsold auction tokens (must NOT be the strategy)
    address fundsRecipient;          // MUST be the LBPStrategy (it sweeps the raise at migration)
    uint64  startBlock; uint64 endBlock; uint64 claimBlock;
    uint256 tickSpacing;             // Q96 price granularity of the auction book
    address validationHook;          // optional per-bid gate (allowlists etc.)
    uint256 floorPrice;              // Q96 starting floor
    uint128 requiredCurrencyRaised;  // graduation threshold
    bytes   auctionStepsData;        // packed issuance schedule
}
```

Lifecycle: `initializeDistribution` validates everything, deploys the auction
via the pinned factory, sends it `totalSupply − reservedTokenAmountForLP`,
retains the LP reserve, and reserves the target `PoolId` so no second auction
can claim the same key. Bids run between `startBlock`/`endBlock`. After
`migrationBlock`, permissionless `migrate(initializer)`:

- sweeps the raise; applies `lpAllocationSchedule` to compute the LP currency
  budget; initializes the pool at the auction clearing price; mints the
  position plan (currency + reserved tokens) to `positionRecipient` (or
  per-position overrides); sweeps **unallocated raise + unused reserve** to
  `recipient`; emits `Migrated(initializer, key, sqrtPriceX96, plan)`.
- on failure: raise + reserve go to `recipient` (`FundsRecovered` +
  `MigrationFailed`), and the launch never gets a pool.
- unsold auction tokens are claimed separately via the auction's
  `sweepUnsoldTokens()` by `tokensRecipient`.

Pool key subtlety (integrators must resolve from `Migrated`, not assume): with
`hook = address(0)`, migration prefers the canonical hookless key but falls back
to `hooks = LBPStrategy` if the hookless pool already got initialized by someone
else. Nonzero hooks must inherit `InitializerHook` (ERC165-checked, launch-time
validated); `GatedSwapHook` additionally blocks all swaps until its immutable
`gatekeeper` calls `approveSwaps()`. Dynamic-fee pools require a nonzero hook.

Live sample (block 28691406, initializer `0x7523e6e4…3a64`): native currency,
hookless, fee 3000 / spacing 60, full-range single position, 25% of raise to LP,
`recipient` = `positionRecipient` = the creator's **EOA**. So on pools.trade the
creator directly receives ~75% of the raise at migration plus the LP NFT.

**Creator revenue in the LBP shape is therefore three streams**, all of which
the adapter must own to preserve the Sinjoh guarantee:

1. the swept raise share → adapter as `recipient` (native **or ERC20** — the
   router's generalized normalization from the Pons v2 spec covers the ERC20
   case; native wraps to WETH as usual);
2. ongoing LP fees → adapter as `positionRecipient`: the adapter holds the v4
   position NFT(s) and collects via
   `positionManager.modifyLiquidities(DECREASE_LIQUIDITY(liquidity=0) + TAKE_PAIR)` —
   new machinery vs the vault claim, both currency sides arrive (token + quote),
   so `intakeAssets()` is `[token, quoteOrWETH]` here, like Pons v1;
3. unsold auction tokens → adapter as `tokensRecipient` (asset: the launch
   token itself).

`migrate()` is permissionless — the keeper should call it at `migrationBlock`
rather than waiting for third parties, and must handle the `MigrationFailed`
branch (funds arrive at the adapter as a refund; the launch has no pool; the
router's subject route never activates).

## Auxiliary strategies (in scope as launch-composition options)

- **UniversalRouterStrategy** `0x1242…DCEE`: `configData = abi.encode(router, recipient, route)`
  where `route = abi.encode(commands, inputs, deadline)` for
  `IUniversalRouter.execute`. Used via `distributeWithNative` for the dev buy
  leg of an instant launch. Constraints from source: the route must use `TAKE`
  with an explicit recipient (never `TAKE_ALL`) and must sweep its own unspent
  native — the strategy holds no balance and anything stranded is claimable by
  anyone. For the adapter, a direct v4 swap by the adapter itself in the launch
  transaction is equivalent and keeps the no-caller-calldata rule; the UR
  strategy matters mainly for parity with UI-built launches.
- **TokenSplitter** `0x4F5E…73CE`: splits one distribution across N
  `(recipient, amount)` legs without custody — the composition primitive for
  "X% auction + Y% airdrop + Z% team" launches.
- **MerkleClaimFactory / MerkleClaim**: deploys Uniswap's audited
  `MerkleDistributorWithDeadline` and funds it;
  `configData = abi.encode(bytes32 merkleRoot, address owner, uint256 endTime)`.
  Airdrop legs of a split launch. Uniswap has not deployed the factory on
  Robinhood Chain, so Sinjoh deploys the byte-identical upstream artifact
  (commit `dd8769c`) itself at the deterministic address
  `0x0C8B3e001C8DbBDbe15089c887C9323E097F0a15` — CREATE2 through the canonical
  deployer, zero salt, reproducible from the artifact alone. See
  `sinjoh-launchpad-adapters/script/DeployPoolsTradeMerkleClaimFactory.s.sol`.
- Periphery position recipients that UI launches may name and our indexer must
  recognize: `TimelockedPositionRecipient` (holds an LP NFT until a block, then
  approves an immutable operator), `BuybackAndBurnClaimRecipient`,
  `CompoundingClaimRecipient`.

## Adapter family

`SinjohPoolsTradeAdapter` (one clone per launch, per the launchpad-adapter
spec), with the launch shape chosen by typed parameters at `launch(...)`:

- **Instant, creator-fee**: `feeBeneficiary = adapter`; verify the FEEB NFT
  arrived for the snapshotted `tokenId`; `router.bind(token)`; optional dev buy
  against the fresh pool in the same tx. `collect()` =
  `feeSplitter.collectFees([tokenId])` then `vault.claim(tokenId, 0, 0)`, wrap
  native → WETH. `intakeAssets() = [WETH]`. The FEEB NFT is the revocable-
  recipient hazard (transferable, exact analogue of Pons v2's
  `transferCreatorFeeRecipient`) — the adapter must hold it forever and expose
  no transfer path.
- **Instant, no-creator-fee**: same launch path against `0xAD44…04b2`;
  `collect()`/`forward()` permanent no-ops, `intakeAssets() = []`.
- **LBP**: adapter is `recipient`, `positionRecipient`, and `tokensRecipient`;
  it validates `fundsRecipient = LBPStrategy` and `migrationBlock > endBlock`
  (the strategy re-checks both). `collect()` gains a position-fee leg
  (DECREASE 0 + TAKE_PAIR on held NFTs) alongside sweeps already delivered by
  `migrate`. `intakeAssets()` = `[token, WETH]` for native-currency auctions,
  `[token, currency]` otherwise. Bind happens at launch (token exists before
  the auction), but the subject's v4 route only becomes real at `Migrated` —
  the keeper and UI must key on that event and resolve the actual pool key from
  it (hookless-fallback subtlety above).
- **Buyback route**: instant-launch pools are static
  `(native, token, 2500, 25, no hook)` from birth — simpler than Pons v2 (no
  phases, no meme hook). LBP pools use the `Migrated` key, which may carry a
  hook (incl. `GatedSwapHook` pre-approval, during which swaps revert — treat
  as `NoMarket`). Same signed-floor guard posture as Pons v2: hookless/no-oracle
  pools expose no view quote.

Security posture carried over unchanged: pinned addresses + code hashes, no
caller calldata, one-shot creator-only launch, delta-asserted forwards, FEEB
and LP NFTs held permanently, `receive()` does no work.

## Watch items (operational, not deferrals)

- `ContinuousClearingAuctionFactory.protocolFeeController()` is zero today; a
  future controller would take a cut of raises. `feeRoutingIntact()`-style
  monitoring should read it.
- Strategy deployments rotate with versions (v3.0.0 → v3.2.0 changed launcher
  address, tick spacing 60 → 25, and the fee-split set). Pin by code hash and
  expect redeploys; the launcher address itself changed once already.
- The pools.trade UI was not observable during this research (broken on launch
  day). The protocol surface above is complete regardless of which subset the
  UI exposes; re-verify UI-built launch shapes (esp. whether it names EOAs or
  periphery recipients as `positionRecipient`) once it is up.

## Verification trail

- Sample token creation tx: `0xedc62d248aa7f93c112ff3f7961a9bf128d22e873fff87f4ef8ef8f53ef2e76c`
- Live v3.2.0 instant launch sampled: `0x3cb9c0e00f2df0695dbbff139b39a78cac87bb9822edaa2782ccaefa8184b406`
- Live LBP registration decoded: block 28691406, tx `0x0d62d0d2cb6e6b46188f74f2a855610bff5d3e6c2ebe1a814cd36832141b6980`; 67 `InitializerCreated` events since block 28500000
- Explorer: `https://robinhoodchain.blockscout.com` (launcher, UERC20Factory, CCA factory, UniversalRouterStrategy verified; LBPStrategy matched to repo source by events and reads)
- On-chain reads: `initialTick()`, `feeSplitter()`, `beneficiaryVault()`, `launcher()` on `0x23f8…27f1`; `getSplits()` on `0xeFF166…ACDf`; `initializerFactory()`, `protocolFeeController()` on the LBP/CCA pair; vault fallbacks
- Sources: `Uniswap/liquidity-launcher` @ `dd8769c` (+ v3.1.1 tag for LBP), `Uniswap/uerc20-factory` @ `de5bacd`, `Uniswap/continuous-clearing-auction` (audited, OpenZeppelin 2025-2026)
