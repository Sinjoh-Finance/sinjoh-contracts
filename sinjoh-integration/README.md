# sinjoh-integration

Cross-package rehearsal harness — deliberately not a package. It composes
`sinjoh-fee-router` and `sinjoh-raffle-rewards` against the live Pons v2
deployment, which neither package may import on its own (both are standalone by
specification).

```sh
RH_RPC_URL=https://rpc.mainnet.chain.robinhood.com forge test
```

`ProductionPonsV2Raffle.fork.t.sol` is the reference implementation of the
launch ordering: predict router → predict curve/token → build the raffle around
the predicted curve → deploy raffle, then router naming it as sink → launch →
verify every prediction → revenue to prize pool → committed round pays a real
holder. A UI implementing the flow should follow it step for step; the keeper's
`src/ponsv2/predict.ts` and `raffle-launch.ts` are the off-chain twins of the
prediction steps, fixture-pinned to the Solidity encodings.

Without `RH_RPC_URL` the suite skips (a skipped fork test reports as passing at
trivial gas — check the gas, not the green).
