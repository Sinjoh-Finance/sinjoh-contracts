# Sinjoh Contracts v2

Greenfield implementation of the integrated Sinjoh v2 protocol specifications in
[`../specs/contracts-v2`](../specs/contracts-v2/README.md).

This package does not modify, migrate, or import the implementations of deployed v1 contracts.
OpenZeppelin Contracts 5.6.1 is imported from the repository's pinned vendored dependency.

## Implemented protocols

| Protocol | Status |
| --- | --- |
| Shared project interfaces and identity | implemented |
| `ProjectVotesToken` | implemented |
| Staking + PoS NFT | implemented |
| Multisig Accounts | pending |
| Token Governance | pending |
| Registry + Treasury Vaults | pending |
| Router | pending |
| Airdrop | pending |
| Basket | pending |
| Funding Bands | pending |
| Raffle/Liquidity v2 binding | pending |
| Launcher | pending |

## Verification

```sh
forge fmt --check
forge build --sizes
forge test
```
