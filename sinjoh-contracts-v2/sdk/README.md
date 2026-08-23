# Contracts v2 SDK

Typed, framework-neutral helpers generated from the exact audited Solidity artifacts.

```ts
import {
  buildLaunchFromPreset,
  encodeGovernanceAction,
  pendingWork,
  projectTreasuryVaultV2Abi,
  validateLaunchConfig,
} from "@sinjoh/contracts-v2-sdk";
```

- `buildLaunchFromPreset` accepts only creator-owned choices and hydrates a complete reviewed
  platform preset. Creator forms never collect adapter, oracle, pool, proof, route, or protocol
  infrastructure fields.
- Funding Bands presets use the platform-managed V3 integration factory: preflight predicts the
  guard and position adapter and launch deploys both atomically. Release tooling can use
  `fundingBandFactoryIntegrationApprovalLeaf` to build the automatic factory approval leaf,
  `fundingBandPairIntegrationApprovalLeaf` for a reviewed predeployed pair, and
  `swapIntegrationApprovalLeaf` for reusable swap adapter/guard pairs. These helpers encode exact
  addresses and runtime hashes from the release manifest; this is platform plumbing, not a
  creator-form field.
- `predictLaunch` returns stable deterministic addresses without requiring a complete launch.
- `validateLaunchConfig` performs the same full preflight used by `launch` before a wallet prompt.
- `encodeGovernanceAction` creates one `{ target, value, data }` action usable by either governance
  workflow without exposing raw calldata assembly to the UI.
- `projectRecord` discovers the complete project from the Registry.
- `buildProjectLaunchManifest` cross-checks the validated preflight against the post-launch
  Registry record and returns canonical JSON-safe provenance. `serializeProjectLaunchManifest` and
  `projectLaunchManifestHash` make that artifact deterministic for publication or signing; no
  project address is entered manually.
- `pendingWork` provides one-call status helpers for every module with keeper or recovery work.
- `launchErrorMessage` converts stable Launcher custom-error names into corrective product copy.
- `buildVerifiedAirdropEpoch` is the attestor-safe path: it requires two independently acquired RPC
  snapshots to agree on block hash, time, complete holder set, weights, and eligible supply before
  creating anything signable. `buildAirdropEpoch` is the deterministic lower-level tree primitive;
  it sorts positive-weight holders, retains zero-entitlement leaves, and builds the exact
  direction-aware Merkle-sum proofs used by automatic push delivery.
  `airdropCommitmentTypedData` supplies the attestor signing payload.
- `reconstructHolderAirdropSnapshot` replays complete ERC-20 transfer history;
  `reconstructStakerAirdropSnapshot` replays PoS position ownership. Both fail closed on malformed
  log ordering and cross-check reconstructed aggregate and eligible historical supply.
- `planAirdropPushBatches` skips already-settled holders, respects the on-chain batch cap, and keeps
  zero-entitlement leaves in the work queue because they still count toward epoch finalization.
- `encodeAirdropPushCalls`, `encodeAirdropRetryCreditCall`, `encodeAirdropClaimCreditToCall`, and
  `encodeAirdropFinalizeCall` return
  typed permissionless keeper transactions; `pendingWork.airdropCredit` exposes exact retry work.
- `reconstructRaffleSnapshot` replays complete ERC-20 history in canonical log order and computes
  either snapshot or window-minimum holder weights. Zero and the canonical burn address are always
  excluded; platform-provided custody exclusions are applied automatically.
- `buildVerifiedRaffleRound` requires matching snapshots from two providers before producing the
  exact padded Merkle-sum tree used by the Raffle. Its roots, proofs, and winner indices are tested
  against the normative Solidity-generated fixtures.
- `encodeRaffleCommitCall`, `encodeRaffleClaimCalls`, `encodeRaffleRetryCall`, and
  `encodeRaffleClaimOwedToCall` and `encodeRaffleCloseCall` cover the complete lifecycle. Winners never need to register,
  build a proof, or submit a transaction. `pendingWork.raffleRound`, `raffleCredit`, and
  `raffleStockCredit` expose all round and retry state needed by apps and keepers.
- `buildLiquidityLaunchAccountConfig` combines a versioned platform pool profile with only the
  creator's liquidity split, contribution limits, cadence, and fee destination. Adapter, guard,
  route, hook, fee tier, tick spacing, and slippage infrastructure never enter creator forms;
  creator/Treasury recipient addresses are materialized atomically by the Router.
- `encodeLiquidityAccountConfig` encodes the exact `FundingConfig` wrapper, including the release
  approval proof, used by Router and direct funding paths.
- `encodeLiquidityMintCall`, `encodeLiquidityCollectCall`, and the two fee-delivery helpers cover
  all permissionless Liquidity work. The guard supplies the authoritative output floor by default,
  while an operator may only strengthen it. `pendingWork.liquidityAccount`, `liquidityFeeCredit`,
  and `liquidityProtocolFee` expose the complete operational state.

Run `npm test` to rebuild the ABIs from Foundry artifacts, type-check the package, and verify the
shared Solidity/TypeScript calldata fixture.
