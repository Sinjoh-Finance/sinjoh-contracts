<!-- BRAINBLAST:CACHE slug=openzeppelin-contracts version=5.6.1 fetched=2026-08-27 -->
# Component: OpenZeppelin Contracts

**Date checked:** 2026-08-27
**Version:** 5.6.1
**Disposition:** HIT

## Facts

- The repository uses OpenZeppelin Contracts 5.6.1.
- Relevant existing components are `ERC721Royalty`, `SafeERC20`, and `ReentrancyGuard`.
- ERC-20 and ERC-721 behavior should be extended through the installed library rather than copied.

## Risks

**LOW — Custom behavior around standard primitives**

Native royalty routing, source authorization, and proof-carrying restricted transfers are protocol-specific and need direct tests around the imported primitives.
