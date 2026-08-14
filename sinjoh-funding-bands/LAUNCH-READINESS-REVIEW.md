# Funding Bands launch-readiness review

Review date: 2026-08-14

## Verdict

**Pons v2 contract mechanics: PASS. Public mainnet launch today: NO-GO.**

The Pons v2 path completed a fresh launch, graduation, two deposits into one real
Uniswap v4 position, a real hooked swap across the band, full position burn,
native ETH receipt from the canonical PoolManager, WETH wrapping, exact 1% fee
accounting, and liability crediting on a disposable Robinhood mainnet fork.

No unresolved critical contract defect was found after the fixes below. Launch is
still blocked on operational work that cannot be proven by Solidity tests: a
manipulation-resistant reference-price publisher, ETH/USD publication, production
signer custody and monitoring, exact deployment rehearsal, and independent audit.
The immutable/no-rescue design makes those gates mandatory rather than optional.

The largest remaining architectural risk is liveness: the v4 guard currently has
one immutable ECDSA signer. If that signer is permanently lost or unavailable,
active Pons v2 positions cannot pass settlement and cannot be rescued or migrated.
This must be explicitly accepted or replaced with a reviewed redundant signing
design before deployment.

## Critical defects found and corrected

1. **Native Pons v2 settlement would have reverted.** Uniswap v4 `TAKE_PAIR`
   sends native ETH from PoolManager, not PositionManager. The manager now derives
   and freezes the canonical PoolManager, requires StateView to bind the same
   manager, and accepts native ETH only from that address. Mocks reproduce the
   real sender and the live fork proves the flow.
2. **Production guard evidence could not be supplied during registration.**
   `create` now accepts bounded `guardData` and checks every lower boundary before
   freezing bands.
3. **Displayed prices did not exactly match executable tick-rounded positions.**
   Stored and emitted WETH prices are now derived from the final usable ticks for
   both token orientations.
4. **The deployment script could silently combine mismatched profile lists and
   did not run on macOS Bash 3.2.** It now works on Bash 3.2, checks every supplied
   runtime hash before broadcast, captures the deployment result, and reads back
   all manager immutables, profile addresses, hook-data hashes, PoolManager,
   profile count, and oracle age.
5. **A metadata-compatible counterfeit Fee Router could be selected.** The manager
   now freezes an approved Fee Router clone runtime hash and requires both exact
   bytecode and matching creator/subject/intake metadata.
6. **Pons v2 lacked a production-grade second price signal.** The new v4 guard
   requires both canonical StateView spot and a short-lived signed reference tick.
   Signatures bind chain, guard, funding manager, pool, token orientation,
   direction, reference tick, and validity window. Low-`s`, valid-`v`, signer,
   context, expiry, and dependency-code checks are enforced.
7. **Robinhood lacked a configured ETH/USD adapter in this repository.** The new
   AggregatorV3-compatible signed oracle enforces Robinhood chain ID, immutable
   signer, five-minute maximum observation age and authorization lifetime,
   monotonic observations, replay resistance, and canonical signatures.

## Data-flow review

| Data entering or leaving | Authority and validation | Result |
|---|---|---|
| Launch creator, token, phase, pair, fee, spacing, hook | Immutable Pons v2 factory record plus token self-attestation; only `PoolCreated`; only native ETH/WETH | Passed locally and on live fork |
| Pool identity | Reconstructed `PoolKey` and `PoolId`; canonical StateView/PoolManager agreement | Passed locally and on live fork |
| ETH/USD | Immutable signed oracle; positive complete round; freshness checked again by manager | Contract path passed; publisher operations pending |
| Current band price | Canonical v4 spot plus independently signed reference tick; both must be on the required side | Passed locally and on live fork; independent data source pending |
| Creator inventory | Exact `transferFrom` delta; fee-on-transfer rejected; exact approvals cleared after use | Passed |
| v4 action payloads | Core constructs pool, ticks, liquidity, recipient, hook, and actions; caller controls none of them | Passed with real Pons hook |
| Native settlement proceeds | Only canonical PoolManager may send ETH; exact balance delta wrapped into frozen WETH | Passed with real PoolManager |
| Fee Router destination | Exact configured runtime hash plus creator, subject, WETH intake, and subject intake | Passed, including counterfeit rejection |
| Creator/router proceeds | Pull ledger; liabilities reduced before transfer; exact sender/recipient deltas; retry after failure | Passed |
| Protocol fee | 1% of cumulative realized WETH, incremental charge, no fee on subject residual/LP fees | Passed unit and invariant tests |
| Events and UI reads | Requested USD values plus executable tick-rounded WETH values and immutable recipients | Passed unit assertions |

## Verification evidence

### Automated tests

- **47 local tests passed, zero failed:** 24 core lifecycle/security tests, 6 Pons
  v2 profile tests, 3 Pons v1/TWAP tests, 6 signed v4 guard tests, 5 signed
  ETH/USD tests, and 3 stateful accounting invariants.
- **786,432 intensified invariant calls passed:** 1,024 runs × 256 calls for each
  of three invariants, with zero handler reverts.
- **2,048 market-cap conversion fuzz cases passed** across realistic supply,
  ETH/USD, market-cap, tick-spacing, and token-orientation inputs.
- **1 live-fork end-to-end Pons v2 test passed:** fresh launch and graduation,
  production signed oracle and guard, real PositionManager/Permit2/hook mint and
  increase, real swap, burn, native settlement, WETH wrap, and 1% accounting.
- Maximum ten-band create-and-fund scenarios passed for v3 and Pons v2/v4. The
  core v3 test used about 3.14 million gas; the full signed Pons v2 batch used
  about 9.11 million gas, both well below Robinhood's observed block limit.
- Both subject-token address orientations, native and WETH quotes, partial
  proceeds delivery, failed-delivery retry, residual isolation, price reversal
  rules, stale/future/negative/incomplete oracle data, replay/malleability,
  duplicate bands, overlapping bands, post-cross funding, double settlement,
  unauthorized creator actions, unsolicited NFTs, counterfeit routers, and
  mismatched v4 infrastructure are covered.

### Build and analysis

- `forge fmt --check`: pass.
- `forge lint --severity high --severity med`: pass.
- `forge build --sizes`: pass. `SinjohFundingBands` runtime is 22,782 bytes,
  leaving 1,794 bytes under EIP-170.
- `bash -n script/deploy.sh`: pass. Safe preflight failure was also exercised
  without broadcasting.
- Slither ran 102 detectors over 67 contracts. Its broad run reported only
  expected/false-positive patterns in the reviewed code. Targeted high-impact
  detectors reported three reentrancy findings; all affected public entrypoints
  are protected by `nonReentrant`, and transfers use checks-effects-interactions.
  Slither also emitted unresolved-reference errors in duplicated vendored
  Uniswap sources, so this is partial corroboration rather than a clean static
  analysis certification.
- `forge coverage --ir-minimum` compiled, but Foundry's coverage analyzer could
  not resolve relative imports in vendored Uniswap packages. Coverage percentage
  is therefore unavailable; behavioral and invariant results above are the
  reliable evidence.

## Live Robinhood dependencies verified

| Component | Address | Runtime code hash |
|---|---|---|
| WETH | `0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73` | `0x5706be52f64875fee65a2cec0d80e47a23d8793cbe85d214b48445e2d05f5353` |
| v3 factory | `0x1f7d7550B1b028f7571E69A784071F0205FD2EfA` | `0xec72b1abd1f2faee020cfea9c646bd8994f9fb389054f6e574f103a895091739` |
| v3 PositionManager | `0x73991a25C818Bf1f1128dEAaB1492D45638DE0D3` | `0x0a493d1af3d0f25fed8efa205244ebee14114267a08647fc38c515c7cd6ead4f` |
| v4 PositionManager | `0x58daec3116aae6D93017bAAea7749052E8a04fA7` | `0xc873e135dc9aaec88489cfbad146b4cb49d6a32e0d80326377784b7ba17670b2` |
| v4 StateView | `0xF3334192D15450CdD385c8B70e03f9A6bD9E673b` | `0x7d9c591e0956fd89d98feb4ffcfe8bf1f7a62bd485edd979fa21d104b49878a6` |
| v4 PoolManager | `0x8366a39CC670B4001A1121B8F6A443A643e40951` | `0xbd3881180b547f5fe817545743cfb4343e96b1bc6640dcd70c106b0066e95626` |
| Permit2 | `0x000000000022D473030F116dDEE9F6B43aC78BA3` | `0x5208783f52488f7d3493e5e38311ab707c1d75457fe472a19b0b4d57d66a7fca` |
| Pons v2 factory | `0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e` | `0x89a27da6f703e0a7cdd4f233e7cb57604ff75b164530962d3ff7cf8483a67d84` |
| Pons v2 hook | `0xE5e702641Ea86F4ae6cC3cDaeD2B886f976Be044` | `0xc21b1e6c1b45403e81a581f22ed6d9c747997af1cfdac1b1dc9f4b1d346a10db` |
| Pons buyback swap adapter | `0x39217172A3F07E827557093989039F968A571D43` | `0xbf53dc3ec1c40573955362ae5715d219daac4669497d7514f7a7ebff8684d3f8` |

The v4 PositionManager and StateView both resolved the PoolManager shown above.
Re-query and record all values in the signed deployment manifest immediately
before deployment. The currently observed Sinjoh Fee Router clone runtime hash is
`0xf9461aa7ef61b19963cdc3da6d2fe09022718bd753e8c6b7239dce49254ce8fe`;
it still requires independent approval for the deployment manifest.

## Mandatory launch gates

1. **Independent audit:** audit the exact commit, linked library bytecode, no-rescue
   custody model, v4 action encodings, signed-price scheme, and Fee Router clone.
2. **Reference-price service:** define and document the source independently of
   the Pons pool, aggregation method, outage policy, maximum deviation, signing
   API, authentication, monitoring, and incident shutdown procedure. Signing the
   same manipulable pool spot would defeat the second-source protection.
3. **ETH/USD service:** publish fresh signed rounds continuously, alert before the
   manager's `maxOracleAge`, and test stale/no-data recovery. Official
   [Chainlink release notes](https://docs.chain.link/data-streams/release-notes)
   indicate Data Streams support on Robinhood, but no standard AggregatorV3
   ETH/USD address was identified in the reviewed configuration.
4. **Signer security and liveness:** decide whether a single immutable ECDSA signer
   is acceptable. If retained, use separate least-privilege keys, HSM or managed
   signing, no deployer key reuse, audited signing payload generation, rate limits,
   logs, alerts, and tested redundant infrastructure. A new deployment cannot
   recover positions already held by an old manager after permanent signer loss.
5. **Deployment rehearsal:** deploy the exact artifacts on a fresh fork, provide
   full code hashes and hook-data hashes, read back every immutable, compare
   runtime bytecode, execute one complete band, and preserve a signed manifest.
6. **Frontend/indexer:** update the five-argument `create` ABI, request fresh guard
   evidence for create/fund/settle, index every lifecycle event, show executable
   tick-rounded boundaries, distinguish draft from committed inventory, and test
   interrupted approval/create/fund flows.
7. **Operational runbooks:** monitor oracle age, signer health, settlement failures,
   liability-versus-balance, PoolManager/StateView code hashes, and proceeds that
   remain undelivered. Document that direct token transfers are stranded.

## Scope limits

- **Pons v2:** mechanically approved by this review after graduation, subject to
  the mandatory gates above.
- **Pons v1:** local tests pass; no live Robinhood fork lifecycle yet.
- **pools.trade and letscash.fun:** not implemented as production profiles and not
  fork-tested. They must not be enabled or advertised as supported.
- The live fork tracks current deployed bytecode and intentionally creates a fresh
  token. The public RPC did not provide a reliable pinned archival fixture, so CI
  should rerun this test immediately before deployment and whenever Pons or
  Uniswap dependencies change.
