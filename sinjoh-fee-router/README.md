# Sinjoh Fee Router

Immutable, deterministic fee routing for Sinjoh launch assets. The factory deploys
EIP-1167 clones with CREATE2 and initializes each clone atomically from a canonical
configuration.

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
chain ID `46630`, verifies the expected deployer address, and deploys the locked
implementation plus its factory.

```sh
DEPLOYER_PRIVATE_KEY=... forge script script/DeployFeeRouter.s.sol:DeployFeeRouter \
  --rpc-url https://rpc.testnet.chain.robinhood.com \
  --broadcast
```

Router clones are deployed later from reviewed, per-subject configurations. The
creator, protocol fee recipient, treasury, and governance fields should use
`0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49` for the testnet release.
