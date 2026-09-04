# Yield Banks production activation

The deployment pipeline must reject activation until every required manifest entry satisfies
`yield-banks-manifest.schema.json` and its live runtime code hash matches.

Verified chain constants that must appear by their complete address:

- Robinhood Chain WETH: `0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73`
- WETH EIP-1967 implementation observed on 2026-08-31:
  `0xc6b81b429797e0f555440b70cd99e032d7ae947e`
- WETH implementation runtime hash observed on 2026-08-31:
  `0xbe1295f37be34ffe03ad779bda0ef278907e1856b51a3be2f35ee541d75d4650`
- WETH proxy runtime hash observed on 2026-08-31:
  `0x5706be52f64875fee65a2cec0d80e47a23d8793cbe85d214b48445e2d05f5353`
- USDG: `0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168`
- USDG EIP-1967 implementation: `0x68184c449e1a8f34fa18d289737129fd27b66f8f`
- SeaDrop 1.0: `0x00005EA00Ac477B1030CE78506496e8C2dE24bf5`
- SeaDrop 1.0 runtime hash: `0x53e4b9339cf624803c9a7d0195576cca5b917920813508d86b3eb93dcbabeb5c`
- Seaport 1.6: `0x0000000000000068F116a894984e2DB1123eB395`
- Seaport 1.6 runtime hash: `0x95809b70c9659c30188db5fdd87103e24b1a55379af8c851fca393aba0224a00`
- Delta position builder: `0x6235cF6bd8419b34942F4EDDB39C880BD96dD700`
- Delta position builder runtime hash: `0xb9b462897f26b3d9082e6db057e363ea01cee5931f39bc62d52eeaa4aa7a9039`
- Delta Uniswap V3 factory: `0x1f7d7550B1b028f7571E69A784071F0205FD2EfA`
- Delta Uniswap V3 factory runtime hash: `0xec72b1abd1f2faee020cfea9c646bd8994f9fb389054f6e574f103a895091739`
- Delta position manager: `0x73991a25C818Bf1f1128dEAaB1492D45638DE0D3`
- Delta position manager runtime hash: `0x0a493d1af3d0f25fed8efa205244ebee14114267a08647fc38c515c7cd6ead4f`
- Robinhood Stock Token beacon: `0xe10b6f6B275de231345c20D14Ab812db62151b00`
- Robinhood Stock Token implementation observed through that beacon:
  `0xb35490d6f9163DE4F80d88dc75c3516eb64C5aE2`

The production release manifest is mainnet-only (`chainId: 4663`). A testnet deployment plan may
still be rehearsed on chain `46630`, but it cannot be promoted with mainnet WETH, USDG, SeaDrop, or
Seaport addresses. A testnet release needs a separately researched dependency set and release
schema instead of reusing this manifest.

Still required from the operator and review process:

1. creator, Sinjoh, allocation-operator, guardian, proposer, and timelock recipients;
2. the collection's reviewed Robinhood Stock Token contracts, eligibility classification, explicit custody/income model, and HTTPS disclosure;
3. every Chainlink/reference feed and heartbeat;
4. every base-sleeve allocation route, reverse rebalance route, price feed, and runtime code hash;
5. each Delta infrastructure generation's factory, position manager, position builder, runtime
   hashes, and approved Yield Banks route/sleeve/adapter/feed creation-code hashes;
6. runtime hashes, source commit, dependency lock hash, deployment transaction hashes, and audit hashes;
7. immutable collection-specific `maxSupply`, fee-weight schedule, `secondaryRoyaltyBps`, and
   per-sleeve strategy count/cap/operator-loss limits; and
8. timelock authorization of each Project V2 revenue bridge for `YIELD_BANK_PROJECT_REVENUE`.

The deployment plan must declare an `openSeaManager` wallet separately from the creator payout
recipient. `YieldBankNFT` is initially owned by that manager so the custom SeaDrop contract appears
in OpenSea Studio and its drop/collection settings can be published. After the manifest-bound
SeaDrop settings are configured, the manager calls `transferOwnership(collectionTimelock)`. The
timelock proposer schedules `acceptOwnership()` on the NFT, and anyone executes it after the
collection's configured delay. Release verification requires `owner()` to equal the collection timelock; no mint
should be opened before that handoff is complete.

The manifest must classify both WETH and USDG as EIP-1967 proxies and bind each live implementation address and
implementation runtime hash. Every Robinhood Stock Token must bind its proxy runtime, the beacon
stored in the ERC-1967 beacon slot, the beacon runtime hash, the implementation returned by the
beacon, and the implementation runtime hash. A proxy runtime hash by itself is not sufficient: it
does not change when governance upgrades the active logic.

Robinhood Stock Token dividends and splits are represented through the token's multiplier model;
they are not separate cash distributions to the sleeve. The launch equity model must therefore
record `balance-appreciation`, and every PriceHub reference used for a Stock Token must already be
multiplier-adjusted. Do not compare a multiplier-adjusted Chainlink quote to an unadjusted REST
price.

`YieldBankSystemFactoryDeployer` uses governance-only CREATE3 so the system-factory address is
fixed by the reviewed `factorySalt`, independent of factory init code. The system factory then uses
CREATE3 for the eight collection components, including the separately deployed and codehash-pinned
account implementation, so constructor wiring can be planned without an init-code address cycle.
The pinned deployment plan must order dependencies so the base sleeves deploy before the portfolio
allocator, the allocator deploys before `DeltaPoolController`, and both deploy before the revenue
router. The allocator accepts the controller's predicted nonzero CREATE3 address during its
constructor; the controller then verifies the already-deployed allocator and reads the predicted
collection address from it. The factory rechecks the allocator/controller relationship against the
predicted collection before CREATE2 deploys the collection. This ordering breaks the immutable
address cycle without accepting an unbound component. The collection follows through CREATE2 after
every component runtime hash passes.
Direct native or ERC-20 transfers to the revenue router are reserved for royalty synchronization. Only the
allocation operator may synchronize them, supplying fresh guarded route calldata for the current
amount; timelock-bound route addresses and runtime hashes cannot be caller-selected.

The deployment input must validate against `yield-banks-deployment-plan.schema.json`. It must
contain the full encoded component init code and collection configuration—never environment-derived
addresses. Execute it with:

The collection configuration's `feeWeightRanges` is an ordered list of inclusive token-id
boundaries and positive relative weights. The final boundary must equal `maxSupply`; up to 4
ranges are supported. Use an empty list for equal-weight collections. The 4-range limit keeps the
complete constructor bytecode plus its encoded configuration below EIP-3860 on mainnet. This schedule is immutable
after deployment and governs collection-wide fee distributions and exit-tax redistributions; it
does not alter the primary backing actually recorded for each NFT.

Fee weights are collection configuration, not protocol constants. Every collection deployed from
this factory generation may choose its own supply and range schedule. Because the configuration ABI
and collection creation-code hash include the schedule, deployments made with the previous factory
generation remain unchanged and a newly registered factory version is required for weighted
collections.

```sh
YIELD_BANK_DEPLOYMENT_PLAN=/absolute/path/to/reviewed-plan.json \
  forge script script/DeployYieldBanks.s.sol:DeployYieldBanks \
  --rpc-url "$YIELD_BANK_RPC_URL" --account "$FOUNDRY_ACCOUNT" --broadcast
```

Configure each source-verified Delta generation once on `DeltaPoolController`. The release manifest
contains the infrastructure graph and exact creation-code hashes; it contains no pool list. Owners
may then request any canonical, initialized, unlocked, liquid Delta V3 pool paired with WETH. The
controller verifies `factory.getPool(token0, token1, fee)` on every selection. This WETH-pair
constraint belongs to the current adapter generation, not to a hard-coded token or pool.
The owner UI and allocation workflow use `isAllocationPool`, which additionally rejects an existing
foundation if its exact manager/builder/binary commitment is no longer the factory's current
generation. Dynamic foundations do not consume global distribution-asset slots: redemption first
requires the holder to rebalance fully out of the active pool, so dynamic sleeve shares never enter
the burn-time distribution loop.
`isSelectablePool` is the lower-level canonical-pool discovery check.

Before enabling a generation, the collection timelock must execute all three setup calls: authorize
`DeltaPoolController` once with `StrategyRegistry.setRegistrar(controller, true)`, authorize it once
with `PriceHub.setRegistrar(controller, true)`, and call
`DeltaPoolController.configureInfrastructure(factory, config)` with the source-verified dependency
graph and locally built creation-code hashes. These are controller/infrastructure grants, not
pool-specific grants. The release verifier fails unless both registrar permissions, every runtime
and creation-code hash, every dependency getter, and the controller's active infrastructure record
all match the manifest.

When a requested pool has no materialized foundation, the allocation operator calls
`MaterializeYieldBankDeltaPool.s.sol`. It submits the selected pool, per-foundation cap/position/loss
limits, and the locally built creation code. The controller rejects binaries whose creation-code
hashes differ from governance's infrastructure approval, then deploys and verifies both routes, the
isolated one-adapter sleeve, and the adapter itself. It also registers the adapter and dynamic sleeve
atomically. Pool-specific governance and manifest edits are neither required nor available.

Set `YIELD_BANK_DELTA_CONTROLLER`, `YIELD_BANK_DELTA_POOL`,
`YIELD_BANK_DELTA_MAXIMUM_POSITIONS`, `YIELD_BANK_DELTA_ADAPTER_CAP_BPS`, and
`YIELD_BANK_DELTA_MAXIMUM_LOSS_BPS` to the reviewed values, then execute:

```sh
forge script script/MaterializeYieldBankDeltaPool.s.sol:MaterializeYieldBankDeltaPool \
  --rpc-url "$YIELD_BANK_RPC_URL" --account "$FOUNDRY_ACCOUNT" --broadcast
```

If the paired token lacks a direct trusted USD feed, the operator can ask the controller to deploy
the approved `DeltaV3TwapUsdFeed` binary. It binds the selected pool's actual runtime hash, prepares
observation history, and configures PriceHub. The quote remains fail-closed until at least the full
`twapWindow` has elapsed and `latestRoundData()` succeeds. The pool-derived price inherits economic
manipulation risk from that pool; use a current independent reference source when one exists and set
nonzero reviewed liquidity and deviation controls. The controller enforces the collection's
immutable maximum heartbeat, maximum grace period, minimum TWAP window, maximum reference
deviation, and maximum spot/TWAP deviation so the allocation operator cannot weaken those policy
bounds. Use
`script/ConfigureYieldBankDeltaPoolFeed.s.sol` for this controller-mediated path; the old standalone
pool, adapter, and feed deployers have been removed so production tooling cannot bypass controller
registration.

Every strategy action remains manual. The allocation operator supplies the WETH conversion amount,
minimum paired-token output, Delta ladder rungs, current-tick bounds, and deadline when depositing. A
withdrawal explicitly identifies each position and liquidity amount to unwind, its token minima,
the paired-token amount to convert back, minimum WETH output, and exact WETH to return. A full exit must
list every live position and returns any residual WETH and paired tokens in kind to the sleeve. Use the
SDK's `encodeYieldBankDeltaDepositData`, `encodeYieldBankDeltaWithdrawalData`,
`encodeYieldBankDeltaCollectionData`, and `encodeYieldBankDeltaExitData` helpers; do not hand-encode
operator calldata.

Owner-selected allocation execution is manual as well. Before activation, the collection timelock
must bind WETH entry routes for the Robinhood Stock Token and USDG sleeves and a reverse-to-WETH route
for USDG, every reviewed Stock Token, and every Delta paired token. The release manifest's `routeBindings` section
records each exact address and runtime hash, and the verifier checks the live allocator mappings.
Dynamic pool routes are controller-deployed and bound during materialization; they are not entries in
the release manifest's base `routeBindings`. For each execution the operator must use the SDK's `prepareYieldBankTargetExecution` helper with
current per-asset minima, adapter unwind calldata, maximum adapter-withdrawal-loss values, expected
target revision, and deadline. Holders use `prepareYieldBankTargetAllocation`; that call changes
only the requested target and never moves backing by itself. Each revision is executable once, and
any later rebalance requires another owner request.

After source verification and OpenSea configuration, complete every provenance and transaction
field in a manifest conforming to `yield-banks-manifest.schema.json`, then verify all runtime code,
factory/configuration commitments, account implementation, supply, royalty percentage, SeaDrop,
proceeds-vault, and operator bindings:

The manifest must record the OpenSea-observed secondary royalty percentage and recipient. They must
match the collection's immutable `secondaryRoyaltyBps` and revenue router exactly; a configuration
drift blocks release even though ERC-2981 itself cannot force a marketplace to pay.

It must also record every enumerable SeaDrop mint path and authorization set: the public-stage
tuple, allowlist root and stages, fee recipients, payers, token-gated assets and stages, signed-mint
signers and validation bounds. The verifier reads these values from
`0x00005EA00Ac477B1030CE78506496e8C2dE24bf5`, recomputes `mintStagesHash`, and rejects any payout,
price, time window, supply or wallet cap, fee, restriction, payer, signer, gate-token, or allowlist
drift. A nonempty allowlist requires an immutable, NFT-bound `YieldBankMintStagePolicy`. Each policy
stage owns an independent token-id range, price, allowlist time window, supply cap, and wallet cap.
Initial allowlist windows do not overlap, so the policy can identify SeaDrop's otherwise omitted
stage from the current time. After the last allowlist window, OpenSea's single public stage can be
rotated among unsold tiers. A public configuration is accepted only when its price, wallet cap, fee,
and fee-recipient restriction uniquely match one immutable tier. This keeps every unsold tier at its
original price without a custom mint site. A staged-policy manifest must have empty payer,
token-gated, and signed-mint sets so SeaDrop cannot enter the parameter-less NFT callback through an
ambiguous route. The verifier checks all policy terms and the proceeds
vault rejects any payout that differs from the policy's exact expected net amount.
The configured eligibility policy is separately codehash-pinned and read back from the collection
and all three sleeves.
Because Seaport supplies no eligibility proof, `canReceiveNFT(recipient, "")` must decide NFT
transfer eligibility solely from recipient-address state; a proof-required NFT transfer policy is
not OpenSea-compatible.

```sh
# Before using either deployment schema, rejects unresolved or external references:
node script/verify-yield-bank-schemas.mjs

node script/verify-yield-banks-manifest.mjs \
  /absolute/path/to/yield-banks-manifest.json "$YIELD_BANK_RPC_URL"

# After building both sibling repositories, proves every SDK read/write ABI record against Forge:
node script/verify-yield-bank-sdk-abi.mjs
```

The release manifest records the factory and collection salts, full collection configuration hash,
system plan hash, collection creation-code hash, metadata base URI and contract URI with their
hashes, and per-address version, provenance, deployment transaction, verification transaction, and
runtime code hash.

Publish the manifest's exact collection overview URL to the public API as an address-keyed JSON
object in `YIELD_BANK_OPENSEA_COLLECTIONS_JSON`. The API rejects non-OpenSea hosts, non-overview
paths, queries, fragments, and invalid collection addresses. It does not invent an asset URL when
the reviewed slug is absent.

No placeholder address is valid in an actual deployment plan or transaction. OpenSea Drop publishing and creator payout configuration must be
completed as an operational canary after the custom NFT is deployed. A collection's concrete
pool prices, caps, and transaction parameters are reviewed operation inputs, not protocol defaults.
Their absence from the release manifest does not block other pools and does not require another
contract implementation.

For the first `$INJOH`/WETH collection, the verified `$INJOH` token is
`0x2cC0FAC44B8252f6B10208B091aFf2c94B4da77D` and the Delta factory returns pool
`0xB09fa4f04032b9d9e690ac4a1d29523b5f9A72DC` at fee `10000`, with tick spacing `200`.
The controller discovers this pool from the verified factory; neither `$INJOH` nor its pool is
hard-coded or listed in the collection release manifest. A valid PriceHub quote and operator-reviewed
materialization parameters are still required before funds can enter it. Do not substitute the
USDG/WETH canary pool or infer an address from a ticker.

The canary must use a positive-priced public, token-gated, signed, or policy-backed Merkle SeaDrop
stage with fee basis points below 10,000. A policy-backed allowlist must be generated from reviewed
stage inputs and verified against its published root before minting.
