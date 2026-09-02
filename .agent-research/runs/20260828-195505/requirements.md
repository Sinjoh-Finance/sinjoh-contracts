# Simplified Yield Banks Holdings Requirements

Yield Banks initially supports exactly three collection holdings:

1. Robinhood Stock Tokens held directly for total-return exposure, including reinvested dividends.
2. USDG held directly, with no lending venue.
3. Manually managed Delta `$INJOH/WETH` liquidity positions.

The system must remain able to add reviewed adapters later without deploying a generalized strategy
framework now. Primary proceeds remain idle until the configured allocation operator acts. The
implementation must remove the USDG lending adapter, canary promotion, asynchronous withdrawals,
strategy risk classes, and unused harvest machinery. A concrete Delta adapter must not infer an
unverified swap, pool, position, or exit lifecycle.
