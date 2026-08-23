# Sinjoh Contracts V2 mainnet UI handoff

Status: **deployed and verified, not promoted into production consumers**

Chain: Robinhood Chain mainnet (`4663`)

Deployment date: `2026-08-23`

Source commit: `08679352491763289fa9507c44d2b40e0a381844`

Deployment blocks: `44390930` through `44390934`

This is the handoff for the comprehensive pre-wiring sweep. It does not authorize a production
UI, API, indexer, keeper, SDK deployment-registry, or environment cutover by itself.

## Canonical release artifact

Use [`deployments/project-launcher-v2-4663-0867935-chainlink.json`](./deployments/project-launcher-v2-4663-0867935-chainlink.json)
as the machine-readable source of truth. It pins the release commit, build hash, compiler settings,
addresses, runtime hashes, creation-code hashes, external infrastructure, approval root, leaves,
and Merkle proofs.

The release can be rechecked without a signer:

```bash
source /tmp/sinjoh-v2-mainnet-release.env
export RELEASE_GIT_COMMIT="$(jq -r .gitCommit deployments/project-launcher-v2-4663-0867935-chainlink.json)"
export RELEASE_SOURCE_TREE_HASH="$(jq -r .sourceTreeHash deployments/project-launcher-v2-4663-0867935-chainlink.json)"
export RELEASE_BUILD_HASH="$(jq -r .buildHash deployments/project-launcher-v2-4663-0867935-chainlink.json)"
test "$(git -C .. rev-parse "${RELEASE_GIT_COMMIT}:sinjoh-contracts-v2")" = "$RELEASE_SOURCE_TREE_HASH"
node script/verify-release-manifest.mjs deployments/project-launcher-v2-4663-0867935-chainlink.json
node script/verify-deployed-release.mjs deployments/project-launcher-v2-4663-0867935-chainlink.json
```

## UI entry points

| Contract | Address | Runtime hash | Deployment transaction |
| --- | --- | --- | --- |
| `ProjectLauncherV2` | `0x42921684FC82077cF49f73C7daFD5F3ca7949d79` | `0x153d5534433ba92761002db30c3a67cde525d7bef6bfe43544dc4cb47f73b47c` | `0x289c604152f89503f864a3777239a911d7daa68cd2d2ef8648c4146ed8b334e9` |
| `ProjectRegistryV2` | `0xc6eDD9Dbfc996eE86B1fBd72B589D7DfBd6EeDBD` | `0x02c50998fc1ee2bae540d38fecfc947d6fdc0cda2271f871b2fc0988d7404ca7` | `0xfb50331bf1b68afc483b9f594ef8d0aba16a1ee09c21ff6f7e89e3d301acebaa` |
| `ProjectLaunchDeployerV2` | `0xa6990b81Ea94ff9e209F0F99d988c260e10dFF9a` | `0x096203d781ae7fb690cb20bdf838ceee9f1392e7f0c4b47d504c42266277bf5b` | `0x888ba3ca5e67b29500a38013df75530e9d07fcc48ba302cf3100e8ac60fec21a` |

Explorer base: `https://robinhoodchain.blockscout.com`

Sourcify base: `https://repo.sourcify.dev/4663`

The browser should transact only with the Launcher. The deployment engine and creation-code stores
are immutable implementation plumbing, not user-facing contracts.

Suggested future UI manifest block:

```ts
contractsV2: {
  status: "deployed-not-promoted",
  protocolVersion: 2,
  deploymentBlock: 44390934n,
  launcher: "0x42921684FC82077cF49f73C7daFD5F3ca7949d79",
  launcherRuntimeCodeHash:
    "0x153d5534433ba92761002db30c3a67cde525d7bef6bfe43544dc4cb47f73b47c",
  registry: "0xc6eDD9Dbfc996eE86B1fBd72B589D7DfBd6EeDBD",
  registryRuntimeCodeHash:
    "0x02c50998fc1ee2bae540d38fecfc947d6fdc0cda2271f871b2fc0988d7404ca7",
  deploymentEngine: "0xa6990b81Ea94ff9e209F0F99d988c260e10dFF9a",
  deploymentEngineRuntimeCodeHash:
    "0x096203d781ae7fb690cb20bdf838ceee9f1392e7f0c4b47d504c42266277bf5b",
}
```

## Fixed release infrastructure

| Purpose | Address | Runtime hash |
| --- | --- | --- |
| Raffle implementation | `0x7161B292Ddd8c644Cd535D6C7d9a213751bb6778` | `0xba22d4e2aa622933541cb231f6ab8eca670539c748c8507e21742125157a0010` |
| Randomness adapter | `0xD16BCD59ca33C1e85578Aa5d60a02C4E2231c491` | `0x72ce584dc295ce6e9bfb87803e2445c44a79ced3e5461d894d5028c13f9f5d0b` |
| Project swap adapter | `0xc9F600ebaf9EE1F4a24568D2e4Af9E8df1e07D7B` | `0x17b8eecc60ff9af5768240b0384e96c4e54fd8611355297e45146303294c6ac6` |
| Funding-band integration factory | `0xc711C84b7966CEc718DAB694A8127DaA1c2A3DE0` | `0x42af7b6fdbaab808c06db8761a7a91578a1e07cc75ce40551b9d6e010c71dcb3` |
| Funding-band quote adapter | `0xd0458b56d9A9557df6A73E5340d9FFccED9c4CE2` | `0x6bde18fbfb602edfb4e5554b44ae9fe1f7b2d47ccbe35a7311b0936134a66efd` |
| Chainlink ETH/USD feed | `0x78F3556b67E17Df817D51Ef5a990cDaF09E8d3A9` | `0xbd6f524cdc4268b6bd1bb6f77a8821faeea9c52ee9e0afa0b6d948ce82c966c2` |
| V3 price guard, fee `500` | `0xCFeDB3dD27770c55b7aAC95c2218E2DeA65844dF` | `0xa1eb83fbcd5959e18a125614d807969eae7cde0c718670e5aaecbe089797be4f` |
| V3 price guard, fee `3000` | `0xca0504D06673BF71069d3E00dD534cB8290accDA` | `0x0ccd2e844de8f5ee2dccdeca6140189a3e75c791a2a9d1969976f1447b495872` |
| V3 price guard, fee `10000` | `0x4e7e1651A025053d74561485A45cf5A8DAEe4d11` | `0x6ad1162bbc16e7298069e52ae6d2313aabf751733f92c1e833e3ce8a54bcbd63` |

The protocol fee recipient is `0x5Bb7582557F5be30b62c335Ad3ccf4bA79E138c5`. The release approval root is
`0x8a2bc95e7c4fdadae31a44d90e7dec61ec84103569341c58fa3b1a41fe773b22`.
Both are immutable in this deployment engine.

## Feature gates

- **Baskets:** hard-disabled in this release. `basketEnabled == false`; the Basket implementation,
  ERC-4626 factory, runtime hashes, and Basket creation-code hash are all zero. Do not render a
  Basket choice, silently substitute a Basket config, or import the prototype Basket ABI into the
  production launch path. Baskets will ship as their own later release.
- **Funding Bands:** deployed and ready for the later production-wiring sweep. The quote asset is
  canonical WETH, and its immutable quote adapter reads Chainlink's direct `ETH / USD` feed. USDG
  is not a supported Funding Bands asset or oracle dependency. Keep the production UI gate closed
  until the infrastructure sweep verifies the final preset, automation, indexer, API, and UI wiring.
  The reviewed preset must reject observations older than five minutes and must never substitute a
  DEX-pool price or weaken the onchain staleness checks.
- **Raffle:** available. Its implementation is initialization-locked and the deployment engine
  supplies the reviewed randomness adapter and protocol fee recipient. Creator forms must not ask
  users to enter those release-owned values.
- **Token, Multisig/Token Governance, Timelock, Staking, Treasury, Airdrop, Router, Liquidity:**
  deployed through the Launcher from the exact creation code pinned in the release manifest.

## ABI and SDK source

The exact generated ABIs are in [`sdk/src/abis.generated.ts`](./sdk/src/abis.generated.ts). The
contract-local package exports the launch/read/action helpers from [`sdk/src/index.ts`](./sdk/src/index.ts):

- `buildLaunchFromPreset`
- `validateLaunchConfig`
- `predictLaunch`
- `projectRecord`
- `buildProjectLaunchManifest`
- `projectLauncherV2Abi` and `projectRegistryV2Abi`
- typed custom-error names and user-facing launch error copy

Do not manually recreate the nested `ProjectLaunchConfig` tuple in UI code. Promote the reviewed
contract-local SDK surface into the public SDK first, then consume that typed package from the app.
The platform owns reviewed presets; the creator owns only the fields represented by
`CreatorLaunchChoices`.

## Wallet launch sequence

1. Assert chain ID `4663` and verify the Launcher, Registry, and deployment-engine runtime hashes.
2. Load one versioned, platform-reviewed preset. Keep Baskets disabled. Do not enable Funding Bands
   until the separate infrastructure-wiring sweep is complete.
3. Hydrate creator-owned choices with `buildLaunchFromPreset`.
4. Call `validateLaunchConfig(config)` and `predictLaunch(config)` against the canonical Launcher.
5. Simulate `launch(config)` from the exact connected creator address. A different sender fails with
   `CreatorMustLaunch`.
6. Submit the same simulated call through the wallet, wait for a successful receipt, and preserve
   the transaction hash if receipt observation is temporarily unavailable. Never sign a second
   launch merely because receipt polling failed.
7. Decode `ProjectLaunchCompleted` from the Launcher, then read the Registry by both `projectId` and
   subject. Assert the config hash, subject, creator, controller, enabled-module bitmap, and every
   predicted module address before reporting success.
8. Build and persist the canonical project launch manifest from the confirmed receipt and Registry
   readback.

The Launcher is nonpayable. Do not attach ETH to `launch(config)`.

## Indexer and API handoff

Start V2 discovery at block `44390934`:

- Launcher event: `ProjectLaunchCompleted(projectId, subject, creator, controller, launchConfigHash, enabledModules)`
- Registry events: `ProjectLaunched`, `ProjectModules`, and `ProjectMetadataUpdated`

The Registry had `projectCount() == 0` at handoff, so the first indexed V2 project should be index
zero. The API/indexer should still enumerate the Registry rather than assuming that count remains
zero or requiring a manual per-project publication step.

API responses for V2 projects must preserve:

- protocol version and canonical Registry/Launcher identity;
- the complete module bitmap and module addresses;
- governance mode, controller, vote source, reference supply, canonical pool, and metadata version;
- the launch transaction, block, config hash, and release commit/build hash;
- explicit feature availability. Baskets must remain unavailable. Funding Bands should appear only
  after its production wiring is deliberately enabled, not merely because support contracts exist.

## Verification record

- Deployment: `18/18` receipts succeeded, with no pending transactions.
- Runtime/state: every deployed and external dependency hash, immutable, core cross-link, approval
  root, creation-code store/hash/chunk, and Raffle implementation lock was read back from chain.
- Source: all `18` deployed contracts report matching creation and runtime source on Sourcify.
- Contracts: `459` passed, `0` failed, `1` intentionally skipped fork test.
- Contract-local SDK: `23` passed.
- Public SDK: `119` passed; typecheck, OpenAPI lint, package dry-run, and release metadata passed.
- Platform/API/keepers/indexers: `316` passed; typecheck and Envio code generation passed.
- UI: lint and typecheck passed; production build completed; `420` tests passed.

No production consumer was rewired while producing this handoff.
