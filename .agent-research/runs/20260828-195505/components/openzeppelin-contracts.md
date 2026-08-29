<!-- BRAINBLAST:CACHE slug=openzeppelin-contracts version=5.6.1 fetched=2026-08-27 -->
# Component: OpenZeppelin Contracts

**Date checked:** 2026-08-28
**Disposition:** HIT — reused from cache fetched 2026-08-27

## Facts

- The repository is pinned to version 5.6.1 and imports `SafeERC20`, `ReentrancyGuard`, ERC-20,
  and two-step ownership from the installed package.
- Release source: https://github.com/OpenZeppelin/openzeppelin-contracts/releases/tag/v5.6.1

## Assumptions

- No upgradeable storage layout is involved in the new holdings contracts.

## Inferences

- The minimal adapter path should continue importing these components rather than embedding copies.

## Risks

**MEDIUM — external-call lifecycle risk**

Adapter deposits and exits require reentrancy protection, measured receipts, and zeroed temporary
allowances even when an external protocol is allowlisted.

**LOW — ownership handoff risk**

Two-step registry ownership must be accepted before production activation.

## Resolved questions

**Is a custom token-transfer wrapper necessary?**

No. The installed `SafeERC20` component provides the required transfer and force-approval behavior.
