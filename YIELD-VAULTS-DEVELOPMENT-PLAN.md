# Yield Vaults — Development and Delivery Plan

> **Superseded historical plan:** use `YIELD-BANKS-DEVELOPMENT-PLAN.md`, version 2.0.
> No requirement, default, integration, or naming choice in this file is canonical.

**Status:** Superseded historical planning record
**Prepared:** 2026-08-27
**Source architecture:** `YIELD-VAULTS-BLUEPRINT.md`
**Feasibility research:** `.agent-research/runs/20260827-215719/final-report.md`
**Target network:** Robinhood Chain (mainnet chain ID `4663`; testnet chain ID `46630`)

## 1. Purpose and planning rule

This document turns the Yield Vaults concept into work that can be assigned, implemented, reviewed, tested, audited, and released. It does not silently promote recommendations from the architecture blueprint into product requirements.

Every statement in this plan is classified as one of:

- **Confirmed:** explicitly requested by the product owner.
- **Recommended:** a design proposal that requires approval before it becomes a requirement.
- **Conditional:** technically feasible only after the named dependency is verified.
- **Blocked:** implementation or production release cannot proceed until the named evidence or authority exists.

The development team must stop at **Gate 0** if a decision changes economics, ownership, redemption, or third-party integration behavior. Engineers may build isolated mocks and generic primitives before those decisions, but must not encode an unapproved choice into production contracts.

## 2. Confirmed product requirements

The following requirements are confirmed from the product discussion:

1. Launch one collection capped at exactly **3,000 NFTs**.
2. Each NFT represents its own isolated treasury/economic account.
3. NFT treasuries can have exposure to:
   - Stock Tokens;
   - liquidity positions on Delta; and
   - a USDG sleeve that deploys capital into configured lending strategies.
4. The protocol must support adding new strategy implementations in the future without replacing the NFT collection.
5. The architecture must keep three understandable portfolio categories:
   - Core Stock Token sleeve;
   - Market-Making sleeve using Delta strategy adapters; and
   - USDG Yield sleeve supporting lending adapters and future configured strategies.
6. Each token ID must remain associated with its own treasury. The exact owner-control, operator, transfer, and redemption rules are intentionally left open under D4, D13, and D15.
7. Redemption charges exactly **5% of every asset redeemed** while more than one NFT remains. The charge is redistributed in kind to the remaining live NFTs. The final NFT is exempt and receives the remaining distributor dust.

Everything else—including mint price, primary-sale percentages, allocation weights, royalty behavior, sale mechanics, redemption outputs, governance membership, asset selections, and launch protocols—remains subject to an explicit decision below.

`YIELD-VAULTS-BLUEPRINT.md` labels several of those recommendations “settled.” That label records the prior architecture proposal; it is not evidence of explicit product-owner approval. Because this plan was requested without feature assumptions, those choices remain open until the decision log records approval.

## 3. Feasibility conclusions

| Capability | Status | Evidence and constraint | Development consequence |
|---|---|---|---|
| 3,000 isolated NFT accounts | Verified | Deterministic minimal-proxy accounts and per-token accounting are standard EVM patterns; existing Sinjoh V2 uses deterministic clones | Build one deterministic account per token ID; do not deploy 3,000 full strategy stacks |
| Per-NFT economic isolation at scale | Verified with architecture condition | Holding shares in three collection sleeves avoids 3,000 copies of every external position | Each account owns sleeve shares; sleeves own external assets |
| Bearer-style ownership transfer | Verified | Current ERC-721 ownership controls the token account and transfers the complete economic claim | Use normal ERC-721 transfer semantics with no additional protocol transfer registry |
| Equal distributions to live NFTs | Verified | Accumulator accounting avoids looping over all NFTs | Use a high-precision per-live-NFT accumulator and per-account debt checkpoints |
| Delta v3 LP and staking lifecycle | Conditional | The builder is verified, but the exact stake/farm/zap/manager interfaces still need to be resolved | Full LP fees and staking/reward support are required scope; implementation starts by obtaining exact contracts, ABIs, and fork behavior |
| Delta fee and reward harvesting | Conditional | Delta documentation describes fees, WETH streaming, claim fee, and withdrawal behavior | Implement and test trading fees, staking rewards, streaming, and withdrawal as one complete integration |
| Stock Token custody and transfer | Conditional | Exact Stock Token contracts and token-level transfer behavior have not been selected | Use the signed asset manifest and propagate the actual token contract behavior without adding another transfer gate |
| Stock Token valuation | Conditional | Official price feeds are available, but feed addresses and the Robinhood Chain sequencer feed must be selected and verified | PriceHub cannot be finalized before the signed asset/feed manifest |
| USDG lending | Conditional | No lending venue has been selected | Select the production lending venue and implement its exact deposit, yield, withdrawal, loss, and receipt-token behavior |
| Future strategies | Verified with governance condition | Immutable, allowlisted adapters can be added through a registry and timelock | No arbitrary calls or `delegatecall`; every new adapter is a separate reviewed version |
| Atomic NFT redemption | Verified if output is sleeve shares | External protocols can pause or revert, so atomic underlying unwinds are not dependable | Recommended burn transfers sleeve shares; optional unwinding is a separate user action |
| Existing Sinjoh V2 revenue routing | Blocked pending design choice | Current router restricts sinks to registered same-project modules | Select a successor router/module or a purpose-built source bridge; do not bypass identity checks |
| Production launch | Blocked | Exact asset/feed/pool/lending manifests, the complete Delta lifecycle, production infrastructure, audit, and launch authority are unresolved | Local/testnet work can proceed; mainnet cannot |

Authoritative references used by the research pass:

- Robinhood Chain: <https://docs.robinhood.com/chain/>
- Robinhood Stock Tokens: <https://docs.robinhood.com/chain/stock-tokens/>
- Robinhood Chain price feeds: <https://docs.robinhood.com/chain/oracles-and-price-feeds/>
- Delta documentation: <https://deltaliquidity.app/docs>
- Verified Delta v3 builder source: <https://robinhoodchain.blockscout.com/address/0x6235cF6bd8419b34942F4EDDB39C880BD96dD700?tab=contract>

Known onchain addresses for integration planning:

| Component | Robinhood Chain address | Status |
|---|---|---|
| Delta v3 builder | `0x6235cF6bd8419b34942F4EDDB39C880BD96dD700` | Verified source |
| WETH | `0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73` | Research-verified; recheck in release manifest |
| USDG | `0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168` | Research-verified; recheck in release manifest |

No other address is authorized by this document. Every pool, Stock Token, feed, sequencer feed, lending vault, router, farm, manager, distributor, and recipient address must be supplied in a signed deployment manifest with chain ID, bytecode hash, source, and approval evidence.

## 4. Decisions required before feature freeze

The recommendations below are architecture proposals, not approved features.

| ID | Decision | Options | Recommendation | Blocks |
|---|---|---|---|---|
| D1 | Primary-sale economics | Set vault/creator/Sinjoh/operations percentages | Do not encode the illustrated `80% / 10% / 5% / 5%` until approved | Sale router, financial tests, disclosures |
| D2 | Initial sleeve allocation | Set Stock/Delta/USDG percentages | Treat illustrated `50% / 35% / 15%` as a proposal; approve exact bounds and rounding | Sale settlement, rebalancing, metadata |
| D3 | Sale model | Fixed price all-or-refund, rolling mint, auction, allowlist phases | Fixed-price escrow with exact-3,000 success and full refund on failure | SaleEscrow state machine |
| D4 | Redemption output | Underlying assets, sleeve shares, or asynchronous unwind | Atomic burn for sleeve shares; optional separate unwind | NFT burn, account, sleeve interfaces |
| D5 | Stock Token contract behavior | Record the selected tokens' actual transfer, pause, freeze, and return-value behavior | Propagate the underlying token result without adding a separate protocol transfer gate | Asset manifest and fork tests |
| D6 | Asset manifest | Exact three Stock Tokens, pools, fees, tick ranges, feeds, decimals, trading calendars | Versioned signed manifest; no contract literals outside the manifest | PriceHub and external adapters |
| D7 | Package placement | Add to `sinjoh-contracts-v2` or create `sinjoh-yield-vaults` | New Foundry package for an independent audit/release lifecycle; reuse libraries, not storage | Repository scaffolding and CI |
| D8 | Existing project revenue path | Successor router action/module or direct authenticated bridge | New explicit router action/module with invariant-preserving destination registration | RevenueRouter integration |
| D9 | USDG lending venue | Select the exact production protocol/vault | Deploy the USDG allocation into the selected lending venue at launch; any temporarily uninvested USDG is transaction liquidity, not the strategy | Lending adapter and mainnet allocation |
| D10 | Governance composition | Multisig members, quorum, timelock, guardian, emergency powers | Separate delayed governance from narrow pause-only guardian | Registry, timelock, runbook |
| D11 | Royalties and ongoing fees | None or exact percentages, recipients, and sunset rules | Specify separately from protocol yield; never rely on royalties for solvency | Revenue router and marketplace metadata |
| D12 | Dynamic artwork | Static metadata, live NAV/yield traits, or hybrid | Launch static base art plus verifiable read-only portfolio traits | Metadata/indexer/UI scope |
| D13 | Bound-token burn | Disable bound-token burn, unwrap before burn, or support pro-rata bound claims | Disable burn while non-transferable/unclaimable assets exist | Redemption safety |
| D14 | Launch and canary policy | Allocation caps, loss limits, observation window, escalation authority | Per-adapter and collection caps with staged enablement and exit-only state | Release and operations |
| D15 | NFT ownership and control | Bearer claim follows ERC-721 ownership or uses separate treasury-operation approvals | Bearer claim controlled by current ERC-721 owner; operators may transfer the NFT but cannot execute treasury actions unless separately authorized | NFT/account authority and approvals |
| D16 | Redemption charge | **Closed by product owner:** 5% in-kind redistribution | Charge 5% of each redeemed asset when another live NFT remains; final NFT is exempt and receives remaining dust | Fixed requirement for burn accounting, tests, and UI |

### Gate 0 exit criteria

Gate 0 passes only when:

- D1–D16 have dated decisions and named approvers in `docs/yield-vaults/decision-log.md`;
- the product owner has approved the complete fund-flow diagram and every fee recipient;
- the team has chosen the package/repository and integration ownership boundaries;
- no unresolved decision can change storage layout, ownership, redemption, or sale accounting; and
- acceptance criteria in this plan have been approved by engineering, security, operations, and product.

## 5. Target system architecture

The recommended architecture is:

```text
NFT owner
   │ owns ERC-721 token ID
   ▼
Deterministic YieldVaultAccount(token ID)
   ├── CoreStockTokenSleeve shares
   ├── MarketMakingSleeve shares
   └── USDGYieldSleeve shares
           │
           └── approved immutable strategy adapters

Collection sleeves own the real external assets:
   Stock Tokens │ Delta/Uniswap v3 positions │ USDG/lending receipts

Ongoing revenue
   → authenticated CollectionRevenueRouter
   → YieldVaultDistributor accumulator
   → equal claim per live NFT
   → token account
   → sleeve deposits according to approved allocation
```

This separates four concerns:

1. **Ownership:** the NFT owner controls the token account's allowed lifecycle actions.
2. **Accounting:** the account holds independently measurable sleeve shares.
3. **Execution:** collection sleeves and adapters interact with external protocols.
4. **Governance:** a timelock queues configuration changes before they execute, preventing an administrator from changing strategy targets or limits instantly. A separate guardian is an emergency brake: it may stop new deposits or rebalances, but it cannot withdraw treasury assets, change recipients, or activate a strategy. Holder transfers, claims, and redemption remain available under their normal rules.

The system must not use a loop across 3,000 NFTs for revenue allocation, strategy operation, transfer, or redemption.

## 6. Delivery model

### 6.1 Work-size vocabulary

Sizes are review scope, not calendar estimates:

- **S:** one focused change, normally one production contract/module and its tests.
- **M:** several connected modules with one trust boundary.
- **L:** cross-contract or cross-repository behavior requiring integration tests.
- **XL:** economic/security subsystem requiring a dedicated threat model and audit attention.

No schedule is asserted. Calendar planning requires team composition, reviewer availability, audit vendor capacity, and external protocol access. The delivery lead must estimate dates only after those inputs are named.

### 6.2 Required roles

| Role | Responsibility |
|---|---|
| Product owner | Approves economics, user flows, asset choices, and launch criteria |
| Protocol architect | Owns invariants, contract boundaries, storage, and change control |
| Solidity core engineer | NFT, accounts, accounting, registries, sale, redemption |
| Strategy integration engineer | Delta, Stock Token, oracle, and lending adapters |
| Security lead | Threat model, test strategy, audit readiness, incident controls |
| SDK/release engineer | ABIs, typed clients, manifests, bytecode/provenance checks |
| Platform engineer | Keeper, indexer, API, alerting, data reconciliation |
| Frontend engineer | Sale, portfolio, claims, transfer, and redemption UX |
| Operations authority | Multisig, timelock, guardian, deployment and incident runbooks |

One person may hold multiple roles, but every approval must identify the role exercised.

## 7. Dependency graph and execution order

```text
G0 Decision and feasibility freeze
 │
 ├── F0 Repository + CI ── F1 Types/manifests ── F2 Registries/governance
 │                               │                       │
 │                               └──────────────┬────────┘
 │                                              ▼
 ├────────────────────────── C1 Sale ── C2 NFT/account ── C3 Distribution
 │                                              │               │
 │                                              └─────── C4 Revenue/ops
 │
 └── S0 Strategy lifecycle ── S1 Price/market state ── S2 Base sleeve
                                      │                    │
                                      ├──── S3 Stock ──────┤
                                      ├──── S4 USDG ───────┤
                                      └──── S5 Delta ──────┘
                                                            │
                                 I1 Existing revenue bridge ┤
                                                            ▼
                         P1 SDK ── P2 Indexer/API ── P3 UI/metadata
                                      │                    │
                                      └──── O1 Operations ─┘
                                                   │
                                                   ▼
                                           Q1 Security/audit
                                                   │
                                                   ▼
                                               R1 Release
```

Parallelism rules:

- F0, the decision log, mock integration contracts, and test harness design can proceed together after the package decision.
- C1–C4 and S0–S2 may proceed in parallel once shared types and invariants are frozen.
- S3, S4, and S5 may proceed in parallel only after the base sleeve interface, PriceHub contract, adapter lifecycle, and test-token semantics are stable.
- SDK, indexer, and UI may prototype against versioned mock ABIs. Production integration starts only after ABI freeze.
- External adapters cannot leave mock/test status until official source, ABI, address, bytecode, and pinned-fork behavior are recorded.
- Final audit begins after feature and storage freeze; only audit fixes may enter afterward.

## 8. Work breakdown

### G0 — Product and external-integration freeze (XL)

**Objective:** Convert every open choice and external dependency into approved, testable input.

**Dependencies:** None.

**Work packages:**

- G0.1 Create the decision log for D1–D16 with owner, options, recommendation, evidence, decision, approver, and date.
- G0.2 Create one audited fund-flow ledger covering mint, refund, settlement, revenue, claim, strategy deposit, harvest, transfer, burn, tax, and post-burn unwrap.
- G0.3 Produce the asset/feed/pool/lending manifest with complete addresses, chain IDs, decimals, token behavior, code hashes, sources, and approvers.
- G0.4 Produce Delta integration evidence for every method and address the adapter will call, including staking, reward claiming, streaming, and exit.
- G0.5 Select the production USDG lending venue and record its exact deposit, yield, receipt-token, withdrawal, and loss semantics.
- G0.6 Approve governance signers, quorum, timelock delay, guardian limits, and key custody procedure.

**Deliverables:** `docs/yield-vaults/decision-log.md`, `fund-flow-ledger.md`, `asset-manifest.json`, `integration-evidence/`, and `governance-policy.md`.

**Exit gate:** All Gate 0 criteria pass; manifest validation rejects incomplete or duplicate entries; security signs off on trust assumptions.

**Rollback:** No production code has been deployed. Reopen decisions and invalidate dependent design approvals.

**Feasibility:** Conditional; exact third-party contracts and integration evidence are external blockers.

### F0 — Repository, package, and CI foundation (M)

**Objective:** Give Yield Vaults an isolated, reproducible build and release surface.

**Dependencies:** D7.

**Work packages:**

- F0.1 Create the selected Foundry package using Solidity `0.8.28`, Cancun EVM, optimizer, and via-IR settings only after confirming compatibility with all dependencies.
- F0.2 Pin every dependency and commit the lock/remapping state.
- F0.3 Add formatting, build, unit, fuzz, invariant, coverage, static-analysis, and size checks.
- F0.4 Add the package to `.github/workflows/contracts-ci.yml`; current CI omits `sinjoh-contracts-v2` even though `scripts/test-all.sh` includes it.
- F0.5 Separate testnet and mainnet deployment configuration; reject implicit chain selection.
- F0.6 Add documentation and change-log templates plus an invariant registry.

**Deliverables:** package scaffolding, CI jobs, test profiles, release scripts, and `docs/invariants.md`.

**Exit gate:** A clean checkout produces byte-identical artifacts; all checks run in CI; deliberate test failure fails CI; EIP-170 size checks cover every deployable contract.

**Rollback:** Delete the new package/CI jobs before dependent work lands; no deployed state exists.

**Feasibility:** Verified.

### F1 — Shared types, identifiers, and manifests (M)

**Objective:** Define canonical identifiers and reject ambiguous configuration.

**Dependencies:** F0, D1, D2, D6.

**Work packages:**

- F1.1 Define collection, sleeve, strategy, asset, pool, and feed identifiers.
- F1.2 Define immutable collection configuration and bounded mutable policy types.
- F1.3 Implement manifest schema validation for chain ID, complete address, code hash, decimals, interfaces, source URL, risk limits, and approval.
- F1.4 Define typed errors and events before implementation to stabilize observability and SDK generation.
- F1.5 Add configuration hash computation so contracts, SDK, indexer, and UI can prove they use the same release.

**Deliverables:** Solidity types/libraries, JSON schemas, fixtures, event/error catalog.

**Exit gate:** Round-trip tests produce identical config hashes across Solidity and TypeScript; malformed manifests fail with a specific reason.

**Rollback:** Version the schema; never reinterpret an already published config hash.

**Feasibility:** Verified after decisions.

### F2 — Protocol registry, collection factory, and governance roots (L)

**Objective:** Register canonical implementations and create collections deterministically.

**Dependencies:** F1, D10.

**Work packages:**

- F2.1 Implement `YieldVaultProtocolRegistry` for approved factory, implementation, and release metadata.
- F2.2 Implement `YieldVaultCollectionFactory` with deterministic deployment prediction and duplicate-config rejection.
- F2.3 Implement `CollectionTimelock` using a reviewed standard library.
- F2.4 Separate governance, guardian, keeper, fee recipient, and upgrade/release authorities.
- F2.5 Make guardian powers risk-reducing only: pause deposits, block new strategy allocation, or move an adapter to exit-only; no arbitrary asset transfer.
- F2.6 Emit full configuration and authority events for indexers.

**Deliverables:** registries, factory, timelock, authority matrix, deterministic address library.

**Exit gate:** Predicted and deployed addresses match; unauthorized role actions fail; timelocked actions cannot execute early; guardian cannot increase exposure or redirect funds.

**Rollback:** Disable factory version in the protocol registry; deployed collections remain immutable and independently operable.

**Feasibility:** Verified.

### C1 — Collection controller and sale escrow (XL)

**Objective:** Accept mint payments without exposing buyer funds to an unsuccessful sale.

**Dependencies:** F1, F2, D1, D3.

**Work packages:**

- C1.1 Implement the collection state machine: configured, sale active, success pending settlement, active, failed/refunding, paused, and wound down as approved.
- C1.2 Implement `SaleEscrow` with per-buyer receipts, cap enforcement, close conditions, refund paths, and settlement exactly once.
- C1.3 Route settlement according to approved economics using pull-safe or atomic bounded transfers.
- C1.4 Define treatment of excess payment, fee-on-transfer tokens, rebasing tokens, native currency, and accidental transfers. Recommended launch scope is one exact-behavior ERC-20 payment token.
- C1.5 Prevent strategy deployment before a successful sale and completed settlement.

**Deliverables:** `YieldVaultCollection`, `SaleEscrow`, payment router, state-machine tests.

**Exit gate:** All-or-refund conservation holds under fuzzing; total buyer refunds plus approved settlement equals receipts; reentrancy cannot double mint/refund/settle; the sale never exceeds 3,000 NFTs.

**Rollback:** Before settlement, transition to refund state under the approved failure rules. After settlement, sale code cannot reclaim vault assets.

**Feasibility:** Verified after economics and sale-model approval.

### C2 — NFT, deterministic token account, and ownership policy (XL)

**Objective:** Bind each token ID to one deterministic economic account controlled by current NFT ownership.

**Dependencies:** F2, C1, D4, D13, D15, D16.

**Work packages:**

- C2.1 Implement the capped ERC-721 collection and immutable token-ID-to-account derivation.
- C2.2 Implement `YieldVaultAccount` with only approved claim, deposit, redemption, and recovery actions; no generic executor.
- C2.3 Resolve authority dynamically from current NFT ownership so transfer moves control without moving every sleeve share.
- C2.4 Use standard ERC-721 transfer semantics without a separate transfer registry or attestation service.
- C2.5 Specify approval/operator behavior and prevent marketplace approvals from becoming arbitrary treasury execution authority.
- C2.6 Implement burn lifecycle and permanent consumed-token protection.

**Deliverables:** NFT, account implementation/factory, ownership and operator tests, account address prediction in SDK fixtures.

**Exit gate:** Former owners lose control in the same transaction as transfer; account address is stable; no one can mint above 3,000 or reuse a burned token ID; transfers do not call a separate registry or attestation service.

**Rollback:** Pause mint/transfer where authorized; core ownership contracts are immutable, so defects require a new collection version rather than hidden migration.

**Feasibility:** Verified.

### C3 — Equal-per-live-NFT distribution accounting (XL)

**Objective:** Allocate ongoing collection revenue equally without iterating over the collection.

**Dependencies:** C2, F1.

**Work packages:**

- C3.1 Implement a high-precision accumulator, per-account debt/checkpoint, remainder handling, and live-supply snapshots.
- C3.2 Define mint and burn ordering so a token cannot claim value from before mint or after burn.
- C3.3 Support permissionless claim-for-account while ensuring output can only enter the correct account/sleeves.
- C3.4 Define zero-live-supply handling and unsupported-token rejection.
- C3.5 Prove solvency after arbitrary claim, mint, transfer, burn, and distribution sequences.

**Deliverables:** `YieldVaultDistributor`, mathematical specification, reference model, fuzz and invariant suite.

**Exit gate:** Distributed amount equals claimed plus pending plus bounded dust; claims are order-independent within rounding tolerance; no path loops over NFT supply; transfer neither duplicates nor erases accrued value.

**Rollback:** Pause new distributions while preserving claims. Never reset accumulator or debt for a live account.

**Feasibility:** Verified.

### C4 — Revenue router and operations reserve (L)

**Objective:** Authenticate revenue sources and allocate funds only to approved destinations.

**Dependencies:** C3, D1, D8, D11.

**Work packages:**

- C4.1 Implement `CollectionRevenueRouter` with source allowlists, token allowlists, recipient bounds, and accounting events.
- C4.2 Implement approved protocol, creator, operations, and NFT-holder allocations without commingling sale principal.
- C4.3 If retained, implement `OperationsReserve` with budget caps, recipient rules, and sunset policy.
- C4.4 Reject direct accounting credit from unauthenticated token transfers.
- C4.5 Add end-to-end reconciliation between source receipts, router allocations, distributor credit, and reserve spending.

**Deliverables:** router, reserve if approved, revenue-source interfaces, reconciliation tests.

**Exit gate:** Every unit received is assigned exactly once; unauthorized sources cannot create claims; recipient changes obey governance delay and bounds; reserve cannot spend sleeve principal.

**Rollback:** Remove source from allowlist, pause routing, and preserve already credited claims.

**Feasibility:** Verified for native sources; current Sinjoh V2 source integration remains conditional on D8.

### S0 — Strategy registry and adapter lifecycle (XL)

**Objective:** Add future strategy versions without granting open-ended execution rights.

**Dependencies:** F2, D10, D14.

**Work packages:**

- S0.1 Implement immutable adapter registrations keyed by code hash, interface version, asset set, and risk class.
- S0.2 Implement lifecycle states: proposed, canary, active, deposit-paused, exit-only, retired, and rejected.
- S0.3 Enforce per-adapter, per-sleeve, and collection exposure caps.
- S0.4 Timelock risk-increasing changes; allow guardian only to pause or reduce risk.
- S0.5 Prohibit `delegatecall`, arbitrary targets, mutable adapter logic, and unbounded token approvals.
- S0.6 Define version replacement as register-new/de-risk-old, never silently mutate semantics.

**Deliverables:** `StrategyRegistry`, lifecycle library, governance actions, adapter review template.

**Exit gate:** No unregistered adapter receives funds; state transitions are monotonic with explicit governed exceptions; old versions remain identifiable and withdrawable; guardian cannot activate or fund a strategy.

**Rollback:** Move adapter to deposit-paused or exit-only; revoke allowances; execute documented exit; retain accounting history.

**Feasibility:** Verified.

### S1 — PriceHub and market state (XL)

**Objective:** Centralize asset valuation and market-state decisions without treating an oracle price as execution truth.

**Dependencies:** F1, G0.3.

**Work packages:**

- S1.1 Implement PriceHub adapters for approved Stock Token feeds and market/sequencer state.
- S1.2 Record feed decimals, heartbeat/staleness, multiplier semantics, market hours, and fallback behavior in the manifest.
- S1.3 Prevent mixing raw REST prices with adjusted onchain feeds or applying multipliers twice.
- S1.4 Implement stale, invalid, negative, zero, and sequencer-grace-period rejection.
- S1.5 Keep valuation separate from swap slippage checks and realized settlement accounting.

**Deliverables:** `PriceHub`, feed adapters, oracle simulation fixtures, signed feed manifest.

**Exit gate:** All approved feeds reproduce official examples; stale/down/closed-market conditions trigger specified behavior; no unapproved fallback can authorize a trade or transfer.

**Rollback:** Pause valuations and new allocations; existing shares remain redeemable according to the approved safe path.

**Feasibility:** Blocked for production until feed addresses and the sequencer-health source are supplied.

### S2 — Base sleeve and share accounting (XL)

**Objective:** Create auditable pooled sleeves whose shares are the per-NFT accounting unit.

**Dependencies:** S0, S1, F1.

**Work packages:**

- S2.1 Define a narrow sleeve interface for deposit, share preview, redemption, asset value, pause state, and adapter exposure.
- S2.2 Implement initial-share, rounding, donation, dust, loss, and zero-liquidity behavior.
- S2.3 Use actual balance deltas, allowance clearing, reentrancy guards, and checks-effects-interactions.
- S2.4 Implement in-kind share transfer for NFT burn and separate optional sleeve unwrapping.
- S2.5 Handle unsolicited tokens without letting them manipulate share price or become governance loot.
- S2.6 Define loss recognition; never promise principal preservation.

**Deliverables:** base sleeve/share token, accounting library, adversarial token fixtures, reference model.

**Exit gate:** Total assets and shares conserve value within defined rounding; first-depositor/donation attacks fail; a loss is assigned pro rata; NFT burn does not call external adapters.

**Rollback:** Pause deposits, preserve share transfers/redemptions, and de-risk adapters.

**Feasibility:** Verified.

### S3 — Core Stock Token sleeve (XL)

**Objective:** Hold and rebalance the configured Stock Token basket under oracle and market controls.

**Dependencies:** S1, S2, D6.

**Work packages:**

- S3.1 Implement only the approved token set and target-weight/risk bounds.
- S3.2 Verify transfer restrictions, decimals, pause behavior, mint/burn semantics, and liquidity for each token on a pinned fork.
- S3.3 Implement controlled acquisition/rebalance paths using approved venues and slippage bounds.
- S3.4 Enforce market-hours, stale-feed, exposure, and concentration circuit breakers.
- S3.5 Define restricted or frozen token handling without blocking NFT-level sleeve-share redemption.

**Deliverables:** `CoreStockTokenSleeve`, asset adapters if required, fork tests, asset risk sheets.

**Exit gate:** Exact selected assets pass behavior tests; stale/closed/down feeds stop risk-increasing actions; native token transfer failures are surfaced without adding another transfer gate; a frozen token cannot freeze NFT burn when D4 uses sleeve shares.

**Rollback:** Stop purchases/rebalances, retain or unwind assets according to liquidity and token-contract behavior, and expose status in UI.

**Feasibility:** Blocked for production until D6 is resolved and the selected contracts pass fork integration tests.

### S4 — USDG Yield sleeve and lending adapters (L/XL)

**Objective:** Deploy USDG into configured lending strategies through bounded adapters.

**Dependencies:** S0, S2, D9.

**Work packages:**

- S4.1 Implement `USDGYieldSleeve` and the selected production lending adapter. Plain USDG balances are transient transaction liquidity, not the launch strategy.
- S4.2 Verify USDG transfer semantics, decimals, pause/blacklist behavior, and liquidity on a pinned fork.
- S4.3 Implement the venue's exact immutable adapter; use generic ERC-4626 behavior only if the selected vault actually conforms in integration tests.
- S4.4 Test deposit/redeem limits, liquidity shortfall, loss, fees, share inflation, pause, and emergency withdrawal.
- S4.5 Add the configured allocation and transaction-liquidity behavior without promising principal protection or active lender management.

**Deliverables:** USDG sleeve, selected lending adapter, integration fixtures, and documented venue semantics.

**Exit gate:** USDG is deposited into the selected lending venue; yield and receipt tokens reconcile to sleeve value; lending failures cannot block sleeve-share transfer; venue impairment is reflected rather than reverted away or hidden.

**Rollback:** Stop new deposits into the affected adapter and preserve holder claims while withdrawals execute according to the venue's actual liquidity rules.

**Feasibility:** Conditional on D9 and the selected venue's exact integration behavior.

### S5 — Delta market-making sleeve and adapter (XL)

**Objective:** Create, stake, manage, harvest rewards from, and exit Delta-compatible v3 LP positions.

**Dependencies:** S0, S1, S2, D6, G0.4.

**Work packages:**

- S5.1 Resolve and record every Delta contract, address, ABI, custody transition, and method used for LP creation, staking, reward claims, streaming, rebalancing, and exit.
- S5.2 Implement `DeltaV3StrategyAdapter` around the verified Delta v3 builder at `0x6235cF6bd8419b34942F4EDDB39C880BD96dD700` plus the exact configured Delta staking and reward lifecycle.
- S5.3 Validate token ordering, pool fee, tick spacing, range bounds, minimum amounts, deadlines, callbacks, approvals, and recipient ownership.
- S5.4 Account separately for principal, unclaimed trading fees, claimed trading fees, staking rewards, streamed-but-unclaimable WETH, claimable WETH, and the documented claim fee.
- S5.5 Implement harvest/rebalance with minimum-value thresholds, slippage/price-deviation checks, keeper authorization, and no assumed auto-compounding.
- S5.6 Test unstaking, reward collection, stream completion, and withdrawal returning both pool assets, including failure at every Delta call boundary.

**Deliverables:** market-making sleeve, Delta adapter, pinned-fork suite, integration evidence package, operational thresholds.

**Exit gate:** The adapter reproduces LP creation, staking, trading-fee collection, reward claiming, seven-day streaming, unstaking, and two-asset exit on a pinned mainnet fork; position custody is provable at every step; accounting reconciles to token balances and claimable/streaming rewards.

**Rollback:** Pause deposits/rebalances, collect/withdraw through the verified path, transfer underlying sleeve shares without forcing external calls.

**Feasibility:** Conditional; the builder is verified, the complete proposed Delta lifecycle is not yet verified.

### I1 — Existing Sinjoh project revenue integration (L)

**Objective:** Let approved existing Sinjoh revenue sources fund Yield Vaults without weakening project identity checks.

**Dependencies:** C4, D8.

**Work packages:**

- I1.1 Document current `ProjectRouterV2` restrictions: sinks must be registered same-project modules.
- I1.2 Design a successor router action/module or authenticated bridge with explicit source project, destination collection, token, amount, replay protection, and authorization.
- I1.3 Add module-bit/version handling rather than overloading existing meanings in `ProjectModuleBits.sol`.
- I1.4 Keep deployed V2 storage and behavior unchanged; use a new versioned integration surface.
- I1.5 Reconcile source debit with collection-router receipt in contracts and indexer.

**Deliverables:** integration RFC, selected contracts, migration-free compatibility tests, event schema.

**Exit gate:** Funds cannot be redirected across projects/collections without explicit authority; replay and identity-confusion tests fail safely; deployed V2 contracts are untouched.

**Rollback:** Disable bridge/source permission; existing projects and Yield Vault collections continue independently.

**Feasibility:** Conditional on D8; direct use of current V2 sink action is not feasible.

### P1 — ABI, deployment manifest, and SDK support (L)

**Objective:** Give clients one typed, release-verified interface to the protocol.

**Dependencies:** ABI freeze for F2, C1–C4, S0–S5.

**Repository:** `/Users/dsb/sinjoh-sdk`.

**Work packages:**

- P1.1 Generate and publish ABIs in `@sinjoh/abis`.
- P1.2 Publish complete addresses, chain IDs, creation transactions, code hashes, compiler settings, source commit, audit hashes, and config hashes in `@sinjoh/deployments`.
- P1.3 Add typed collection, account, sleeve, strategy, claim, redemption, and prediction helpers to `@sinjoh/sdk`.
- P1.4 Make the SDK reject chain/address/code-hash/config-hash mismatches.
- P1.5 Add transaction simulation and human-readable fund-flow previews.

**Deliverables:** versioned SDK packages, deployment schema, generated docs, integration fixtures.

**Exit gate:** SDK address predictions match contracts; every write is simulated; clients cannot silently use an artifact from another chain or release.

**Rollback:** Deprecate affected package version and manifest; contracts remain accessible through prior pinned versions.

**Feasibility:** Verified; existing SDK already has ABI, deployment, provenance, promotion, and prediction foundations.

### P2 — Indexer and API (L)

**Objective:** Reconstruct ownership, holdings, claims, strategy state, and fund flows from chain data.

**Dependencies:** Stable events/config hash from F1 and contract ABI freeze.

**Repository:** `/Users/dsb/sinjoh-platform` (`sinjoh-indexer`, `sinjoh-api`, migrations).

**Work packages:**

- P2.1 Extend the indexer schema for collections, token accounts, owners, sleeve shares, strategies, positions, distributions, claims, burns, and governance actions.
- P2.2 Backfill deterministically from deployment block and handle reorgs/idempotent replay.
- P2.3 Expose read APIs for collection state, NFT portfolio, claimable revenue, strategy health, and complete provenance.
- P2.4 Reconcile indexed totals against onchain totals and raw RPC logs.
- P2.5 Mark estimated valuation separately from realized token balances.

**Deliverables:** Envio config/schema/handlers, database migrations, API routes, reconciliation jobs.

**Exit gate:** Replay from genesis deployment produces the same state; reorg tests recover; aggregate indexed shares/claims equal onchain values within documented rounding.

**Rollback:** Rebuild the index from the deployment block; API includes release/config hash to prevent mixed versions.

**Feasibility:** Verified; platform already has indexer/API infrastructure.

### P3 — Sale, portfolio, strategy, and redemption UI (L)

**Objective:** Make ownership, value sources, strategy state, risk, and fund movements understandable before signature.

**Dependencies:** P1, P2, D12.

**Repository:** `/Users/dsb/Sinjoh-UI`.

**Work packages:**

- P3.1 Add sale/refund/settlement status and exact payment breakdown.
- P3.2 Add token page showing full ownership, account, sleeve shares, holdings, claimable amount, strategy exposure, and valuation timestamp.
- P3.3 Add claim and allocation previews with before/after balances.
- P3.4 Add burn confirmation showing irreversible NFT destruction, exact sleeve shares received, the fixed 5% in-kind charge, and optional later unwrap.
- P3.5 Show stale oracle, paused strategy, loss, token-level transfer failure, and exit-only states without masking risk behind APY.
- P3.6 Add static or dynamic metadata according to D12; label estimates and source timestamps.

**Deliverables:** routes/components, transaction simulations, accessible states, analytics events, UX test scripts.

**Exit gate:** Automated wallet-flow tests cover mint payment, sale refund, settlement display, revenue claim, sleeve allocation, transfer, burn, and optional unwrap. For each write, the review screen must assert source asset/amount, destination, fees, minimum received, resulting ownership, and irreversible effects where applicable. State fixtures must assert the exact enabled/disabled controls and warning copy for pause, loss, stale data, token-transfer failure, refund, transfer, exit-only strategy, and burn.

**Rollback:** Feature-flag UI entry points by release manifest; never imply that hiding the UI disables contracts.

**Feasibility:** Verified after ABI freeze; existing UI uses viem/wagmi and release manifests.

### O1 — Keeper, monitoring, reconciliation, and runbooks (L)

**Objective:** Operate bounded strategies without making automation a custody authority.

**Dependencies:** S3–S5, P2, D10, D14.

**Repository:** `/Users/dsb/sinjoh-platform` (`sinjoh-keeper`, monitoring/infrastructure).

**Work packages:**

- O1.1 Extend the existing keeper planner/runner/scheduler rather than creating a second service.
- O1.2 Simulate every harvest/rebalance/exit before submission and enforce onchain-equivalent bounds.
- O1.3 Add idempotency, nonce control, concurrency locks, retry classification, and transaction replacement policy.
- O1.4 Alert on stale feeds, price deviation, range exit, claim backlog, reconciliation mismatch, adapter cap, loss, pause, failed exit, low keeper funds, and governance action.
- O1.5 Write normal-operation, degraded-mode, incident, signer-loss, RPC-failure, and recovery runbooks.
- O1.6 Ensure keeper compromise cannot redirect recipients, register adapters, change caps, or transfer arbitrary assets.
- O1.7 Provision at least two independently configured production RPC paths, document provider limits, test automatic failover, and keep indexer ingestion independent from the keeper's primary RPC.

**Deliverables:** keeper jobs, dashboards, alerts, SLOs, runbooks, game-day scripts.

**Exit gate:** Chaos tests cover duplicate work, RPC failure, provider failover, reorg, revert, stale simulation, and compromised keeper; onchain checks stop unsafe transactions independently; provider capacity is load-tested against measured keeper, indexer, API, and monitoring demand.

**Rollback:** Disable keeper key/job; permissionless/user exits and governance controls remain available.

**Feasibility:** Verified; external actions remain conditional on their adapters.

### Q1 — Security engineering, verification, and independent audit (XL)

**Objective:** Prove the economic and authority invariants before mainnet value is accepted.

**Dependencies:** Continuous from F0; final stage requires feature/storage freeze.

**Work packages:**

- Q1.1 Maintain a threat model for owner, operator, marketplace, keeper, guardian, governance, creator, revenue source, external protocol, oracle, token, and RPC compromise.
- Q1.2 Map every invariant in `YIELD-VAULTS-BLUEPRINT.md` to at least one automated test and monitoring check where observable.
- Q1.3 Run static analysis, unit, fuzz, stateful invariant, differential/reference-model, gas, bytecode-size, and storage-layout checks.
- Q1.4 Run pinned-fork integration tests for exact deployed external code.
- Q1.5 Run end-to-end tests across contracts, SDK, indexer, keeper, API, and UI.
- Q1.6 Commission independent audit(s) for core accounting and external adapters; triage every finding with proof of fix or explicit launch-blocking rejection.
- Q1.7 Run deployment rehearsal and incident game day using production manifests and signer roles.

**Deliverables:** threat model, test traceability matrix, reports, audit package, remediation ledger, launch security sign-off.

**Exit gate:** Zero unresolved critical/high findings; all 25 blueprint invariants pass; every external adapter can revert without blocking core NFT burn; release artifacts match audited commit and compiler output.

**Rollback:** Any post-freeze semantic change returns the affected scope to review and audit. No waiver can turn a failing conservation/authority invariant into a pass.

**Feasibility:** Verified as a process; audit outcome cannot be assumed.

### R1 — Deployment, canary, promotion, and release (XL)

**Objective:** Deploy reproducibly, cap initial exposure, and promote only from observed evidence.

**Dependencies:** All prior exit gates, D14, audit sign-off, and product launch approval.

**Work packages:**

- R1.1 Deploy and test locally with deterministic fixtures.
- R1.2 Deploy to Robinhood Chain testnet chain ID `46630`; execute the complete sale-to-redemption lifecycle.
- R1.3 Rehearse against a pinned Robinhood Chain mainnet chain ID `4663` fork using exact bytecode and balances.
- R1.4 Generate final deployment manifest and independently verify all complete addresses, code hashes, ABIs, compiler settings, constructor/init data, roles, source commit, and audit hashes.
- R1.5 Deploy immutable core and verify source; transfer authorities according to the governance policy.
- R1.6 Enable strategies in canary state below approved caps; observe for the approved window and exit successfully before promotion.
- R1.7 Publish SDK/UI/indexer release only after onchain manifest verification.

**Deliverables:** rehearsal report, deployment transactions, verified source, release manifest, authority handoff receipts, canary report, public disclosures.

**Exit gate:** Every mainnet blocker in Section 3 is cleared; configuration equals approved hashes; canary entry and exit succeed; monitoring and incident responders are live; product, security, and operations sign release.

**Rollback:** Before sale settlement, use the approved refund path. Disable defective adapters and UI manifests. Immutable core defects require a new collection version; no forced NFT migration or hidden proxy upgrade.

**Feasibility:** Blocked until external, audit, and approval gates pass.

## 9. Test and proof plan

### 9.1 Test layers

| Layer | Required proof |
|---|---|
| Unit | Every state transition, access rule, rounding branch, error, and event |
| Fuzz | Payments, weights, share conversion, accumulator math, claim ordering, mint/burn ordering, slippage bounds |
| Stateful invariant | Conservation, solvency, authorization, supply cap, no double claim, no post-burn claim, no cross-account theft |
| Reference-model differential | Distributor and sleeve results match a simple high-precision offchain model |
| Adversarial token | Reentrancy, fee-on-transfer, rebasing, missing returns, false returns, blacklist/pause, donation |
| Pinned-fork integration | Exact Stock Token, oracle, USDG, Delta, pool, and lending code selected in the manifest |
| Cross-repository E2E | Wallet → UI → SDK → contracts → logs → indexer/API → keeper → UI |
| Release/provenance | Deployed runtime and configuration match audited artifacts and published manifest |

### 9.2 Non-negotiable invariant groups

1. **Supply:** no more than 3,000 NFTs; a burned ID never returns.
2. **Ownership:** only current ownership/policy authority controls the token account.
3. **Sale conservation:** escrow receipts equal refunds plus settlement plus bounded dust.
4. **Distribution solvency:** contract balance covers total claimable obligations.
5. **No double allocation:** revenue, claims, shares, and burns are accounted once.
6. **Share conservation:** sleeve assets and liabilities reconcile under deposits, losses, donations, and redemptions.
7. **Isolation:** one NFT cannot spend or claim another NFT's shares or accrual.
8. **External independence:** every external adapter may revert or pause while NFT burn still transfers sleeve shares.
9. **Authority monotonicity:** guardian and keeper cannot increase risk or redirect value.
10. **Manifest identity:** every external call target and release contract matches chain, full address, and bytecode hash.
11. **Oracle safety:** stale/down/invalid data cannot authorize a risk-increasing action.
12. **Adapter containment:** no arbitrary call, `delegatecall`, unlimited persistent approval, or unregistered strategy.

The detailed 25-invariant catalog in the architecture blueprint must be copied into a traceability matrix with columns for contract, test name, monitoring signal, owner, and result.

## 10. Environments and release gates

| Environment | Permitted activity | Required gate |
|---|---|---|
| Local deterministic chain | All mocks, accounting, state machines, adversarial tests | F0 |
| Robinhood Chain testnet `46630` | Full UX and operational rehearsal using test assets/integrations | Stable mock/testnet manifest |
| Pinned mainnet fork `4663` | Exact external bytecode integration and failure testing | Signed candidate manifest |
| Robinhood Chain mainnet `4663` core deployment | Source verification and authority setup; no public value yet | Audit + product + deployment approval |
| Mainnet canary | Capped approved strategy exposure | D14 thresholds + live monitoring |
| Public sale/active collection | Approved production behavior | All R1 exit criteria |

Testnet success is not evidence that a mainnet address, liquidity condition, or external protocol behavior is valid. Fork success is not a substitute for independent audit.

## 11. Deployment manifest and provenance requirements

Every release manifest must contain:

- network name and numeric chain ID;
- complete address for every contract, token, pool, feed, router, adapter, distributor, recipient, signer, timelock, and guardian;
- deployment/creation transaction and block;
- implementation and runtime bytecode hashes;
- ABI hash and interface version;
- compiler version, optimizer settings, EVM version, and metadata settings;
- constructor or initializer arguments;
- source repository and exact commit;
- collection configuration and configuration hash;
- external source/verification URL and last verification block;
- audit report hash and audited commit;
- role holder, quorum, delay, and authority-transfer transaction; and
- promotion state: proposed, testnet, fork-verified, canary, active, exit-only, or retired.

SDK, indexer, keeper, API, and UI must refuse a manifest whose chain, config hash, or runtime bytecode does not match the connected network.

## 12. Failure, rollback, and recovery policy

| Failure | Required response | Funds/access preserved |
|---|---|---|
| Sale target/model fails | Enter refund state according to approved rules | Buyers recover escrowed payment |
| Revenue source fails | Disable source; keep distributor claims live | Existing claims remain solvent |
| Oracle stale/down | Stop valuation-dependent and risk-increasing actions | Share ownership and safe exits remain |
| Adapter deposit defect | Pause deposits and revoke allowances | Existing shares and exit accounting remain |
| External venue impaired | Mark loss, switch exit-only, withdraw as available | Loss is transparent and pro rata |
| Keeper compromised | Disable key/job | Keeper cannot redirect custody or governance |
| Guardian compromised | Governance replaces guardian after delay/emergency process | Guardian cannot increase exposure or transfer assets |
| Core immutable defect before sale | Abandon release and redeploy corrected version | No user value accepted |
| Core immutable defect after launch | Pause bounded functions, disclose, design opt-in new collection/version | No forced migration or concealed upgrade |
| Indexer/API/UI defect | Roll back application manifest and rebuild index | Onchain ownership remains authoritative |

Recovery instructions must never depend on a single web application, indexer, keeper, or signer.

## 13. Existing code reuse boundaries

The implementation should reuse reviewed patterns, libraries, and test ideas—not inherit deployed state or unsuitable semantics.

Reuse candidates:

- deterministic clone/address prediction patterns from `BasketManagerV2`;
- bearer ownership and manager transfer-hook patterns from `BasketNFTV2`, adapted to unrestricted ERC-721 transfer and the selected operator model;
- exact-balance-delta and allowance-clearing patterns from `ERC4626BasketYieldAdapter`;
- repository release, size-check, ABI-generation, provenance, and prediction tooling;
- existing keeper planner/runner/scheduler/simulation infrastructure;
- existing Envio indexer, API, UI release-manifest, viem, and wagmi foundations.

Do not directly reuse or mutate:

- the one-primary-basket model in `BasketManagerV2`;
- the multi-step external-target burn path in `BasketVaultV2` for core NFT redemption;
- `ERC4626BasketYieldAdapter` as pooled sleeve accounting without redesign—it is bound to one basket/vault and its impairment behavior is not suitable here;
- existing meanings in `ProjectModuleBits.sol`;
- deployed immutable V2 storage or routing identity checks; or
- any arbitrary-execution account or strategy pattern.

## 14. Handoff and change-control protocol

### 14.1 Work-item standard

Create one issue and normally one pull request per numbered work package. Each issue must contain:

- requirement classification and linked decision IDs;
- objective and non-goals;
- dependencies and target repository;
- contracts/modules/events/errors affected;
- threat-model delta;
- exact acceptance tests and exit gate;
- manifest or documentation changes;
- rollback/disable path; and
- reviewer roles.

No work item may use “support Delta,” “add lending,” “handle compliance,” or “make upgradeable” as acceptance criteria. It must name exact contracts, methods, addresses/manifests, failure cases, and proof.

### 14.2 Pull-request evidence

Every PR must include:

- linked decision and invariant IDs;
- tests added and commands/results;
- gas and bytecode-size delta for Solidity;
- ABI/event/schema change declaration;
- external integration evidence if applicable;
- security reviewer sign-off for authority/accounting changes; and
- documentation and deployment-manifest changes.

### 14.3 Change classes

- **Class A:** wording, UI copy, or offchain display; standard review.
- **Class B:** bounded offchain operations or indexer/API behavior; platform + security review.
- **Class C:** adapter version or risk-bound change; governance delay, fork test, canary, and security review.
- **Class D:** economics, ownership, redemption, sale, core accounting, or immutable configuration; return to Gate 0, update blueprint/decision log, and re-audit affected scope.

## 15. Milestone exit checklist

### Milestone A — Specification frozen

- Gate 0 passes.
- Fund-flow ledger balances.
- Architecture, interfaces, events, errors, and invariants are reviewed.
- External unknowns are either resolved or explicitly excluded from launch scope.

### Milestone B — Core protocol complete

- F0–F2 and C1–C4 pass their exit gates.
- Ownership, sale, distribution, and redemption invariants pass without external adapters.
- SDK can predict addresses and simulate the core lifecycle.

### Milestone C — Sleeve framework complete

- S0–S2 pass.
- Mock Stock, Delta, and lending adapters prove containment.
- Burn succeeds when all mocks revert.

### Milestone D — Production integrations proven

- S3–S5 and I1 pass for only the approved launch scope.
- Exact mainnet-fork behavior is captured and reproducible.
- Every external address/code hash appears in the candidate manifest.

### Milestone E — Product and operations ready

- P1–P3 and O1 pass.
- Full E2E, reconciliation, accessibility, disclosure, and incident-game-day checks pass.

### Milestone F — Audit and launch ready

- Q1 passes with no unresolved critical/high issues.
- Security, product, and operations sign the identical manifest/config hash.
- R1 deployment rehearsal and canary exit pass.

## 16. Definition of done

Yield Vaults is ready for a public mainnet launch only when:

1. The approved collection creates no more than 3,000 NFTs and every token has one deterministic isolated account.
2. NFT transfer and burn implement the approved economic-ownership rules using standard ERC-721 transfers.
3. Sale, ongoing revenue, sleeve accounting, claims, losses, and redemption conserve value within declared rounding bounds.
4. The three sleeve categories work independently, and failure of any external adapter does not block core redemption.
5. Only signed-manifest external contracts receive approvals or funds.
6. Future strategy versions can be proposed, delayed, capped, canaried, paused, made exit-only, and retired without arbitrary execution or changing existing adapter code.
7. SDK, indexer, API, keeper, UI, monitoring, and runbooks are release-hash aligned.
8. All invariant, fork, E2E, provenance, and deployment-rehearsal checks pass.
9. Independent audit findings are resolved and the deployed bytecode matches the audited artifacts.
10. Product, security, and operations approve the same launch configuration.

## 17. Product-owner review agenda

Review and approve the plan in four passes:

1. **Economics and launch:** D1, D2, D3, D11, D14, D16.
2. **Ownership and redemption:** D4, D13, D15. D16 is a closed product decision.
3. **Assets and integrations:** D6, D8, D9.
4. **Control and product surface:** D7, D10, D12.

For each decision, record either the recommended option, a different explicit option, or “excluded from launch.” Once those entries are signed, the delivery lead can convert every numbered work package into assignable issues without inventing features or feasibility claims.
