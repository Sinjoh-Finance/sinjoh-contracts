# Component: OpenZeppelin Contracts

**Date checked:** 2026-08-24
**Sources:**
- Documentation index: https://docs.openzeppelin.com/llms.txt
- ERC-20 API: https://docs.openzeppelin.com/contracts/5.x/api/token/erc20
- Changelog: https://docs.openzeppelin.com/contracts/5.x/changelog

## Facts

- The pinned local package reports version 5.6.1.
- In Contracts 5.x, `_transfer`, `_mint`, and `_burn` are not virtual; transfer, mint, and burn customizations belong in `_update`.
- `_update` receives zero-address endpoints for mint and burn and is the common accounting hook.
- The 5.x changelog records the removal of the prior before/after transfer hooks.

## Assumptions

- The vendored 5.6.1 source is the exact source compiled by Foundry.

## Inferences

- ProjectVotesToken's existing `_update` override is the correct library extension point; graduation safety belongs in the immutable custody-exclusion set, not in a second transfer hook or token rewrite.

## Risks

**LOW — Hook migration can silently bypass vote accounting after a dependency change**

Future OpenZeppelin major upgrades must revalidate the transfer customization point. The pinned 5.6.1 implementation and current override are consistent today.

## Resolved questions

**Is a custom token transfer rewrite required for graduation?**

No. The existing `_update` override observes all transfers; the missing input was the post-graduation custody identity.
