# Contracts v2 release artifacts

Release deployment is intentionally fail-closed. Do not invoke the Foundry broadcast script
directly. Run:

```sh
./script/deploy-release.sh
```

The wrapper refuses a dirty worktree, a mismatched RPC chain, missing audit/fork/testnet evidence,
or an external dependency whose runtime hash differs from the approved value. It then runs format,
build/size, Solidity, invariant, and SDK gates before broadcasting and verifies the generated JSON
manifest afterward.

Required environment variables:

- `RPC_URL`, `EXPECTED_CHAIN_ID`, and `PRIVATE_KEY`;
- `PROTOCOL_FEE_RECIPIENT` and `INTEGRATION_APPROVAL_ROOT`;
- `V3_FACTORY`, `V3_POSITION_MANAGER`, `V4_POSITION_MANAGER`, `V4_STATE_VIEW`, and `PERMIT2`;
- one corresponding `*_RUNTIME_HASH` for every external address above;
- `AUDIT_GATE_STATUS=passed`, `AUDIT_REPORT_VERSION`, and `AUDIT_EVIDENCE_PATH`;
- `FORK_EVIDENCE_PATH`, `TESTNET_EVIDENCE_PATH`, `ROLE_EVIDENCE_PATH`, and
  `ASSET_FLOW_EVIDENCE_PATH`;
- `VERIFIER`, `VERIFIER_URL`, and `VERIFIER_API_KEY` for source publication.

Each evidence path must point to a non-empty local artifact; the wrapper records its SHA-256 hash.
Human verification of the evidence and audit provenance remains mandatory. The wrapper derives the
immutable git commit, package tree hash, and deployed-bytecode build hash itself. The manifest schema is
[`release-manifest.schema.json`](./release-manifest.schema.json).

This workflow does not manufacture or validate the authorship of audit/canary evidence. Until independent audit and live
rehearsal artifacts exist, deployment correctly remains blocked at preflight.
