# Piggy Banks OpenSea Launch Handoff

## Final product decision

Piggy Banks is the first collection using the generic Yield Banks protocol. Collection-specific
names, supply, prices, tier ranges, wallet limits, eligibility thresholds, dates, fee weights,
redemption asset, and sleeve choices are runtime inputs. None are protocol constants.

The approved OpenSea-only sale model is:

1. Never downgrade or discount unsold Alpha, Prime, or Premium NFTs.
2. Run four sequential allowlist windows.
3. Rotate OpenSea's one public stage through unsold Alpha, Prime, and Premium inventory at each
   tier's original price.
4. Leave Standard as the ongoing public sale at 0.01 ETH.
5. Periodically reopen any remaining higher tier by rotating the same public stage; restore the
   Standard public stage afterward.

There is no custom mint page or payer gateway. Buyers mint through OpenSea, which calls
`0x00005EA00Ac477B1030CE78506496e8C2dE24bf5` directly.

## Immutable tier terms

| Tier | Token IDs | Supply | Price | Fee weight | Lifetime per-wallet cap |
|---|---:|---:|---:|---:|---:|
| Alpha | 1-3 | 3 | 0.5 ETH | 30x (`60`) | 1 |
| Prime | 4-33 | 30 | 0.1 ETH | 7.5x (`15`) | 3 |
| Premium | 34-333 | 300 | 0.03 ETH | 2.5x (`5`) | 5 |
| Standard | 334-3333 | 3,000 | 0.01 ETH | 1x (`2`) | 10 |

The integer fee weights are equivalent to the displayed multipliers and total 8,130 units across
all 3,333 NFTs. A tier's wallet counter and inventory counter persist across its allowlist window
and every later public reopening. Later tiers do not wait for earlier tiers to sell out.

## Eligibility snapshot

| Minimum `$INJOH` balance | Highest tier | Included lists |
|---:|---|---|
| 10,000,000 | Alpha | Alpha, Prime, Premium, Standard |
| 1,000,000 | Prime | Prime, Premium, Standard |
| 100,000 | Premium | Premium, Standard |
| 10,000 | Standard | Standard |
| Below 10,000 | None | None |

The generated snapshot uses block `51362917`, block hash
`0x4e7951ac6e5821b680b3da2e71f4f08533f417b3689613ba5c5d2700e9848257`, and token
`0x2cC0FAC44B8252f6B10208B091aFf2c94B4da77D`. It contains 1,357 eligible wallets and
2,177 tier leaves:

- Alpha: 24 wallets
- Prime: 172 wallets
- Premium: 624 wallets
- Standard: 1,357 wallets

OpenSea uploads:

- `outputs/piggy-banks-opensea-20260904/alpha-opensea-allowlist.csv`
- `outputs/piggy-banks-opensea-20260904/prime-opensea-allowlist.csv`
- `outputs/piggy-banks-opensea-20260904/premium-opensea-allowlist.csv`
- `outputs/piggy-banks-opensea-20260904/standard-opensea-allowlist.csv`

The independent repository tree root is
`0x3b75fe931e7b924402fe851a204b671bc35ea7294706403ec50e84c7288f3792`.
OpenSea Studio may build a different combined tree from the CSV uploads. Read the root that OpenSea
actually writes to SeaDrop and record that observed root in the production manifest. Never replace
OpenSea's root with the independent root unless the proofs were built from the independent files.

## Launch schedule

All local times are America/New_York (EDT, UTC-04:00) on September 4, 2026.

| Window | EDT | UTC | Unix range |
|---|---|---|---:|
| Alpha allowlist | 12:00:00-12:04:59 | 16:00:00-16:04:59 | 1788537600-1788537899 |
| Prime allowlist | 12:05:00-12:14:59 | 16:05:00-16:14:59 | 1788537900-1788538499 |
| Premium allowlist | 12:15:00-12:29:59 | 16:15:00-16:29:59 | 1788538500-1788539399 |
| Standard allowlist | 12:30:00-12:59:59 | 16:30:00-16:59:59 | 1788539400-1788541199 |
| Alpha public | 13:00:00-13:04:59 | 17:00:00-17:04:59 | 1788541200-1788541499 |
| Prime public | 13:05:00-13:14:59 | 17:05:00-17:14:59 | 1788541500-1788542099 |
| Premium public | 13:15:00-13:29:59 | 17:15:00-17:29:59 | 1788542100-1788542999 |
| Standard public | 13:30:00 onward | 17:30:00 onward | 1788543000-1820078999 |

OpenSea caps a public-stage duration at 365 days. The configured Standard end is September 4, 2027
at 13:29:59 EDT; renew it before then if inventory remains.

## Deployment order

The following deployed release is superseded and must not be reused for this mint:

- Factory: `0xc576771755F55bD8586a8fF36b14595d5a93196C`
- Collection: `0x73aB56d87CAA618085c47004cA78611E5cCe5bc0`
- NFT: `0x25A8A3876544EA95Ad704E215e88c2b96A599DfA`
- Proceeds vault: `0xa2007827Dbc6075013cE2BB5687E1a07bE7Cd2aC`
- Distributor: `0x0bCca76e07aD6b0EbcF2420dBa996f7Ddf529f11`
- Timelock: `0xA633E1fc6d0f13A657a354DBF33b6CBe99544191`

The NFT pins its mint policy, and the collection creation bytecode has changed. Deploy in this order:

1. Deploy and register `DeployYieldBankPublicFactoryV106Mainnet`; it reuses unchanged V1.0.5
   component stores, replaces the collection creation-code store, and deprecates V1.0.5.
2. Put the verified V1.0.6 factory address and runtime code hash into a private copy of
   `deployments/piggy-banks-production.env.example`.
3. Deploy the new collection with `DeployYieldBankCollectionMainnet`.
4. Record every emitted address. Use only the new collection, NFT, proceeds vault, distributor,
   revenue router, allocator, sleeves, controller, and timelock from that deployment.
5. Set `YIELD_BANK_COLLECTION` to the new collection and run `ConfigureYieldBankMintPolicy` once.
   The policy is immutable after the first mint and cannot be replaced.
6. Source-verify the new contracts before accepting a mint.
7. In OpenSea Studio, import the four CSVs as four sequential allowlist stages with the exact
   immutable terms above. Set creator payout to the **new proceeds vault**, allow only OpenSea's
   approved fee recipient, and configure Alpha as the first public window.
8. Read SeaDrop state and complete a schema-valid production manifest. The verifier must confirm
   exact payout, allowlist root/stages, public terms, allowed fee recipients, empty payer list,
   empty token-gated list, empty signer list, immutable policy, tier ranges, runtime hashes, and
   ownership.
9. Run eligible and ineligible production canaries before the public announcement.
10. Rotate PublicDrop to Prime, Premium, and Standard at the schedule boundaries. Verify the
    onchain tuple after every transaction before announcing the next window.
11. Transfer NFT ownership to the **new collection timelock** after Standard is installed, then
    accept ownership through that timelock. Future higher-tier reopenings use timelock operations.

The launch manager is `0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49`. Never move, send, swap,
approve, burn, or otherwise touch `$INJOH` held by that wallet. Tell the user before any transaction
that spends ETH from it. The side test wallet is
`0xe4605138e185FBeE40ff6193A044aa0BE2909216` and may be used for canaries.

## Commands

Run from `sinjoh-contracts-v2`. Use a private environment file; do not commit credentials.

```sh
forge fmt --check
SINJOH_RPC_PRIMARY="$YIELD_BANK_RPC_URL" \
ROBINHOOD_MAINNET_RPC_URL="$YIELD_BANK_RPC_URL" \
  forge test
npm --prefix sdk test
node script/verify-yield-bank-schemas.mjs
```

Before the V1.0.6 governance broadcast, read the governance nonce and compute the next two CREATE
addresses. Supply those exact values to the fail-closed deployment script:

```sh
forge script script/DeployYieldBankPublicFactoryV106Mainnet.s.sol:DeployYieldBankPublicFactoryV106Mainnet \
  --rpc-url "$YIELD_BANK_RPC_URL" --account "$FOUNDRY_ACCOUNT" --broadcast
```

Deploy the collection after replacing the zero factory placeholders in the environment file:

```sh
forge script script/DeployYieldBankCollectionMainnet.s.sol:DeployYieldBankCollectionMainnet \
  --rpc-url "$YIELD_BANK_RPC_URL" --account "$FOUNDRY_ACCOUNT" --broadcast
```

Pin the tier policy:

```sh
forge script script/ConfigureYieldBankMintPolicy.s.sol:ConfigureYieldBankMintPolicy \
  --rpc-url "$YIELD_BANK_RPC_URL" --account "$FOUNDRY_ACCOUNT" --broadcast
```

Rotate the one public stage by setting `MINT_PUBLIC_STAGE_INDEX` to `0`, `1`, `2`, or `3` and its
exact start/end values, then running:

```sh
forge script script/ConfigureYieldBankPublicStage.s.sol:ConfigureYieldBankPublicStage \
  --rpc-url "$YIELD_BANK_RPC_URL" --account "$FOUNDRY_ACCOUNT" --broadcast
```

After every deployment or configuration transaction:

```sh
node script/verify-yield-banks-manifest.mjs \
  /absolute/path/to/yield-banks-manifest.json "$YIELD_BANK_RPC_URL"
```

## Final no-assumption gate

- Do not use any address from the superseded collection as a substitute for a new deployment value.
- Do not mint until the production manifest verifier passes against the current chain head.
- Do not enable token-gated drops, signed mints, or allowed payers for this launch.
- Do not overlap allowlist windows with each other or with an active public window.
- Do not use collection-global supply as a tier boundary.
- Do not change a tier's price, wallet cap, fee, restriction flag, or token-ID range.
- Do not transfer NFT ownership before the actor responsible for the initial rotations can execute
  them. The configured timelock delay is 86,400 seconds.
- Do not leave manager ownership in place after the Standard public stage is verified.
- Do not treat the independent Merkle root as OpenSea's observed root without comparing them.
- Do not expose or commit private keys, passwords, temporary password files, or RPC credentials.
