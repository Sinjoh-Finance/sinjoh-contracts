# Yield Banks transaction-integrity research

## Executive Summary

Yield Banks is a configurable OpenSea-minted ERC-721 whose net primary proceeds are held for manual
allocation across Stock Tokens, USDG, and a reviewed Delta v3 $INJOH/WETH LP adapter. NFT owners can
request full reallocation of existing backing; an authorized operator executes within owner-selected
loss, expiry, route, and slippage bounds.

**Verdict: Build with caution.** The transaction architecture and implemented ABI surfaces are
internally consistent, but activation must remain gated on a collection-specific mainnet manifest,
real dependency/code hashes, legal eligibility review, OpenSea configuration, and an independent
smart-contract audit. The top risk is treating external configuration—especially SeaDrop pathways,
upgradeable asset implementations, feeds, and routes—as static. The key irreversible decision is the
collection's deployment-time supply/economics/policy configuration. The biggest remaining spec gap is
the actual eligibility policy and production addresses for the first collection.

No engineering review can truthfully guarantee that a new financial protocol will have “no issues.”
This run instead makes every known transaction path typed, simulated/tested, and release-verifiable,
and states the external risks that code cannot eliminate.

## Risk Heatmap

| Component | Critical | High | Medium | Low |
|---|---:|---:|---:|---:|
| OpenSea SeaDrop | 0 | 2 | 0 | 0 |
| OpenSea Seaport | 0 | 1 | 0 | 0 |
| Robinhood Chain | 0 | 1 | 1 | 0 |
| Stock Tokens | 0 | 2 | 1 | 1 |
| USDG | 0 | 1 | 0 | 0 |
| Delta v3 | 0 | 2 | 1 | 0 |
| Chainlink feeds | 0 | 1 | 1 | 0 |
| OpenZeppelin | 0 | 0 | 1 | 1 |
| Viem | 0 | 1 | 1 | 0 |
| Wagmi | 0 | 1 | 1 | 0 |
| Envio | 0 | 2 | 1 | 0 |
| Uniswap v3/v4 | 0 | 1 | 2 | 0 |
| **Total** | **0** | **15** | **10** | **2** |

High risks are: alternate SeaDrop paths/wrong payout; premature ownership handoff; optional secondary
royalties; network/dependency mixing; Stock Token multiplier mistakes; external eligibility rules;
USDG implementation drift; Delta slippage; Delta dependency drift; invalid/stale feeds; unsimulated
calldata; wrong wallet chain; missing Envio events; wrong indexer start block; and concentrated-
liquidity slippage. The implementation or release gate mitigates each, except that optional royalties,
legal eligibility, market risk, provider reliability, and third-party governance remain external.

## Components researched

| Component | Version | Status |
|---|---|---|
| OpenSea SeaDrop | unversioned deployed instance | Fresh this run |
| OpenSea Seaport | 1.6 deployed instance | Fresh this run |
| Robinhood Chain | mainnet 4663 | Fresh this run |
| Stock Tokens | unversioned beacon deployment | Fresh this run |
| USDG | unversioned EIP-1967 deployment | Fresh this run |
| Delta v3 | unversioned verified deployment | Fresh this run |
| Chainlink feeds | unversioned per feed | Fresh this run |
| OpenZeppelin Contracts | 5.6.1 | Reused from cache (fetched 2026-08-27) |
| Viem | 2.55.19 / 2.55.10 | Reused from cache (fetched 2026-08-24) |
| Wagmi | 2.19.5 | Reused from cache (fetched 2026-08-24) |
| Envio HyperIndex | 3.2.1 | Reused from cache (fetched 2026-08-24) |
| Uniswap v3/v4 | v3 unversioned / v4 core 1.0.2 | Reused from cache (fetched 2026-08-27) |

## What a coding or deployment agent must know

1. SeaDrop primary mint value is native ETH. Its configured fee is removed before net payout reaches
   the YieldBankProceedsVault; configurable Sinjoh/creator/operations/backing splits apply to that net.
2. YieldBankNFT accepts only the pinned SeaDrop, paid callback-visible stages, and an empty opaque
   allowlist. The release hash includes public stage, allowlist root, fee recipients, payers, token-
   gated stages, signers, and signed-validation bounds.
3. Configure OpenSea while `openSeaManager` owns the NFT, call `transferOwnership(timelock)`, then have
   the timelock call `acceptOwnership()`. Activation fails until the final owner is the timelock.
4. Use chain 4663 and managed RPC providers. WETH is
   `0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73`; USDG is
   `0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168`; SeaDrop is
   `0x00005EA00Ac477B1030CE78506496e8C2dE24bf5`; Seaport is
   `0x0000000000000068F116a894984e2DB1123eB395`.
5. Bind proxy/beacon implementations, not just proxy runtime. A later implementation change requires
   re-review and a fresh manifest.
6. Treat Stock Token dividend/split effects as multiplier-aware balance appreciation. Do not combine
   raw REST prices with already adjusted onchain feeds.
7. Every wallet write must simulate with the actual account and chain, submit the simulation request,
   wait for a successful receipt, handle replacement/observation failures, and reconcile canonical
   state. The UI already follows this sequence.
8. Manual allocator/adapter calls require explicit route data, output/share floors, loss limits, tick
   bounds, position actions, and deadlines. The keeper never invents these values.
9. Envio indexes only declared events from the configured address/start block; deploy and fully sync a
   new index before relying on it for holder/accounting state.
10. ERC-2981 and the observed OpenSea setting do not guarantee secondary royalties.

## Pre-deployment decisions required

- First collection supply, mint price/stages, configurable split percentages, default sleeve weights,
  royalty rate, eligibility policy, Stock Token list, feeds, $INJOH/WETH pool, and role addresses.
- Independent audit scope and audit hash.
- Legal eligibility/disclosures for Stock Tokens and supported jurisdictions.
- Production RPC/indexer providers and monitoring thresholds.

## Requirements corrections

- Buyers pay native ETH through SeaDrop, not WETH directly. WETH is the internal accounting/allocation
  asset after manual execution.
- There is no sellout escrow, success threshold, deadline release, or refund mechanism.
- Supply and economics are collection configuration, never fixed to 3,000 or hard-coded percentages.
- Public language uses “Stock Tokens.”
- Secondary royalty synchronization is best-effort external revenue, not guaranteed backing.

## What this research prevents

It prevents mainnet/testnet dependency mixing, proxy implementation blind spots, unbound SeaDrop mint
paths, zero-proceeds allowlists, wrong payout routing, unusable OpenSea ownership, multiplier double-
counting, hand-built ABI tuple drift, unsimulated UI writes, and silent indexer omissions.

Run summary: 7 components researched fresh and 5 reused from cache. `--fresh` forces full re-research.
