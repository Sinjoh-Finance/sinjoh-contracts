# Sinjoh Contracts V2 mainnet UI handoff

Status: **deployed and verified, not promoted into production consumers**

Chain: Robinhood Chain mainnet (`4663`)

Deployment date: `2026-08-23`

Source commit: `ddec345432e464bf87e8ab4f463132c67282cdca`

Deployment blocks: `44346587` through `44346591`

This is the handoff for the comprehensive pre-wiring sweep. It does not authorize a production
UI, API, indexer, keeper, SDK deployment-registry, or environment cutover by itself.

## Canonical release artifact

Use [`deployments/project-launcher-v2-4663-ddec345.json`](./deployments/project-launcher-v2-4663-ddec345.json)
as the machine-readable source of truth. It pins the release commit, build hash, compiler settings,
addresses, runtime hashes, creation-code hashes, external infrastructure, approval root, leaves,
and Merkle proofs.

The release can be rechecked without a signer:

```bash
source /tmp/sinjoh-v2-mainnet-release.env
export RELEASE_GIT_COMMIT="$(git -C .. rev-parse HEAD)"
export RELEASE_SOURCE_TREE_HASH="$(git -C .. rev-parse HEAD:sinjoh-contracts-v2)"
export RELEASE_BUILD_HASH="$(jq -r .buildHash deployments/project-launcher-v2-4663-ddec345.json)"
node script/verify-release-manifest.mjs deployments/project-launcher-v2-4663-ddec345.json
node script/verify-deployed-release.mjs deployments/project-launcher-v2-4663-ddec345.json
```

## UI entry points

| Contract | Address | Runtime hash | Deployment transaction |
| --- | --- | --- | --- |
| `ProjectLauncherV2` | `0x4536Eb881C2A9D841562e622660F949b45117AFB` | `0x95e1d0606be4de8e06575d5fc0ce1dc6e382bc9b727f27b33b16ebfe32487e24` | `0x46397849cb914ef3f83f3c4a5fc587c9a96f449acb5d1cb92490eb2fc443c133` |
| `ProjectRegistryV2` | `0x608f4951AE73976EcEfB15a409B72d84e367F340` | `0x1acba80386751647f010d4e227746ddc8f61ed12112de17d43252e6598e1142d` | `0x93281bb6dfdfaa69991371bc360311f56cdcd019537720f77afbb5941fab8ac7` |
| `ProjectLaunchDeployerV2` | `0x62e2bb69C72c3baa72ddf9CeD4AdfC664Fa10dFa` | `0xdc8db2c6c2cae04a410ce9d925f74e04e336f134871e376aaa56dc9e62b44d3d` | `0x96193f8d3dd8d884cfa07641f8aae732de5baa71bca003d16dda335ce444bab2` |

Explorer base: `https://robinhoodchain.blockscout.com`

Sourcify base: `https://repo.sourcify.dev/4663`

The browser should transact only with the Launcher. The deployment engine and creation-code stores
are immutable implementation plumbing, not user-facing contracts.

Suggested future UI manifest block:

```ts
contractsV2: {
  status: "deployed-not-promoted",
  protocolVersion: 2,
  deploymentBlock: 44346591n,
  launcher: "0x4536Eb881C2A9D841562e622660F949b45117AFB",
  launcherRuntimeCodeHash:
    "0x95e1d0606be4de8e06575d5fc0ce1dc6e382bc9b727f27b33b16ebfe32487e24",
  registry: "0x608f4951AE73976EcEfB15a409B72d84e367F340",
  registryRuntimeCodeHash:
    "0x1acba80386751647f010d4e227746ddc8f61ed12112de17d43252e6598e1142d",
  deploymentEngine: "0x62e2bb69C72c3baa72ddf9CeD4AdfC664Fa10dFa",
  deploymentEngineRuntimeCodeHash:
    "0xdc8db2c6c2cae04a410ce9d925f74e04e336f134871e376aaa56dc9e62b44d3d",
}
```

## Fixed release infrastructure

| Purpose | Address | Runtime hash |
| --- | --- | --- |
| Raffle implementation | `0x333358b15dEB6c0a23Ad7AE50A2c890EBa15e035` | `0xba22d4e2aa622933541cb231f6ab8eca670539c748c8507e21742125157a0010` |
| Randomness adapter | `0xD16BCD59ca33C1e85578Aa5d60a02C4E2231c491` | `0x72ce584dc295ce6e9bfb87803e2445c44a79ced3e5461d894d5028c13f9f5d0b` |
| Project swap adapter | `0xc9F600ebaf9EE1F4a24568D2e4Af9E8df1e07D7B` | `0x17b8eecc60ff9af5768240b0384e96c4e54fd8611355297e45146303294c6ac6` |
| Funding-band integration factory | `0x134eC02Da40362dAF332a9B9c6B6BDae90Aa1405` | `0x42af7b6fdbaab808c06db8761a7a91578a1e07cc75ce40551b9d6e010c71dcb3` |
| Funding-band quote adapter | `0x14F6EBa91724c4Fd9c0bc22D5412502Eb3CC4F9B` | `0x205698f5fa62567c1b9c6059a868f28a2e408c004c8d9815e60f4d42d2b9560e` |
| V3 price guard, fee `500` | `0x4cfe313d27Cb8A951381Cb18d8e53FC3d431bAcA` | `0xa1eb83fbcd5959e18a125614d807969eae7cde0c718670e5aaecbe089797be4f` |
| V3 price guard, fee `3000` | `0xe5e0Fe035031651659d755793701AD41944b3AF2` | `0x0ccd2e844de8f5ee2dccdeca6140189a3e75c791a2a9d1969976f1447b495872` |
| V3 price guard, fee `10000` | `0xE1fc5EBeb1Ff1062074DB6b9413BA8739dE59b44` | `0x6ad1162bbc16e7298069e52ae6d2313aabf751733f92c1e833e3ce8a54bcbd63` |

The protocol fee recipient is `0x5Bb7582557F5be30b62c335Ad3ccf4bA79E138c5`. The release approval root is
`0x9a03a1c049ba2dd72a17444751c29c37c19ced9c2a8952aefabbed935264dd5f`.
Both are immutable in this deployment engine.

## Feature gates

- **Baskets:** hard-disabled in this release. `basketEnabled == false`; the Basket implementation,
  ERC-4626 factory, runtime hashes, and Basket creation-code hash are all zero. Do not render a
  Basket choice, silently substitute a Basket config, or import the prototype Basket ABI into the
  production launch path. Baskets will ship as their own later release.
- **Funding Bands:** infrastructure is deployed and correctly bound, but the feature must remain
  disabled in launch presets and UI for now. The ownerless WETH/USDG oracle currently returns
  `OracleNotReady()` because active pool liquidity is about `0.898e18`, below its immutable `1e18`
  safety floor. Do not weaken or bypass this. A future enablement requires `latestPriceUsdE8()` to
  succeed plus a fresh end-to-end readiness check, or an explicitly approved replacement release.
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
2. Load one versioned, platform-reviewed preset. Keep Baskets and Funding Bands disabled as above.
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

Start V2 discovery at block `44346591`:

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
- explicit feature availability. Basket and Funding Bands must not appear active merely because an
  ABI or deployed support contract exists.

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
