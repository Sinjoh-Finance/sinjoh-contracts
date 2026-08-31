# Component: OpenSea SeaDrop

**Date checked:** 2026-08-31
**Version:** unversioned
**Disposition:** MISS-unversioned

## Facts

- SeaDrop mints first, then calls `_splitPayout` for paid mints. Source: https://raw.githubusercontent.com/ProjectOpenSea/seadrop/main/src/SeaDrop.sol
- `_splitPayout` sends the affiliate fee and creator payout as native ETH. Source: https://raw.githubusercontent.com/ProjectOpenSea/seadrop/main/src/SeaDrop.sol
- A custom contract may be used for an OpenSea Drop if it preserves the SeaDrop mint interface. Source: https://docs.opensea.io/docs/deploying-a-seadrop-compatible-contract.md

## Assumptions and inferences

- The collection's creator payout address must accept native ETH.
- Exact receipt correlation can remain atomic because the NFT mint hook runs before the payout transfer.

## Risks

**CRITICAL — Incompatible payout intermediary**

A router that rejects native ETH, removes an extra fee, or delays forwarding destroys exact per-mint receipt accounting.

## Resolved questions

**Can the existing general SinjohFeeRouter receive SeaDrop payouts directly?**

No. Its source deliberately rejects native intake during synchronization and applies a separate fixed protocol fee, while Yield Banks requires exact collection-configured economics.
