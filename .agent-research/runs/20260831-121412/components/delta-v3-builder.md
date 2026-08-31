# Component: Delta V3 builder deployment

**Date checked:** 2026-08-31
**Version:** unversioned live deployment
**Disposition:** MISS-unversioned

**Sources:**
- https://robinhoodchain.blockscout.com/address/0x6235cF6bd8419b34942F4EDDB39C880BD96dD700
- https://robinhoodchain.blockscout.com/address/0x1f7d7550B1b028f7571E69A784071F0205FD2EfA
- https://robinhoodchain.blockscout.com/address/0x73991a25C818Bf1f1128dEAaB1492D45638DE0D3
- live JSON-RPC reads on chain 4663 through https://rpc.mainnet.chain.robinhood.com

## Facts

- The live builder at `0x6235cF6bd8419b34942F4EDDB39C880BD96dD700` reports factory
  `0x1f7d7550B1b028f7571E69A784071F0205FD2EfA`, position manager
  `0x73991a25C818Bf1f1128dEAaB1492D45638DE0D3`, and WETH
  `0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73`.
- The builder accepts a pool address when minting a ladder. The pool is not intrinsically limited
  to `$INJOH`/WETH by the builder interface.
- Positions are ordinary V3 ERC-721 position NFTs returned to the caller.

## Assumptions

- “Delta” in the product requirement refers to this live builder/factory/position-manager stack.

## Inferences

- The existing adapter's `injoh` field is product hard-coding around a generic second pool token;
  it can be renamed without changing the external builder call shape.
- One adapter instance remains pool-specific because it owns and accounts for positions from one
  immutable pool.

## Risks

**HIGH — Shared-sleeve adapters do not provide owner-specific pool choice.** If multiple pool
adapters sit inside one fungible sleeve, every sleeve shareholder owns a pro-rata mixture of all
pools, regardless of the pool selected in the UI.

**HIGH — Unversioned deployment identity can drift operationally.** Every adapter must bind the
builder, factory, manager, pool, routes, and their runtime hashes; release verification must read
them back from chain 4663.

**MEDIUM — Position-NFT custody can strand assets.** Pool-specific custody must reject unsolicited
NFTs and prove full enumeration, collection, proportional withdrawal, and complete exit.

## Resolved questions

**Is `$INJOH` required by the live builder?**

No. Live contract reads show the builder binds WETH, its V3 factory, and its position manager; the
pool address is supplied to the ladder-mint call. The current `$INJOH` restriction is local adapter
configuration.

**Is there versioned public Delta documentation for this exact deployment?**

Unresolvable from public sources. The official explorer and live contract reads were checked; the
integration must therefore be treated as an unversioned onchain deployment and bound by code hash.
