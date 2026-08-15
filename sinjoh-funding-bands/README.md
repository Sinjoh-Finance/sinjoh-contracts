# Sinjoh Funding Bands

Creator-controlled scale-out positions for verified Robinhood Chain launches.
Creators register one to ten immutable USD market-cap bands, fund them with
subject tokens, and receive WETH as one-sided concentrated liquidity is crossed.
A band can instead deliver to a matching Sinjoh Fee Router for buyback, burn,
liquidity, or another immutable routing policy.

## What is implemented

- Creator and pool identity resolved by constructor-frozen launch verifiers.
- USD market-cap boundaries converted once using a fresh ETH/USD snapshot.
- Correct tick orientation for subject-as-token0 and subject-as-token1 pools.
- Atomic exact-delta funding and one position NFT per band.
- Uniswap v3 and v4 mint, increase, full settlement, and position closure paths.
- Native v4 quote proceeds wrapped into the manager's immutable WETH.
- Frozen per-profile v4 hook data passed to mint, increase, and burn actions.
- Atomic launch inventory escrow: the configured developer-buy share leaves
  creator custody in the launch transaction, then the complete ladder is
  created and funded permissionlessly as soon as Pons v2 graduates.
- A bytecode-pinned v4 guard that requires fifteen uninterrupted seconds above a band.
- Permanent onchain settlement eligibility after confirmation; no execution expiry.
- Reversal detection from independently cross-checked canonical v4 Swap history.
- An ownerless ETH/USD adapter using the canonical WETH/USDG Uniswap v3 15-minute
  TWAP, a spot-deviation bound, and a minimum-liquidity floor.
- A governance-recoverable observer authority that cannot move inventory or proceeds.
- Exactly 1% charged on cumulative realized WETH, with subject fees delivered in kind.
- Audited Fee Router clone runtime-hash pinning; metadata-compatible impostors are rejected.
- Permissionless pull delivery to the immutable creator/router and protocol recipient.
- Aggregate liability accounting, exact allowance cleanup, and unsolicited NFT rejection.
- A concrete Pons v1 launch verifier and bounded Uniswap v3 TWAP guard.

Market-cap conversion and v4 execution use linked libraries so the custody contract
remains under EIP-170. Deployments must therefore publish and verify
`FundingBandMath`, `FundingBandV4`, and `SinjohFundingBands` bytecode.

## Verify locally

```sh
forge fmt --check
forge build --sizes
forge test
```

The suite covers both token orderings, creator snapshotting, stale/incomplete
oracles, v3 and v4 position lifecycles, native wrapping, fee-on-transfer rejection,
router binding, split delivery, exact protocol fees, and stateful liability
invariants.

## Launch-profile status

| Profile | Implementation | Activation status |
|---|---|---|
| Pons v1 / Uniswap v3 | `SinjohPonsV1LaunchVerifier` + `SinjohV3TwapBandPriceGuard` | Source-complete; Robinhood mainnet fork fixture and bytecode-hash signoff still required. |
| Pons v2 / Uniswap v4 | `SinjohPonsV2LaunchVerifier` + `SinjohV4ConfirmedBandPriceGuard` | Live fork suite passes launch, graduation, adapter-created launch ownership, mint, increase, hooked swap, continuous confirmation, burn, native receipt, WETH wrap, and fee accounting. |
| pools.trade / Uniswap v4 | Core-compatible verifier/guard boundary | Not activatable until the live launcher record, strategy/hook behavior, and observation source pass the fork suite. |
| letscash.fun / Uniswap v4 | Core-compatible verifier/guard boundary | Not activatable until the canonical live contracts and hook observation mechanism pass the fork suite. |

An omitted profile is unsupported by construction. Adding a profile to an existing
manager is impossible; a new immutable deployment is required.

## Deployment

`script/deploy.sh` accepts comma-separated configuration. `DEPENDENCIES`
must be ordered as WETH, v3 factory, v3 PositionManager, v4 PositionManager, v4
StateView, Permit2, and ETH/USD oracle. Every dependency, verifier, and guard must
have a matching expected code hash.

```sh
DEPENDENCIES=0xWETH,0xV3_FACTORY,0xV3_PM,0xV4_PM,0xV4_STATE_VIEW,0xPERMIT2,0xETH_USD \
DEPENDENCY_HASHES=0x...,0x...,0x...,0x...,0x...,0x...,0x... \
PROFILE_ADDRESSES=0xVERIFIER,0xGUARD \
PROFILE_HASHES=0x...,0x... \
PROFILE_HOOK_DATA_HASHES=0x... \
PROFILES='[(0xVERIFIER,0xGUARD,0xHOOK_DATA)]' \
FEE_ROUTER_CODEHASH=0x... \
PROTOCOL_FEE_RECIPIENT=0x... \
MAX_ORACLE_AGE=3600 \
DEPLOYER_PRIVATE_KEY=... \
./script/deploy.sh
```

The script is compatible with macOS's default Bash 3.2. It code-hash checks every
dependency and profile contract before broadcasting, then reads back every immutable,
profile address, and hook-data hash from the deployed manager. A mismatch aborts the
deployment workflow instead of printing an apparently successful address.

`script/deploy-pons-v2-production.sh` is the reviewed Robinhood-mainnet path. Deploy
`DeployPonsV2AdapterFactory.s.sol` first, then pass its address as
`SINJOH_PONS_V2_ADAPTER_FACTORY` and its `adapterRuntimeCodehash()` readback as
`SINJOH_PONS_V2_ADAPTER_CODEHASH`. Independently record and pass the deployed
factory and implementation runtime hashes as
`SINJOH_PONS_V2_ADAPTER_FACTORY_CODEHASH` and
`SINJOH_PONS_V2_ADAPTER_IMPLEMENTATION_CODEHASH`. The script refuses an adapter
generation that does not implement launch inventory escrow. It pins the live
Pons v2 factory, hook, the new adapter-clone runtime hash, Uniswap
infrastructure, Fee Router runtime hash, and protocol recipient. It deploys the
ownerless v3 TWAP oracle, verifier, launch escrow, confirmation guard, linked
libraries, and manager; one-time binds the escrow and manager; verifies all
readbacks; one-time binds the adapter factory to that exact escrow; and emits
addresses, runtime hashes, and transaction hashes as JSON. Once bound, the
adapter rejects any substituted escrow before the upstream Pons launch call.

The production observer cross-checks Alchemy archive state against Envio's
independent PoolManager event history. A crossing arms a fifteen-second timer;
any intervening reversal disarms it, while an uninterrupted period finalizes
settlement eligibility permanently onchain. The event stream catches dips that
start and recover entirely between keeper cycles. Below-band create/fund checks
remain canonical StateView spot checks.
The sole observer role is recoverable through two-step governance and cannot
move inventory, settle a band without confirmed history, or redirect proceeds.
The UI must refuse a new Funding Bands launch whenever the observer is unhealthy,
the manager runtime hash differs, or its frozen verifier/guard profile differs.
Already-escrowed plans retain a permissionless manual activation fallback and
active bands retain permissionless arm, settle, and delivery fallbacks.

See [`PONS_V2_COMPATIBILITY.md`](./PONS_V2_COMPATIBILITY.md) for the local and live-fork
Pons v2 test boundary, [`UI-INTEGRATION.md`](./UI-INTEGRATION.md) for the Pons create,
token, and profile integration map, and [`LAUNCH-READINESS-REVIEW.md`](./LAUNCH-READINESS-REVIEW.md)
for the security review, evidence, and remaining launch gates.
