# Mainnet Deployment Provenance

Verified: 2026-08-18

Network: Robinhood Chain mainnet (`chainId` 4663)

This registry maps every known Sinjoh mainnet deployment generation to the Git
commit that reproduces its runtime bytecode. Annotated Git tags are the stable
public identifiers; commit hashes are included for independent verification.

## Verified tags

| Tag | Source commit | Runtime checks |
|---|---|---:|
| `deploy/mainnet/core-2026-07-30` | `f39cd1a110a9f2ef43e120bc8bb131759501b032` | 8 |
| `deploy/mainnet/simple-swap-v2-2026-07-30` | `2a64128c56ca3a99bd9d19d1ecada665c2806638` | 1 |
| `deploy/mainnet/flap-base-2026-08-01` | `a1ca609de496df9e6b172f30fb1a105d74ef2b48` | 4 |
| `deploy/mainnet/flap-execution-2026-08-02` | `2692c80b02198b31cdfd75d386fc8ea962136fa0` | 3 |
| `deploy/mainnet/flap-payout-2026-08-02` | `df0d09d42361b4f91d7417d78de88b5dc2c86bf1` | 1 |
| `deploy/mainnet/pons-v2-adapter-2026-08-04` | `768b5f326427b43a6bf4060ac22139228200cc57` | 2 |
| `deploy/mainnet/pons-v2-buyback-2026-08-04` | `d9051387323e5b79491dce4c31ef8e6ca1beee5b` | 2 |
| `deploy/mainnet/pons-v2-pair-buyback-2026-08-04` | `18cfe90cc343aafe7598d4eaa09a5bd29a23d480` | 2 |
| `deploy/mainnet/pools-trade-2026-08-05` | `1b3ff4c40923f79b8210fb9d6a236318e0acfb60` | 10 |
| `deploy/mainnet/raffle-randomness-2026-08-05` | `9a43fd600e9bd95031ba06bd78b02231bc5ff249` | 2 |
| `deploy/mainnet/raffle-price-guards-2026-08-05` | `9347bb4a714f29280b37060881f45a80ed0e7831` | 3 |
| `deploy/mainnet/letscash-2026-08-11` | `06728770ef27339f531a6dd4f9b4afcf83df1522` | 4 |
| `deploy/mainnet/funding-bands-v1-2026-08-14` | `47ca8b460588e3d2c8b780838e813bc8e3503661` | 6 |
| `deploy/mainnet/funding-bands-v2-2026-08-14` | `ffb5aedf577a7566335273da901b7ab222ce66c4` | 6 |
| `deploy/mainnet/funding-bands-v3-2026-08-15` | `7b42c164aebc01a3eeba40a75f7655eee9876c25` | 7 |
| `deploy/mainnet/funding-bands-v4-2026-08-15` | `036972edec6b07a2f867bbe1582d3e51aaae0a65` | 11 |
| **Total** | | **72** |

The pools.trade Merkle claim factory is an explicitly identified byte-identical
deployment of an upstream Uniswap artifact and is not counted as a Sinjoh
source-runtime check.

## Verification method

For each tag:

1. Check out the source commit in a fresh clone.
2. Compile the relevant Foundry package with its pinned `solc` and settings.
3. Fetch runtime code from the public Robinhood Chain RPC.
4. Require exact byte length equality.
5. Require every runtime byte to match except compiler-declared immutable and
   linked-library reference ranges.
6. Compare the resulting code hash with `mainnet-deployments.json` where the
   registry contains one.

This method verifies the executable runtime rather than relying on commit
timestamps, deployment notes, or Forge's broadcast `commit` field.

## Dirty-worktree correction

Forge records the current `HEAD` in broadcast JSON even when deployment source
contains uncommitted changes. This occurred for the corrected simple swap
adapter and several integration deployments. Their tags intentionally point to
the first commits that captured and reproduced the deployed source, not the
earlier hashes recorded by Forge.

## Preservation rule

Do not move, delete, or retarget these tags. When history is filtered into
`sinjoh-contracts`, preserve every tag whose target survives and publish a
machine-readable mapping if the filtered commit hash changes.
