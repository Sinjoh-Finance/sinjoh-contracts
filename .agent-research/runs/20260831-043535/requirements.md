# Yield Banks remediation requirements

Source: `YIELD-BANKS-DEVELOPMENT-PLAN.md` plus the 2026-08-31 code review.

- Preserve per-collection supply and configurable primary economics.
- Preserve SeaDrop/OpenSea primary minting and manual backing allocation.
- Accept and account for native and ERC-20 secondary royalties without caller-selected routes.
- Make the ERC-2981 percentage configurable per collection.
- Make an NFT owner's allocation revision one-shot and owner-bound to execution limits.
- Correct adapter withdrawal projections.
- Make redemption and restricted-share eligibility checks use the same proof.
- Do not reuse an external fee router if it adds an unapproved fee or breaks exact mint accounting.
- Keep the Stock Token model and primary fee-router topology as explicit product decisions.
