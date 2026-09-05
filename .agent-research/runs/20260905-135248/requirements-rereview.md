# Requirements re-review

1. **Wrong assumption corrected:** Pons pair approval proves launch support; it does not prove that
   a WETH/stock pool exists. A Pons launch is the project token paired directly with the approved
   stock asset.
2. **Missing constraint:** an immutable stock-conversion raffle must reserve inventory or pass a
   live route preflight at its maximum per-slot spend before creation.
3. **Underspecified:** the existing deployed raffle generation accepts at most 16 stock routes,
   while 26 are executable now and 53 canonical assets must be representable. The next generation
   should raise the ceiling to 64.
4. **Immutable choice:** the selected stock assets, adapters, guards, and route bytes are frozen in
   each raffle. They cannot safely be filled optimistically and repaired later.
5. **Missing operational dependency:** supporting the 27 stocks without a ready direct route
   requires a funded reserve plus an authorized replenishment process. Code cannot manufacture
   that inventory.

