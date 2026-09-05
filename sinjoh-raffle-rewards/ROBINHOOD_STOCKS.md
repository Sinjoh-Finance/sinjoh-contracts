# Robinhood Chain mainnet stock routes

`script/StockRouteManifest.sol` is the source of truth. On 2026-09-05, the following 25
address-sorted routes passed the full five-minute guard, quote, buy, sell, beacon-integrity, and
exact-transfer preflight for a 0.01 WETH maximum prize. With the production tax defaults, that
exercised a maximum single swap input of 0.009 WETH.

| Index | Symbol | Stock token | Fee | Canonical WETH pool |
|---:|---|---|---:|---|
| 0 | AMC | `0x05a3d1Cd21d0C88145E82600E62e7E496e0F222B` | 10000 | `0xcF38764Ae8c92222Af4358A701871A6235Cfc7b7` |
| 1 | RDDT | `0x05b37Fb53A299a1b874A619e1c4C404D52C36F4C` | 10000 | `0xA541143F20D7b0643123064aBF25F423E375b531` |
| 2 | SPY | `0x117cc2133c37B721F49dE2A7a74833232B3B4C0C` | 500 | `0xDDCBBa3666f578E3F09516f21Ff85BFee859AB5e` |
| 3 | GME | `0x1b0E319c6A659F002271B69dB8A7df2F911c153E` | 500 | `0xc6BCC95043DC48C204bB2D57fb264a10Efe0a607` |
| 4 | DJT | `0x1D11f0496982706C5e14A514D4E79F2e6BdE4516` | 500 | `0x95DEF4ea143630d64CAA8F55F7570D8023f20265` |
| 5 | TSLA | `0x322F0929c4625eD5bAd873c95208D54E1c003b2d` | 3000 | `0xA953CA88ff430e9487c60cA34d757414f4efdA07` |
| 6 | BB | `0x48E39E56aCdbA37b09020C0b734A613C9a2f100A` | 10000 | `0x183304567485e97e68835708f572aAA0e0E71d08` |
| 7 | SPCX | `0x4a0E65A3EcceC6dBe60AE065F2e7bb85Fae35eEa` | 500 | `0xC3c9F0171490Ef0F4536fe493F3b0EbB5ee0CB5e` |
| 8 | COST | `0x4EA005168D7F09a7A0Ba9D1DEf21a479950E44C2` | 10000 | `0xc478A811a0002BE4321A142D5446247456b1cB05` |
| 9 | TSM | `0x58FfE4a942d3885bAa22D7520691F611EF09e7AA` | 3000 | `0x91280dB3392EA92C08d8134b5760Fb4798B69547` |
| 10 | COIN | `0x6330D8C3178a418788dF01a47479c0ce7CCF450b` | 3000 | `0x6707aeAc7D0e519B083219d27BB427364363183A` |
| 11 | LLY | `0x8005d266423c7ea827372c9c864491e5786600ea` | 3000 | `0x666bA98aB094793e276215448F2485FD8e3c3CE5` |
| 12 | BE | `0x822CC93fFD030293E9842c30BBD678F530701867` | 3000 | `0xe3ECA0Fa4A9Bd2C90852c94FE4A756dA11300489` |
| 13 | SGOV | `0x92FD66527192E3e61d4DDd13322Aa222DE86F9B5` | 10000 | `0x7F310e3D05E575Bd449E4484eF5Da15863ea43B1` |
| 14 | INDA | `0xACEF2e09adb47aD6aBeBAD9fF06689E60615C2B6` | 3000 | `0xF5b37a305E7304a70067be356EE611ac29f706EB` |
| 15 | AAPL | `0xaF3D76f1834A1d425780943C99Ea8A608f8a93f9` | 500 | `0x8bb3514e2204E1cDF3Ac149EFEe7Ff04D91B719f` |
| 16 | SNDK | `0xB90A19fF0Af67f7779afF50A882A9CfF42446400` | 3000 | `0x995c1Ad5Eb998b1BdD89F515C4BB64760c411b62` |
| 17 | META | `0xc0D6457C16Cc70d6790Dd43521C899C87ce02f35` | 3000 | `0xa4BdB396a69617eb7F70E2cc1EF526f7340b1B0d` |
| 18 | HIMS | `0xCceE82fE024c36fA15E1005edE3E9e4787e23D09` | 3000 | `0xeB576c467d69E084A0fDc6dDf744467804634650` |
| 19 | NVDA | `0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC` | 500 | `0x62AB521f71431f78ac374CdbadC6cda3c8916b6C` |
| 20 | QQQ | `0xD5f3879160bc7c32ebb4dC785F8a4F505888de68` | 3000 | `0xA40D00a55d43bA2d188039DCF88bD68f4F133E78` |
| 21 | CRCL | `0xdF0992E440dD0be65BD8439b609d6D4366bf1CB5` | 10000 | `0x754DdD4bF8E8635B4301a7f4Af2Ea7A82AB6cEA7` |
| 22 | MSTR | `0xec262a75e413fAfD0dF80480274532C79D42da09` | 10000 | `0x70504a6FafdbfB75fE971FAA4dD716e79aC5624c` |
| 23 | RBLX | `0xF0C4BF4C582cb3836e98394b1d4e7B7281101bE8` | 3000 | `0x6d25417718A8D6c529130a8ccC4BfBf0a18219D3` |
| 24 | MU | `0xfF080c8ce2E5feadaCa0Da81314Ae59D232d4afD` | 10000 | `0x301F48EC369BB3bfA0bC04d44A79037aa0EE2340` |

Every route uses WETH `0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73`, factory
`0x1f7d7550B1b028f7571E69A784071F0205FD2EfA`, and the reviewed swap adapter
`0xc9F600ebaf9EE1F4a24568D2e4Af9E8df1e07D7B` with runtime codehash
`0x17b8eecc60ff9af5768240b0384e96c4e54fd8611355297e45146303294c6ac6`.
The fee-matched guards are:

- fee 500: `0xDad51edC925D4CCd46c1229763F40d1F32c7480C`, runtime codehash `0xd0d2cf2912d6344ddfaf657911a1fb2a9a4e74ecd6e829d835c18dd342f9801e`
- fee 3000: `0xd01273Fa749BF16e333cFB85D27fD11A82D1515D`, runtime codehash `0xf3919ec4ce39d29d19e96af0452d1fe53cbb2dfce2a1e7ea053d48ae7f6cfc8f`
- fee 10000: `0xf81d21e0b51A7DD815f44682B63b7e732E0b4803`, runtime codehash `0xd99afa61854a819bd0adcd593bbc8c3a9a278e5fe29cd2b6f150efe9cdc8b74d`

All use a 300-second TWAP, 1,000 bps maximum spot deviation, 750 bps output
slippage, 300-second quote validity, and 1 WETH comparison amount. `routeData` is
`abi.encode(uint24(fee))`; empty guard data selects the production guard behavior.

## Asset integrity

Every stock is an upgradeable beacon proxy. The reviewed beacon is
`0xe10b6f6B275de231345c20D14Ab812db62151b00`; its reviewed implementation is
`0xb35490d6f9163DE4F80d88dc75c3516eb64C5aE2` with runtime codehash
`0xdc07e86ee482f99641bdafb9a0d772846b167401e094d90a666b94dbdcd1eec7`.
The preflight also verifies 18 decimals, live pause state, exact transfers, and the shared beacon.
An upstream beacon or implementation change fails the gate and requires a behavior re-review.

## Deployment gate

Run immediately before freezing any raffle configuration:

```bash
forge script script/PreflightStockRoutes.s.sol:PreflightStockRoutes \
  --rpc-url https://rpc.mainnet.chain.robinhood.com
```

The preflight pins the adapter and guard runtimes, stock beacon implementation, decimals, pause
state, pool fee, observation history, guard configuration, output floor, and real swap execution.
It never broadcasts. A pass is time-bound evidence, not permanent certification.

GLD `0xC9a981FEE1F9DEc688bb123ccDeCc63D0deBFC4e` is excluded because pool
`0x26250bA84465454bc731F710E46F1f32b167d66B` did not hold the required 300 seconds of
observations during the final 2026-09-05 release preflight. GOOGL
`0x2e0847E8910a9732eB3fb1bb4b70a580ADAD4FE3` has a funded fee-100 pool at
`0x8fB9301586f27e2cff85312F7c1d0F16C6167cdE`, but is excluded until a fee-100 guard is deployed and
the same preflight passes. JNJ `0x03DfbBE0AC4E7bCDaFd08eD41A400326B77D8c80`, MRNA
`0x43B07D15cE533bEc5476d70C22a78a1B2B662155`, MRVL
`0x62fd0668e10D8B72339BE2DCF7643001688ff13B`, and SLV
`0x411eFb0E7f985935DAec3D4C3ebaEa0d0AD7D89f` have funded pools that did not pass current guarded
readiness. They must not be added optimistically.

## Prize sizing

The UI must keep every selected route's maximum single stock-conversion input at or below the
route cap in `StockRouteManifest`. Mystery mode inherits the lowest selected route cap. A fresh
preflight must pass before raising any cap.
