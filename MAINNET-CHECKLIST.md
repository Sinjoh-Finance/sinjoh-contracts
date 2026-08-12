# Mainnet launch checklist

Target: **Robinhood Chain mainnet, chain ID `4663`** (testnet was `46630` — one
digit apart, and several bugs during migration came from exactly that).

Covers both repositories:

- `/Users/dsb/Sinjoh` — contracts, deploy scripts, keeper, indexer, Supabase,
  clear-signing descriptors
- `/Users/dsb/Sinjoh-UI` — the app (`main` @ `acd132b`)

---

## Already done

- [x] UI cut over to chain 4663: config, Blockscout explorer, mainnet RPC
      fallbacks, `.env.example` (Sinjoh-UI #26, #27)
- [x] All user-visible testnet language removed; network pill and footer derive
      from chain config
- [x] 96 approved RWA presets, each verified on chain (symbol + 18 decimals)
- [x] SJTEST reference fixture removed from the UI; launches now come solely
      from the launch index
- [x] Nine production deploy scripts flipped to chain 4663 (#13)
- [x] Pons dependency addresses swapped to mainnet, each verified on chain (#13)
- [x] Nine SJTEST/testnet-flow scripts deleted (#14)
- [x] `SinjohTestnetPriceGuard` (no slippage bound) replaced by
      `SinjohSharedV3TwapPriceGuard` (#15)
- [x] Stale dependency code-hash pins corrected; `DeployFeeRouter` given the
      pins it was missing (#15, #16)

---

## Phase 0 — before deploying (nothing here is blocked)

### 0.1 Keeper — highest risk

- [ ] Delete or disable `sinjoh-keeper/config/testnet/sticker.json`. It is
      chain 46630, **`enabled: true`**, lists the SJTEST token as a live fee and
      airdrop asset, and is copied into the image by `sinjoh-keeper/Dockerfile:14`.
      It is the natural target of `SINJOH_MANIFEST_DIR`.
- [ ] Add a chain-ID allowlist to `sinjoh-keeper/src/config.ts:44`. Today
      `chainId` is only validated as a positive integer, so a testnet manifest
      will happily run against mainnet keys. The live cross-check at
      `src/chain.ts:57` catches a mismatched RPC but not a wrong manifest.
- [ ] Repoint the CLI default manifest at `src/cli.ts:16` (currently
      `./config/testnet.example.json`) and `sinjoh-keeper/.env.example:16`.
- [ ] Replace the testnet default `SINJOH_RPC_PRIMARY` at
      `sinjoh-keeper/.env.example:2`.
- [ ] Create the mainnet manifest skeleton. Addresses land in Phase 2.
- [ ] Add pool priming as a keeper step — call
      `SinjohSharedV3TwapPriceGuard.prime(tokenA, tokenB, cardinality)` for each
      new launch pool. Code can be written now; the guard address comes from the
      manifest at runtime.

### 0.2 Supabase — highest risk

- [ ] Delete `supabase/migrations/20260728001000_seed_sjtest.sql`. On
      `supabase db push` it inserts an `status = 'active'` SJTEST launch on chain
      46630 into production. The UI reads `public_launches`, so a testnet token
      would render as a live mainnet launch.

### 0.3 Indexer

- [ ] `sinjoh-indexer/config.yaml`: chain `4663` (`:59`), start block `8991118`
      (`:60`), mainnet RPCs (`:63`, `:68`, `:70`).
- [ ] Remove the `${VAR:-testnet_default}` fallbacks for the six contract
      addresses (`:75`–`:89`). A single unset variable currently makes the
      indexer silently index testnet instead of failing.
- [ ] Update `sinjoh-indexer/.env.example:1-14` to match.

### 0.4 Clear-signing descriptors

Wallets key descriptors by chain ID + address, so every one of these currently
degrades hardware-wallet clear signing to blind signing.

- [ ] Flip `chainId` 46630 → 4663 in all four files under `clear-signing/`,
      including the EIP-712 domain at `eip712-LaunchAuthorization.json:15`.
- [ ] Set the mainnet Pons launch factory `0xA5aAb3F0c6EeadF30Ef1D3Eb997108E976351feB`
      in `calldata-PonsLaunchFactory.json` and `eip712-LaunchAuthorization.json`.
- [ ] `calldata-SinjohFeeRouter.json` and `calldata-SinjohFeeRouterFactory.json`
      need deployed addresses — Phase 2.
- [ ] Update `clear-signing/README.md:18`.

### 0.5 Fork tests

- [ ] Retarget `RobinhoodTestnet.fork.t.sol` in all five packages, plus
      `RouterFirstPonsLaunch.fork.t.sol`. They early-return on any chain other
      than 46630, so against a mainnet fork they **pass green while asserting
      nothing** — they read as coverage and provide none.
- [ ] Run a full mainnet-fork rehearsal of the launch path. Both
      `UI-NOTES.md:629` and `DEVELOPMENT_PLAN.md:125` list this as a release
      gate and nothing currently implements it.

### 0.6 Documentation

- [ ] Per-package READMEs (`sinjoh-fee-router`, `sinjoh-liquidity-manager`,
      `sinjoh-airdrop-distributor`, `sinjoh-pons-v1-adapter`,
      `sinjoh-revenue-collector`): each still prints a testnet `--rpc-url` in its
      deploy command and claims the script verifies chain 46630.
- [ ] `sinjoh-pons-v1-adapter/README.md:20-21` and
      `DEVELOPMENT_PLAN.md:91-116` publish dependency addresses and code hashes
      that now **contradict the deploy scripts**. These are the exact tables an
      operator consults before broadcasting.
- [ ] Document `DeploySharedPriceGuard` — it exists in no README, and its output
      is no longer returned by `DeployFeeRouter`, so threading the guard address
      into launch configuration is currently an undocumented manual step.
- [ ] `sinjoh-keeper/README.md:9,49`, `RUNBOOK.md:3,7`,
      `KEEPER_REQUIREMENTS.md`, `INFRASTRUCTURE.md`, `STRATEGY.md`,
      `UI-NOTES.md`, root `README.md:73-83`.
- [ ] Decide what to do with the historical records: `TESTNET_DEPLOYMENTS.md`,
      `SJTEST_TESTNET_REPORT.md`, `testnet-deployments.json`. Suggest keeping
      them but labelling them clearly as superseded.

### 0.7 Environment and infrastructure

- [ ] Vercel: set every value from `Sinjoh-UI/.env.example`. Missing
      `NEXT_PUBLIC_REOWN_PROJECT_ID` silently drops WalletConnect (injected
      wallets only); missing Supabase vars make Explore and Manage render empty.
- [ ] Railway: set `SINJOH_RPC_ORIGIN`. The keeper already sends the Alchemy
      `Origin` header (`sinjoh-keeper/src/chain.ts:8-16`) — no code change needed.
- [ ] Confirm the Alchemy allowlist contains exactly `https://app.sinjoh.com`,
      or browser reads 403 with a non-obvious error.
- [ ] Confirm the archive RPC actually reaches back to block `8991118`, or
      launch discovery and Explore analytics silently return nothing.
- [ ] Provision a dedicated low-value keeper signer and separate Supabase keys
      for the routing keeper and airdrop worker (`INFRASTRUCTURE.md:38-40,66-67`).
- [ ] Decide on `SINJOH_AIRDROP_AUTO_SUBMIT`. On mainnet it auto-commits Merkle
      roots with the attestor key and pushes payment batches with no review. If
      unattended releases are intended, also set `SINJOH_AIRDROP_AUTO_ENQUEUE`
      and choose its per-account interval; auto-enqueue refuses to run without
      auto-submit.

---

## Phase 1 — deploy the contracts

Preconditions: `DEPLOYER_PRIVATE_KEY` resolves to
`0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49` (every script asserts this), and
the wallet is funded on 4663.

Order matters only where noted; `REVENUE_COLLECTOR` must exist first.

- [ ] 1. `DeployRevenueCollector` — no dependencies. Sets governance to
        `0x39E2f5eFdFd808F26B98979a06BA11ea82E1C85f` and the initial processor to
        that same address.
- [ ] 2. `DeployFeeRouter` — emits the router implementation and router factory.
- [ ] 2a. `DeploySimpleSwapAdapter` — emits the independently deployable simple
        swap adapter. The scripts stay separate so both fit under EIP-170.
- [ ] 3. `DeploySharedPriceGuard` — the one guard every launch points at.
- [ ] 4. `DeployAirdropDistributor` — requires `REVENUE_COLLECTOR`.
- [ ] 5. `DeployLiquidityManager` — requires `REVENUE_COLLECTOR`.
- [ ] 6. `DeployPonsLiquidityManager` — requires `REVENUE_COLLECTOR`.
      **See open decision 1: on mainnet this is now identical to step 5.**
- [ ] 7. `DeployPonsV1AdapterFactory` — no dependencies.
- [ ] 8. `DeployV3ExecutionFactory` — optional CREATE2 deployment.
- [ ] 8a. `DeployV3RouteGuardDeployer`, then `DeployV3RouteExecutionFactory` —
        optional ordered CREATE2 deployments. The split keeps each script under
        EIP-170; the second fails closed until the first address has code. The
        EIP-2470 singleton is confirmed present on 4663.
- [ ] Record every address, transaction hash, and runtime code hash in a new
      `mainnet-deployments.json` (mirror the shape of `testnet-deployments.json`).

**Do not run `DeployRouterOwnedPons`** unless it is deliberately replacing
`DeployFeeRouter` — it deploys the same router implementation and factory, so
running both produces two competing sets.

---

## Phase 2 — wire the deployment in

- [ ] Fill all ten addresses in `Sinjoh-UI/config/manifest.ts:26-84` with their
      measured runtime code hashes. Until this happens the launch flow is
      **correctly fail-closed** — the UI verifies pinned bytecode and will
      report "does not match the reviewed deployment."
- [ ] Fill the three entries whose `expectedRuntimeCodeHash` is currently
      `null`: `liquidityManagerV4`, `ponsAdapterFactory`,
      `ponsAdapterImplementation`. A null hash bypasses bytecode pinning.
- [ ] Bump `manifest.version` (`config/manifest.ts:17`) once the manifest is
      genuinely all-mainnet. It already claims to be.
- [ ] Fill the keeper mainnet manifest and deploy it to Railway.
- [ ] Fill indexer contract addresses.
- [ ] Fill the two Sinjoh clear-signing descriptors.

---

## Phase 3 — go live

- [ ] Launch your own test token on mainnet and verify the full path end to end:
      launch, router binding, fee collection, conversion, airdrop, liquidity mint.
- [ ] Confirm the first liquidity mint waits for TWAP readiness rather than
      failing permanently. A new pool needs its observation buffer primed and
      roughly one 15-minute window of history before the guard will quote.
- [ ] Launch `$INJOH`.
- [ ] Point protocol revenue at it: call `setProcessor(<$INJOH fee router>)` on
      the revenue collector from the governance address. No redeploy is needed —
      the processor is designed to be replaceable, and `renounceOwnership` is
      permanently disabled so the setting can never be stranded.
- [ ] Announce.

---

## Open decisions

1. **`DeployLiquidityManager` and `DeployPonsLiquidityManager` are now
   identical.** On testnet they used different v3 factories
   (`0xdf9e3D6f…` vs `0xFECCB63C…`); on mainnet both resolve to
   `0x1f7d7550…` / `0x73991a25…`, so they construct `SinjohLiquidityManager`
   with byte-identical arguments. Running both yields two indistinguishable
   managers. Decide whether you still want two instances (the v3/v4 account
   separation noted in `UI-NOTES.md:435`) or one — and if two, whether the
   scripts should be merged into one parameterised script.

2. **Audit before or after launch.** `STRATEGY.md:32,49` lists audits as a
   pre-mainnet gate; nothing has been audited.

3. **`maxSpotDeviationBps = 1000`** on the shared price guard was my choice, not
   yours. Wider suits volatile launch tokens; tighter is stricter anti-sandwich.
   Cheap to change — redeploy the guard and repoint the manifest. Existing
   launches keep whatever guard they were configured with.

4. **Deployer and governance keys.** Both are still the testnet EOAs
   (`0x3d58…3f49` deployer, `0x39E2…C85f` governance). Fine if you control them
   on mainnet; otherwise update the script constants before Phase 1.

---

## Verified mainnet reference values

Every value below was read from chain 4663, not copied from a document.

| Item | Value |
|---|---|
| Chain ID | `4663` (`0x1237`) |
| Public RPC | `https://rpc.mainnet.chain.robinhood.com` |
| Explorer | `https://robinhoodchain.blockscout.com` |
| Pons launch factory | `0xA5aAb3F0c6EeadF30Ef1D3Eb997108E976351feB` (start block `8991118`) |
| Pons locker | `0x736D76699C26D0d966744cAe304C000d471f7F35` |
| WETH | `0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73` |
| v3 factory | `0x1f7d7550B1b028f7571E69A784071F0205FD2EfA` |
| v3 position manager | `0x73991a25C818Bf1f1128dEAaB1492D45638DE0D3` |
| Swap router | `0xCaf681a66D020601342297493863E78C959E5cb2` |
| Quoter V2 | `0x33e885eD0Ec9bF04EcfB19341582aADCb4c8A9E7` |
| Launch fee | `0.0005 ETH` |

Mainnet Pons launch parameters differ from testnet — all are pinned in the UI
manifest and verified at runtime:

| Parameter | Testnet | Mainnet |
|---|---|---|
| Protocol fee share | 20% | **30%** (creators keep 70%) |
| Graduation threshold | 0.005 ETH | **4.2 ETH** |
| Max wallet | 2% | **5%** |
| Max transaction | 100% | **5.5%** |
| Restriction window | 366 blocks | **2 blocks** |
| Router requires deadline | true | **false** |

The Uniswap v3 pool init code hash is identical on both chains
(`0xe34f199b…8b54`), verified by recomputing a live pool's CREATE2 address.

### RPC endpoints

- **Alchemy** — works, but **requires an `Origin` header**. Without it every
  request returns "Unspecified origin not on whitelist." The UI relay and the
  keeper both send it.
- **QuickNode** — works with no Origin header. Good archive/logs endpoint;
  Alchemy caps `eth_getLogs` at ten blocks.
- **dRPC** — **unusable.** Returns "chain is not available on free plan."
