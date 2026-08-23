# Contracts v2 release artifacts

The current release is explicitly non-Basket. Its Launcher rejects Basket module selections, its
release bundle omits the Basket creation-code store, and deployment does not publish Basket vault
or yield-adapter infrastructure. Basket will ship as a separate release after its RWA/dividend
design is finalized.

Release deployment is intentionally fail-closed. Do not invoke the Foundry broadcast script
directly. Run:

```sh
./script/deploy-release.sh
```

The wrapper refuses a dirty worktree, a mismatched RPC chain, or an external dependency whose
runtime hash differs from the configured value. It then runs format, build/production-size,
Solidity, invariant, and SDK gates before broadcasting and verifies the generated JSON manifest
afterward. Set `SIMULATE_ONLY=1` to run the same deployment and manifest checks without loading a
Foundry account, signing, broadcasting, or publishing source.

Required environment variables:

- `RPC_URL`, `EXPECTED_CHAIN_ID`, `DEPLOYER_ADDRESS`, and `FOUNDRY_ACCOUNT`;
- `PROTOCOL_FEE_RECIPIENT`;
- `PROJECT_SWAP_ADAPTER` and its `PROJECT_SWAP_ADAPTER_RUNTIME_HASH`;
- `FUNDING_BAND_QUOTE_ASSET`, `FUNDING_BAND_QUOTE_USD_AGGREGATOR`, and their runtime hashes;
- `RANDOMNESS_ADAPTER` and its approved `RANDOMNESS_ADAPTER_RUNTIME_HASH`;
- `V3_FACTORY`, `V3_POSITION_MANAGER`, `V4_POSITION_MANAGER`, `V4_STATE_VIEW`, and `PERMIT2`;
- one corresponding `*_RUNTIME_HASH` for every external address above;
- `VERIFIER`, `VERIFIER_URL`, and `VERIFIER_API_KEY` for source publication.

The deployment derives the four-leaf integration-approval root and every Merkle proof from the
three deployed fee-tier guards and the Funding Bands integration factory; operators do not supply
or approve a root manually. The wrapper derives the immutable git commit, package tree hash, and a
bytecode build hash covering every production contract embedded in or deployed by the release. The
manifest schema is
[`release-manifest.schema.json`](./release-manifest.schema.json).
Implementation and factory addresses are paired with runtime hashes, including the Raffle,
randomness, and Funding Bands V3 integration factory. Basket and ERC-4626 fields are explicitly
zero in this non-Basket release.

After an individual project launch, applications use the SDK's `buildProjectLaunchManifest` with
the exact validated preflight and Registry readback. It rejects mismatched configuration hashes,
identities, governance, supply, modules, or predicted addresses before emitting canonical JSON.
The artifact shape is [`project-launch-manifest.schema.json`](./project-launch-manifest.schema.json).

Simulation still requires a target-chain RPC that permits historical and state reads. Use a
temporary `DEPLOYMENT_MANIFEST_PATH` during rehearsal so a dry run cannot replace a saved release
manifest.
