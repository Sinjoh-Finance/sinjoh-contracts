# Sinjoh Treasury Vault

An immutable, non-upgradeable treasury for Sinjoh projects.

`SinjohTreasuryVault` custodies native currency and ERC-20s under exactly one governor
address and performs exactly two operations: governor-instructed single-asset transfers and a
timelocked two-step governor handoff. All spending policy, capital deployment, and governance
capability live outside the kernel — in governor modules, middleware, and sink protocols — so
a deployed vault never migrates and never needs to.

`SinjohJoint` is the Standard governor module: a 2-of-3 joint-account (multi-signature)
control system with quorum-managed signer rotation and fixed proposal lifetimes. It also
serves as the reusable owner primitive for other Sinjoh protocols.

Upgrading governance later — token voting, futarchy, liquid democracy, policy middleware — is
one timelocked governor handoff; funds never move. Design rationale:
[TREASURY_DESIGN.md](../TREASURY_DESIGN.md).

## Build and test

```sh
forge build
forge test
```

OpenZeppelin Contracts is pinned to v5.6.1 under `lib/openzeppelin-contracts`.

## Deployment

The deployment script verifies the chain ID and deploys the permissionless
`SinjohTreasuryFactory` once. Individual treasuries are created afterwards by anyone
calling `createStandardTreasury([signer1, signer2, signer3])` — one Joint (2-of-3, 30-day
proposal lifetime) governing one vault (3-day handoff delay, recovery rail disabled):

```sh
forge script \
  script/DeployStandardTreasury.s.sol:DeployStandardTreasury \
  --rpc-url <robinhood-mainnet-rpc-url> \
  --account sinjoh-deployer \
  --broadcast
```

## Robinhood mainnet deployment

| Contract | Address |
|---|---|
| `SinjohTreasuryFactory` | `0x6C70e5ea0EfC774d4099De14Ab4383F6a44AAB2B` |

Deployed at block 27152780
(tx `0xe96c9411a7b7baf8d5e7d638efd88f9bb9c6e0a516c3af1414648d2431473de7`), verified
on-chain: 3-day handoff delay, 30-day proposal TTL.
