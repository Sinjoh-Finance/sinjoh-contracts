# Funding Bands UI integration

UI sweep performed against the public Pons interface on 2026-08-12. Pages
inspected included Explore, Create with Advanced expanded, a bonding-curve Pons
v2 token, a graduated Pons v2 token, and the disconnected Profile state at
mobile, tablet, and desktop widths. No wallet was connected and no transaction
was submitted.

## Existing Pons flow

The Create page currently asks for token identity, paired asset, developer buy,
and then advanced creator-economics fields: creator wallet, creator tax, and
snipe-tax exemptions. Its summary card shows launch fee, pair, trade fee, launch
window, graduation threshold, and locked liquidity.

A Pons v2 token page already has the state distinction Funding Bands needs:

- before graduation it shows `Bonding curve` and progress to graduation;
- after graduation it shows `Uniswap v4`;
- both states expose creator, fixed supply, pair asset, market cap, and creator
  fee information.

The Profile page is wallet-gated and describes itself as the place for positions,
PnL, and trades. It is the natural portfolio surface for a creator's band ladder.

## Recommended launch integration

Place a collapsed **Scale out with Funding Bands** card directly below
**Developer buy** and above **Advanced**. It is inventory policy tied to the
developer buy, not a creator-fee setting. Enabling it should open a dedicated
step or drawer; ten editable ranges will not fit cleanly inside the existing
single-column Advanced disclosure.

The setup step should contain:

1. Token inventory allocated now, with an optional equal-split shortcut.
2. One to ten rows containing lower market cap, upper market cap, token amount,
   and destination.
3. Destination choice per row: creator wallet or a validated Sinjoh Fee Router.
4. A chart preview with the current/graduation market cap and every band range.
5. Requested USD boundaries alongside the estimated fixed WETH boundaries.
6. A fee summary: Funding Bands charges 1% of each band's realized WETH. A Fee
   Router destination subsequently charges its own 1% intake fee, producing a
   1.99% combined effective fee on the original WETH.
7. An irreversible-action acknowledgement: after onchain activation, inventory,
   ranges, and destinations cannot be withdrawn or edited.

The launch summary card should add:

```text
Funding Bands   5 bands · 8% of supply · activates after graduation
Destination     3 creator · 2 fee router
```

## Pons v2 transaction timing

Pons v2 has no Uniswap v4 pool until its bonding curve graduates. Funding Bands
cannot create or fund concentrated positions at launch time.

The launch UI may save a Funding Bands **draft**, keyed by creator and predicted
token address, but it must not describe that draft as committed inventory. The
creator still holds the developer-buy tokens and can spend them before
graduation.

After graduation, show a creator-only **Activate Funding Bands** task on the
token page and Profile page. The current contract requires:

1. ERC-20 approval for the selected subject-token amount.
2. `SinjohFundingBands.create(...)` to freeze the profile and band definitions.
3. `SinjohFundingBands.fund(...)` to place the inventory.

The UI should present this as one guided operation with three wallet steps and
resume safely after any interruption. A future `createAndFund` entry point could
reduce this to approval plus one protocol transaction, but the UI must not assume
that function exists today.

Only native-ETH and canonical-WETH Pons v2 launches are eligible in the current
release. For USDG or another Pons pair, keep the control visible but disabled with
the precise explanation: **Funding Bands currently supports ETH/WETH pairs.**

## Token page

Add a public **Funding Bands** panel below the market summary and above recent
trades:

- a market-cap ladder showing each lower/upper range;
- status per band: Draft, Awaiting graduation, Ready to activate, Active,
  Settled, or Delivered;
- inventory deposited and current subject/WETH composition;
- immutable destination with a creator or Fee Router label;
- gross realized WETH, 1% protocol fee, net WETH, and delivery state;
- **Arm settlement** once the upper edge is crossed;
- the 15-minute confirmation countdown and persistent eligible state while price
  remains above the band, with a reset when a below-band state is observed or
  more inventory is funded;
- permissionless **Settle** and **Send proceeds** actions when available.

For the creator, an active band may expose **Add tokens** only while the profile
guard is below its lower boundary. Once the boundary is entered, disable the
action; it may be re-enabled if the guard later confirms price has returned below
the lower boundary before settlement.

## Profile page

Add a **Funding Bands** tab next to positions/PnL with four task groups:

- **Drafts**: locally or server-saved launch configurations.
- **Needs action**: graduated launches waiting for creator activation or bands
  waiting for token approval/funding.
- **Active ladders**: live band progress and available later deposits.
- **Proceeds**: settled WETH/subject balances and delivery status.

The creator identity must come from the immutable launch `deployer`, not Pons's
mutable creator-fee recipient. If those addresses differ, label both explicitly.

## Data and contract reads

The frontend needs:

- Pons v2 launch phase, pair asset, immutable deployer, and graduated pool data;
- Funding Bands `AccountCreated`, `BandConfigured`, `BandFunded`,
  `BandSettlementArmed`, `BandSettlementDisarmed`, `BandSettled`, `ProceedsSent`,
  and `ProtocolFeeSent` events in the indexer;
- `getAccount`, `getBand`, `proceedsOwed`, `totalLiability`, and `protocolOwed`;
- current ETH/USD for previews, while making clear the onchain snapshot is taken
  only when `create` executes;
- canonical v4 spot for Pons v2 `create`, `fund`, and `armSettlement`, with
  empty `guardData` for this profile;
- guard confirmation state to render waiting, active countdown, and permanent
  settlement eligibility; `settlementArmedAt` remains the manager hold timestamp;
- Fee Router `creator`, `subject`, and intake-asset validation before allowing a
  router destination, plus equality with the manager's immutable
  `feeRouterCodehash`.

## UI issues observed during the sweep

- The sticky navigation bar overlays the middle of the Create form at mobile,
  tablet, and desktop widths. Fix its stacking/offset behavior before adding the
  taller Funding Bands editor.
- The compact mobile layout is already long. Funding Bands should use a focused
  step/drawer with sticky Next/Back controls, not ten inline rows on the base
  launch form.
- The public Create and token-detail pages were console-clean during isolated
  checks. The anonymous Profile state exposes no creator controls, so connected
  wallet behavior still needs a dedicated integration test once a frontend is
  available in the Sinjoh repository.
