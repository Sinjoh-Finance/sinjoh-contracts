# Stock strategy development

`StockStrategyMath` is the arithmetic foundation for the proposed dividend-only sleeve. It validates one stock or a basket of two/three distinct assets with positive weights totaling 10,000 bps. Currency allocations conserve the input amount. Dividend reservation rounds down, preserving principal share equivalents.

It must only receive an authenticated, isolated cash-dividend multiplier transition and a correct pre-event eligible principal checkpoint. It does not authenticate an event or establish entitlement; price movements, splits and pending events must not trigger income. The same arithmetic is implemented in `@sinjoh/sdk` with matching test vectors.

## Implemented components

- `StockCorporateActionRegistry`: sequential, immutable corporate-action records with evidence hashes; checks the observed active token multiplier, rejects duplicates/future events and blocks operations during an unclassified change or oracle pause. Classification is trusted governance input. The intended owner is the existing collection timelock; an HTTPS response or Chainlink price is not an authenticated dividend event. The operational classification/review process is not deployed.
- `StockDividendAccounting`: per-bank, per-asset principal and dividend reserves. New deposits start at the current checkpoint. Splits/reverse splits reserve zero, and already-reserved units stay separate from principal. Bounded checkpoint processing handles delayed settlement.
- `StockDividendVault`: custody companion for an integrating sleeve. It pulls exact tokens from its immutable controller, attributes them to one bank, sells only that bank's reserves over a governance-bound route, enforces the existing PriceHub's validity checks and an immutable loss limit, and settles exact proceeds through the escrow. Principal withdrawals return only to the controller. Final principal exit is blocked while token dividends remain unconverted.
- `StockDividendEscrow`: funded cash credits, duplicate-conversion protection, current-owner resolution at settlement and best-effort wallet delivery. Failed delivery preserves the credited wallet's claim, including after NFT transfer/burn. No arbitrary payout recipient or admin sweep exists.

The payout policy crystallizes ownership when dividend tokens are converted and cash is credited. Before conversion the reserve belongs to the bank; after conversion the cash credit belongs to that wallet. This avoids stranding an already-earned cash credit when the NFT subsequently transfers or burns. This policy must be disclosed in the final product.

## Integration boundary

These components are local, unactivated code. **`StockDividendVault` is not an allocator-compatible sleeve** and does not acquire spending authority over existing bank treasuries. The integrating sleeve must implement owner-bound basket selection, isolated receipt valuation, LP/Stock composition, permissionless revenue handling, admission/proxy identity checks and the complete allocator redemption/burn path. It must never burn the final bank receipt while principal or unconverted reserves remain in this vault. Tests use an explicit controller harness; they do not prove that the deployed allocator already calls it.

The unchanged mainnet LP extension was separately proven to register, fund and exit a new dynamic sleeve. That is a custody-extension proof, not proof of the owner-specific Stock+LP strategy. The deployed allocator supports one active dynamic destination; replacing the existing Delta factory's source hashes would disable entry into older foundations. Neither limitation is bypassed or silently changed here.

The vault accepts a configured loss ceiling no greater than 500 bps; that constructor ceiling is not a recommendation or a selected production parameter. Its actual limit, eligible assets, route graph, governance review process and implementation/proxy bindings must be in the release artifact. The registry's manifest hash is evidence provenance, not proof that a token is economically or legally eligible. All catalog assets remain disabled for allocation.

No contract has been broadcast and no production funds have moved. See the platform's `docs/stock-strategy/DIVIDEND-IMPLEMENTATION.md` for test evidence and the exact remaining release boundary.

Validation: `forge test --match-contract 'Stock(Dividend|CorporateAction|StrategyMath)' -vv`.
