# Component: Robinhood Stock Tokens

**Date checked:** 2026-08-28
**Disposition:** MISS-unversioned

## Facts

- Stock Tokens are 18-decimal ERC-20 debt securities providing economic exposure rather than legal
  or beneficial ownership of the referenced securities:
  https://docs.robinhood.com/chain/stock-tokens/
- Dividends and splits are handled through `uiMultiplier()` while raw ERC-20 balances remain static.
- Robinhood's per-token Chainlink feed already includes the multiplier. Integrators must not apply
  it again when valuing one token:
  https://docs.robinhood.com/chain/oracles-and-price-feeds/
- Stock feeds operate 24/5 and may pause during corporate actions.

## Assumptions

- The collection's launch stock-token addresses remain deployment-manifest inputs.

## Inferences

- No dividend claim or sweep adapter belongs in the MVP. Direct custody captures the reinvested
  dividend exposure through the multiplier.

## Risks

**CRITICAL — restricted-holder incompatibility**

Stock Tokens carry jurisdiction and holder restrictions. Production activation remains blocked
until the collection's holder-eligibility policy has counsel approval.

**HIGH — multiplier double counting**

Applying `uiMultiplier()` to an already multiplier-adjusted feed silently overstates NAV.

## Resolved questions

**Are dividends transferred to the sleeve as a separate token?**

No. Official documentation says dividends are reinvested through the onchain multiplier.
