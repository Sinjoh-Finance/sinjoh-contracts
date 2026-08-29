# Requirements re-review

- **Wrong assumption corrected:** Stock Token dividends are represented through the token multiplier;
  the MVP must not add a separate dividend-claim subsystem.
- **Wrong assumption corrected:** USDG is directly held and must not be described as a lending or
  automatic yield strategy.
- **Immutable deployment inputs:** Every collection must bind its exact `$INJOH` token, pool,
  PriceHub feeds, routes, Delta builder, factory, position manager, runtime hashes, position limit,
  and allocation cap before activation.
- **Transaction inputs:** Ladder rungs, current-tick bounds, deadlines, token minima, liquidity to
  remove, conversion amount, and output floor remain explicit operator choices.
- **Scope held:** The concrete adapter uses the verified ladder builder and ordinary V3 NFT lifecycle.
  It does not add staking, zaps, automatic keepers, queued withdrawals, lending, or new governance.
