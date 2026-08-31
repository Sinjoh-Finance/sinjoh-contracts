<!-- BRAINBLAST:CACHE slug=openzeppelin-contracts version=5.6.1 fetched=2026-08-27 -->
# OpenZeppelin Contracts

Version: 5.6.1
Disposition: MISS-new
Primary sources: https://docs.openzeppelin.com/contracts/5.x/ and https://github.com/OpenZeppelin/openzeppelin-contracts/releases/tag/v5.6.1

## Verified facts

- The repository's v2 contracts use OpenZeppelin Contracts 5.6.1.
- Relevant modules include ERC-721, `Clones`, `SafeERC20`, access-control primitives, pausing, and reentrancy protection.
- Clones do not run implementation constructors; every vault clone must be initialized exactly once and initialization must bind its token ID, collection, and manager.
- OpenZeppelin 5.6.1 was released on 2026-02-27.

## Assumptions and inferences

- Deterministic clone salts should bind `chainId`, factory, collection, and `tokenId` so addresses cannot collide across deployments.
- The NFT and vault need explicit transfer/burn state-machine tests because the bearer claim crosses two contracts.

## Risks

- **MEDIUM — Clone initialization or salt mistakes.** An uninitialized clone or ambiguous salt can let the wrong party seize a treasury or make the advertised deterministic address false.
- **LOW — Custom hook risk.** ERC-721 transfer eligibility and exit-lock overrides can break normal transfer behavior unless all mint, transfer, burn, and reentrancy cases are tested.

## Unresolved

- None for the library. Contract-level safety depends on Sinjoh's implementation and audit.
