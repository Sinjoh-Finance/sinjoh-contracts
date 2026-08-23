# Funding Bands

## 1. Objective

`ProjectFundingBandsV2` lets project governance commit project-token inventory to one-sided
concentrated-liquidity bands above the current platform market cap. When price moves through a band,
the inventory converts into quote proceeds and the proceeds are sent to the creator, Treasury,
Router, buyback/burn, buyback/airdrop, Raffle, or Basket via the Treasury.

Bands may be created after launch. A band that was approved earlier, or whose range was crossed in
the past and later fell below it, may be activated as long as the current verified market cap is
below the band's lower bound at activation.

## 2. Market-cap definition

For deterministic bands, the protocol uses the fixed `referenceSupply` stored in the project
registry:

```text
platformMarketCap = subjectQuoteTwapPrice * referenceSupply * quoteUsdPrice
```

This is a fixed-supply fully diluted value. Token burns do not move a band boundary by changing the
denominator. The UI must label the value and show the underlying TWAP window, USD source timestamp,
and effective rounded pool ticks.

The first release requires:

- a platform-approved subject/quote TWAP guard;
- a platform-approved quote/USD oracle when quote is not USD-denominated;
- a TWAP window at least as long as the configured 5-minute-to-24-hour confirmation period;
- fresh oracle observations;
- canonical pool and launch-record verification.

## 3. Band configuration

```solidity
enum ProceedsDestination {
    CREATOR,
    TREASURY,
    BUYBACK_BURN,
    BUYBACK_AIRDROP,
    ROUTER,
    RAFFLE,
    BASKET_VIA_TREASURY
}

struct BandConfig {
    uint128 lowerMarketCapUsdE8;
    uint128 upperMarketCapUsdE8;
    uint128 subjectAmount;
    ProceedsDestination destination;
    bytes destinationConfig;
}
```

Rules:

- one to ten live/unsettled bands per project;
- lower bound is nonzero and lower than upper bound;
- live bands do not overlap and may have gaps; their IDs preserve creation history even when the
  live-band array changes order during removal;
- effective ticks remain distinct after pool tick-spacing rounding;
- subject amount is nonzero and fully prefunded;
- Treasury is required; optional Router, Airdrop, and Raffle addresses are validated against the
  same Registry project before the Bands contract is deployed;
- destination config is bounded and hashed before funding;
- a funded band's bounds, inventory, pool, and destination are immutable.

## 4. Post-launch creation and retroactive eligibility

Only the project's immutable controller may create/fund a band. Creation checks the current
TWAP-derived platform
market cap at execution time:

```text
currentMarketCap < lowerMarketCap
```

There is deliberately no “price has never crossed this bound” historical check. If current price
has returned below the lower bound, governance may create/fund the band. This implements the
requested post-launch/retroactive setup behavior without pretending to reconstruct an authoritative
all-time price history on-chain.

The controller batches `Treasury.send(subject, amount, bands)` and `bands.createBand(...)` in one
governance execution. The first call prefunds exact inventory and the second atomically validates
current eligibility and opens the position; if either call fails, both revert. A pending proposal
does not reserve inventory or freeze market-cap eligibility. If market cap reaches/exceeds the
lower bound before execution, the whole batch reverts and no tokens leave Treasury.

## 5. Funding and position custody

Treasury supplies project-token inventory before the controller's `createBand` or `increaseBand`
call in the same atomic batch. `uncommittedSubjectBalance()` makes prefunded inventory explicit and
subtracts every residual, delivery, and fee liability so one band cannot reuse another band's
tokens. The contract measures exact position spend and mints/increases one one-sided position per
band using only canonical pool/ticks derived from the band configuration.

Callers cannot provide a pool, ticks, recipient, hook, PositionManager, or alternate launch supply.
The manager accepts position NFTs only during an expected mint from the canonical PositionManager.

Committed inventory cannot be withdrawn, reassigned, or moved to another band. Additional funding
is permitted only while the current market cap remains below the lower bound and is added to the
same position.

## 6. Band lifecycle

```text
NONE -> ACTIVE -> ARMED -> SETTLED_PENDING_DELIVERY -> DELIVERED
                    |                  |
                    +-> ACTIVE         +-> retry or controller recovery
                        (reversal)
```

`armSettlement` is permissionless after the live/TWAP price reaches the configured settlement
boundary. A fresh final TWAP covering at least the complete confirmation period, plus an advancing
observation timestamp and ID, prevents a single-block crossing from settling the band. The default
confirmation period is 15 minutes; factory bounds are 5 minutes to 24 hours.

`settle` is permissionless after uninterrupted confirmation and requires a fresh observation whose
timestamp and ID both advance beyond the arming observation. It removes 100% of band liquidity,
collects quote principal and both-asset LP fees/residuals, closes the empty position, charges the
existing cumulative 1% service fee on realized quote proceeds, and executes the immutable
destination. A contract-wide remainder carry makes the fee on many band settlements equal the fee
on the same cumulative quote proceeds settled once.

If price reverses before confirmation, the band returns to ACTIVE. Once successfully settled, it
cannot be recreated under the same band ID or receive more funding.

## 7. Proceeds destinations

### CREATOR

Sends measured net quote proceeds and in-kind subject fees/residuals to the immutable creator.

### TREASURY

Deposits net proceeds into the registered Treasury as ordinary balance.

### BUYBACK_BURN

Performs a guarded quote-to-subject swap and burns the measured subject output. In-kind subject
fees are burned directly.

### BUYBACK_AIRDROP

Performs a guarded quote-to-subject swap and funds the project's Airdrop with the measured subject
output. In-kind subject fees are included. The Airdrop's holder/staker mode remains authoritative.

### ROUTER

Funds the project's Router, which executes its current governance-approved route set.

### RAFFLE

Normalizes into the immutable Raffle prize asset when needed and funds the registered Raffle through
its guarded route. No raffle settings are changed.

### BASKET_VIA_TREASURY

Deposits proceeds into the registered Treasury with `routeToBasket=true`. The Treasury's active
basket policy determines the Basket allocation. Bands do not fund a Basket directly in this mode.

Every conversion uses platform-approved adapters/guards fixed in the destination configuration.
The release approval root commits the exact chain, pool/runtime hashes, quote asset, fixed reference
supply, adapter/guard runtime hashes, slippage ceiling, and route-data hash. The constructor then
independently verifies that the selected guard and position adapter are bound to the exact Bands
address, subject, pool, and assets. A caller cannot substitute a route or weaken minimum output.

## 8. Failure handling

Settlement changes state only after the position NFT is burned, its reported liquidity is zero,
and all proceeds are measured against real balance deltas.
If destination execution fails, proceeds are recorded in destination-specific retry escrow and the
band remains `SETTLED_PENDING_DELIVERY`. Anyone may retry the immutable destination. Project
governance may redirect permanently incompatible escrow only to another allowed destination for the
same project through an explicit recovery proposal.

Position closure cannot be replayed and delivery retry never re-charges the service fee.
Permissionless surplus recovery deposits only balances above all residual, delivery, and fee
liabilities into the same-project Treasury, so accidental ERC-20 transfers are not stranded.

## 9. Events and views

Events:

- `FundingBandsCreated(projectId, subject, controller, creator, treasury, pool, quote,
  referenceSupply, guard, adapter, timing, approvalRoot)`;
- `BandCreated(projectId, bandId, lower, upper, subjectAmount, destination, configHash)`;
- `BandFunded(bandId, amount, positionId)`;
- `BandArmed(bandId, qualifyingSince, executableAt)`;
- `BandDisarmed(bandId, observedMarketCap)`;
- `BandSettled(bandId, grossQuote, protocolFee, netQuote, subjectResidual)`;
- `BandDeliveryEscrowed/DeliverySucceeded/DeliveryFailed/DeliveryRecovered(...)`;
- `ProtocolFeeSent(asset, amount)`.
- `SurplusRecovered(asset, amount)`.

Views return requested/effective bounds, arming timestamp and observation identity, position ID,
committed inventory, residual inventory, immutable destination config, live band IDs, exact delivery
and fee liabilities, uncommitted prefunding balance, and approval-leaf/hash helpers. The frontend
reads the approved guard for current market cap/source timestamps and simulates the exact governance
batch before proposing it.

## 10. UX and DevX contract

The normal creator flow is intentionally narrow:

1. choose one or more non-overlapping market-cap ranges, token amounts, and proceeds destinations;
2. review the fixed-supply FDV label, current verified market cap, effective pool ticks, and the
   exact Treasury amount to commit;
3. submit one governance proposal containing the complete Treasury-prefund + band-create batch;
4. follow ACTIVE, ARMED, pending-delivery, and DELIVERED status from indexed events and `bandStatus`.

The product does not ask creators for pool addresses, oracle addresses, adapters, PositionManager
addresses, tick values, Merkle leaves, proofs, slippage math, or raw destination bytes. Launcher/SDK
tooling selects approved integrations, derives canonical configs/proofs, checks module identity,
simulates the full batch, and translates custom errors into corrective UI copy. Keepers need no role
or project-specific configuration: they read live IDs and call arm, disarm, settle, retry, or fee
forwarding when the corresponding preflight succeeds.

## 11. Invariants

1. Every active band position is owned by the Funding Bands contract and maps to one band.
2. Committed inventory cannot be withdrawn before settlement.
3. Creation/funding succeeds only while current market cap is below the effective lower bound.
4. A band settles at most once and service fees are charged once on cumulative realized quote.
5. Destination success plus retry escrow equals all measured net proceeds and residuals.
6. No destination can cross project boundaries.
7. Position and swap approvals are zero after every successful external integration call.
8. Reference supply, controller, project identity, pool, quote asset, and integration approval root
   never change.
9. Surplus recovery cannot reduce a residual, delivery, or protocol-fee liability.

## 12. Acceptance criteria

1. Governance can create a new band months after launch when current market cap is below its lower
   bound.
2. Governance can create a band after a historical crossing when price has returned below its lower
   bound.
3. Creation reverts when current market cap is at or above the lower bound.
4. All seven destination modes deliver the documented asset flow in integration tests.
5. Buyback/burn decreases project-token total supply by measured purchased + residual tokens.
6. Buyback/airdrop funds the project's configured holder/staker Airdrop account.
7. Basket proceeds pass through Treasury and respect its current basket allocation.
8. A destination failure preserves exact proceeds for retry without reopening the position.
9. Band boundaries remain stable after project-token burns because `referenceSupply` is fixed.
10. The real Treasury and controller can atomically prefund and create a band with the production
    Treasury ABI.
11. A stale or replayed observation cannot create, arm, disarm, or settle a band.
12. Governance can recover a failed delivery to another typed same-project destination without
    reopening the position or charging the service fee again.
13. Splitting equal quote proceeds across multiple sequential bands cannot reduce the cumulative 1%
    service fee.
14. The approved market-cap guard's TWAP window cannot be shorter than the settlement confirmation
    period.

## 13. Out of scope

- withdrawing active band inventory;
- moving a funded band's bounds or destination;
- historical “never crossed” price proofs;
- downside bands below current price in the first release;
- arbitrary destination calls.
- creator-supplied external integration addresses or raw AMM configuration.
