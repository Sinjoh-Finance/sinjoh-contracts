# Component: Delta Liquidity

**Date checked:** 2026-08-28
**Disposition:** MISS-unversioned

## Facts

- Delta runs on Robinhood Chain, chain ID 4663, and documents both stake and shaped-position
  products: https://deltaliquidity.app/docs
- Stake exits return both underlying coins without an automatic swap, exit penalty, or lockup.
- Stake rewards are WETH streamed over seven days; Delta charges 1% of collected fees.
- Delta documents `DeltaPositionBuilder` at
  `0x6235cF6bd8419b34942F4EDDB39C880BD96dD700`.
- The explorer-verified `DeltaPositionBuilder` mints ordinary Uniswap position NFTs directly to
  `msg.sender`. Its constructor binds the Uniswap factory and position manager, and its source
  validates pool identity, tick ranges, deadlines, and token-transfer limits:
  https://robinhoodchain.blockscout.com/api?module=contract&action=getsourcecode&address=0x6235cF6bd8419b34942F4EDDB39C880BD96dD700
- Delta's documented single-asset `DeltaZap` at
  `0xC0b8eC7589ee49c53305517bFd53BEd708392294` did not expose verified source or ABI through the
  explorer API during this run.

## Assumptions

- `$INJOH` begins as WETH proceeds and therefore needs an explicitly reviewed conversion path
  before a two-sided position can be created.

## Inferences

- A concrete adapter cannot safely guess whether Yield Banks should use a stake, a shaped ladder,
  or a zap. The generic synchronous adapter control plane can be completed now; Delta activation
  must wait for exact `$INJOH`, pool, entry, custody, fee-claim, and exit bindings.

## Risks

**CRITICAL — incomplete entry and exit lifecycle**

Activating against an unverified zap or incomplete position lifecycle can strand collection backing
or produce a position that the redemption path cannot unwind.

**HIGH — two-asset and streamed-reward accounting**

An exit may return both `$INJOH` and WETH, while rewards can remain streamed. A concrete adapter must
define valuation and full-exit behavior for all of them.

## Resolved questions

**Can the concrete Delta adapter be safely implemented from the current requirements alone?**

No. Public sources identify a verified position builder, but the exact collection token, pool,
single-sided conversion route, chosen Delta product, and complete redemption lifecycle are not yet
bound.
