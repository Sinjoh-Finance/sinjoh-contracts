# Yield Banks Delta pool-selection requirement

Date: 2026-08-31

The existing Yield Banks requirements remain in `YIELD-BANKS-DEVELOPMENT-PLAN.md`, except that the
market-making option must not be hard-coded to `$INJOH`/WETH. A Yield Bank owner should be able to
select an existing Delta V3 pool. The implementation must preserve per-NFT economic attribution,
must not expose one holder to another holder's selected pool, and must retain manual execution,
slippage limits, eligibility controls, runtime-codehash binding, and extensibility.

The unrequested operations-reserve component and all operations fee legs must also be removed.
