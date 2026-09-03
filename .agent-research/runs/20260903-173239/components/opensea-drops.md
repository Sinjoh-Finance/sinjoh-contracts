# OpenSea Drops

Version: unversioned  
Disposition: MISS-unversioned  
Primary sources: https://docs.opensea.io/llms.txt,
https://docs.opensea.io/docs/part-4-edit-drop-settings, and
https://docs.opensea.io/docs/part-5-publish-your-drop, plus the live official
https://api.opensea.io/api/v2/chains response observed 2026-09-03

## Verified facts

- The self-serve editor supports presale stages with uploaded wallet lists, prices, durations, and
  per-wallet limits.
- Current self-serve documentation says every hosted drop ends with a public sale.
- Publishing requires an onchain wallet transaction; minting begins only according to the saved
  schedule.
- Current primary-drop documentation states a 10% platform fee. This is distinct from current
  secondary-marketplace fees.
- The official OpenSea chains endpoint currently lists `robinhood` / Robinhood Chain, so the
  production drop must select Robinhood Chain rather than the Ethereum default shown in Studio.

## Assumptions and inferences

- The Piggy Banks whitelist-only requirement conflicts with the documented self-serve final public
  stage unless the collection sells out in presale or OpenSea enables a nonstandard/manual setup.
- Launch tooling must read the actual configured primary fee immediately before root generation and
  publication; it must not rely on the secondary-market fee.

## Risks

- **CRITICAL — Hosted public-stage conflict.** A required final public stage could allow wallets
  below 10,000 $INJOH to mint any unsold supply.
- **HIGH — Mutable external fee.** Hardcoding an assumed OpenSea fee without verifying the final
  editor transaction can make every paid mint revert or account the wrong proceeds.
- **MEDIUM — External publication state.** Correct contracts do not by themselves create or publish
  the hosted OpenSea drop page.

## Unresolved

- Public documentation does not describe a self-serve option for omitting the final public stage.
  A whitelist-only hosted setup must be confirmed in the actual editor or with OpenSea support.
