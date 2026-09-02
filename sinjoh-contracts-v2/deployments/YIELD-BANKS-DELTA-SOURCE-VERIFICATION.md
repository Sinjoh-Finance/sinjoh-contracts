# Yield Banks Delta source verification

Verified on 2026-08-31 against Robinhood Chain mainnet, chain ID `4663`, using the official public
RPC and a live Foundry fork. These are observations, not timeless constants: deployment verification
must re-read every value at the same block used for activation.

## Canonical dependency graph

| Role | Complete address | Runtime code hash observed |
| --- | --- | --- |
| Delta position builder | `0x6235cF6bd8419b34942F4EDDB39C880BD96dD700` | `0xb9b462897f26b3d9082e6db057e363ea01cee5931f39bc62d52eeaa4aa7a9039` |
| Delta V3 factory | `0x1f7d7550B1b028f7571E69A784071F0205FD2EfA` | `0xec72b1abd1f2faee020cfea9c646bd8994f9fb389054f6e574f103a895091739` |
| Delta V3 position manager | `0x73991a25C818Bf1f1128dEAaB1492D45638DE0D3` | `0x0a493d1af3d0f25fed8efa205244ebee14114267a08647fc38c515c7cd6ead4f` |
| Robinhood Chain WETH proxy | `0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73` | `0x5706be52f64875fee65a2cec0d80e47a23d8793cbe85d214b48445e2d05f5353` |
| WETH implementation | `0xc6b81b429797e0f555440b70cd99e032d7ae947e` | `0xbe1295f37be34ffe03ad779bda0ef278907e1856b51a3be2f35ee541d75d4650` |
| Robinhood Chain USDG proxy | `0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168` | `0x864cc9ad53b338b82da1f7cab85ab0b3d5c8861acb422b6fec63cf36234f36a6` |
| USDG implementation | `0x68184c449e1a8f34fa18d289737129fd27b66f8f` | `0x3a551ac5c744af57e68a1d1431ac403c0f516ffd7d224a75746aee11fc4f3baf` |

The builder getters returned that exact factory, position manager, and WETH. The position manager
returned the same factory and WETH. `DeltaPoolController`, the release verifier, and the SDK verifier
repeat those graph checks rather than trusting a manifest address in isolation.

## Known live pool used only as an integration canary

The factory returned `0x52e65B17fB6E5BA00Ed806f37Afcd2DaA50271Ca` for
`0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73` / `0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168`
at fee `100`. The pool reported the same factory, token pair, fee `100`, tick spacing `1`, a nonzero
liquidity value, and an unlocked `slot0`. Its observed runtime hash was
`0x3298b5dd4e6f115074c526a55ad05a36fd73a0034ac22ec6cbaab32cc9c1e8d2`.

This pool is not a protocol default and is not a substitute for the live `$INJOH`/WETH pool. Its
liquidity changed during this review, which is why liquidity is a live activation/operation check,
not a copied constant.

The `$INJOH` token is `0x2cC0FAC44B8252f6B10208B091aFf2c94B4da77D`, with observed runtime
hash `0x7e6ca88b216c0b26c5f8497f3e7106648f4bcd8ed41eedfa1c80787fb407f4e2`.
The Delta factory returns `$INJOH`/WETH pool
`0xB09fa4f04032b9d9e690ac4a1d29523b5f9A72DC` at fee `10000`. The pool reports
WETH as token 0, `$INJOH` as token 1, tick spacing `200`, nonzero liquidity, an unlocked `slot0`,
and runtime hash `0xfae0473dfc8dbfe849e964297fb68e7bbb2a0d588c457f0b74d2e93572c08eb0`.

## Transaction ABI and custody proof

The verified builder source exposes
`mintLadder(address pool,Rung[] rungs,int24 minimumCurrentTick,int24 maximumCurrentTick,uint256 deadline)`
and returns the minted position IDs. `Rung` is ordered as lower tick, upper tick, token-0 amount,
token-1 amount, token-0 minimum, and token-1 minimum. The builder mints the V3 position NFTs to its
caller and refunds unused inputs.

`DeltaV3LPAdapter` consumes the returned IDs, then independently reads every position from
`0x73991a25C818Bf1f1128dEAaB1492D45638DE0D3` and checks owner, token pair, fee, liquidity, and pool
identity. It rejects unsolicited position NFTs. Withdrawals bind every position ID, liquidity
amount, token minimum, paired-token conversion amount, minimum WETH output, exact WETH return, and
deadline. Full exit requires every tracked live position.

The live fork test `test/fork/DeltaV3LPAdapter.fork.t.sol` successfully minted through the deployed
builder, recorded and valued the returned position, and completely exited it.

## Fail-closed activation rules

- Governance approves a source-verified infrastructure generation—not individual pools—by binding
  the factory, position manager, position builder, their live runtime hashes, and the exact creation
  code hashes for routes, sleeves, adapters, and fallback feeds.
- Owners may select any live canonical pool for an active infrastructure generation when the pool is
  WETH-paired, returned by `factory.getPool(token0, token1, fee)`, initialized, unlocked, and has
  nonzero liquidity. If already materialized, its exact infrastructure commitment must still be the
  current one. The release manifest contains no per-pool list.
- The allocation operator remains the manual execution gate. On first use it calls
  `DeltaPoolController.materializePool`; the controller itself deploys one isolated sleeve, adapter,
  and two exact-direction routes from governance-approved binaries and then binds their identities.
- V3 pool runtime hashes are not shared constants: constructor immutables make canonical pools'
  deployed bytecode differ. The controller derives the selected pool's current runtime hash during
  materialization and every adapter and route binds that exact value.
- Factory `getPool`, pool factory/token/fee/liquidity/lock state, builder dependencies, manager
  dependencies, route direction, strategy registration, sleeve binding, adapter state, allocation
  cap, and all relevant runtime hashes must match.
- WETH and USDG proxy implementation slots are checked in addition to proxy runtime hashes.
- A pool-TWAP price requires nonzero configured minimum liquidity, aged observations,
  spot/TWAP deviation limits, a separately reviewed WETH/USD source, and the PriceHub freshness and
  optional independent-reference checks. It remains unavailable until the complete TWAP window has
  elapsed after oracle preparation.
- The owner loss ceiling covers total before/after oracle-valued portfolio loss as well as adapter
  withdrawals. The guardian has an oracle-independent, paused-state, in-kind emergency exit.
- An NFT with an active dynamic Delta allocation cannot burn until an owner-approved rebalance has
  removed that allocation. This keeps redemption independent of swaps and pool oracles.

## Upgrade and shutdown behavior

If Delta deploys a new factory, manager, or builder, the collection timelock can approve the verified
dependency graph and binaries without a collection implementation upgrade. A new factory leaves
existing foundations on other factories unchanged. Replacing dependencies for the same factory
changes its infrastructure commitment: foundations created under the prior commitment are
automatically blocked from fresh selection and deposits, while withdrawals, fee collection, and
emergency exits remain available through their immutable original bindings. Deactivating a factory
has the same fail-closed deposit behavior. This prevents an infrastructure update from silently
routing new money through stale dependencies and prevents shutdown from stranding custody.

The `$INJOH` token and pool above have direct live-chain verification, including a successful
exact-pool route and builder mint test. They are canary inputs for Sinjoh's own collection, not
protocol defaults. The controller discovers that pool from the approved factory at runtime; it does
not require an `$INJOH` address or pool address in the release manifest.
