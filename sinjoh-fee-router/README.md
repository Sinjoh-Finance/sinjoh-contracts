# Sinjoh Fee Router

Immutable, deterministic WETH-first fee routing for Sinjoh launch assets. The
factory deploys EIP-1167 clones with CREATE2 and initializes each clone
atomically from a canonical configuration.

The router accepts only the launched token and WETH. Launched-token fees swap
to WETH first. WETH is then split into buckets that can keep WETH, unwrap to
native ETH, swap directly to one ERC-20, buy back the launched token, or fund
the liquidity manager. Outputs can be sent to wallets, funded into a sink, or
sent to the burn address.

For Pons v2, the launch creator may set `creatorTaxBps` to zero or 1 to 5,000 bps.
The same transaction also checks the selected factory's live `maxCreatorTaxBps()`,
so a lower upstream cap is enforced without hardcoding it. The initial creator-fee
recipient must be either the creator or this router. A router recipient enables
permissionless escrow claims and normal immutable routing; a creator recipient
keeps all Pons creator revenue outside Sinjoh accounting.

## Local verification

```sh
forge fmt --check
forge lint
forge test
forge coverage --report summary
forge build --sizes
```

## Pons v1 deployment script

The router-owned Pons deployment script accepts the key only through the process
environment, verifies Robinhood mainnet chain ID `4663`, verifies the expected
deployer address, and deploys the router implementation and deterministic factory.
It is not the Pons v2 testnet path.

```sh
DEPLOYER_PRIVATE_KEY=... forge script \
  script/DeployRouterOwnedPons.s.sol:DeployRouterOwnedPons \
  --rpc-url https://rpc.mainnet.chain.robinhood.com \
  --broadcast
```

For new launches the UI predicts the clone without needing the future subject
address, deploys it with `deployPons`, and calls `launchPonsToken` on the clone.
Pons therefore records the router as both deployer and fee wallet. The router
binds the returned subject and sends any developer-buy output to its configured
Sinjoh creator in the same transaction.

`collectPonsFees` is permissionless. Pons authorizes it because the call reaches
the locker from the router that deployed the token; proceeds can only enter that
same immutable router.

The end-to-end live flow — router creation, Pons launch, developer-buy
delivery, Pons fee collection, subject-to-WETH normalization, routing, wallet
delivery, and protocol-fee delivery — was exercised by a testnet-only script
that has been removed. Reinstate an equivalent rehearsal against a mainnet
fork before broadcasting; see the mainnet fork gate in `DEVELOPMENT_PLAN.md`.

Pons v2 addresses are intentionally absent. Once Pons publishes verified Robinhood
testnet contracts, pin their chain ID, address, and runtime code hash in a separate
v2 deployment script and exercise the live cap, preview economics, launch readback,
fee escrow claim, WETH synchronization, and recipient paths before any mainnet work.

The prepared script refuses to run without both published dependency code hashes:

```sh
PONS_V2_FACTORY=... \
PONS_V2_FACTORY_CODEHASH=... \
PONS_V2_FEE_ESCROW_CODEHASH=... \
DEPLOYER_PRIVATE_KEY=... \
forge script script/DeployRouterOwnedPonsV2Testnet.s.sol:DeployRouterOwnedPonsV2Testnet \
  --rpc-url https://rpc.testnet.chain.robinhood.com --broadcast
```
