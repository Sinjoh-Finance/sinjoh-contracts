# Research plan

1. Reconstruct Pons approvals from every `PairTokenApprovalUpdated(address,bool)` event from the
   factory deployment block through the current head, then fold later changes over earlier ones.
2. Join the approved addresses to the official Robinhood registry and read token metadata and
   Pons launch economics directly from chain.
3. Enumerate WETH/stock pools for each guarded Pons V3 fee tier, quote both directions, validate
   the five-minute TWAP guard, and simulate the swap adapter at a 0.01 WETH prize size.
4. Pin runtime code hashes and guard parameters so a future upstream change fails closed.
5. Re-read Sinjoh launch and raffle contracts/UI to identify limits that are Sinjoh policy rather
   than upstream capability.

