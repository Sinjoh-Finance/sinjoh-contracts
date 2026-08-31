# Robinhood Stock Tokens

Version: unversioned beacon deployment
Disposition: MISS-unversioned

Sources: https://docs.robinhood.com/chain/stock-tokens/,
https://docs.robinhood.com/chain/stock-token-apis/,
https://docs.robinhood.com/chain/contracts/,
https://docs.robinhood.com/chain/brand-guidelines/

## Facts

- Stock Tokens are 18-decimal ERC-20 tokenised debt securities providing economic exposure, not
  legal or beneficial ownership of the underlying share.
- Dividends and splits adjust `uiMultiplier()` while raw balances remain static. Onchain Chainlink
  prices are multiplier-adjusted; REST `/prices` values are not.
- Public copy must use “Stock Tokens,” not “tokenized stocks” or “tokenized equities.”

## Risks

- **HIGH — Ignoring multiplier semantics misstates NAV or dividend behavior.** Mitigated by the
  onchain multiplier-adjusted feed model and a release constraint of `balance-appreciation` income.
- **HIGH — Eligibility and securities restrictions are external legal requirements.** The onchain
  eligibility policy must be selected and reviewed before activation.
- **MEDIUM — Mixing REST and onchain prices double-adjusts or under-adjusts value.** V1 NAV uses the
  reviewed onchain feed only.
- **LOW — Disallowed public terminology creates brand/compliance risk.** UI and renderer copy now use
  “Stock Tokens.”

No public-source question remains unresolved.
