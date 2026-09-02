# Component: OpenSea Seaport

**Date checked:** 2026-08-31
**Version:** unversioned
**Disposition:** MISS-unversioned

## Facts

- OpenSea orders express marketplace and creator fees as consideration recipients. Source: https://docs.opensea.io/docs/opensea-fees.md
- A native ETH listing uses native consideration for both seller and fee recipients. Source: https://docs.opensea.io/docs/opensea-fees.md
- Additional recipients are payable addresses. Source: https://docs.opensea.io/docs/seaport-models.md
- Creator fees vary by collection and may not be required. Source: https://docs.opensea.io/docs/opensea-fees.md

## Assumptions and inferences

- A royalty receiver without a payable native ingress is incompatible with native-fee orders.
- Secondary earnings must never be treated as guaranteed backing.

## Risks

**CRITICAL — Native royalty recipient rejection**

Native-fee orders cannot pay a contract that rejects ETH.

**HIGH — Marketplace configuration drift**

The onchain ERC-2981 signal and OpenSea collection fee configuration may differ unless deployment verification compares both.

## Resolved questions

**Must a secondary royalty router support arbitrary sale currencies?**

Yes. Seaport consideration can use native ETH or ERC-20 assets.
