# Contracts v2 pre-audit review

Status: **engineering review in progress; not an independent audit and not production approval**.

## Automated gates

The package currently passes `forge fmt --check`, `forge lint`, `forge build --sizes`, the complete
Foundry unit/fuzz/invariant/integration suite, and `npm test --prefix sdk`. Foundry invariants use
256 runs × 64 calls and fuzz tests use 1,000 runs. The suite contains the specified 25 integration
flows, two cross-module system invariant suites, and all eight required end-to-end journeys (plus a
separate staker-dividend journey).

`script/coverage.sh` runs the all-modules Launcher suite under production compiler settings, then
runs source-only LCOV coverage for every other suite under Foundry's minimum-IR instrumentation.
The split is required because coverage instrumentation expands the Launcher's stored creation code
past EIP-3860 even though the production-mode launch passes. The script uses temporary in-package
dependency links to work around Foundry Solar's inability to resolve relative imports outside the
package root and removes them on exit. The retained report is `security/coverage.lcov`: 4,407 / 8,311
lines (53.03%), 670 / 1,295 functions (51.74%), and 392 / 1,657 branches (23.66%) across all source,
including copied interfaces, external libraries, and defensive error paths. The instrumented run
completed 409 tests with zero failures and one explicitly environment-gated fork skip.

Slither/Aderyn/Semgrep were not installed in the review environment. Their findings are therefore
**not dispositioned**. The release preflight requires independent audit evidence and cannot be used
to convert this document into audit evidence.

## Deliberate compiler warning

`Create3ProxyV2.deploy` executes `SELFDESTRUCT` after creating its sole child. This is intentional:
the proxy is created and destroyed in the same transaction, the case that EIP-6780 preserves under
Cancun. It has no storage, authority, or subsequent use; the child address is verified to contain
code immediately afterward. Release compilation is pinned to Solidity 0.8.28 and `evm_version =
"cancun"`. Auditors must still confirm the target chain's opcode semantics before deployment.

## Assembly inventory

| Surface | Purpose | Bounds / disposition |
| --- | --- | --- |
| `CreationCodeChunkV2` constructor | return inert `STOP || creationCode` runtime | input is bounded by `CreationCodeStoreV2`; leading STOP prevents execution |
| `CreationCodeStoreV2.creationCode` | `EXTCODECOPY` immutable chunks | recorded total length and hash are checked before every deployment |
| `Create3ProxyV2` / `Create3V2` | one CREATE from deterministic CREATE2 proxy | zero result and final predicted bytecode are checked; proxy has no retained role |
| `ProjectLaunchDeployerV2._sortedUnique` | truncate an overallocated memory array | new length never exceeds allocated candidate length |
| Router isolated execution | cap copied downstream revert data | copies at most 256 bytes plus original length; failed share becomes backed escrow |
| Airdrop isolated payment | gas-limit recipient and cap revert data | copies at most 256 bytes; failed payment becomes recipient credit |

All blocks use Solidity's `memory-safe` dialect. No `delegatecall` exists in v2 sources.

## Low-level and native calls

- Treasury, Router, Airdrop, Basket, Raffle, and Liquidity native sends check success and either
  revert atomically or create an exact retryable liability according to that protocol's spec.
- Router and Airdrop self-calls are typed entrypoints guarded so arbitrary callers cannot use the
  isolated execution surface.
- ERC-721 `ownerOf` static calls are used only to prove a burned/nonexistent position and validate
  exact NFT lifecycle state.
- The Raffle/Liquidity `SafeTransferLib` accepts ERC-20 calls returning no value or canonical true,
  rejects false/revert, and rejects malformed balance queries.

## Approval inventory

Every integration allowance is exact and cleared to zero after success:

- Treasury swaps, Basket funding, and Basket burn price;
- Router swaps and typed Treasury/Airdrop/Raffle/Liquidity funding;
- Basket swaps, yield deposits, and dividend sinks;
- Funding Band position, swap, and destination funding;
- ERC-4626 deposits and Liquidity Permit2 approvals.

Atomic revert restores the pre-call allowance on failure; the failed operation does not leave a new
committed allowance. Tests assert zero post-success allowances on each standard route. Funding Band
position-NFT approval is limited to the one bound adapter and the position must be burned with zero
reported liquidity before settlement continues.

## External trust boundaries

| Integration | Contract-enforced assumptions | Remaining release evidence |
| --- | --- | --- |
| ERC-4626 Basket adapter | synchronous standard, exact measured deposits/shares, principal high-water mark, Basket-only recipient | selected vault fork run is still required |
| Funding Band market-cap guard | exact project/pool/supply binding, minimum TWAP window, fresh advancing observation | production guard/oracle implementation and fork evidence are missing |
| Funding Band position adapter | exact Bands/subject/quote/pool/manager binding and complete exit | production adapter and fork evidence are missing |
| swap adapters/guards | immutable runtime/route approval leaf, exact deltas, cleared allowance | every selected production route needs fork evidence |
| Raffle randomness | immutable adapter and timeout/retry accounting | selected provider liveness/unpredictability evidence is missing |
| Uniswap v3/v4 + Permit2 | release-pinned addresses/runtime hashes and permanent position custody | target-chain fork and testnet rehearsal are missing |

These missing artifacts are intentionally required by `script/deploy-release.sh`, which records
their SHA-256 hashes and requires an explicit passed audit status. Human verification of authorship
and substance remains mandatory.

## Decimal and oracle assumptions

- Project-token voting and staking use raw token units; no decimal normalization is assumed.
- Funding Band market caps use USD E8 values and immutable `referenceSupply`; the approved guard is
  responsible for subject/quote and quote/USD decimal normalization.
- Swap/Basket/Liquidity accounting compares measured raw balances and does not infer decimals.
- Frontends must label fixed-supply FDV, observation age/window, and effective rounded ticks.

## Privilege summary

- Registry is append-only and has no project execution or custody power.
- Launcher, deployment engine, creation-code stores, ERC-4626 factory, and Basket clone
  implementation are ownerless and are never project controllers.
- Each project controller is exactly its independent Multisig Account or Token Governance Timelock.
- Guardians can pause only the explicitly specified staking behavior and cannot withdraw assets.
- Keepers are permissionless and can only advance typed work/retry paths.
- Protocol fee recipients can receive accumulated fees but cannot configure or seize projects.

The all-module journeys assert controller readbacks and zero Launcher/deployer token custody. A
testnet-generated role report and asset-flow reconciliation remain mandatory release evidence.
