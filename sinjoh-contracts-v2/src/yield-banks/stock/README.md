# Piggy Banks Stock sleeve

This is the allocator-compatible, dividend-only Stock sleeve for the existing Piggy Banks collection. `StockCompositeSleeve` and `StockCompositeLPAdapter` use the existing dynamic-sleeve registration mechanism. Each bank retains its NFT, treasury account, allocator and revenue rights. Product USDG/LP/Stock targets use the existing USDG slot plus Stock and LP portions within the dynamic slot.

A bank selects one stock, or two/three distinct stocks whose internal weights total 10,000 basis points. Per-bank custody and LP units determine a nontransferable 36-decimal value-indexed `StockBankReceipt`; different bank baskets do not share pro-rata stock entitlements. The original INJOH/WETH pool supplies LP exposure through its unchanged adapter implementation.

`StockCorporateActionRegistry` is owned by the existing collection timelock. It authenticates complete, sequential issuer multiplier transitions with unique source and evidence hashes. Classification is trusted governance input; an HTTPS response, a pending event or a Chainlink price change alone cannot authorize a payout. The worker may checkpoint published actions and settle reserves but cannot publish or set owner allocations.

`StockDividendAccounting` separates principal and dividend reserve units. For a pure dividend from multiplier m0 to m1, it reserves `floor(principal * (m1 - m0) / m1)` raw units. Splits and price gains reserve zero. Later deposits start at the current checkpoint and cannot claim a previous dividend.

`StockDividendVault` pulls exact tokens from the composite, enforces isolated custody and oracle/route limits, and converts only dividend reserves. `StockDividendRoute` performs Stock → WETH → USDG. `StockDividendEscrow` credits the current NFT owner at conversion, attempts payment and retains funded credit for that wallet on delivery failure. Transfer/burn cannot redirect an already-funded credit. Unconverted reserves follow the bank. Tiny full-exit reserves at or below 100 payout base units remain backing and are not reported as cash income.

The selected loss ceiling is 1%; caller minima cannot weaken the current oracle floor. Unknown multiplier changes and unavailable prices fail closed. Composite-wide NAV depends on valid held-asset prices. The nested LP adapter supports at most 64 positions and has governed maintenance functions.

`PreparePiggyBanksStock.s.sol` deploys genuine canonical V3 registration infrastructure, seeds 0.01 ETH of deployer-funded liquidity, and prepares the existing 24-hour governance batch. `StockReleaseVerifier` checks new bindings and preserves the previous LP infrastructure in the atomic activation. The native signing runner source-pins the deployment, caps spending and requires a separate readiness record before activation. Mainnet deployment is not established until confirmed receipts exist.

Validation includes 44 Stock contract tests, the existing 12 dynamic-controller tests, mainnet-fork infrastructure/lifecycle checks and actual UI-generated single/two/three-stock + LP round trips through the original LP sleeve and back to USDG. See the platform repository's `docs/stock-strategy/PRODUCTION-INTEGRATION.md` and `OPERATIONS.md` for detailed evidence, event review, worker operation and hosted cutover.
