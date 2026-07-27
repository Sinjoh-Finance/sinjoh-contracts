# Sinjoh Liquidity Manager

Permanent full-range Uniswap v3/v4 liquidity custody with immutable per-funder
configuration, guarded fixed-share swaps, one position per account, and
account-scoped residual/fee accounting. The manager charges no fee on contributed
principal; it accrues a fixed 1% protocol fee only from LP fees actually collected.

The package pins the official Uniswap source releases used by the integration:
v3 core/periphery `1.0.0`, v4 core `1.0.2`, and v4 periphery `1.0.3`.

## Local verification

```sh
forge fmt --check
forge lint
forge test
forge coverage --report summary
forge build --sizes
```

## Robinhood testnet deployment

The script verifies chain ID `46630`, the expected deployer, and every configured
Uniswap dependency bytecode hash before broadcasting. `REVENUE_COLLECTOR` must be
a deployed contract and becomes the immutable protocol-fee recipient.

```sh
DEPLOYER_PRIVATE_KEY=... REVENUE_COLLECTOR=... forge script \
  script/DeployLiquidityManager.s.sol:DeployLiquidityManager \
  --rpc-url https://rpc.testnet.chain.robinhood.com \
  --broadcast
```
