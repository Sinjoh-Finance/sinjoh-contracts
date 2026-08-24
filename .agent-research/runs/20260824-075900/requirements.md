Production is a **no-go today**. Production has not been changed.

The contracts themselves are well tested, and GovTest verified the single-token architecture successfully. However, the production UI launch path is not yet wired to execute that architecture, VaultTest and MixTest have not been launched, and several deployment artifacts remain only on the local machine.

## Current release status

| Area | Status |
|---|---|
| Project V2 contracts | Deployed and verified |
| Single-token invariant | Verified with GovTest |
| GovTest token page | Working on Preview |
| Preview deployment | Ready |
| Canonical launch discovery | Working |
| Wallet-signed Project V2 launch through UI | **Not complete** |
| VaultTest | **Not launched** |
| MixTest | **Not launched** |
| Production ownership transfer | **Not complete** |
| Production deployment | **Not performed** |

## Preview

Permanent branch URL:

[[https://sinjoh-ui-git-codex-sinjoh-v2-overhaul-sinjoh.vercel.app](https://sinjoh-ui-git-codex-sinjoh-v2-overhaul-sinjoh.vercel.app/)](https://sinjoh-ui-git-codex-sinjoh-v2-overhaul-sinjoh.vercel.app)

Current deployment:

[[https://sinjoh-ij7zglxqz-sinjoh.vercel.app](https://sinjoh-ij7zglxqz-sinjoh.vercel.app/)](https://sinjoh-ij7zglxqz-sinjoh.vercel.app)

- Deployment ID: `dpl_GtrX6JNdcj9asXh6q9iWnAzy4RrM`
- Target: Preview
- Status: Ready
- The permanent branch URL currently points to this deployment.
- Preview uses `NEXT_PUBLIC_SINJOH_DATA_MODE=legacy`.
- Production environment variables were not changed.

## GovTest verification

Token page:

[[GovTest on Preview](https://sinjoh-ui-git-codex-sinjoh-v2-overhaul-sinjoh.vercel.app/token/0xaFc1637BD6576eA4bdF23e67d31dcd48D0c8eCBC)](https://sinjoh-ui-git-codex-sinjoh-v2-overhaul-sinjoh.vercel.app/token/0xaFc1637BD6576eA4bdF23e67d31dcd48D0c8eCBC)

Contracts:

- Token: `0xaFc1637BD6576eA4bdF23e67d31dcd48D0c8eCBC`
- Curve: `0xB09d0E75835F015d36aEf9F0d0fEF1AEe679Ede2`
- Governor: `0x25cFaB02d5B1323717cE063e3C56B1aE8e59fBCc`
- Timelock/controller: `0xbE1BA27caC267cCc8691568bA23C5fBBB08095Af`
- Router: `0x34453833539A1196d15575A2Ad635832603AA6de`
- Project adapter: `0x51f0d4f6f17731f32DE2EB93e1ED95C6C31A3810`
- Registry: `0x729Ee6B1AB170b63F6D369AaBa5591edEE709e22`
- Project ID: `0xf3880e867b7a07f3b1bcdac5f290b46c15d3289a2e53c5624e56a6befd1b6c25`

Transactions:

- Adapter deployment: `0xabedeb137ca8bc8e931120bcae9b15c9185a74327793e8f5d306c5e9f6f41326`
- Atomic token and Project V2 launch: `0x61c4b141f95c5aa39ddc5afa13154024b3ba873c3cf34a6e98549eeefabf090a`

Verified behavior:

- The Pons token is the Registry subject.
- That same token supplies governance voting power.
- The Governor references that same token.
- No second governance token was created.
- The curve and project adapter cannot vote.
- This configuration has no Treasury, Raffle, Staking, Airdrop, or Liquidity module.

GovTest was launched through a deployment script—not through the public wallet-connected UI.

## Canonical Project V2 deployment

- Launcher: `0x4C10aDE88e7865345Dcf2aE1AA2ba17B618c3aE9`
- Registry: `0x729Ee6B1AB170b63F6D369AaBa5591edEE709e22`
- Deployment engine: `0x8C43c5fB15Aef4a6658EE9Fb49584C2BcF9AC333`
- Validator: `0x9cBAa4ccE55c244004607A8D71d61Ee3A88C546F`
- Pons project-token factory: `0x464f4ec338FdB944bae6A7C3087a26c13b51Bc4e`
- Launchpad project-token factory: `0xE1F48414C491a6a5031091F132E92EC9eC46b65D`

Manifest:

[project-launcher-v2-4663-e7bed3c-canonical.json](/Users/dsb/sinjoh-contracts-unified-governance/sinjoh-contracts-v2/deployments/project-launcher-v2-4663-e7bed3c-canonical.json)

SHA-256:

`98cb1818b1e284cbc695fbc75580e3107818a657bcf25e34e1837d1879485646`

## Canonical Pons V2 deployment

- Factory: `0x7DCeEaB0A53684b001A4900768a52eAcDb27294e`
- Hook: `0xE9Ec0Ffc7d5bEF33f815D7b0cDd15A7c5Dc1e044`
- Locker: `0x1006fA85294A9c38AA4214d52c86CC970Ddc5647`
- Buyback vault: `0xA61f18568d3B817bbb95450D42F7403e871Ce0a1`
- Graduation executor: `0x9bF18e0d38Ee9DA8eE414e0c2e491899A3b6386D`
- Launch deployer: `0xa0bc05240f1cD1f3Df7FEfA35e48C19ffF4c6ACe`
- Fee escrow: `0xd3AFEB2a57f70eF218Aa82451c51B2fb0416Ac9e`
- Adapter factory: `0x96e2de90c66d7fD55a18dDbE6B75073A2115844D`
- Adapter implementation: `0x50444a640510d3F763bCfC5e8706b41c9a1A20A2`

The stack is currently owned by the test wallet:

`0xe4605138e185FBeE40ff6193A044aa0BE2909216`

That wallet’s private key was shared in chat. It must not remain the production owner. Confirm the final production multisig before transferring ownership. The expected existing protocol owner is:

`0xFdDE5a1E3cDF791Da71E49F817D70C7ceD72CC36`

## Test results

- Core Foundry tests: 468 passed, 0 failed, 1 skipped
- SDK tests: 24 passed
- Adapter tests: 112 passed
- UI tests: 423 passed
- UI production build: passed
- Onchain deployment verifier: passed
- GovTest browser smoke test: passed without console errors

## Remaining production blockers

1. Wire the launch UI to call the canonical Project V2/Pons adapter path. Governance launches are still explicitly blocked in the current UI implementation.
2. Submit a complete launch from the UI with a normal connected wallet.
3. Launch and inspect VaultTest.
4. Launch and inspect MixTest.
5. Expose Project V2 governance information on token pages.
6. Resolve the current “Fee routing metadata is not available yet” state.
7. Commit and push the canonical manifest and GovTest deployment script.
8. Commit and publish the Pons contracts and deployment script; the Pons branch currently has no upstream and the earlier push was rejected with HTTP 403.
9. Transfer Pons production ownership away from the exposed test wallet.
10. Move Production from legacy compatibility mode to the reviewed canonical release configuration.
11. Configure the Production domain in Reown and any domain allowlists.
12. Verify canonical ingestion in the production API/indexer instead of relying indefinitely on server-side Registry reconciliation.
13. Run a final production-candidate smoke test and retain the legacy path as a rollback until same-block reconciliation succeeds.

## Repository state

UI:

- Repository: `/Users/dsb/Sinjoh-UI`
- Branch: `codex/sinjoh-v2-overhaul`
- Pushed commit: `c337cf4ca544948b24c5067d0966d4283d67bf78`
- The branch matches its remote.
- There are unrelated user-owned changes in `app/(product)/manage/page.tsx`, `components/wallet-modal.tsx`, `exports/`, `supabase/`, and `vendor/`. These were not included in the release commit.

Core:

- Repository: `/Users/dsb/sinjoh-contracts-unified-governance`
- Branch: `codex/unified-governance-token`
- Pushed commit: `e7bed3cad4a55e62aa58cf9881ce04348420a8bc`
- The canonical manifest and `LaunchGovTestCanonical.s.sol` remain uncommitted.

Pons:

- Repository: `/Users/dsb/ponsfamily`
- Branch: `codex/unified-governance-token`
- Latest local commit: `b37ba316ac2b22bedea4c7a74b9865e2a48ffa4d`
- The deployment script directory remains uncommitted.
- These commits are not currently published to a remote branch.

The correct production handoff verdict is therefore: **contracts proven, Preview functional for discovery and viewing, but production launch execution and two required configurations remain unverified. Do not promote this Preview to Production yet.**