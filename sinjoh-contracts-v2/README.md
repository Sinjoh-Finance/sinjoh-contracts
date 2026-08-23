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
| Treasury Vaults | implemented |
| Registry | implemented |
| Router | implemented |
| Airdrop | implemented |
| Basket | implemented |
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

`ProjectTreasuryVaultV2` uses the same controller ABI with either independent governance model. It
provides exact native/ERC-20 accounting, guarded proof-approved swaps, optional policy-based Basket
reservations with permissionless keeper execution, and typed Basket NFT management without a
generic arbitrary-call surface. Frontends and keepers can read complete route status and verify an
exact swap approval on-chain.

`ProjectRegistryV2` is an append-only canonical discovery layer. One record tells clients which
governance workflow and modules are enabled, resolves every explicit address without bytecode
probing, and supports only controller-authored UI metadata revisions. It has no project control,
asset custody, deployment, recovery, or generic execution authority.

`ProjectRouterV2` accepts exact attributed or synced revenue, carries the cumulative 1% fee
remainder, and executes constructor-initialized or governance-versioned typed routes. Cumulative
allocation prevents micro-batch bias; failed and paused shares remain exact versioned escrow for
permissionless retry or governance re-keying into an active same-asset action. Its work/action and
approval views are designed for direct keeper and frontend consumption.

`ProjectAirdropV2` creates immutable per-funder reward accounts and pushes holder- or staker-mode
payments without recipient claims. EIP-712 epoch commitments are permissionlessly relayed, while
on-chain checkpoints and direction-aware weight/amount Merkle sums verify every proportional leaf.
Failed recipients and dust destinations become exact retryable credits; one-call account/epoch
status and proof/hash helpers support frontends, workers, and independent artifact verification.

`BasketManagerV2`, `BasketNFTV2`, and each isolated `BasketVaultV2` implement locked yield baskets.
Funding follows a complete proof-approved input/target route matrix, realized yield is harvested on
the selected daily or weekly cadence into the matching Airdrop account, and failed downstream
delivery remains exactly retryable. Optional governance updates perform an atomic in-vault
rebalance. Principal can leave only through resumable NFT burn settlement, with an optional exact
project-token burn price and in-kind tax. The per-Basket Vault is a deterministic clone of one
audited implementation so the launch is both address-predictable and EVM-size compliant.
