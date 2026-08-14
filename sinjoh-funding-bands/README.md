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
- Dual spot/reference guard boundary; no generic spot-only v4 profile exists.
- A bytecode-pinned v4 spot plus five-minute signed-reference guard for Pons v2.
- An immutable-signer, AggregatorV3-compatible ETH/USD oracle option for Robinhood Chain.
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
| Pons v2 / Uniswap v4 | `SinjohPonsV2LaunchVerifier` + `SinjohV4SignedBandPriceGuard` | Live fork suite passes launch, graduation, mint, increase, hooked swap, burn, native receipt, WETH wrap, and fee accounting. Deployment still requires signer/oracle operations and independent audit signoff. |
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

Mainnet deployment remains intentionally out of scope until every enabled profile
passes the compatibility requirements in [`SPEC.md`](./SPEC.md).
The current signed v4 guard uses one immutable ECDSA signer; permanent signer loss
would prevent settlement of active v4 bands. This liveness model requires explicit
security approval or a redundant replacement design before deployment.

See [`PONS_V2_COMPATIBILITY.md`](./PONS_V2_COMPATIBILITY.md) for the local and live-fork
Pons v2 test boundary, [`UI-INTEGRATION.md`](./UI-INTEGRATION.md) for the Pons create,
token, and profile integration map, and [`LAUNCH-READINESS-REVIEW.md`](./LAUNCH-READINESS-REVIEW.md)
for the security review, evidence, and remaining launch gates.
