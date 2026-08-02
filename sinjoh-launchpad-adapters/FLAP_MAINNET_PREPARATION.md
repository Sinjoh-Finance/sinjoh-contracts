# Flap mainnet preparation

Phase 1 is preparation only. Nothing in this document authorizes a Robinhood
mainnet broadcast or an irreversible token launch.

## Reviewed mainnet snapshot

The fork suite is pinned to Robinhood mainnet block `25,471,700` on chain
`4663`. It deploys fresh Sinjoh infrastructure inside the fork, launches a real
Flap Tax Token V3 through the live Portal, buys, sells, collects, wraps,
forwards, synchronizes, pays the creator, and sends the router's one-percent fee
to the deployed Sinjoh revenue collector.

| Dependency | Address | Runtime code hash |
| --- | --- | --- |
| Flap Portal | `0x26605f322f7fF986f381bB9A6e3f5DAb0bEaEb09` | `0xcecb292d9c022858199c9348abf0d5836f9ea4dab5cf03710e1dcf41fd9a4c35` |
| Flap Tax Token V3 implementation | `0x7777C8743C88B3aff3cf262135beF2c8b2e83333` | `0xa73abf611d52de6364ec684feed2ef3e9aec9706a02b808523e75a6d8438b164` |
| Mainnet WETH | `0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73` | `0x5706be52f64875fee65a2cec0d80e47a23d8793cbe85d214b48445e2d05f5353` |
| Sinjoh revenue collector | `0x5Bb7582557F5be30b62c335Ad3ccf4bA79E138c5` | `0x2a2605aed6c20353f19ea155b13605c9730f53b8b0fc9f2c1aea78433654789b` |

The Portal reported `v5.15.2`. The reviewed Portal commitment is
`0xb789978b5db7d4d20b60a96ac19d9b9f4a667f2182a2d833a3dfb02459fbb713`;
it commits to the proxy runtime, encoded version response, and native-quote
configuration response.

The TaxProcessor created by the live mainnet Portal reported `feeRate = 300`.
This was established by deliberately trying the alternative assumption in the
fork: the adapter rejected it with `FlapFeeRateMismatch`, after which the
observed 300-bps value passed the complete route and final-payout test.

## Prepared scripts

### Dark infrastructure

`script/DeploySinjohFlapMainnetInfrastructure.s.sol` deploys only:

1. the launchpad-agnostic `SinjohFeeRouter` implementation;
2. its `SinjohFeeRouterFactory`; and
3. `SinjohFlapAdapterFactory` plus its self-deployed implementation.

It cannot launch a token. It requires chain `4663`, the reviewed mainnet
deployment wallet, and the exact dependency hashes above. It also verifies the
new router implementation hash and every factory/implementation relationship
after construction, then emits all new runtime hashes for the signed deployment
manifest.

Simulation only:

```sh
forge script \
  script/DeploySinjohFlapMainnetInfrastructure.s.sol:DeploySinjohFlapMainnetInfrastructure \
  --rpc-url "$ROBINHOOD_MAINNET_RPC_URL"
```

Do not add `--broadcast` during Phase 1.

### Irreversible canary launch

`script/LaunchSinjohFlapMainnetCanary.s.sol` is prepared for the later canary
phase but must not be broadcast during Phase 1. It:

- requires the newly deployed factory addresses and their recorded code hashes;
- rechecks every upstream dependency and the reviewed Portal commitment;
- requires a freshly mined `FLAP_TOKEN_SALT` whose predicted address ends in
  `7777` and has no code;
- configures the deployed Sinjoh revenue collector as `protocolFeeRecipient`;
- uses a WETH-only, 100-percent creator canary bucket; and
- performs full immutable readback after launch.

Required values after the dark infrastructure deployment:

```text
SINJOH_AGNOSTIC_ROUTER_FACTORY
SINJOH_AGNOSTIC_ROUTER_FACTORY_CODEHASH
SINJOH_FLAP_ADAPTER_FACTORY
SINJOH_FLAP_ADAPTER_FACTORY_CODEHASH
SINJOH_FLAP_ADAPTER_IMPLEMENTATION_CODEHASH
FLAP_TOKEN_SALT
```

The salt must be mined immediately before the approved canary window rather
than committed here. Publishing a usable salt early lets another Portal caller
occupy the predicted token address.

## Verification

Run the mainnet proof with:

```sh
forge test --force --match-contract SinjohFlapAdapterMainnetForkTest -vv
```

The acceptance conditions are:

- exact dependency hashes and chain ID;
- exact predicted token and `7777` suffix;
- launch, buy, and sell success;
- intact marketing and commission routing;
- full native-balance wrapping, adapter forwarding, and router synchronization;
- a one-percent Sinjoh protocol fee;
- creator and real revenue-collector payouts; and
- zero final router WETH balance and zero liability.
