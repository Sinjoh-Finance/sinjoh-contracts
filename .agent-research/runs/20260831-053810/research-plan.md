# Research plan

1. OpenSea: read official SeaDrop deployment/settings docs and source; inspect all enumerable mint
   configuration getters, payout behavior, ownership requirements, and creator-earnings limits.
2. Robinhood Chain: verify chain IDs, native gas/payment asset, canonical WETH/USDG addresses, RPC
   production guidance, and live bytecode.
3. Stock Tokens and feeds: verify decimals, `uiMultiplier()`, corporate-action behavior, oracle
   adjustment, API differences, disclosures, brand terminology, proxy/beacon implementations.
4. Delta/Uniswap: inspect verified live builder/factory/position-manager bindings and v3 position,
   slippage, deadline, and custody semantics.
5. Viem/Wagmi/Envio/OpenZeppelin: reuse unchanged cached research, then verify the implementation
   follows simulation-before-write, chain checks, receipt checks, exact event declarations, and safe
   initialization/ownership patterns.
6. Compile Solidity, compare every SDK ABI function record to artifacts, decode representative
   calldata, run unit/fuzz/invariant/integration tests, and inspect repository diffs.
