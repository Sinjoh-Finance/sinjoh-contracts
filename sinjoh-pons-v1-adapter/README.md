# Sinjoh Pons v1 Adapter

Minimal immutable bridge from Pons v1 fee collection to a Sinjoh fee router.
Forwarding is permissionless. Adapter-triggered collection is permissionless only
after the Pons locker owner approves the adapter as a fee collector; the fee
redirect setting alone controls payout and does not grant collection authority.

## Local verification

```sh
forge fmt --check
forge lint
forge test
forge coverage --report summary
forge build --sizes
```

## Robinhood testnet dependencies

- Pons v1 locker: `0x9E18AFba6eADDC1A00Edd35FB7AB6C5CD1E1dEE0`
- Pons v1 WETH: `0x37E402B8081eFcE1D82A09a066512278006e4691`

The deployment script verifies both bytecode hashes, chain ID `46630`, and the
expected deployer before deploying the implementation-backed CREATE2 factory.

```sh
DEPLOYER_PRIVATE_KEY=... forge script \
  script/DeployPonsV1AdapterFactory.s.sol:DeployPonsV1AdapterFactory \
  --rpc-url https://rpc.testnet.chain.robinhood.com \
  --broadcast
```
