# Component: OpenZeppelin Contracts

**Date checked:** 2026-09-03
**Version:** `5.6.1`
**Sources:**
- Release: https://github.com/OpenZeppelin/openzeppelin-contracts/releases/tag/v5.6.1
- Utility API: https://docs.openzeppelin.com/contracts/5.x/api/utils#ReentrancyGuard
- Local pinned package: `sinjoh-treasury-vault/lib/openzeppelin-contracts/package.json`

## Facts

- The installed dependency declares version `5.6.1`.
- `ReentrancyGuard` supplies one guard shared by all `nonReentrant` functions on a contract.
- The project already imports OpenZeppelin ERC-721, royalty, ownership, clone, and reentrancy
  implementations rather than reimplementing them.

## Assumptions

- The repository continues to pin this dependency for the deployment build.

## Inferences

- The existing NFT and collection can continue using the installed ownership, ERC-721, royalty,
  clone, and reentrancy components; the selected OpenSea-only schedule adds no gateway contract.

## Risks

**LOW — Embedded deployment bytecode size**

`YieldBankCollection` deploys an NFT in its constructor, so NFT changes increase collection initcode.
The repository's 49,152-byte EIP-3860 regression test must remain green.

## Resolved questions

**Is a library component available for the guard?** Yes, use the installed `ReentrancyGuard`.

**Auth, install, rate limits, and changes**

This is a source dependency with no authentication or rate limits. Version `5.6.1` is locally
pinned and has an official release page.
