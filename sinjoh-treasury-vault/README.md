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

## Standard deployment

The deployment script verifies the chain ID and deploys the Standard preset — one Joint
(2-of-3, 30-day proposal lifetime) governing one vault (3-day handoff delay, recovery rail
disabled):

```sh
SIGNER_1=0x... SIGNER_2=0x... SIGNER_3=0x... forge script \
  script/DeployStandardTreasury.s.sol:DeployStandardTreasury \
  --rpc-url <robinhood-mainnet-rpc-url> \
  --account 0xsinjoh-deployer \
  --broadcast
```
