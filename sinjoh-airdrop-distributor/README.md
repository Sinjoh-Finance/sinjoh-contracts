# Sinjoh Airdrop Distributor

Immutable-attestor, account-scoped Merkle-sum distributions for subject-token holders.
The distributor accrues a fixed 1% protocol fee on every funding receipt and pushes
the remaining 99% to recipients without signatures, approvals, or claims.

The contract uses Robinhood Chain's canonical `ArbSys` precompile at `0x64` for L2
block-number and block-hash verification. It never compares snapshot heights to
Solidity `block.number`.

## Local verification

```sh
forge fmt --check
forge lint
forge test
forge coverage --report summary
forge build --sizes
```

## Robinhood testnet deployment

The deployment script reads the key from the process environment, verifies chain ID
`46630`, calls `ArbSys.arbBlockNumber()`, verifies the expected deployer, and deploys
the distributor with that address as its immutable attestor. `REVENUE_COLLECTOR`
must be a deployed contract and becomes the immutable protocol-fee recipient.

```sh
DEPLOYER_PRIVATE_KEY=... REVENUE_COLLECTOR=... forge script \
  script/DeployAirdropDistributor.s.sol:DeployAirdropDistributor \
  --rpc-url https://rpc.testnet.chain.robinhood.com \
  --broadcast
```
