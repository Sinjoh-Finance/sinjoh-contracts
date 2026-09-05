<!-- BRAINBLAST:CACHE slug=pons-v3-routes version=0xec72b1abd1f2faee020cfea9c646bd8994f9fb389054f6e574f103a895091739 fetched=2026-09-05 -->
# Pons V3 raffle routes

Status: fresh this run.

Official/live source: Robinhood Chain RPC at `https://rpc.mainnet.chain.robinhood.com`.

Pinned dependencies:

- Factory `0x1f7d7550B1b028f7571E69A784071F0205FD2EfA`, runtime codehash
  `0xec72b1abd1f2faee020cfea9c646bd8994f9fb389054f6e574f103a895091739`.
- WETH `0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73`, runtime codehash
  `0x5706be52f64875fee65a2cec0d80e47a23d8793cbe85d214b48445e2d05f5353`.
- Quoter `0x33e885eD0Ec9bF04EcfB19341582aADCb4c8A9E7`, runtime codehash
  `0x3db0868d945e9304c9bc6a8b2181948109ea617647142f3c4083e14393496a28`.
- Swap adapter `0xc9F600ebaf9EE1F4a24568D2e4Af9E8df1e07D7B`, runtime codehash
  `0x17b8eecc60ff9af5768240b0384e96c4e54fd8611355297e45146303294c6ac6`.
- Fee-500 guard `0xDad51edC925D4CCd46c1229763F40d1F32c7480C`.
- Fee-3000 guard `0xd01273Fa749BF16e333cFB85D27fD11A82D1515D`.
- Fee-10000 guard `0xf81d21e0b51A7DD815f44682B63b7e732E0b4803`.

Facts:

- All guards use a 300-second TWAP, 1,000 bps maximum spot deviation, 750 bps output slippage,
  300-second validity, and 1 WETH comparison amount.
- At 0.01 WETH, 26 distinct stocks pass pool, TWAP, quote, and buy/sell execution checks.
- GOOGL has a funded 0.01% pool at `0x8fB9301586f27e2cff85312F7c1d0F16C6167cdE`, but no corresponding
  fee-100 guard is deployed.
- JNJ, MRNA, MRVL, and SLV have funded pools whose current guarded route fails readiness.
- The other 22 stocks have no funded direct pool in the checked fee tiers.

Risks:

- HIGH — configuring an immutable raffle with an unexecutable route permanently degrades the
  affected reward slots.
- HIGH — pricing a different fee-tier pool from the one the adapter executes can produce a valid
  quote for the wrong market.
- MEDIUM — route readiness is time-dependent; every deployment must rerun the live preflight at
  the configured maximum per-slot prize.

