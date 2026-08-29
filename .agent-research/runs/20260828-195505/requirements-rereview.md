# Requirements Re-review

- **Sound:** Directly hold Stock Tokens and USDG.
- **Wrong assumption corrected:** Stock Token dividends are not separately paid to a collection
  contract; they are reinvested through the token multiplier.
- **Sound:** Keep one small, synchronous adapter extension point for manually operated positions.
- **Missing constraint:** The concrete `$INJOH` token, Delta product, pool, and WETH-to-`$INJOH`
  conversion route are not supplied.
- **Immutable choice:** Every activated adapter and venue must be bound by address and runtime code
  hash in the deployment manifest.
- **Implementation consequence:** Remove USDG lending, canary promotion, queued withdrawals,
  risk-class/audit metadata, and generic harvesting. Do not activate a concrete Delta adapter yet.
