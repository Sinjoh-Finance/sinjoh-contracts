# Sinjoh Yield Banks Development Plan

Version: 2.0

Date: 2026-08-28

Status: Canonical implementation plan

Network: Robinhood Chain, chain ID 4663

Supersedes: Every conflicting primary-sale, fixed-supply, escrow, refund, and sale-state requirement in `YIELD-VAULTS-BLUEPRINT.md`

## 1. Objective

Build Sinjoh Yield Banks as an ERC-721 collection protocol in which each NFT is bound to a deterministic treasury account and represents backing held through the collection's three portfolio sleeves.

Primary minting and secondary trading must be compatible with OpenSea on Robinhood Chain. Primary proceeds must remain uninvested in a collection-specific holding contract until an authorized Sinjoh operator manually executes the allocation.

## 2. Locked product decisions

These requirements are settled and must not be reinterpreted during implementation.

| Area | Canonical rule |
|---|---|
| Product name | **Yield Banks** |
| Supply | `maxSupply` is configured independently for each collection and is immutable after deployment |
| Supply behavior | Reaching `maxSupply` only prevents further minting; it does not trigger sale success, fund release, or another lifecycle transition |
| Primary mint venue | OpenSea Drop on Robinhood Chain |
| Secondary venue | OpenSea through standard ERC-721 approvals and Seaport transfers |
| Primary payment | The native asset required by the OpenSea/SeaDrop mint transaction, not a buyer WETH transfer to Sinjoh |
| Proceeds custody | A collection-specific `YieldBankProceedsVault` receives the actual primary proceeds paid to the creator payout address |
| Mint-time movement | No proceeds are transferred to recipients, wrapped, swapped, deposited, or invested when an NFT is minted |
| Mint-time accounting | The vault records the exact proceeds and backing entitlement attributable to the newly minted token range without moving the funds |
| Allocation trigger | An authorized Sinjoh allocation operator manually submits the allocation transaction |
| Failed sale | There is no failed-sale state |
| Buyer refunds | There is no protocol refund path |
| Sale deadline | There is no protocol sale deadline |
| Sellout dependency | Fees, backing, transferability, and redemption do not depend on sellout |
| Transferability | A successfully minted NFT is transferable without waiting for investment allocation |
| Redemption | A holder can redeem whether the token's primary backing is still pending or has already been invested |
| Primary economics | Configure backing, creator, Sinjoh, and operations basis points per collection; commit them immutably at deployment; require a positive backing share and an exact 10,000-basis-point sum |
| OpenSea fee | OpenSea's platform fee is external to the collection-configured split; contracts account from measured proceeds rather than assuming a platform-fee amount |
| Portfolio weights | Configure positive Core, Market-Making, and USDG weights per collection; commit them immutably at deployment; require an exact 10,000-basis-point sum |
| Exit tax | Preserve the 5% in-kind exit tax for non-terminal redemption and no exit tax for the final live Yield Bank |

## 3. Explicitly removed design

The following model is deleted, not adapted:

- fixed 3,000-token supply;
- `YieldBankSaleEscrow`;
- WETH approval before mint;
- `mintPriceWeth` and `saleDeadline` collection configuration;
- `SALE_ACTIVE`, `SALE_SUCCESS`, `SALE_FAILED`, and `CANCELED` collection states;
- `SALE_LOCKED` and `REFUNDED` token states;
- transfer and approval locks pending sellout;
- sale finalization at a supply threshold;
- all-or-refund accounting;
- `failSale()` and `refund(tokenId)`;
- automatic fee release at sellout;
- automatic seed allocation after sellout;
- any SDK, indexer, API, or UI field that represents those concepts.

No replacement deadline, minimum raise, owner finalization, or sale-success rule is to be introduced.

## 4. External integration boundary

OpenSea currently supports Robinhood Chain and has a live Robinhood Chain collection with primary minting and secondary activity. OpenSea's public SeaDrop repository documents native-value primary mints and states that ERC-20 primary payments are future functionality. OpenSea's current Drop settings documentation states a 10% primary platform fee.

Implementation must not assume that the public SeaDrop deployment table for older chains is complete for Robinhood Chain. Before importing an address into source or a deployment manifest, Phase 0 must verify the exact Robinhood Chain mint contract, runtime code hash, supported token interface, payout call order, and OpenSea Studio onboarding path from a live OpenSea Drop and an official OpenSea source.

Authoritative references at plan finalization:

- OpenSea Robinhood Chain announcement: <https://opensea.io/blog/articles/robinhood-chain-is-live-on-opensea>
- Live Robinhood Chain mint and secondary collection: <https://opensea.io/collection/robinhood-doggos/overview>
- OpenSea Drop settings and current primary fee: <https://docs.opensea.io/docs/part-4-edit-drop-settings>
- OpenSea SeaDrop repository: <https://github.com/ProjectOpenSea/seadrop>
- OpenSea Seaport documentation: <https://docs.opensea.io/docs/seaport>

## 5. System topology

```text
                                  OPENSEA PRIMARY DROP
                                            |
                           native payment   |   mintSeaDrop(...)
                                            v
                                  approved SeaDrop contract
                                      |             |
                              mint callback      net payout
                                      |             |
                                      v             v
                               YieldBankNFT   YieldBankProceedsVault
                                      |             |
                                      |             | exact receipt tranche
                                      v             | recorded; ETH stays idle
                             YieldBankCollection    |
                                      |             |
                         creates token account      |
                         and distribution debt      |
                                      |             |
                                      +-------------+
                                            |
                                  manual operator action
                                            |
                     +----------------------+----------------------+
                     |                      |                      |
                     v                      v                      v
             fixed fee recipients   wrap backing to WETH   guarded allocator
                                                                  |
                              +-----------------------------------+------------------+
                              |                                   |                  |
                              v                                   v                  v
                       Core Sleeve shares              Market-Making shares   USDG shares
                              |                                   |                  |
                              +-------------------+---------------+------------------+
                                                  |
                                    token-bound treasury accounts

                                  OPENSEA SECONDARY MARKET
                                            |
                                  Seaport ERC-721 transfer
                                            |
                                            v
                                      YieldBankNFT
```

### 5.1 Initial portfolio implementation

The initial implementation stays deliberately narrow:

- the Core sleeve directly holds the collection-configured set of reviewed Robinhood Stock Tokens;
- Stock Token economic distributions are reflected through the tokens' rebasing multiplier rather
  than modeled as a separate protocol dividend claim;
- the USDG sleeve holds USDG directly and does not deposit it into a lending venue;
- the Market-Making sleeve holds `$INJOH`/WETH Delta positions only through a separately reviewed,
  synchronous adapter;
- strategy actions are explicit allocation-operator transactions; there is no automatic keeper,
  queued-withdrawal state machine, or strategy action during mint;
- each sleeve's maximum adapter count, maximum per-adapter allocation, and maximum operator-accepted
  loss are constructor configuration committed by the deployment manifest;
- future venues extend the same small adapter interface and registry/codehash checks without changing
  minting, proceeds custody, NFT ownership, or primary entitlement accounting.

The generic adapter boundary is part of v1. A concrete Delta adapter cannot enter a production
manifest until the exact `$INJOH` token, `$INJOH`/WETH pool, entry route, position parameters,
valuation method, and complete-exit behavior have passed the integration gate. Those values are not
guessed or embedded as protocol defaults.

## 6. Lifecycle and state model

### 6.1 Collection state

```text
DEPLOYED --> ACTIVE <--> INVESTMENT_PAUSED --> CLOSED
                |
                +-- minting may continue while investment is paused
                    if the OpenSea Drop remains active
```

- `DEPLOYED` exists only during construction and registration.
- `ACTIVE` means mint, transfer, settlement, and redemption are available.
- `INVESTMENT_PAUSED` blocks new manual allocations and strategy actions but does not block transfers, settlement, or redemption.
- `CLOSED` is reached only when `mintedSupply == maxSupply` and the final live Yield Bank is redeemed. If unminted capacity remains when live supply reaches zero, the collection stays `ACTIVE`; no owner-finalization mechanism is introduced.

### 6.2 Token state

```text
UNMINTED --> ACTIVE --> BURNING --> BURNED
               |
               +-- backing status is separate:
                   PENDING_ALLOCATION --> ALLOCATED --> CLAIMED_TO_ACCOUNT
```

- Minted tokens are `ACTIVE` immediately.
- Investment status is not a token transfer state.
- A token can be transferred while backing is pending.
- A token can be burned while backing is pending; the proceeds vault releases the token's recorded backing entitlement in WETH through the normal exit-tax path.

## 7. OpenSea-compatible mint adapter

### 7.1 `YieldBankNFT`

Replace the collection-only custom mint entry point with the exact OpenSea-supported SeaDrop token interface verified in Phase 0.

Required behavior:

1. Only the pinned Robinhood Chain SeaDrop contract may invoke the primary mint callback.
2. The SeaDrop address and its runtime code hash are included in the collection integration binding and release manifest.
3. `maxSupply` is read from immutable collection configuration and enforced for every quantity.
4. Token IDs remain sequential from `1` through `maxSupply`.
5. For every token ID, the collection deploys or records its deterministic account and initializes distributor debt before any external receiver callback can observe the NFT.
6. The NFT reports the minted token range to `YieldBankProceedsVault` before control returns to SeaDrop for payout.
7. If the payout fails, the complete SeaDrop transaction reverts, including NFT minting and account initialization.
8. `tokenURI`, `contractURI`, ERC-165, ERC-721, and EIP-2981 behavior must satisfy OpenSea metadata discovery.
9. Standard `approve`, `setApprovalForAll`, `transferFrom`, and `safeTransferFrom` remain available for Seaport.
10. Transfer eligibility may use only recipient-address state available during a standard ERC-721 transfer. No proof argument may be required from Seaport.

### 7.2 OpenSea configuration

The deployment/operator runbook must configure:

- the Yield Banks NFT contract as the Drop collection;
- the per-collection `YieldBankProceedsVault` as the sole creator payout address;
- the exact immutable `maxSupply`;
- the intended OpenSea mint stages and price configuration;
- the allowed OpenSea fee recipient settings required for a hosted Drop;
- collection metadata and OpenSea URL;
- secondary creator-fee signaling separately from primary proceeds.

OpenSea configuration is operational state and must be recorded in the deployment manifest. The protocol must not depend on secondary royalties being paid.

## 8. Proceeds holding and exact accounting

### 8.1 `YieldBankProceedsVault`

`YieldBankProceedsVault` replaces `YieldBankSaleEscrow`. It is a holding and accounting contract, not an escrow and not a sale-success coordinator.

It stores:

- the pinned NFT, collection, SeaDrop, allocation operator, WETH, allocator, and fixed fee recipients;
- total accounted native proceeds;
- total pending backing;
- accrued but unreleased creator, Sinjoh, and operations amounts;
- sequential mint-receipt tranches;
- per-tranche token range, quantity, exact net proceeds, deterministic rounding allocation, pending backing, and allocation status;
- per-token primary-backing claim/withdrawal state without requiring a supply-sized loop.

### 8.2 Mint receipt handshake

```text
SeaDrop.mint(...)
  -> YieldBankNFT.mintSeaDrop(recipient, quantity)
      -> collection prepares token IDs/accounts/debt
      -> proceedsVault.noteMint(startTokenId, quantity)
      -> NFT mints the token range
  <- returns to SeaDrop
  -> SeaDrop sends exact creator payout to proceedsVault.receive()
      -> vault requires the pinned SeaDrop caller
      -> vault requires one pending mint note
      -> vault records exact received ETH against that range
      -> vault clears the pending note
```

The vault must reject an unsolicited normal ETH transfer. Forced ETH must not change accounted proceeds or allocation amounts; solvency checks use `balance >= accounted liabilities`, never exact raw balance equality.

### 8.3 Entitlement accounting

For each mint-receipt tranche:

- the collection-configured backing basis points become token backing entitlement;
- the collection-configured creator basis points become creator entitlement;
- the collection-configured Sinjoh basis points become Sinjoh entitlement;
- the collection-configured operations basis points become operations entitlement;
- division remainder is assigned deterministically and total accounting must equal the exact received amount;
- no asset leaves the vault during this accounting step.

The vault must support different net receipt amounts across OpenSea mint transactions without treating all tokens in the collection as if they paid the same amount. A tranche may contain multiple tokens minted in the same transaction; quotient and remainder rules must conserve every wei.

## 9. Manual proceeds allocation

### 9.1 Authority

- Only the collection's configured allocation operator may start a primary allocation.
- The expected production operator is a Sinjoh-controlled multisig supplied in the deployment manifest.
- The guardian may pause allocations.
- Operator rotation requires the collection timelock.
- No operator call may choose an arbitrary recipient, sleeve, router, pool, or asset.

### 9.2 Allocation transaction

The operator selects a bounded contiguous range of complete, unallocated receipt tranches and supplies only guarded execution inputs such as minimum outputs, minimum shares, and deadlines.

The transaction atomically:

1. Computes exact backing and fee liabilities from stored tranche records.
2. Marks the selected tranches in progress before external calls.
3. Transfers the stored creator, Sinjoh, and operations amounts to their fixed recipients.
4. Wraps only the backing amount from native ETH to the pinned WETH contract.
5. Allocates WETH at the collection's immutable configured sleeve weights through codehash-pinned routes.
6. Measures actual route input consumption and actual sleeve shares received.
7. Records the resulting three sleeve-share entitlements per tranche and token with deterministic remainder handling.
8. Clears every temporary allowance.
9. Marks the tranches allocated.

If any leg fails, the whole transaction reverts and all native proceeds remain accounted in the vault.

The implementation batch bound is selected from Robinhood Chain gas profiling. It is a transaction-safety bound, not a collection supply rule.

### 9.3 Claim to token account

Primary sleeve shares remain claimable by token ID and follow the NFT through transfers. Settlement or redemption moves a token's exact primary sleeve-share entitlement into its deterministic treasury account exactly once.

Ongoing collection revenue continues to use the existing lazy distributor accumulator. Primary backing must not use the global live-supply accumulator because tokens may have different receipt amounts and allocation times.

## 10. Redemption before and after allocation

### 10.1 Pending allocation

When an `ACTIVE` token is burned before its primary backing is allocated:

1. Settle ongoing distributor claims.
2. Read the token's exact pending native-backing entitlement from its receipt tranche.
3. Mark that entitlement withdrawn before external calls.
4. Wrap the backing amount to WETH.
5. Apply the existing 5% exit tax in WETH unless this is the terminal live token.
6. Accrue the tax to the remaining live tokens through the distributor.
7. Transfer the remainder to the snapshotted holder.
8. Leave the token's already-recorded creator, Sinjoh, and operations liabilities in the vault for the next manual fee release/allocation transaction.
9. Burn the NFT and close its deterministic account.

### 10.2 Allocated backing

When an `ACTIVE` token is burned after allocation:

1. Claim any unclaimed primary sleeve shares to its account.
2. Settle ongoing distributor claims.
3. Burn the NFT.
4. Apply the existing in-kind exit tax to every tracked asset unless terminal.
5. Transfer the remaining assets to the snapshotted holder.
6. Close the account.

No price oracle, swap, strategy withdrawal, or OpenSea call is allowed in the core burn path.

## 11. Contract changes

### 11.1 Remove

- `sinjoh-contracts-v2/src/yield-banks/YieldBankSaleEscrow.sol`
- sale/refund methods, events, errors, storage, and states from `YieldBankCollection.sol`
- WETH mint approval and collection mint entry point from `YieldBankCollection.sol`
- sale-lock approval logic from `YieldBankNFT.sol`

### 11.2 Add

- `sinjoh-contracts-v2/src/yield-banks/YieldBankProceedsVault.sol`
- verified OpenSea/SeaDrop interfaces under `sinjoh-contracts-v2/src/yield-banks/interfaces/`
- receipt-tranche and primary-entitlement types in `YieldBankTypes.sol`
- native-to-WETH/manual primary allocation entry point with bounded tranche processing
- OpenSea-compatible contract metadata support
- deployment script and release-manifest generation for the complete system

### 11.3 Modify

- `YieldBankCollection.sol`: configurable supply, immediate active mint lifecycle, account/debt initialization, pending-backing burn, and close semantics
- `YieldBankNFT.sol`: verified SeaDrop mint interface and standard OpenSea transfer compatibility
- `CollectionPortfolioAllocator.sol`: proceeds-vault authorization, exact input-consumption checks, and primary tranche allocation output
- `YieldBankDistributor.sol`: keep ongoing revenue/exit-tax accounting; do not overload it with unequal primary entitlements
- `YieldBankSystemFactory.sol`: include collection config, collection salt, SeaDrop binding, proceeds vault, and every component plan record in the committed system plan hash
- `YieldBankCollectionFactory.sol`, registries, interfaces, renderer, README, ABIs, and deployment manifests to use the corrected topology

## 12. SDK plan

Update `/Users/dsb/sinjoh-sdk/packages/sdk/src/yield-banks.ts` and generated ABI exports:

- change `maxSupply: 3000` to a validated positive per-collection value;
- replace `saleEscrow` with `proceedsVault`;
- remove sale deadline, refunded supply, total-paid sale success, WETH mint approval, and direct collection mint helpers;
- add OpenSea collection/drop URL fields;
- add receipt-tranche, pending backing, allocated backing, and manual allocation views;
- add operator transaction preparation for bounded tranche allocation;
- retain settle, transfer, and burn helpers using dynamic `maxSupply` validation;
- verify runtime code at every manifest address before constructing writes;
- validate integer basis points, exact 10,000-basis-point sums, positive backing/sleeve weights, SeaDrop binding, WETH binding, and the collection configuration hash;
- expose complete addresses in all formatted output.

The Sinjoh SDK does not submit primary mint transactions. The user mints on OpenSea.

## 13. Indexer and API plan

### 13.1 Indexer

Update `/Users/dsb/sinjoh-platform/sinjoh-indexer` schemas and handlers:

- remove sale escrow, sale state, refund count, deadline, and fixed-supply fields;
- add `maxSupply`, `proceedsVault`, `seaDrop`, OpenSea URL, accounted proceeds, pending backing, released fees, allocated backing, next tranche, and pending tranche count;
- index mint receipt, primary allocation, primary claim, pending-backing redemption, operator rotation, and allocation-pause events;
- derive minted and live supplies exclusively from canonical events with reorg-safe idempotency;
- preserve strategy and ongoing distributor state;
- correct existing strategy withdrawal accounting so requested assets, returned assets, and remaining position units cannot drift.

### 13.2 API

Update the Yield Banks endpoints in `/Users/dsb/sinjoh-platform/supabase/functions/raffle/index.ts`:

- list endpoint returns dynamic supply and OpenSea links;
- detail endpoint returns proceeds-vault and allocation state instead of sale state;
- token detail returns pending versus allocated backing;
- backing reconciliation includes the proceeds vault's accounted native liabilities and invested sleeve liabilities at one block;
- a healthy response requires all configured liability sources to be queried successfully; missing reads cannot produce a false-green result;
- operator data is read-only; no API endpoint holds an allocation signing key.

## 14. UI plan

Update the Yield Banks pages in `/Users/dsb/.codex/worktrees/yield-banks-ui`:

- replace the direct WETH approval/mint interface with **Mint on OpenSea**;
- add **View / buy / sell on OpenSea** for secondary activity;
- show `mintedSupply / maxSupply` dynamically;
- remove sale success, failed sale, refund, deadline, and escrow language;
- show actual primary status as **Proceeds pending allocation**, **Partially allocated**, or **Allocated**;
- show that pending proceeds are held but not invested;
- preserve settle, transfer, and burn actions with dynamic token-ID bounds;
- clearly disclose that secondary creator fees are realized only when paid, not guaranteed;
- never imply that reaching max supply unlocks backing.

Manual allocation is performed through a reviewed operator script/SDK transaction. A public admin dashboard is not required for v1.

## 15. Deployment and OpenSea onboarding

Each collection deployment must produce a signed/reviewed manifest containing:

- chain ID;
- collection ID and immutable `maxSupply`;
- collection, NFT, proceeds vault, account implementation, distributor, revenue router, operations reserve, allocator, timelock, guardian, sleeves, WETH, SeaDrop, renderer, strategies, feeds, pools, and routes;
- complete address, runtime code hash, version, and provenance for each contract;
- factory salt, full collection configuration hash, and full system plan hash;
- allocation operator and all fixed recipients;
- OpenSea collection slug/URL and recorded Drop configuration;
- OpenSea platform fee observed at configuration time;
- metadata base/contract URI provenance;
- deployment and verification transaction hashes.

The launch runbook is:

1. Verify Robinhood Chain SeaDrop and Seaport addresses and runtime hashes.
2. Deploy and verify the complete Yield Banks collection system deterministically.
3. Confirm predicted and deployed addresses match the manifest.
4. Configure the OpenSea Drop with the NFT and proceeds vault.
5. Re-read the live OpenSea configuration and compare it with the manifest.
6. Execute a canary mint.
7. Confirm NFT ownership, deterministic account, receipt tranche, proceeds-vault accounting, OpenSea metadata, and secondary listing support.
8. Execute a canary manual allocation with guarded minimums.
9. Confirm exact fee conservation and sleeve-share entitlement.
10. Test a secondary transfer and redemption.
11. Open the remaining mint stage only after all checks pass.

## 16. Test and verification plan

### 16.1 Contract unit and fuzz tests

- configurable supplies of 1, 2, 3,000, and values above 3,000 with no magic-number behavior;
- exact max-supply enforcement for multi-mint quantities;
- unauthorized SeaDrop and wrong-codehash rejection;
- account/debt initialization before ERC-721 receiver callbacks;
- exact mint-note/payout handshake and rollback when payout fails;
- multiple mint transactions, quantities, and net receipt amounts;
- per-tranche quotient/remainder conservation for every wei;
- unsolicited ETH rejection and forced-ETH exclusion from accounted proceeds;
- no external transfer, wrap, approval, or investment during mint;
- immediate transfer and approval after mint while allocation is pending;
- OpenSea/Seaport-style transfer through an approved operator;
- address-only transfer eligibility and rejection of ineligible recipients;
- operator-only allocation, guardian pause, timelocked operator rotation;
- arbitrary recipient/router/sleeve rejection;
- nonzero minimums, deadline enforcement, codehash pinning, input-consumption measurement, and allowance clearing;
- atomic rollback for every allocation leg;
- exact net-proceeds conservation under non-default configured primary economics;
- exact backing allocation conservation under non-default configured sleeve weights;
- unequal tranche backing and exact sleeve-share entitlements;
- pending-backing burn, exit-tax redistribution, and terminal no-tax behavior;
- allocated and unclaimed backing burn;
- new tokens cannot claim old ongoing revenue;
- transferred NFTs retain pending and allocated entitlement by token ID;
- final live burn with mint capacity still open does not incorrectly close the collection;
- reaching max supply does not release or allocate funds and creates no sale-success state;
- factory plan hash commits to components, configuration, salt, SeaDrop, and runtime hashes;
- stateful invariants for solvency, conservation, one-time claim, and one-time burn.

### 16.2 Core invariants

1. `mintedSupply <= maxSupply` for every collection.
2. Every minted token has exactly one deterministic account and one primary receipt entitlement.
3. Accounted native liabilities never exceed the proceeds vault's native balance.
4. Raw surplus ETH cannot increase a token entitlement or satisfy an allocation amount.
5. Received net proceeds equal pending backing plus withdrawn backing plus allocated backing at recorded native cost basis plus all fee liabilities/releases plus deterministic dust.
6. A token's primary entitlement can be claimed or withdrawn exactly once.
7. No sale threshold, time, or supply count can move proceeds.
8. Only a successful manual operator transaction can invest pending backing.
9. NFT transfer changes the beneficiary of token-bound claims without moving the claims.
10. Redemption cannot call OpenSea, SeaDrop, an oracle, a swap route, or a strategy.
11. Backing cannot move to an administrator or arbitrary recipient.
12. The final live token receives distributor dust and pays no exit tax.

### 16.3 Integration and fork tests

- Robinhood Chain fork verification of WETH behavior and every pinned dependency;
- verified SeaDrop interface/runtime binding on Robinhood Chain;
- hosted OpenSea canary Drop using the deployed custom collection;
- primary mint through OpenSea with exact vault receipt reconciliation;
- OpenSea metadata refresh and collection-level metadata;
- Seaport listing, approval, purchase, and post-transfer redemption;
- indexer replay, reorg, duplicate-event, and same-block liability reconciliation;
- API failure injection for RPC timeout, stale indexed block, missing code, and partial liability reads;
- UI tests for OpenSea links, dynamic supply, pending allocation, partial allocation, allocated backing, transfer, and burn;
- gas profiling to select the maximum safe receipt-tranche allocation batch.

### 16.4 Coverage map

```text
CODE PATHS                                            USER FLOWS
[NEW] SeaDrop mint adapter                            [NEW] Primary mint on OpenSea
  |-- authorized SeaDrop                                |-- Drop page -> wallet -> mint [E2E]
  |-- supply available                                  |-- NFT appears with metadata [E2E]
  |-- recipient eligible                                `-- proceeds remain pending [E2E]
  |-- account/debt initialized
  `-- payout succeeds or all state reverts             [NEW] Secondary sale
                                                        |-- approve/list through Seaport [E2E]
[NEW] Proceeds vault                                    |-- buyer receives NFT [E2E]
  |-- pending mint handshake                            `-- token entitlement follows [E2E]
  |-- exact receipt tranche
  |-- deterministic rounding                           [NEW] Manual allocation
  |-- unsolicited payment rejected                      |-- operator submits guarded batch [E2E]
  `-- forced ETH excluded                               |-- fee recipients paid exactly
                                                        `-- sleeve claims recorded exactly
[CHANGED] Collection lifecycle
  |-- dynamic max supply                               [CHANGED] Redemption
  |-- immediate ACTIVE token                            |-- pending backing -> WETH [E2E]
  |-- no sale states                                    |-- allocated backing -> shares [E2E]
  `-- close condition separate from sellout             `-- clear recoverable errors

[CHANGED] SDK/indexer/API/UI
  |-- runtime-hash verified reads/writes
  |-- event replay and liability reconciliation
  |-- dynamic supply and allocation status
  `-- OpenSea links instead of direct mint
```

Every branch above requires happy-path, boundary, authorization, reentrancy, rollback, and conservation coverage before deployment.

## 17. Realistic failure modes

| Failure | Required handling | User-visible result |
|---|---|---|
| OpenSea calls an unapproved mint contract | Mint reverts before token creation | OpenSea shows a failed mint; no funds or NFT move |
| SeaDrop payout call fails | Entire mint transaction reverts | Buyer retains funds and receives no NFT |
| Mint succeeds but allocation is not yet executed | Receipt remains fully accounted in the vault | NFT shows “Proceeds pending allocation” and remains transferable/redeemable |
| Operator submits stale slippage data | Allocation reverts atomically | Funds remain pending; operator retries with reviewed bounds |
| One portfolio leg fails | Whole allocation reverts | No partial fee or backing movement |
| Direct donation or forced ETH changes raw balance | Donation is rejected or excluded from accounting | No entitlement or solvency distortion |
| Indexer is stale or partially unavailable | API reports degraded/unavailable, not healthy | UI shows data unavailable instead of zero backing |
| OpenSea does not enforce a royalty | No protocol state depends on it | UI reports only royalties actually received |
| Recipient fails eligibility check | ERC-721 transfer reverts | OpenSea purchase cannot complete for that address |
| Strategy is illiquid | Core NFT burn returns sleeve shares and liquid pending backing | Holder retains enforceable sleeve claims |

## 18. Implementation order

### Phase 0: External-integration gate

- Run a fresh Brainblast covering OpenSea, SeaDrop, Seaport, Robinhood Chain, OpenZeppelin, and the existing portfolio integrations.
- Resolve the exact Robinhood Chain SeaDrop address, runtime hash, interface, payout ordering, OpenSea Studio custom-contract support, and canary process.
- Update the canonical architecture and manifest schema only with fetched official/onchain facts.

Exit criterion: a verified OpenSea integration record with no unresolved mint-interface or payout-order question.

### Phase 1: Contract lifecycle replacement

- Replace sale/refund state with the corrected collection/token states.
- Make `maxSupply` immutable and collection-configurable.
- Add immediate active mint bookkeeping and corrected close semantics.
- Remove every escrow/refund/sellout path and its tests.

Exit criterion: unit tests prove no supply value has special behavior beyond the configured cap.

### Phase 2: SeaDrop adapter and proceeds vault

- Implement the verified mint interface.
- Implement mint-note/payout handshake and receipt tranches.
- Pin SeaDrop and runtime code hash.
- Add OpenSea metadata support.

Exit criterion: a SeaDrop-compatible mock and Robinhood fork/canary path prove atomic mint plus exact idle proceeds accounting.

### Phase 3: Manual allocation and redemption

- Add operator authorization, pause/rotation controls, and guarded batch allocation.
- Allocate exact tranche backing into sleeves.
- Add primary claims to token accounts.
- Support pending and allocated redemption.
- Complete conservation and stateful invariant suites.

Exit criterion: every received wei and every sleeve share is assigned exactly once across mint, allocation, transfer, settlement, and burn sequences.

### Phase 4: Factory, deployment, and manifest

- Update deterministic system deployment for the proceeds vault and SeaDrop binding.
- Fix the system plan commitment to include config and salt.
- Add production deployment scripts, verification, and complete manifests.

Exit criterion: a clean environment can predict, deploy, verify, and reproduce the entire system from one reviewed manifest.

### Phase 5: SDK and ABI release

- Publish corrected ABIs and Yield Banks SDK types/helpers.
- Remove obsolete mint/approval/refund APIs.
- Add OpenSea, proceeds, allocation, and dynamic-supply APIs.

Exit criterion: SDK typecheck/tests pass and manifest verification rejects every wrong address or runtime hash.

### Phase 6: Indexer and API

- Migrate schemas and event handlers.
- Add proceeds/allocation reconciliation.
- Correct strategy state drift and false-green backing responses.

Exit criterion: replay and failure-injection tests pass against the new event model.

### Phase 7: UI

- Replace direct mint with OpenSea navigation.
- Replace sale/refund UI with proceeds/allocation state.
- Preserve holder settlement, transfer, and redemption flows.

Exit criterion: production build, typecheck, lint, unit tests, and browser E2E pass for mobile and desktop.

### Phase 8: Security and launch rehearsal

- Run full static analysis, coverage, fuzzing, stateful invariants, fork tests, gas profiling, and independent audit review.
- Deploy a bounded canary collection and complete the OpenSea launch runbook.
- Freeze and sign the production manifest only after canary evidence is reviewed.

Exit criterion: no unresolved P0/P1 issue, complete launch evidence, and explicit production approval.

## 19. Dependency and parallelization plan

| Workstream | Modules | Depends on |
|---|---|---|
| A. External verification | research, deployment manifests | none |
| B. Contract lifecycle | contracts, contract tests | A |
| C. Proceeds/allocation | contracts, contract tests | B |
| D. Factory/deployment | contracts, deployment scripts | C |
| E. SDK/ABIs | SDK | C ABI freeze |
| F. Indexer/API | platform indexer, Supabase function | C event freeze |
| G. UI | Yield Banks UI | E and F interfaces |
| H. Security/rehearsal | all modules | D, E, F, G |

Execution lanes after the contract ABI/event freeze:

```text
Lane A: external verification -> lifecycle -> proceeds/allocation -> factory/deployment
Lane B:                                                    -> SDK
Lane C:                                                    -> indexer/API
Lane D:                                                         SDK + API -> UI
Final: all lanes -> security review -> OpenSea canary -> production manifest
```

Contract phases remain sequential because they share lifecycle and accounting storage. SDK and platform work may proceed in parallel after the ABI/event freeze. UI follows their stable interfaces.

## 20. What already exists

Reuse after correction:

- deterministic token-bound accounts;
- ongoing distributor accumulator and final-token dust handling;
- three sleeve categories and immutable per-collection portfolio weighting;
- revenue router, operations reserve, timelock, guardian, eligibility policy boundary, renderer, registries, and codehash-binding helpers;
- holder settlement, transfer-bound ownership, in-kind burn, and 5% exit-tax model;
- SDK manifest foundation, indexer entities, backing API, and Yield Banks UI routes;
- existing Foundry, TypeScript, API, and UI test infrastructure.

Replace rather than reuse:

- `YieldBankSaleEscrow`;
- collection sale state machine;
- custom WETH mint entry point;
- global one-time seed distribution across a presumed final supply;
- fixed-3,000 validations and presentation;
- sale/refund indexer, API, SDK, and UI models.

## 21. Not in scope

- A Sinjoh-hosted primary mint checkout; primary minting occurs on OpenSea.
- WETH/ERC-20 primary payment; current SeaDrop primary minting uses native value.
- Buyer refunds or sale cancellation logic.
- A minimum raise, deadline, sellout-success, or owner-finalization mechanism.
- A protocol-wide supply default or fixed supply.
- Proof-bearing transfer eligibility that Seaport cannot provide.
- Guaranteed secondary royalties or reliance on forecast royalties as backing.
- A public operator/admin dashboard; v1 manual allocation uses a reviewed multisig transaction flow.
- Free-mint receipt accounting; Yield Banks primary mints are paid mints unless separately specified later.
- OpenSea Seaport Hooks or experimental marketplace-specific transfer hooks.
- Automatic investment on mint.
- Automatic conversion of in-kind redemption into one output asset.
- Strategy integrations that have not passed their separate address, ABI, codehash, liquidity, and oracle gates.

## 22. Definition of done

Yield Banks v1 is complete only when:

1. Collection supply is configured per deployment and no source layer assumes 3,000.
2. A buyer can mint on OpenSea on Robinhood Chain.
3. The mint creates the NFT and deterministic account while leaving exact net proceeds idle in the proceeds vault.
4. No sale-success, refund, deadline, or sellout-release code remains.
5. A holder can list, buy, sell, and transfer through OpenSea/Seaport while proceeds are pending or allocated.
6. An authorized Sinjoh operator can manually allocate bounded receipt tranches with exact, guarded, atomic accounting.
7. Pending and allocated tokens can both redeem without depending on OpenSea, prices, or strategy liquidity.
8. Contracts, SDK, indexer, API, UI, deployment scripts, manifests, and documentation all expose the same corrected model.
9. Conservation, solvency, one-time claim, transfer-following entitlement, and redemption invariants pass under fuzzed state sequences.
10. The complete production deployment is reproducible from a reviewed manifest with every address and runtime code hash verified.

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
|---|---|---|---:|---|---|
| CEO Review | `/plan-ceo-review` | Scope and strategy | 0 | Not run | Product corrections came directly from the user |
| Codex Review | `/codex review` | Independent second opinion | 0 | Not run | Not required to finalize this plan |
| Eng Review | `/plan-eng-review` | Architecture and tests | 1 | Clear | Corrected lifecycle, exact proceeds accounting, pending-backing redemption, OpenSea boundary, and full test plan folded into the plan |
| Design Review | `/plan-design-review` | UI/UX gaps | 0 | Not run | UI implementation follows the ABI/API freeze |
| DX Review | `/plan-devex-review` | Developer experience gaps | 0 | Not run | Not required for architecture finalization |

**VERDICT:** ENG CLEARED — ready to implement beginning with the Phase 0 OpenSea integration gate.

NO UNRESOLVED DECISIONS
