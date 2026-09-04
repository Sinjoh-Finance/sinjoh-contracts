# Yield Bank sequential mint requirements

- Keep the Yield Bank protocol collection-agnostic. No Piggy Banks names, addresses, prices,
  quantities, weights, or holder thresholds may be compiled into protocol behavior.
- Support an ordered, collection-configured set of paid mint stages.
- Each stage has a cumulative token-supply boundary, a native-token mint price, an exact
  SeaDrop platform fee, and a per-wallet limit that applies to that stage rather than to the
  whole collection.
- A stage cannot mint tokens assigned to a later stage.
- Support SeaDrop Merkle allowlists without permitting a zero-proceeds mint to leave an
  unbacked Yield Bank.
- Piggy Banks is the first configuration:
  - Alpha: token IDs 1-3, 30x fee weight, 0.5 native token, one mint per wallet.
  - Prime: token IDs 4-33, 7.5x fee weight, 0.1 native token, three mints per wallet.
  - Premium: token IDs 34-333, 2.5x fee weight, 0.03 native token, five mints per wallet.
  - Standard: token IDs 334-3333, 1x fee weight, 0.01 native token, ten mints per wallet.
- Piggy Banks whitelist eligibility is derived from a frozen $INJOH holder snapshot and
  cascades downward:
  - at least 10,000,000 $INJOH: Alpha, Prime, Premium, and Standard;
  - at least 1,000,000 $INJOH: Prime, Premium, and Standard;
  - at least 100,000 $INJOH: Premium and Standard;
  - at least 10,000 $INJOH: Standard;
  - below 10,000 $INJOH: ineligible.
- Verify source behavior against the canonical SeaDrop implementation and current official
  OpenSea Drops documentation before implementation.
