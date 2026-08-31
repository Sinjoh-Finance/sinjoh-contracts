# OpenSea Seaport / creator earnings

Version: 1.6 deployed at `0x0000000000000068F116a894984e2DB1123eB395`
Disposition: MISS-unversioned

Sources: https://support.opensea.io/en/articles/8867026-how-do-i-set-creator-earnings-on-opensea,
https://eips.ethereum.org/EIPS/eip-2981

## Facts

- ERC-2981 communicates royalty recipient and amount; it does not force payment.
- OpenSea settings permit optional creator earnings for a custom contract that is not using an
  enforcement standard.

## Risks

- **HIGH — Secondary royalty revenue is not guaranteed.** The release gate can verify the observed
  OpenSea setting and immutable ERC-2981 intent, but the product must not promise marketplace-wide
  enforcement.

No public-source question remains unresolved.
