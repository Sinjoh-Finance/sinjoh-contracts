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
returned the same factory and WETH. The adapter constructor, manifest verifier, SDK verifier, and
keeper all repeat those graph checks rather than trusting a manifest address in isolation.

## Known live pool used only as an integration canary

The factory returned `0x52e65B17fB6E5BA00Ed806f37Afcd2DaA50271Ca` for
`0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73` / `0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168`
at fee `100`. The pool reported the same factory, token pair, fee `100`, tick spacing `1`, a nonzero
liquidity value, and an unlocked `slot0`. Its observed runtime hash was
`0x3298b5dd4e6f115074c526a55ad05a36fd73a0034ac22ec6cbaab32cc9c1e8d2`.

This pool is not a protocol default and is not a substitute for the future `$INJOH`/WETH pool. Its
liquidity changed during this review, which is why liquidity is a live activation/operation check,
not a copied constant.

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

- One isolated sleeve and adapter are deployed per admitted pool; owners cannot select arbitrary
  unreviewed addresses.
- Factory `getPool`, pool factory/token/fee/tick spacing/liquidity/lock state, builder dependencies,
  manager dependencies, route direction, strategy registration, sleeve binding, adapter state,
  allocation cap, and all runtime hashes must match.
- WETH and USDG proxy implementation slots are checked in addition to proxy runtime hashes.
- A pool-TWAP price requires minimum liquidity, aged observations, spot/TWAP deviation limits, a
  separately reviewed WETH/USD source, and a distinct manifest-bound reference source.
- The owner loss ceiling covers total before/after oracle-valued portfolio loss as well as adapter
  withdrawals. The guardian has an oracle-independent, paused-state, in-kind emergency exit.
- An NFT with an active dynamic Delta allocation cannot burn until an owner-approved rebalance has
  removed that allocation. This keeps redemption independent of swaps and pool oracles.

## Explicitly unresolved deployment facts

No `$INJOH` token address or `$INJOH`/WETH pool was supplied or deployed during this review. The
protocol therefore contains no guessed `$INJOH` address, pool, fee, tick spacing, price source, or
liquidity threshold. Those are mandatory collection-release inputs and activation must fail until
the exact deployed graph is source-verified, manifest-bound, SDK-verified, and exercised by the
live fork test.
