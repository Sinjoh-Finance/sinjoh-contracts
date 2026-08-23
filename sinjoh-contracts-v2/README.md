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
| Multisig Accounts | implemented |
| Token Governance | implemented |
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

Token Governance is deployed atomically as one `ProjectTimelockV2` that creates and permanently
binds its `ProjectGovernorV2`. The Governor is the sole proposer/canceller, execution is open only
for mature scheduled operations, and role/delay mutation is disabled. Controlled modules authorize
the Timelock address directly. Liquid voting reads `ProjectVotesToken`; staked voting reads
`ProjectStakingPoolV2`. Neither path requires delegation.
