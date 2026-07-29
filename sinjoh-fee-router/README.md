# Sinjoh Fee Router

Immutable, deterministic WETH-first fee routing for Sinjoh launch assets. The
factory deploys EIP-1167 clones with CREATE2 and initializes each clone
atomically from a canonical configuration.

The router accepts only the launched token and WETH. Launched-token fees swap
to WETH first. WETH is then split into buckets that can keep WETH, unwrap to
native ETH, swap directly to one ERC-20, buy back the launched token, or fund
the liquidity manager. Outputs can be sent to wallets, funded into a sink, or
sent to the burn address.

## Local verification

```sh
forge fmt --check
forge lint
forge test
forge coverage --report summary
forge build --sizes
```

## Robinhood testnet deployment

The deployment script accepts the key only through the process environment, verifies
chain ID `46630`, verifies the expected deployer address, and deploys the shared
swap adapter, nonblocking testnet liquidity guard, router implementation, and
factory.

```sh
DEPLOYER_PRIVATE_KEY=... forge script script/DeployFeeRouter.s.sol:DeployFeeRouter \
  --rpc-url https://rpc.testnet.chain.robinhood.com \
  --broadcast
```

Router clones are deployed later from per-launch configurations. The launch UI
installs each clone as the original Pons fee wallet and binds the launched token
after the launch transaction confirms.

The repeatable live flow exercises WETH, native ETH, buyback, another token,
RWA, wallet sends, burns, airdrop funding, and permanent LP:

```sh
DEPLOYER_PRIVATE_KEY=... forge script \
  script/TestnetSimpleFlow.s.sol:TestnetSimpleFlow \
  --rpc-url https://rpc.testnet.chain.robinhood.com \
  --broadcast --slow --gas-estimate-multiplier 200
```
