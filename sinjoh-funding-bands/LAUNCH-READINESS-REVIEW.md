# Funding Bands launch-readiness review

Review date: 2026-08-14

## Verdict

**Pons v2 protocol mechanics: PASS after internal adversarial audit. Exact deployment rehearsal remains.**

The Pons v2 path completed a fresh launch, graduation, two deposits into one real
Uniswap v4 position, a real hooked swap across the band, delayed confirmation,
full position burn, native ETH receipt from the canonical PoolManager, WETH
wrapping, exact 1% fee accounting, and liability crediting on a disposable
Robinhood mainnet fork.

Pons v2 no longer depends on a Safe, ETH/USD signer, or price publisher. An
operational observer cross-checks independent archive state and event history,
and can only advance or reset confirmation state. It cannot move inventory or
proceeds, change bands, or bypass the immutable 30-second requirement.

## Critical defects corrected

1. **Native v4 settlement sender:** native ETH comes from PoolManager, not
   PositionManager. The manager now freezes the canonical PoolManager and accepts
   native ETH only from it. The real fork proves this path.
2. **Price evidence at registration:** `create` accepts bounded profile data and
   validates every lower boundary before bands are frozen.
3. **Executable price display:** stored WETH prices now reflect final tick-spacing
   rounding for either token orientation.
4. **Deployment verification:** the Bash 3.2-compatible script checks configured
   runtime hashes before broadcast and reads back every manager immutable and profile.
5. **Fee Router impostors:** destinations must match the approved runtime code hash,
   creator, subject, and intake assets.
6. **Pons v2 settlement manipulation:** the production guard compares Alchemy
   archive state with Envio's canonical v4 Swap history. Hidden reversals restart
   the 30-second window; uninterrupted confirmation becomes permanently eligible.
7. **ETH/USD availability:** the ownerless `SinjohV3EthUsdOracle` derives ETH/USD
   from the canonical WETH/USDG v3 pool using a full 15-minute TWAP, a 5% maximum
   spot/TWAP deviation, and a `1e18` minimum raw-liquidity floor.
8. **Canonical Pons infrastructure:** the verifier now rejects deployments whose
   hook or PoolManager does not exactly match the Pons factory getters.
9. **Keeper trust boundary:** startup pins the reviewed manager address and runtime
   hash, then verifies the account subject, creator binding, profile, venue, band
   count, quote asset, and settlement delay before planning any call.

## Data-flow results

| Data entering or leaving | Validation | Result |
|---|---|---|
| Launch identity | Immutable Pons v2 record plus token self-attestation; only `PoolCreated`; native ETH only | Passed locally and on live fork |
| Pool identity | Reconstructed `PoolKey`/`PoolId`; pinned StateView and PoolManager | Passed locally and on live fork |
| ETH/USD | Canonical WETH/USDG v3 pool; 15-minute TWAP; spot deviation and liquidity checks | Passed locally and on live fork |
| Band crossing | Live v4 spot plus byte-identical archive/event replay; every reversal resets the 30-second window; final confirmation has no expiry | Hidden reversal passed locally; delayed settlement passed on live fork |
| Creator inventory | Exact transfer delta; fee-on-transfer rejected; approvals cleared | Passed |
| v4 actions | Core constructs pool, ticks, liquidity, recipient, hook, and action payloads | Passed with real Pons hook |
| Native proceeds | Only canonical PoolManager may send ETH; exact delta is wrapped into WETH | Passed with real PoolManager |
| Fee Router | Runtime hash plus creator, subject, WETH intake, and subject intake | Passed, including counterfeit rejection |
| Proceeds | Pull ledger, fixed recipients, failure-safe retries, solvency checks | Passed |
| Protocol fee | Exactly 1% of cumulative realized WETH; no subject-token fee | Passed unit and invariant tests |

## Verification evidence

- **80 tests passed, zero failed:** core lifecycle/security, Pons v1, Pons v2,
  history-confirmed v4 guard, autonomous ETH/USD oracle, fuzzing, invariants, and one
  live Pons v2 mainnet-fork lifecycle.
- **Three accounting invariants passed** over 393,216 intensified calls:
  aggregate liabilities equal detailed ledgers, liabilities never exceed balances,
  and the protocol fee remains exactly 1% of gross WETH.
- **10,000 market-cap conversion fuzz cases passed** across supply, ETH/USD,
  market-cap, tick spacing, and both token orientations in the intensified suite.
- Maximum ten-band creation and funding passed for v3 and Pons v2/v4.
- `forge fmt --check`, compilation, and `git diff --check` pass.
- `SinjohFundingBands` runtime is 24,066 bytes, 510 bytes below EIP-170.

The live test uses production contracts—not a mock—for the Pons factory, bonding
curve, meme hook, buyback adapter, v4 PositionManager, StateView, PoolManager,
Permit2, WETH, USDG, and the WETH/USDG v3 pool.

## Live dependencies used by the fork

| Component | Address | Runtime code hash |
|---|---|---|
| WETH | `0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73` | `0x5706be52f64875fee65a2cec0d80e47a23d8793cbe85d214b48445e2d05f5353` |
| USDG (6 decimals) | `0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168` | `0x864cc9ad53b338b82da1f7cab85ab0b3d5c8861acb422b6fec63cf36234f36a6` |
| WETH/USDG v3 0.01% pool | `0x52e65B17fB6E5BA00Ed806f37Afcd2DaA50271Ca` | `0x3298b5dd4e6f115074c526a55ad05a36fd73a0034ac22ec6cbaab32cc9c1e8d2` |
| v3 factory | `0x1f7d7550B1b028f7571E69A784071F0205FD2EfA` | `0xec72b1abd1f2faee020cfea9c646bd8994f9fb389054f6e574f103a895091739` |
| v3 PositionManager | `0x73991a25C818Bf1f1128dEAaB1492D45638DE0D3` | `0x0a493d1af3d0f25fed8efa205244ebee14114267a08647fc38c515c7cd6ead4f` |
| v4 PositionManager | `0x58daec3116aae6D93017bAAea7749052E8a04fA7` | `0xc873e135dc9aaec88489cfbad146b4cb49d6a32e0d80326377784b7ba17670b2` |
| v4 StateView | `0xF3334192D15450CdD385c8B70e03f9A6bD9E673b` | `0x7d9c591e0956fd89d98feb4ffcfe8bf1f7a62bd485edd979fa21d104b49878a6` |
| v4 PoolManager | `0x8366a39CC670B4001A1121B8F6A443A643e40951` | `0xbd3881180b547f5fe817545743cfb4343e96b1bc6640dcd70c106b0066e95626` |
| Permit2 | `0x000000000022D473030F116dDEE9F6B43aC78BA3` | `0x5208783f52488f7d3493e5e38311ab707c1d75457fe472a19b0b4d57d66a7fca` |
| Pons v2 factory | `0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e` | `0x89a27da6f703e0a7cdd4f233e7cb57604ff75b164530962d3ff7cf8483a67d84` |
| Pons v2 hook | `0xE5e702641Ea86F4ae6cC3cDaeD2B886f976Be044` | `0xc21b1e6c1b45403e81a581f22ed6d9c747997af1cfdac1b1dc9f4b1d346a10db` |
| Pons buyback adapter | `0x39217172A3F07E827557093989039F968A571D43` | `0xbf53dc3ec1c40573955362ae5715d219daac4669497d7514f7a7ebff8684d3f8` |

The WETH/USDG pool had approximately `4.22e18` raw liquidity during this review,
above the adapter's `1e18` floor. Re-query every address, code hash, observation
history, and liquidity value immediately before deployment.

## Remaining launch gates

1. **Independent audit:** audit the exact commit, linked libraries, no-rescue
   custody model, v4 action encodings, history-confirmed settlement design, TWAP
   adapter, and Fee Router clone.
2. **Exact deployment rehearsal:** deploy the final artifacts on a fresh fork,
   compare runtime bytecode and all immutables, execute one complete band, and
   preserve the manifest.
3. **Frontend/indexer:** support the automated keeper's arm/disarm/settle states,
   their events, empty Pons v2 `guardData`, executable tick-rounded boundaries,
   and interrupted approval/create/fund flows.
4. **Monitoring:** watch WETH/USDG liquidity, archive/event agreement, observer
   health, failed settlements, liability versus balance, dependency code hashes,
   and undelivered proceeds. Observer failure must alert immediately because it
   safely pauses new confirmations.

## Residual risks and scope limits

- Pons v2's hook has no historical tick accumulator. Confirmation therefore depends
  on independent archive/event providers and the observer's liveness. Disagreement
  or downtime fails closed and delays settlement rather than accepting partial history.
- ETH/USD inherits USDG's dollar-peg risk and the WETH/USDG pool's market depth.
  The TWAP, spot-deviation check, and liquidity floor reduce manipulation risk but
  cannot eliminate stablecoin or market risk.
- Pons v1 passes local tests but still lacks a live Robinhood fork lifecycle.
- pools.trade and letscash.fun do not yet have production verifiers/guards or
  fork tests and must not be enabled or advertised as supported.
- The public RPC does not provide a reliable pinned archival fixture. Rerun the
  live test before deployment and whenever Pons or Uniswap dependencies change.
