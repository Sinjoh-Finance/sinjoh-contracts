# Implementation and rollout plan

## Stage 1 — ship current maximum support

1. Merge the UI stock snapshot and live approval-delta discovery. Result: all 53 canonical stock
   tokens are launch choices, plus the other approved Pons pairs USDG and cbBTC. Every choice is
   still approval- and economics-checked against the factory before signing.
2. Merge the 26-route certified raffle manifest. Result: any of the 26 can be selected for a
   fixed-stock raffle on the current deployed factory. Mystery mode uses a 16-route subset because
   the live immutable implementation cannot accept more.
3. Keep the immutable per-round cap at or below 0.01 WETH for this route certification and rerun
   `PreflightStockRoutes` immediately before release.

## Stage 2 — remove the legacy mystery ceiling

1. Deploy a new standalone `SinjohRaffleRewards` implementation/factory generation and a new
   Project V2 generation from the tested 64-route code.
2. Record full deployment addresses, runtime codehashes, and blocks in the release manifest.
3. Re-run the 26-route preflight against the exact new maximum prize, then move all 26 certified
   stocks into mystery mode.
4. Preserve existing raffles and factories; generations are immutable and are not upgraded in
   place.

## Stage 3 — unlock the next five market routes

1. Deploy a five-minute fee-100 guard and preflight GOOGL's funded pool. Add GOOGL only after a
   real buy/sell pass.
2. Recheck and, where operationally appropriate, prime or deepen the funded JNJ, MRNA, MRVL, and
   SLV pools. Add each independently after it passes at the intended prize size.

## Stage 4 — fulfill the no-pool stocks from reserve

1. Deploy a protocol-owned stock reserve with per-asset free, reserved, and committed balances.
2. Quote and reserve the exact stock amount before raffle creation; make creation atomic with the
   reservation so concurrent launches cannot overbook inventory.
3. Deliver already-denominated stock directly. Use Pons direct/multihop acquisition for
   replenishment only when the route meets policy, otherwise use an authorized acquisition
   process.
4. Release reservations on cancellation or failed creation, reconcile every delivery by balance
   delta, and retain WETH fallback only for unexpected execution failures.
5. Expose all 53 stocks in raffle configuration, showing availability from market route plus free
   reserve rather than from a static supported/unsupported list.
