# Protocol release operations

This is the normative deployment and promotion runbook for Sinjoh contracts and
their offchain consumers. Package specifications remain normative for protocol
behavior; `mainnet-deployments.json` is the canonical mainnet address registry.

## Non-negotiable rules

1. Promote a reviewed commit and its release bundle, never testnet addresses.
2. Robinhood testnet (`46630`) and mainnet (`4663`) always use separate dependency
   profiles, signers, RPC credentials, databases, service deployments, and manifests.
3. No mainnet private key is stored in GitHub, a `.env` file, shell history, or a
   deployment script. Mainnet signing uses a hardware-backed Foundry account or a
   reviewed multisig transaction.
4. A deployment is not active when its transaction receives an L2 receipt. It is
   eligible for activation only after the deployment block is returned under the
   RPC `finalized` tag and post-deployment verification passes through two providers.
5. Contract deployment and activation are separate changes. Deploy dark, verify,
   then update manifests and consumers.
6. Immutable contracts are not rolled back. Failed generations are disabled in
   offchain manifests and replaced by a new reviewed deployment.

## Environment inventory

The contracts repository publishes deployment and promotion authority. Exact Vercel, Railway, Envio, Supabase, and service-secret placement is maintained by `Sinjoh-Finance/sinjoh-platform`; the UI and SDK are separate consumers.

Machine-readable network policy lives in:

- `deployments/networks/46630.json`
- `deployments/networks/4663.json`

The public Robinhood endpoints are permitted only for smoke checks and independent
verification. Fork tests, indexing, historical holder reconstruction, and production
services use authenticated endpoints. Mainnet must have a primary archive endpoint
and an independently operated secondary endpoint.

### GitHub environments

Create these environments in repository settings before enabling workflows.

#### `robinhood-testnet`

- Restrict deployment branches/tags to the release policy.
- Secrets:
  - `ROBINHOOD_TESTNET_RPC_URL`
  - `ROBINHOOD_TESTNET_ARCHIVE_RPC_URL`
  - `ROBINHOOD_TESTNET_SECONDARY_RPC_URL`
  - `TESTNET_PROTOCOL_DEPLOYER_PRIVATE_KEY` — must resolve to the protocol testnet deployer.
  - `TESTNET_LAUNCH_DEPLOYER_PRIVATE_KEY` — must resolve to the isolated launch testnet deployer.
- Variables:
  - `TESTNET_PROTOCOL_DEPLOYER_ADDRESS` — pins the testnet-only protocol signer; never reuse the mainnet EOA.
  - `TESTNET_LAUNCH_DEPLOYER_ADDRESS` — pins the isolated testnet launch signer.
  - Every other `TESTNET_*` dependency address and code hash referenced by
    `.github/workflows/deploy-testnet.yml`, plus the ECVRF public key coordinates.

The two testnet private keys are low-value hot keys and must not exist on mainnet.
Rotate them if workflow or runner exposure is suspected.

#### `robinhood-mainnet-preflight`

- Store only read-only RPC credentials:
  - `ROBINHOOD_MAINNET_ARCHIVE_RPC_URL`
  - `ROBINHOOD_MAINNET_SECONDARY_RPC_URL`
- Never add a deployer, governance, attestor, keeper, quote signer, or treasury key.

Fork and dependency-drift jobs select these protected environments; no added
workflow requires a repository-level secret.

## Release lifecycle

### 1. Design gate

Before implementation, update the affected package `SPEC.md` with:

- intended behavior and immutable decisions;
- value flows and trust boundaries;
- invariants and supported token behavior;
- external dependencies and their required readbacks/code hashes;
- liveness, replacement, and incident behavior.

A material value-flow or authorization change requires an independent audit or a
documented audit delta accepted before mainnet promotion.

### 2. Pull-request gate

Run locally:

```sh
node scripts/release/validate-config.mjs
scripts/contracts-ci.sh ci all
```

`contracts-ci.yml` runs the same checks independently per package. Fork tests are
deliberately separate because they require protected archive credentials:

```sh
scripts/fork-tests.sh 4663 "$ROBINHOOD_MAINNET_ARCHIVE_RPC_URL"
scripts/fork-tests.sh 46630 "$ROBINHOOD_TESTNET_ARCHIVE_RPC_URL"
```

Every fork test is registered in `deployments/forks/<chainId>.txt`. A test that
silently exits on a dependency or chain mismatch is a failed certification test.

### 3. Release candidate

From a clean worktree after CI passes:

```sh
scripts/contracts-ci.sh build all
node scripts/release/build-release.mjs \
  --network 46630 \
  --release-id rc-YYYYMMDD-N \
  --require-clean
```

The bundle records the source commit, package Git trees, Foundry configuration
digests, compiler/tool versions, first-party artifacts, creation/runtime template
hashes, network profile, deployment plan, and checksums. The GitHub
`release-candidate` workflow archives and cryptographically attests the bundle.

The release tag must be annotated and cryptographically signed. Never retarget a
deployment or release tag.

### 4. Testnet deployment

The current ordered inventory is `deployments/plans/46630.json`. The protected
workflow accepts only an attested testnet release-bundle workflow run and a step
from this inventory. It checks out the source commit bound into that bundle. It
always simulates first; broadcasting requires the explicit boolean input and
environment approval.

After every broadcast:

1. Preserve the Forge broadcast artifact.
2. Wait until every deployment block is `finalized`.
3. Verify source on testnet Blockscout.
4. Record transaction hashes, blocks, addresses, runtime code hashes, constructor
   values, source commit, and the completed plan step in
   `deployments/manifests/46630/current.json`.
5. Run `postdeploy-verify` against primary and secondary RPC providers.
6. Commit the manifest change before a dependent plan step can run.

After contracts are complete, deploy the isolated testnet keeper, indexer, API/UI,
database, storage, and monitors. Run launch, fee routing, liquidity, airdrop,
raffle/randomness, dropped-transaction recovery, process restart, RPC failover,
archive disagreement, low-gas, and indexer replay exercises. Promotion requires at
least one complete protocol cadence and the approved operational soak window.

### 5. Mainnet preparation

Mainnet promotion uses a fresh release bundle for `4663`; the testnet bundle is
evidence, not a mainnet deployment input. Before signing:

The ordered entrypoint inventory is `deployments/plans/4663.json`. Its steps are
intentionally `blocked` in source. A release PR may mark only the reviewed steps
`ready` after their testnet evidence and dependency readbacks are attached; GitHub
never broadcasts them.

- all contract CI and both mainnet fork modes pass;
- external dependency addresses, runtime hashes, proxy implementations, owners,
  live parameters, and launch gates have been re-read;
- every reviewed `deployments/assertions/4663.json` storage-level assertion passes;
- independent audit findings for the delta contain no unresolved critical/high issue;
- expected transaction ordering, CREATE/CREATE2 addresses, constructor values,
  gas requirement, and post-state assertions have two-person sign-off;
- the deployer contains only the required gas balance;
- the prior generation remains the active offchain manifest.

Run `mainnet-preflight`. It verifies the existing dependency/deployment registry
through two providers and emits an unsigned bundle. CI has no broadcast capability.

### 6. Mainnet signing ceremony

Import the hardware-backed account without exposing its key:

```sh
cast wallet import sinjoh-deployer --interactive
cast wallet address --account sinjoh-deployer
```

For scripts with an expected deployer, set the public identity independently and
pass the signer through Foundry:

```sh
export DEPLOYER_ADDRESS=0x...
(cd sinjoh-example && forge script script/DeployExample.s.sol:DeployExample \
  --rpc-url "$ROBINHOOD_MAINNET_RPC_URL" \
  --account sinjoh-deployer)
```

Review the dry-run trace and state changes. Add `--broadcast` only during the
approved ceremony. Funding Bands shell deployments use `DEPLOYER_ACCOUNT` and an
optional `DEPLOYER_PASSWORD_FILE`; they reject raw private-key inputs.

Record the operator, reviewer, release ID, bundle checksum, source commit, signer
address, starting nonce, transaction sequence, gas estimates, and final hashes.
Private keys, seed phrases, keystore passwords, and RPC credentials are never part
of the ceremony record.

### 7. Finalization and activation

After broadcast:

1. Preserve broadcast artifacts immediately.
2. Wait for `finalized`.
3. Verify source on Blockscout.
4. Run `postdeploy-verify` through both providers.
5. Read back every owner, signer, immutable dependency, route, fee, timing value,
   implementation address, initialization flag, and one-time binding.
6. Append a new immutable deployment-generation record and signed deployment tag.
7. Regenerate SDK manifests and require zero drift.
8. Update keeper/indexer first in disabled or read-only mode.
9. Update the UI and public manifest only after backend health/catch-up checks pass.
10. Enable a capped canary, observe, then lift the cap through the reviewed mechanism.

### 8. Cross-repository promotion

Contracts are not made active by merging the UI or changing a Railway variable.
The protocol repository publishes the only address/code-hash authority:

```sh
node scripts/release/build-promotion.mjs \
  --network 4663 --release-id release-YYYYMMDD-N \
  --channel candidate \
  --release-bundle .release-bundles/release-YYYYMMDD-N \
  --require-clean
```

Normally run the protected `publish-promotion` workflow with the successful
release workflow run ID so GitHub verifies the release attestation and attests
`promotion.json`. Active publication additionally requires the attested candidate
workflow run ID. Its binding map is `deployments/consumers/bindings.json` and its
schema is `deployments/schema/promotion.schema.json`.

Promote in this order:

1. Publish and verify a `candidate` artifact from a finalized deployment manifest.
2. Import its exact lock into the SDK, `sinjoh-keeper/config/releases/candidate.json`,
   and the UI repository's `config/releases/candidate.json` through their import
   scripts. Each importer verifies the GitHub attestation before writing.
3. Render the artifact's Railway and Envio variables. Start candidate keepers in
   disabled/read-only mode, let both indexers catch up, and confirm `/ready`.
4. Apply the UI candidate variables to Vercel Preview and run the full canary.
5. Record the candidate in Supabase `public.release_promotions`.
6. Clear the deployment manifest's release-candidate gate only after approval,
   then publish a separate `active` artifact. The workflow refuses to create an
   active mainnet artifact while `releaseCandidate` is true.
7. Promote active keeper/indexers, then Vercel Production, without changing the
   release ID or SHA-256 between consumers.
8. Record the active promotion in Supabase and retain the prior artifact/image for
   offchain rollback.

The UI build and keeper startup fail closed if the artifact, environment release
identity, chain, or pinned contracts disagree. Promotion artifacts contain no
credentials. Signer, RPC, database, and API secrets are provisioned independently
in their owning platform.

## Governance and key separation

The target mainnet authority is a 2-of-3 hardware-backed multisig with signers on
separate devices and recovery locations. The deployer has no ongoing authority.
Treasury, governance, keeper, attestor, ECVRF, and quote-signing identities remain
separate. Move an existing mutable role only after verifying that contract's exact
handoff mechanism and rehearsing it on a mainnet fork; immutable roles require a new
deployment generation.

No ownership transfer is complete until the recipient has accepted it where the
contract uses two-step ownership, the finalized state is verified through two RPCs,
and the manifest records the transition.

## Incident and replacement policy

- **Bad deployment, not activated:** mark the generation rejected and leave all
  consumers on the prior manifest.
- **Bad offchain release:** roll services back by immutable image digest and reconcile
  journals/onchain state before write mode resumes.
- **Compromised hot signer:** stop its service, revoke/rotate service credentials,
  fund a replacement minimally, and reconcile pending hashes before resuming.
- **Dependency runtime/proxy drift:** disable the affected integration immediately;
  do not update an expected hash until the new source and behavior are reviewed.
- **Immutable contract defect:** disable new use in manifests/UI, preserve claimant
  access where safe, deploy a reviewed replacement, and publish the affected scope.
- **RPC disagreement or reorg:** stop activation and state-sensitive writes until two
  providers agree on the finalized block and required historical state.

The scheduled `dependency-drift` workflow continuously checks recorded runtime hashes
and provider agreement. Its failure is an operational alert, never an instruction to
rewrite the manifest automatically.
