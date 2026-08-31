# Delta v3 liquidity deployment

Version: unversioned verified deployment
Disposition: MISS-unversioned

Sources: live verified contracts at
https://robinhoodchain.blockscout.com/address/0x6235cF6bd8419b34942F4EDDB39C880BD96dD700,
https://robinhoodchain.blockscout.com/address/0x1f7d7550B1b028f7571E69A784071F0205FD2EfA,
https://robinhoodchain.blockscout.com/address/0x73991a25C818Bf1f1128dEAaB1492D45638DE0D3,
and https://docs.uniswap.org/contracts/v3/guides/providing-liquidity/mint-a-position

## Facts

- The reviewed builder is `0x6235cF6bd8419b34942F4EDDB39C880BD96dD700`, factory is
  `0x1f7d7550B1b028f7571E69A784071F0205FD2EfA`, and position manager is
  `0x73991a25C818Bf1f1128dEAaB1492D45638DE0D3`.
- The verified builder uses `mintLadder` and returns standard v3 position NFTs to the caller.
- Position creation and removal require per-leg minimum amounts, tick bounds, and deadlines.

## Risks

- **HIGH — Weak slippage/tick/deadline data permits value extraction.** Every manual call includes
  explicit floors and the adapter checks the current tick and route code hash.
- **HIGH — Unreviewed route or dependency drift can move backing unexpectedly.** Activation binds
  adapter, entry/exit routes, builder, factory, manager, pool, and runtime hashes.
- **MEDIUM — Position-NFT custody/accounting errors can strand value.** Adapter tests cover receipt,
  tracked token IDs, collection, partial withdrawal, and full exit.

Unresolvable from public sources: no versioned Delta v4 adapter matching this interface was found.
V4 remains out of scope and disabled.
