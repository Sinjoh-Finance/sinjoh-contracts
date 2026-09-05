# Robinhood Chain asset registry

Status: fresh, unversioned source.

Official sources:

- `https://api.robinhood.com/rhj/assets`
- `https://docs.robinhood.com/chain/contracts/`
- `https://docs.robinhood.com/chain/stock-tokens/`

Facts:

- The registry returned 53 canonical Pons-approved stock/ETF addresses; every one has status
  `ACTIVE` and 18 decimals.
- All 53 use the same beacon `0xe10b6f6B275de231345c20D14Ab812db62151b00` and the beacon currently
  resolves to implementation `0xb35490d6f9163DE4F80d88dc75c3516eb64C5aE2`.
- The official docs describe standard ERC-20 transfers, Chainlink price feeds, and a separate
  `uiMultiplier()` used for corporate-action display adjustments. Raw balances do not track that
  multiplier.
- Fractional market status is `TRADABLE` for 52 assets and `UNTRADABLE` for WYFI
  `0x9e7ABD3C9139D14E4c86DcE0e455AAB7A0C2FB3E`.
- `https://docs.robinhood.com/llms.txt` returned 404 during this run.

Risks:

- HIGH — the stock beacon is upgradeable; an implementation change can alter payout behavior for
  every immutable raffle and must force a fresh review.
- MEDIUM — stock-token transfer availability and market acquisition are jurisdiction- and
  authorization-dependent; a reserve replenisher cannot assume public primary-market access.

