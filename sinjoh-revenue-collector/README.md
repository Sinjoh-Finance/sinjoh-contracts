# Sinjoh Revenue Collector

A minimal, non-upgradeable revenue endpoint for Sinjoh protocol fees.

The collector decouples stable upstream fee destinations from evolving token economics. Sinjoh
contracts send their protocol fees to the collector; the collector forwards native currency and
ERC-20s without an additional fee to the current governance-selected processor.

## Build and test

```sh
forge build
forge test
```

OpenZeppelin Contracts is pinned to v5.6.1 under `lib/openzeppelin-contracts`.

## Robinhood testnet deployment

The deployment script verifies chain ID `46630`, the expected deployer, and the
governance/processor address before broadcasting:

```sh
DEPLOYER_PRIVATE_KEY=... forge script \
  script/DeployRevenueCollector.s.sol:DeployRevenueCollector \
  --rpc-url https://rpc.testnet.chain.robinhood.com \
  --broadcast
```

Testnet collector:
[`0x1e22b9B257c73b309F1fcDA3508A48755896619b`](https://explorer.testnet.chain.robinhood.com/address/0x1e22b9B257c73b309F1fcDA3508A48755896619b).
Its owner and initial processor are
`0x39E2f5eFdFd808F26B98979a06BA11ea82E1C85f`.
