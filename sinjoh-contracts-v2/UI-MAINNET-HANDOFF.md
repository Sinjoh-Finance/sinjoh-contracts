# Sinjoh Project V2 mainnet UI handoff

Status: **canonical deployed release; use this release for production consumers**

Chain: Robinhood Chain mainnet (`4663`)

Canonical source commit: `618f7113cfd58fa818bdc798ee230aba4e05d2a6`

Canonical build hash: `2f869c15eb3f2500ade570880377d5eab57559a5a9771face16e3556b9aae551`

Deployment blocks: `45138065` through `45138244`

The earlier `4ca4f6aca08e7669b1c7e08f21a1219be2cab548` deployment is superseded and must
not be used by the UI, API, SDK, indexers, keepers, or verification scripts.

## Canonical artifacts

- [`deployments/project-v2-recovery-manifest-4663-7837.json`](./deployments/project-v2-recovery-manifest-4663-7837.json)
- [`deployments/project-v2-recovery-promotion-entry-4663-7837.json`](./deployments/project-v2-recovery-promotion-entry-4663-7837.json)
- [`deployments/project-v2-recovery-consumer-input-4663-7837.json`](./deployments/project-v2-recovery-consumer-input-4663-7837.json)
- [`../deployments/consumers/bindings.json`](../deployments/consumers/bindings.json)

The promotion entry is incorporated into `mainnet-deployments.json` under
`currentInfrastructure.projectV2`. Render consumer environments from the repository binding model;
do not copy addresses into application source.

## Browser entry points

| Contract | Address | Runtime code hash | Deployment transaction |
| --- | --- | --- | --- |
| `ProjectLauncherV2` | `0x87B67dfFf09363AA75f4BEf1a43ae7d90C8f497B` | `0x86b7c7f88e40538022f80f00cad22469d622cbfb45a66c8d39577560e6ac5131` | `0x0ed96cfdcb1a484bcfad83756f26f865489689a53fe8233744a612ec8906ae90` |
| `ProjectRegistryV2` | `0xb10f8350264315850D3aa8b9794f34F496F6d0Cf` | `0x4317d73c13f1c9706677709ef42fa4cf4b03202ed130230c363eb2e10082ffe6` | `0xaa8258c49b72d63ce0f7366802904ad5c15f16bb9992c7a9fb901b16a87b2226` |
| `ProjectLaunchDeployerV2` | `0x92EBaC0139001Face632aA25Bf6EC19Dc3a5747e` | `0x4b84e29376fa6ab3363fb7256057e30741b41dd22356d7d5ea7be6ea82edf128` | `0x31cc7ba558ebe23677dadb7b7e5a683ce4d5d7984aa1774ca4c982dfd73bf590` |
| `SinjohPonsV2ProjectAdapterFactory` | `0xAc299024C0f4E561D6e99CEFABB9b7212de729b6` | `0x964762b1cdb587f7dc7d27f796e0ed403e0066e00a7ed0d015c90b1df32c5ec5` | `0x5c632df37c4d79ed4c40ac1f944b431ee7f33ecaceb45a9309b783ac08bdaf41` |
| `SinjohPonsV2ProjectAdapter` implementation | `0x3943b7f46b201CFe5033367Ae2E102555e0ea50F` | `0xd61178a140dc8f8df8a0ae4987dc93b7063334496591c10e81aee660d1d916e6` | `0xc9121126ed8dae4812802ddc23b68fea872d7bfce68947258a24ea6cede2edbd` |

An atomic Pons + Project launch transacts with
`0xAc299024C0f4E561D6e99CEFABB9b7212de729b6`. A direct Project-token launch
transacts with `0x87B67dfFf09363AA75f4BEf1a43ae7d90C8f497B`.

## Canonical Pons V2 dependencies

| Contract | Address | Runtime code hash |
| --- | --- | --- |
| Launch factory | `0x7DCeEaB0A53684b001A4900768a52eAcDb27294e` | `0x3392f4e9040deec97e49bf05fc3a696f295b79806ef83910d84943d431d05e83` |
| Launch deployer | `0xa0bc05240f1cD1f3Df7FEfA35e48C19ffF4c6ACe` | `0x1a02242a68ae3b615880e87cba298a208fe991a7a6f87cbc9b34e596e9518fc7` |
| Fee escrow | `0xd3AFEB2a57f70eF218Aa82451c51B2fb0416Ac9e` | `0xf25f75cfbc1637ba068dc34f69098fa4e8a80f8ee8fe7bf7820594e0b3fed2f1` |
| Meme hook | `0xE9Ec0Ffc7d5bEF33f815D7b0cDd15A7c5Dc1e044` | `0x5f3bc01971cffe8dea490d70f123c25c01ae2c3579b68d40109c3ac68e1461eb` |
| Buyback vault | `0xA61f18568d3B817bbb95450D42F7403e871Ce0a1` | `0x99fd213fd5cccddc5bb26e9ab9763a69bd17f7286333f93ae9c3b96817f8f904` |
| Launch locker | `0x1006fA85294A9c38AA4214d52c86CC970Ddc5647` | `0x5304631acb89c64e75397509c745337b6ddb3e7f529e2297a335114049bcff7d` |
| Uniswap V4 PoolManager | `0x8366a39CC670B4001A1121B8F6A443A643e40951` | `0xbd3881180b547f5fe817545743cfb4343e96b1bc6640dcd70c106b0066e95626` |

The launch factory, hook, locker, and buyback vault are owned by
`0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49`; each `pendingOwner()` is zero.

## Release behavior

- Baskets are disabled.
- Project Raffle, Staking, Treasury, governance, Airdrop, Router, and the Pons Project adapter are available.
- Project Airdrop uses signed `AirdropEpochCommitment` calldata; legacy airdrop calldata is incompatible.
- Project Funding Bands for Pons launches activates after graduation through the canonical Pons V4 Funding Bands path. The Project-specific V3 module is not selected for an atomic Pons launch.
- Protocol fee recipient: `0x5Bb7582557F5be30b62c335Ad3ccf4bA79E138c5`.
- Integration approval root: `0x97c6b100e3d71cb95d125537fcd2736043d90ff56852f425eac29dc33956b19d`.

## Indexer and verification

Start Project V2 discovery at block `45138065` and enumerate Registry
`0xb10f8350264315850D3aa8b9794f34F496F6d0Cf`.

Use the configured Chainstack primary and QuickNode secondary. Never substitute a public
Robinhood RPC or Alchemy.

```bash
cd sinjoh-contracts-v2
export RELEASE_MANIFEST=deployments/project-v2-recovery-manifest-4663-7837.json
RPC_URL="$CHAINSTACK_RPC_URL" node script/verify-deployed-release.mjs "$RELEASE_MANIFEST"
RPC_URL="$QUICKNODE_RPC_URL" node script/verify-deployed-release.mjs "$RELEASE_MANIFEST"
```
