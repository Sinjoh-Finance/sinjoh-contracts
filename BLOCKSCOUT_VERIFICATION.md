# Blockscout Source Verification

Verified: 2026-08-19

Network: Robinhood Chain mainnet (`chainId` 4663)

Explorer: [Robinhood Chain Blockscout](https://robinhoodchain.blockscout.com)

All 72 known source-verifiable deployment contracts are published on the
explorer:

- 71 Sinjoh contracts, libraries, factories, implementations, adapters, and
  guards
- 1 byte-identical upstream Uniswap `MerkleClaimFactory`
- 72 successful creation-bytecode matches
- 0 changed-bytecode results
- 0 failed or pending verifications

The machine-readable evidence is
[`blockscout-verification.json`](./blockscout-verification.json). Each entry
links directly to the explorer and records its deployment tag, source path,
contract name, compiler, optimizer runs, EVM target, verification result, and
license.

## What verification proves

Blockscout recompiles the submitted source with the recorded compiler settings
and compares its creation bytecode with the deployed transaction. A successful
result publishes the source and ABI and enables the explorer's Read/Write
Contract views. It proves source correspondence; it is not an audit or a claim
that the contract is secure. See [`AUDITS.md`](./AUDITS.md) for the separate
security-review status.

## Reproduction method

Each first-party contract was handled as follows:

1. Check out its immutable `deploy/mainnet/*` tag.
2. Build the owning Foundry package with the tag's pinned settings.
3. Match the compiled runtime against Robinhood Chain, ignoring only
   compiler-declared immutable and linked-library ranges.
4. Supply deployed library addresses for linked Funding Bands managers.
5. Submit Standard JSON to Blockscout's v2 verifier with constructor argument
   autodetection.
6. Require `creation_status=success`, `is_verified=true`, and
   `is_changed_bytecode=false` from the explorer.

The four Funding Bands manifests were committed after their corresponding
source generations. The verifier therefore pairs source tag v1 with the
deployment records first present in v2, v2 with v3, v3 with v4, and v4 with
the current canonical manifest. Local runtime matching confirms every pairing.

The raffle factory creates its implementation in its constructor. The
implementation at `0x982F8B6612146E0963DFd18D74e1ffe4E110b47D` was not listed
as a separate runtime check in the original provenance total, but is included
in the explorer registry.

The pools.trade `MerkleClaimFactory` was compiled from Uniswap's exact
`dd8769cd45c0e9450e928513ee129b0af74f7f32` source commit with Solidity 0.8.26,
200 optimizer runs, Cancun, and no bytecode metadata. Its runtime hash matches
the chain and it remains MIT licensed.

## Verification level and metadata

Blockscout labels these contracts `partial` because the deployments
intentionally set `bytecode_hash = "none"` and disabled CBOR metadata. Without
an embedded metadata hash, the explorer cannot call them fully verified even
when creation bytecode matches. The decisive fields for these deployments are:

- `creation_status: "success"`
- `is_changed_bytecode: false`
- `is_verified: true`

## License handling

Sinjoh-owned source is released under Apache-2.0. Historical tags originally
used MIT SPDX comments; the submitted Standard JSON used an Apache-2.0
comments-only overlay. Because bytecode metadata was disabled, this overlay
does not change creation or runtime bytecode.

Blockscout does not replace verification metadata for contracts it already
knows. Consequently, some pre-existing explorer records retain legacy `mit` or
`none` labels. The registry records both the authoritative source license and
the explorer's current label. Third-party code is never relabeled: the Uniswap
factory remains MIT.

## Repeatable tooling

[`scripts/match-deployed-artifacts.mjs`](./scripts/match-deployed-artifacts.mjs)
matches compiled artifacts to manifest addresses and onchain runtime.
[`scripts/verify-blockscout.mjs`](./scripts/verify-blockscout.mjs) submits
Standard JSON through Blockscout's v2 API, retries transient failures, polls to
a terminal status, and fails closed if bytecode is changed or verification
fails.

