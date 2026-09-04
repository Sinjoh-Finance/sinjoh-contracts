# Piggy Banks OpenSea-only fixed-price tier launch

Piggy Banks is one configurable collection deployed through the generic Yield Banks protocol.
Nothing about the collection's name, supply, tier count, prices, dates, wallet limits, or eligibility
thresholds may be hardcoded into the generic protocol.

For this collection, minting must satisfy all of the following:

- Alpha token IDs 1-3 cost 0.5 ETH and permit at most 1 mint per wallet.
- Prime token IDs 4-33 cost 0.1 ETH and permit at most 3 mints per wallet.
- Premium token IDs 34-333 cost 0.03 ETH and permit at most 5 mints per wallet.
- Standard token IDs 334-3333 cost 0.01 ETH and permit at most 10 mints per wallet.
- The four initial allowlist windows run sequentially: Alpha, Prime, Premium, then Standard.
- Each tier opens at its configured time without requiring any earlier tier to sell out.
- After the allowlist windows, the one OpenSea public stage rotates through Alpha, Prime,
  Premium, then Standard.
- Unsold NFTs retain their tier's original price whenever that tier is reopened.
- Standard remains the ongoing public sale; unsold higher tiers may be reopened periodically at
  their original prices by rotating the one public stage.
- A cheaper tier must never mint token IDs assigned to a more expensive tier.
- Presale eligibility is proved through the collection's generated SeaDrop allowlist.
- Minting must use OpenSea and SeaDrop directly, without a custom application mint gateway.
- The complete behavior must be enforced onchain and covered by boundary, pricing, inventory,
  wallet-limit, eligibility, and adversarial tests before deployment.

The integration under research is OpenSea SeaDrop's mint callback and drop configuration surface.
