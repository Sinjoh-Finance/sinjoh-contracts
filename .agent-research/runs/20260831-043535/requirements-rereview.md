# Requirements Re-review

## Wrong assumptions

- A native-incapable ERC-20 synchronizer is not a complete OpenSea royalty receiver.
- The existing general SinjohFeeRouter cannot be inserted into the SeaDrop payout path without changing economics and receipt identity.
- ERC-2981 signaling does not guarantee creator earnings.

## Missing constraints

- Every royalty asset needs a timelock-bound, codehash-pinned route; synchronization is allocation-operator-only and must use fresh amount-specific minimum outputs and deadlines.
- NFT-owner allocation requests need one-shot execution, expiry, and an owner-selected loss ceiling.
- The OpenSea collection fee configuration must be checked against the immutable onchain royalty percentage.

## Immutable choices resolved by deployment configuration

- Per-collection ERC-2981 basis points.
- Whether the collection uses onchain tokenized equities or an offchain custody receipt, declared in the release manifest with an HTTPS disclosure.
- The proceeds vault remains the primary payout/router boundary and applies exactly the collection's configured split without the general router's additional fee.
