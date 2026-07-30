# Sinjoh clear-signing descriptors

These ERC-7730 descriptors give compatible wallets human-readable intent and
field labels for Sinjoh's launch authorization and launch transactions.

They are additive metadata only. They do not change calldata, selectors,
contract execution, or deployed contract addresses. Wallets that do not yet
support ERC-7730 continue to receive the standard transaction request, while
the Sinjoh UI shows the same intent before requesting a signature.

Validate them with:

```sh
uvx erc7730 lint clear-signing/*.json
```

Wallet-wide availability requires publishing the reviewed descriptors through
a registry or wallet integration that supports Robinhood Chain testnet.

The deterministic factory deployment can be decoded by its fixed factory
address. The following launch call targets a newly created router clone, so the
Sinjoh UI also renders the full plain-English intent before opening the wallet;
registries that require every clone address cannot pre-register that second
transaction.
