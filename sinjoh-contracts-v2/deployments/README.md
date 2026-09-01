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
- `WETH`, pinned into the one-to-one native-asset unwrap guard;
- `FUNDING_BAND_QUOTE_ASSET`, `FUNDING_BAND_QUOTE_USD_AGGREGATOR`, and their runtime hashes;
- `RANDOMNESS_ADAPTER` and its approved `RANDOMNESS_ADAPTER_RUNTIME_HASH`;
- `V3_FACTORY`, `V3_POSITION_MANAGER`, `V4_POSITION_MANAGER`, `V4_STATE_VIEW`, and `PERMIT2`;
- `PONS_PROJECT_ADAPTER_FACTORY`, `PONS_PROJECT_ADAPTER_IMPLEMENTATION`, and
  `PONS_LAUNCH_FACTORY`;
- both Pools Instant project adapter factories,
  `POOLS_INSTANT_PROJECT_ADAPTER_FACTORY` and
  `POOLS_INSTANT_NO_FEE_PROJECT_ADAPTER_FACTORY`;
- `POOLS_LBP_PROJECT_ADAPTER_FACTORY` and `POOLS_PROJECT_REGISTRATION_HELPER`;
- one corresponding `*_RUNTIME_HASH` for every external address above;
- `VERIFIER`, `VERIFIER_URL`, and `VERIFIER_API_KEY` for source publication.

For a successor immutable release, set `DEPLOY_FRESH_LAUNCHPAD_FACTORIES=1` and provide
`PONS_FEE_ESCROW` plus `PONS_FEE_ESCROW_RUNTIME_HASH`. The wrapper then deploys new Pons and
Pools adapter factories from the reviewed adapter package, verifies the deployer nonce after each
stage, derives every new address and runtime hash, and binds those unbound factories to the new
Launcher. In this mode, do not provide the six old factory, implementation, and helper variables
listed above; they are replaced by the newly deployed addresses. `SIMULATE_ONLY=1` cannot model
this stateful multi-package sequence. Rehearse it against an Anvil mainnet fork with
`UNLOCKED_DEPLOYMENT=1`, then run the same wrapper against mainnet with the configured
`FOUNDRY_ACCOUNT` and `UNLOCKED_DEPLOYMENT=0`.

For the canonical Robinhood Chain successor, use
`./script/deploy-successor-mainnet.sh`. It requires the authenticated production Chainstack URL in
`RPC_URL` and the independently operated authenticated QuickNode URL in
`RPC_VERIFICATION_URL`; the wrapper rejects public RPC, non-HTTPS URLs, and other provider hosts.
It pins chain ID 4663, requires both providers to agree on the deployer nonce, and
derives all reusable public addresses and runtime hashes from the last canonical manifest. It writes the
new canonical manifest to `deployments/project-launcher-v2-4663.json`. The operator must set
`FOUNDRY_ACCOUNT` to the name of an existing local Foundry keystore; the wrapper does not invent or
create an account alias. It never accepts a raw private key. The operator's only secret input is the
keystore password requested by Foundry at signing time. The successor wrapper rejects any
`DEPLOYER_ADDRESS` other than `0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49`. It preserves the
public Pons factory and its existing launch forwarder: Project adapters call the factory's public
`launchToken` entry point directly, so this release requires no Pons ownership or forwarder change.
The wrapper reuses the already-deployed, unbound successor adapter factories and checks their
runtime hashes before binding them, so resuming the release does not redeploy them or spend that gas
again. Run the same command with `SIMULATE_ONLY=1` first to execute the complete build, test, runtime
hash, and Forge transaction simulation without loading a signer or broadcasting.

The deployment derives the eight-leaf integration-approval root and every Merkle proof from the
three deployed fee-tier guards, the Funding Bands integration factory, the Pons project adapter
factory, both approved Pools Instant project adapter factories, and the Pools LBP project adapter
factory; operators do not supply or approve a root manually. In the same broadcast it binds those
factories to the immutable Project Launcher and Registry and pins the canonical token factories.
The wrapper derives the immutable git commit, package tree
hash, and a bytecode build hash covering every production contract embedded in or deployed by the
release. The manifest schema is
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
