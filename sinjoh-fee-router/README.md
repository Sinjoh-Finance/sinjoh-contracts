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

## The launchpad boundary

This router integrates with no launchpad. It stores one opaque address,
`launchpadAdapter`, which it never calls and which may bind its subject once.
Launching, fee claiming, and every launchpad-specific parameter live behind
`ISinjohLaunchpadAdapter` in `sinjoh-launchpad-adapters`.

**Adding a launchpad means writing an adapter, not editing this contract.**

Fees reach the router by plain transfer and are recognised by `sync(asset)`,
which accepts any asset with a configured normalization route — the subject
token, or a quote asset the launchpad pays fees in. Adapters wrap native value
before forwarding, so intake is uniformly ERC-20.

## Deployment

The deployment script accepts the key only through the process environment,
verifies the chain ID and the expected deployer address, and deploys the router
implementation and deterministic factory.

```sh
DEPLOYER_PRIVATE_KEY=... forge script \
  script/DeployLaunchpadRouter.s.sol:DeployLaunchpadRouter \
  --rpc-url https://rpc.mainnet.chain.robinhood.com \
  --broadcast
```

For an adapter-mediated launch the UI predicts the router clone with
`predictLaunchpadAddress` — which depends only on `(creator, userSalt)`, never on
the config — deploys it with `deployForLaunchpad` naming the predicted adapter,
then deploys the adapter and calls `launch` on it. The adapter binds the returned
subject and delivers any developer buy to the creator in the same transaction.

Both addresses must derive from `(creator, userSalt)` alone: the router config
names the adapter, so folding the config into the adapter's salt would make each
address depend on the other.

The end-to-end live flow was previously exercised by a testnet-only script that
has been removed. `sinjoh-launchpad-adapters` now carries a mainnet-fork suite
covering launch, developer buy, fee accrual, claim and forward against real
deployed contracts; extend that rather than reinstating a testnet script.
