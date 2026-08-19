# Sinjoh Funding Bands — Protocol and Simulation Report

> **Historical design review.** This report records the August 14, 2026 state
> of the implementation at the commit below. It predates the deployed Funding
> Bands generations and must not be read as the current deployment or security
> status. Use `DEPLOYMENT_PROVENANCE.md` and `mainnet-deployments.json` for
> current provenance.

**Report date:** August 14, 2026
**Implementation reviewed:** local `main` commit `038282ddce41645c70ee3740dea2a39fa2a96f45`
**Status at the time:** implemented and passing local tests; not pushed, not deployed, and not yet production-ready for Pons v2

## Executive summary

Sinjoh Funding Bands let a recognized token creator pre-allocate some of their own tokens into as many as ten one-sided concentrated-liquidity positions above the current market price.

As ordinary buyers push the token upward through a band, that position progressively converts from the creator's token into WETH. After both the live price and a manipulation-resistant reference price clear the band's upper boundary, anyone may settle the band. Settlement removes the position, charges Sinjoh's one-time 1% fee on realized WETH, and credits the remaining proceeds to either:

- the launch creator; or
- a matching Sinjoh Fee Router, which can implement strategies such as buybacks and burns.

The important mental model is:

> Funding Bands are an onchain scale-out ladder, not permanent liquidity and not a market-sell bot.

The creator supplies the inventory. Buyers consume that inventory through the AMM. Settlement only closes an already-crossed position and allocates its proceeds.

The simulations show that recycling every band's proceeds into buybacks and burns can remove roughly 6.4%–6.9% of the original supply under the tested configurations. It also creates increasingly large upward price shocks as the bands grow in WETH value. The final buyback in the ten-band run doubled the modeled price by itself, which makes immediate all-at-once buybacks unsafe as a production routing policy. Chunked, price-limited execution is strongly recommended.

## 1. What problem Funding Bands solve

Creators commonly want to recover capital or fund continued token development as a launch succeeds. The usual mechanism is to sell tokens into the market. That approach is simple, but it has two drawbacks:

1. discretionary wallet sales can surprise holders; and
2. a market sale removes active bid liquidity immediately and can produce a sharp red candle.

Funding Bands make the intended scale-out schedule visible and mechanical. Instead of waiting and later submitting a market sell, the creator places token-only liquidity in advance at chosen valuation ranges. Market demand performs the conversion over the full width of each band.

This does not eliminate sell-side pressure. The creator's tokens still enter circulation and buyers still pay WETH for them. The difference is execution: inventory is offered gradually across disclosed price ranges rather than through an arbitrary wallet sale at one moment.

## 2. Core mental model

Each funding band is a concentrated-liquidity position containing only the subject token when it is created below the band.

```text
Creator tokens
      │
      ▼
One-sided band above market
      │
      │ organic buys move through the range
      ▼
Subject inventory converts into WETH
      │
      │ spot + reference price clear upper boundary
      ▼
Permissionless settlement
      │
      ├── 1% of realized WETH → Sinjoh protocol recipient
      │
      └── net WETH + any subject proceeds → creator or Fee Router
```

The protocol supports one Funding Bands account per subject token and between one and ten ordered, non-overlapping bands. Gaps between bands are allowed.

## 3. Who can use it

Only the creator recognized by the supported launchpad at launch can create and fund a token's Funding Bands account.

The creator identity is snapshotted at account creation. Later changes to a launchpad's mutable creator-fee recipient do not transfer control of Funding Bands.

Anyone may perform operational actions that do not change ownership or economics:

- settle an eligible crossed band;
- send already-accounted proceeds to the band's fixed recipient; and
- send accrued protocol fees to the fixed protocol fee recipient.

Permissionless settlement and delivery make the system keeper-friendly without giving keepers custody or discretion over destinations.

## 4. Supported venues and assets

The implementation is restricted to Robinhood Chain, chain ID `4663`.

It has a common core with immutable launch profiles for:

- Uniswap v3-style launches, including a Pons v1 verifier; and
- Uniswap v4-style launches, including a Pons v2 verifier.

Only native ETH or canonical WETH quote configurations are accepted. Native ETH received during v4 settlement is wrapped into WETH before accounting and delivery.

The current support boundary is:

| Launch source | Venue | Current implementation state |
|---|---|---|
| Pons v1 | Uniswap v3 | Verifier and TWAP guard implemented; production fork signoff still required |
| Pons v2 | Uniswap v4 | Graduated native/WETH lifecycle implemented and locally tested; production v4 price guard and exact-bytecode fork tests still required |
| pools.trade | Intended v4 support | Product boundary identified; no active launch profile yet |
| letscash.fun | Intended v4 support | Product boundary identified; no active launch profile yet |

Profiles are frozen in the Funding Bands constructor. Supporting a new launchpad or materially different pool configuration requires a new deployment with the new verifier and guard included.

## 5. How creators configure bands

For each band, the creator chooses:

- lower market capitalization in USD;
- upper market capitalization in USD;
- destination: creator or Sinjoh Fee Router; and
- Fee Router address when the router destination is selected.

The contract requires:

- 1–10 bands;
- nonzero lower boundaries;
- lower boundary strictly below upper boundary;
- ordered, non-overlapping ranges;
- every lower boundary to remain above both guarded price observations when created or funded; and
- tick-rounded ranges that do not collapse to the same tick.

The configuration is intentionally rigid. There is no edit, cancel, withdrawal, reassignment, owner override, or rescue path after creation.

### USD market caps become fixed WETH prices

At account creation, the protocol snapshots:

- the token's current total supply;
- token decimals;
- ETH/USD from the configured oracle; and
- the oracle update timestamp.

For each market-cap boundary, the economic conversion is:

```text
token USD price   = market cap USD / snapshotted supply
token WETH price = token USD price / snapshotted ETH/USD
```

That WETH price is then rounded to usable pool ticks. The rounded tick values, not the creator's ideal decimal inputs, are the executable boundaries.

The resulting bands remain fixed in WETH terms. If ETH/USD changes later, the live USD value represented by each band changes with it. The oracle is used to define the bands once; it does not continuously move them.

## 6. Funding and later deposits

After creating the account, the recognized creator approves the contract and calls `fund` with one or more band IDs and amounts.

Creators may add more tokens to an existing active band, provided both guarded prices are still below its lower boundary. The first deposit creates the position; later deposits increase that same position.

Funding is atomic and uses exact balance-delta accounting. This deliberately excludes fee-on-transfer and rebasing tokens. Directly transferring tokens to the contract does not credit a band and can strand the tokens because the contract has no rescue function.

An unfunded band that the market has already entered becomes permanently unfundable. A settled band can never be reopened.

## 7. Settlement and delivery

A band becomes economically complete when market buying has crossed its upper boundary. Settlement is permitted only when both:

- spot price has crossed the upper boundary; and
- a manipulation-resistant reference price has crossed it.

The reference-price rule is important because a one-block price spike must not be enough to force settlement.

Settlement then:

1. removes all band liquidity;
2. collects WETH, native ETH, and any subject-token fees or residuals;
3. burns or closes the position NFT;
4. wraps native ETH into WETH;
5. charges the cumulative 1% Funding Bands fee on realized WETH; and
6. records liabilities owed to the recipient and protocol.

Delivery is a separate pull-style action. A failed recipient transfer does not roll back or block settlement; the liability remains recorded until a later successful delivery attempt.

The lifecycle is:

```text
CONFIGURED → ACTIVE → SETTLED → DELIVERED
```

Price can reverse before settlement. If it does, a position may convert partly back into the subject token. Settlement therefore waits for a validated upper-boundary crossing rather than treating a temporary touch as final.

## 8. Fees and destinations

### Creator destination

When a band routes directly to the creator:

```text
gross realized WETH
− 1% Funding Bands protocol fee
= 99% credited to the creator
```

There is no fee on deposits, unrealized inventory, returned subject tokens, or failed delivery attempts.

### Fee Router destination

The selected router must identify the same creator and subject token and must accept both WETH and the subject token.

Funding Bands still charges 1% before delivering proceeds. If the Fee Router independently charges its standard 1% intake fee, the combined result is:

```text
gross WETH × 99% × 99% = 98.01% available to the router strategy
```

This is a combined effective fee of 1.99%, not 2.00%, because the router's fee applies after the Funding Bands fee.

Funding Bands itself does not execute a buyback or burn. That behavior belongs in the selected Fee Router strategy. The simulations below assume a router that immediately swaps all available WETH back into the subject token and burns the output.

## 9. Security and trust model

The implementation is deliberately immutable and narrow:

- no owner or admin role;
- no upgrade mechanism;
- no pause switch;
- no arbitrary external-call facility;
- no token or NFT rescue function;
- immutable infrastructure addresses and launch profiles;
- maximum of ten bands;
- creator and recipient fixed at creation;
- canonical v3 pool or v4 Pool ID validation;
- exact transfer-delta checks;
- ERC-20 allowances reset after use;
- unexpected v3 position NFTs rejected;
- reentrancy protection on state-changing entry points; and
- an aggregate-liability solvency check after accounting and delivery operations.

This minimizes governance and custody risk, but it also makes creator mistakes irreversible. The UI must therefore show effective tick-rounded boundaries, fee outcomes, and a prominent final confirmation before account creation.

## 10. Pons v2 integration

Pons v2 launches begin on a bonding curve and later graduate into a Uniswap v4 pool. Funding Bands can only activate after the launch record reaches `GraduationPhase.PoolCreated`, because there is no v4 liquidity position to create before that point.

The Pons v2 launch verifier checks:

- the canonical launch-factory record exists;
- the subject address matches the record;
- the curve is a deployed contract;
- the immutable launch deployer is nonzero;
- graduation reached `PoolCreated`;
- the quote is native ETH or canonical WETH;
- tick spacing is valid;
- the token self-reports the same deployer, factory, and curve; and
- the reconstructed v4 `PoolKey` produces the expected Pool ID and shared Pons meme hook.

The launch creator is the immutable Pons `deployer`, not the mutable `creatorFeeRecipient`.

One Pons v2 nuance is that its launch record does not expose an immutable original-supply field suitable for this verifier. The profile snapshots `totalSupply()` when the Funding Bands account is created. Burns before activation therefore reduce the supply basis used to translate market caps into token prices.

### Pons v2 readiness verdict

The local implementation is mechanically compatible with graduated native-ETH and WETH Pons v2 pools. It is not yet ready for production activation.

Two blockers remain:

1. implement and validate a manipulation-resistant Pons v2/v4 reference-price guard; and
2. run Robinhood Chain fork tests against the exact deployed Pons v2 factory, token, hook, pool manager, position manager, Permit2, StateView, and WETH bytecode.

The local Pons v2 tests use faithful mocks. They validate contract integration and accounting logic, but they cannot prove live hook behavior, observation availability, or deployed-contract compatibility.

## 11. Intended UI integration

### Launch flow

The create-token screen should place a collapsed **Scale out with Funding Bands** section beneath Developer Buy and above Advanced settings.

For Pons v2, the launch-time form can only save an offchain draft. It must say clearly that no inventory has been committed yet. After graduation, the recognized creator completes three wallet steps:

1. approve the token;
2. create the immutable Funding Bands account; and
3. fund the selected bands.

The editor should support 1–10 rows and a chart showing each range, allocation, destination, expected fee treatment, and effective tick-rounded boundary. An irreversible-configuration acknowledgement is required before submission.

Funding Bands should be disabled for unsupported quote assets such as USDG.

### Token page

The public token page should show the disclosed ladder and each band's status:

- configured;
- active;
- ready to settle;
- settled; or
- delivered.

Permissionless actions such as settlement and proceeds delivery can be exposed directly from the band row.

### Creator profile

A Funding Bands area should group tokens into:

- Drafts;
- Needs action;
- Active; and
- Proceeds.

The UI should treat `AccountCreated`, `BandConfigured`, `BandFunded`, `BandSettled`, `ProceedsSent`, and `ProtocolFeeSent` as the canonical event stream while using `getAccount`, `getBand`, `proceedsOwed`, `totalLiability`, and `protocolOwed` for current state.

## 12. Test evidence

The test suite was rerun for this report on August 14, 2026.

| Suite | Result | Coverage focus |
|---|---:|---|
| Core Funding Bands unit tests | 15 passed | creation, creator authorization, 1–10 band limits, oracle validation, funding, exact deltas, v3/v4 settlement, fee accounting, router validation, spot/reference guard behavior |
| Pons v1 profile tests | 3 passed | canonical launch resolution and v3 TWAP guard behavior |
| Pons v2 profile tests | 4 passed | canonical graduated Pool ID, invalid launch rejection, native lifecycle, WETH lifecycle, immutable creator snapshot |
| Invariant tests | 3 passed | solvency, detailed-versus-aggregate liability equality, exact 1% protocol fee |
| **Total** | **25 passed; 0 failed** | — |

The three invariant properties each ran 256 campaigns with 16,384 handler calls, for 49,152 total invariant calls and zero reverts.

The compiled `SinjohFundingBands` runtime is 22,621 bytes, leaving 1,955 bytes below the 24,576-byte EIP-170 runtime limit.

These results establish local correctness against the current test model. They do not replace an independent audit, adversarial economic review, or live Pons v2 fork test.

## 13. Simulation methodology

Two internal analytic simulations were performed. Neither used mainnet, a live RPC, real funds, or real transactions.

Both modeled a Pons v2 native-ETH graduation with:

- original supply: 1,000,000,000 tokens;
- phantom quote reserve: 1.68 ETH;
- graduation quote reserve: 4.20 ETH;
- creator allocation placed into Funding Bands: 10% of supply;
- pool seed inventory: approximately 20.40816% of supply;
- reserved launch inventory: approximately 28.5714% of supply;
- contiguous, geometrically spaced bands;
- exact concentrated-liquidity range math with Pons tick spacing of 200;
- 1% Funding Bands fee;
- 1% Fee Router intake fee;
- 1% Pons buyback swap/hook fee; and
- immediate burn of all tokens bought by the router.

The route modeled for each settled band was:

```text
band gross WETH
× 99% Funding Bands net
× 99% Fee Router net
= 98.01% submitted to the buyback

buyback input
× 99% after Pons hook/swap fee
= amount that moves the pool curve
```

### Definitions used in the results

- **Organic ETH** is new outside buying required to push the token through the bands. It excludes recycled band proceeds.
- **Gross WETH** is what the Funding Band realizes before the Funding Bands and router fees.
- **Buyback input** is the WETH submitted by the router after the 1% Funding Bands fee and 1% router fee, but before the Pons swap/hook fee.
- **Price jump** is the immediate modeled spot-price change caused by that band's all-at-once buyback.
- **Original-supply FDV** multiplies token price by the original 1 billion supply.
- **Live-supply chart cap** multiplies token price by the remaining supply after burns.
- **Depth** is the modeled trade value needed to move the final spot price by 10% in either direction. It is a local spot-depth measure, not total value locked.

### Important limitations

The simulations intentionally isolate Funding Bands economics. They do not model:

- MEV, sandwiching, or arbitrage latency;
- gas costs or keeper costs;
- other pools or routed liquidity;
- unrelated market buys and sells between bands;
- changing ETH/USD after band creation;
- oracle update timing;
- organic LP fee accrual;
- router execution limits or time-weighted execution; or
- behavioral effects from publicly visible buyback expectations.

The user supplied ETH/USD assumptions were held constant for each run. Actual executable USD boundaries are tick-rounded and therefore differ slightly from the requested values.

Band rows are rounded for readability. Aggregate values were calculated from the simulations' full-precision outputs, so summing the displayed rows may differ from a reported total by one unit in the final decimal place.

## 14. Simulation A — five bands, $50K to $1M

### Configuration

- ETH/USD: $2,400
- Pons v2 graduation market cap implied by the modeled pool: $49,392
- Total Funding Bands allocation: 100,000,000 tokens, or 10% of supply
- Five bands: 20,000,000 tokens, or 2% of supply, per band
- Requested span: $50,000 to $1,000,000
- Effective tick-rounded boundaries: approximately $50,381 to $1,011,782

### Band-by-band results

| Band | Effective range | Gross WETH | Buyback input | Tokens burned | Immediate price jump |
|---:|---:|---:|---:|---:|---:|
| 1 | $50.381K–$91.798K | 0.566721 ETH | 0.555443 ETH | 13.519775M | +13.08% |
| 2 | $91.798K–$167.263K | 1.032602 ETH | 1.012053 ETH | 13.355586M | +15.87% |
| 3 | $167.263K–$304.761K | 1.881467 ETH | 1.844026 ETH | 13.186656M | +18.86% |
| 4 | $304.761K–$555.294K | 3.428154 ETH | 3.359933 ETH | 13.020422M | +21.92% |
| 5 | $555.294K–$1.011782M | 6.246316 ETH | 6.122014 ETH | 10.900929M | +73.93% |

### Aggregate results

| Metric | Result |
|---|---:|
| Organic ETH required to cross all bands | 21.475501 ETH |
| Gross WETH realized by bands | 13.155259 ETH |
| WETH submitted to buybacks | 12.893469 ETH |
| WETH moving the pool after swap/hook fee | 12.764535 ETH |
| Tokens bought and burned | 63.983368M |
| Original supply burned | 6.3983% |
| Tokens from the 10% allocation not burned by this strategy | 36.016632M |
| Final original-supply FDV | $1.759817M |
| Final live-supply chart cap | $1.647218M |

The 36.016632 million allocated tokens not burned are not missing. They are the portion of the creator's band inventory that was bought by organic participants rather than recovered by the router's own buybacks.

### Normal-launch comparison

| Comparison | Normal launch | Funding Bands + buyback/burn |
|---|---:|---:|
| Outside ETH needed to reach roughly $1M | 14.846691 ETH | 21.475501 ETH to cross all bands |
| Final value using the same 21.475501 ETH of outside buying | $1.815099M original-supply FDV | $1.759817M original-supply FDV / $1.647218M live-supply cap |
| Supply burned | 0 | 63.983368M |

Funding Bands require more outside buying to traverse the same broad price region because the bands add creator-owned sell inventory above the market. Recycled buybacks then push the price upward and burn supply, but a normal launch given the same amount of outside buying ends at a slightly higher modeled price because it did not first absorb that extra inventory.

### End-state depth

| End state | Pool quote depth | +10% buy value | −10% sell value |
|---|---:|---:|---:|
| Normal launch at $1M | 18.8982 ETH | $2,236 | $2,478 |
| Funding Bands final state | 25.0700 ETH | $2,966 | $3,288 |
| Normal launch after the same outside flow | 25.4607 ETH | $3,013 | $3,339 |

The Funding Bands outcome looks substantially deeper than a normal launch stopped at $1M because the buybacks leave it at a much higher price and quote reserve. Compared fairly at the same outside demand, however, it is about 1.5% shallower than the normal-launch counterfactual.

Most importantly, no band liquidity remains at the end. The bands are withdrawn as they settle. Any lasting depth comes from quote reserve added through market activity, not from permanent Funding Bands liquidity.

## 15. Simulation B — ten executable Pons v2 bands, $40K to $5M

### Why the requested start changed

The original request was ten bands from $25,000 to $5,000,000 with ETH at approximately $1,900. Under the modeled Pons v2 graduation state, the starting market cap was approximately $39,102. A $25,000 lower band would already be below the live market and could not be created or funded.

The executable run therefore used the user-approved range of $40,000 to $5,000,000.

### Configuration

- ETH/USD: $1,900, supplied by the user for the simulation
- Modeled graduation market cap: $39,102
- Total Funding Bands allocation: 100,000,000 tokens, or 10% of supply
- Ten bands: 10,000,000 tokens, or 1% of supply, per band
- Requested span: $40,000 to $5,000,000
- Effective tick-rounded span: approximately $40,691 to $5,043,027

### Band-by-band results

| Band | Effective range | Gross WETH | Buyback input | Tokens burned | Immediate price jump |
|---:|---:|---:|---:|---:|---:|
| 1 | $40.691K–$65.758K | 0.272250 ETH | 0.266833 ETH | 7.357766M | +7.61% |
| 2 | $65.758K–$106.267K | 0.439966 ETH | 0.431211 ETH | 7.305983M | +9.14% |
| 3 | $106.267K–$171.731K | 0.711001 ETH | 0.696852 ETH | 7.249159M | +10.86% |
| 4 | $171.731K–$277.524K | 1.149003 ETH | 1.126138 ETH | 7.188370M | +12.75% |
| 5 | $277.524K–$448.488K | 1.856830 ETH | 1.819879 ETH | 7.117639M | +15.00% |
| 6 | $448.488K–$739.414K | 3.030859 ETH | 2.970545 ETH | 6.993381M | +16.76% |
| 7 | $739.414K–$1.194919M | 4.947199 ETH | 4.848750 ETH | 6.995463M | +19.05% |
| 8 | $1.194919M–$1.931032M | 7.994850 ETH | 7.835753 ETH | 6.935377M | +21.12% |
| 9 | $1.931032M–$3.120616M | 12.919963 ETH | 12.662855 ETH | 6.879512M | +23.10% |
| 10 | $3.120616M–$5.043027M | 20.879120 ETH | 20.463625 ETH | 5.357285M | +102.99% |

### Aggregate results

| Metric | Result |
|---|---:|
| Organic ETH required to cross all bands | 66.026559 ETH |
| Gross WETH realized by bands | 54.201041 ETH |
| WETH submitted to buybacks | 53.122440 ETH |
| Tokens bought and burned | 69.379934M |
| Original supply burned | 6.9380% |
| Tokens from the 10% allocation not burned by this strategy | 30.620066M |
| Remaining total supply | 930.620066M, or 93.0620% |
| Final original-supply FDV | $10.236748M |
| Final live-supply chart cap | $9.526523M |

### Normal-launch comparison

| Comparison | Normal launch | Funding Bands + buyback/burn |
|---|---:|---:|
| Outside ETH needed to reach roughly $5M | 43.730878 ETH | 66.026559 ETH to cross all bands |
| Final value using the same 66.026559 ETH of outside buying | $10.727490M original-supply FDV | $10.236748M original-supply FDV / $9.526523M live-supply cap |
| Supply burned | 0 | 69.379934M |

### End-state depth

| End state | Pool quote depth | +10% buy value | −10% sell value |
|---|---:|---:|---:|
| Normal launch at $5M | 47.49357 ETH | $4,448.89 | $4,930.50 |
| Funding Bands final state | 67.95647 ETH | $6,365.72 | $7,054.83 |
| Normal launch after the same outside flow | 69.56629 ETH | $6,516.52 | $7,221.95 |

As in the five-band run, the Funding Bands final state is deeper than a normal launch stopped at the nominal target because it ends at a higher price. At equal outside demand, the normal launch remains modestly deeper and reaches a somewhat higher price, while Funding Bands provide the distinct benefit of burning 6.94% of supply.

## 16. What the two simulations teach us

| Question | Five bands | Ten bands | Lesson |
|---|---:|---:|---|
| Allocation | 10% total; 2% per band | 10% total; 1% per band | More bands smooth the early scale-out path |
| Modeled supply burned | 6.3983% | 6.9380% | Recycled proceeds can recover and burn most, but not all, of the allocated inventory |
| Largest single buyback | 6.122014 ETH | 20.463625 ETH | WETH proceeds grow sharply at higher valuations |
| Largest immediate jump | +73.93% | +102.99% | Immediate full-balance buybacks become destabilizing near the top |
| Permanent band liquidity left | None | None | Funding Bands are inventory distribution, not permanent LP |
| Equal-demand depth versus normal | Slightly lower | Slightly lower | The strategy does not create free liquidity; it changes ownership and recycles proceeds |

The ten-band design is smoother in its lower and middle ranges because each band contains only 1% of supply. It does not solve the top-band execution problem: the WETH value realized by the highest range is so large relative to pool depth that immediately recycling all of it creates an extreme price discontinuity.

## 17. Plain-language advantages and tradeoffs

### Advantages

- **Predictable creator scale-out:** the ranges and allocations are defined before execution.
- **Less discretionary selling:** buyers consume pre-positioned inventory instead of reacting to wallet market sells.
- **Customizable milestones:** creators choose up to ten market-cap ranges.
- **Transparent routing:** each band permanently names either the creator or a compatible Fee Router.
- **Automation-friendly:** settlement and delivery are permissionless.
- **Composable proceeds:** a Fee Router can fund treasury, buyback, burn, rewards, or other fixed strategies.
- **Post-launch deposits:** creators can add inventory later while the band remains safely above the market.
- **No admin custody:** there is no privileged owner capable of redirecting proceeds.

### Tradeoffs and risks

- **It is still sell-side inventory:** organic buyers must absorb the creator's tokens to cross each band.
- **More demand is required:** the simulations needed more outside ETH to traverse the target range than a normal launch.
- **Configuration is irreversible:** incorrect boundaries, allocations, or destinations cannot be edited or withdrawn.
- **USD labels drift:** after creation, bands are fixed in WETH, so their live USD values move with ETH/USD.
- **No lasting band LP:** settled positions are removed entirely.
- **Immediate buybacks can be violent:** the largest simulated buybacks caused 74% and 103% instantaneous price jumps.
- **Public schedules can be gamed:** traders and MEV searchers can anticipate settlement and router activity.
- **Unsupported token mechanics are rejected:** fee-on-transfer and rebasing behavior are incompatible with exact accounting.
- **Pons v2 is not production-cleared:** the reference guard and exact live-contract fork suite remain blockers.

## 18. Production recommendations

Before activating a buyback-and-burn Funding Bands router on Pons v2:

1. **Build the production v4 price guard.** Settlement must require a manipulation-resistant reference observation in addition to spot.
2. **Fork-test exact Robinhood Chain deployments.** Test both native and WETH launches, actual hook behavior, Permit2 approvals, position creation/increase, settlement, wrapping, and failed delivery recovery.
3. **Chunk buybacks.** Do not submit an entire high-band balance as one swap. Use a maximum price-impact rule, minimum output, time spacing, and a signed or otherwise constrained execution policy.
4. **Separate settlement from strategy execution.** Settling promptly is safe accounting; buying back immediately is an economic decision that should respect current depth.
5. **Consider a configurable split.** A router could divide proceeds between buyback-and-burn, permanent liquidity, and creator/treasury funding. Permanent LP is the direct mechanism for improving lasting depth.
6. **Show effective boundaries in the UI.** The confirmation view should display tick-rounded values and explain that USD values drift after the ETH/USD snapshot.
7. **Make launch-time Pons v2 drafts explicit.** Users must understand that a draft is not funded and cannot become onchain until graduation.
8. **Obtain an independent audit.** Focus review on immutable configuration, v4 action encoding, native/WETH accounting, price-guard assumptions, liability solvency, and hostile recipient/token behavior.

## 19. Current delivery status

The Funding Bands package currently exists in local `main` commit `038282ddce41645c70ee3740dea2a39fa2a96f45` with its specification, implementation, tests, Pons v2 compatibility notes, and UI integration notes.

As of this report:

- local implementation: **complete for the defined test scope**;
- local tests: **25 passed, 0 failed**;
- Pons v2 mock lifecycle: **passing**;
- production Pons v2 guard: **not implemented**;
- exact Robinhood Chain Pons v2 fork suite: **not completed**;
- remote push: **not completed**;
- deployment: **not completed**; and
- contract address: **none**.

## 20. Glossary

**Band**
A one-sided concentrated-liquidity position spanning a creator-selected valuation range.

**Creator**
The immutable launch deployer recognized by the configured launch verifier.

**Subject token**
The launched token placed into Funding Bands.

**Quote asset**
Native ETH or canonical WETH used to buy the subject token.

**Settlement**
Closing a crossed band, collecting its assets, charging the Funding Bands fee, and recording fixed liabilities.

**Fee Router**
A separate Sinjoh component that receives a band's net proceeds and applies a configured allocation strategy.

**Buyback and burn**
Using WETH to buy the subject token from the market and then permanently destroying the purchased tokens.

**Original-supply FDV**
Current token price multiplied by the original supply, useful for comparing price paths before and after burns.

**Live-supply chart cap**
Current token price multiplied by the remaining supply after burns.

**Price guard**
A launch-profile-specific contract that verifies both spot and manipulation-resistant reference prices relative to a band boundary.

## Source basis

This report was checked against the following files in the Funding Bands package at local `main` commit `038282d`:

- `sinjoh-funding-bands/SPEC.md`
- `sinjoh-funding-bands/README.md`
- `sinjoh-funding-bands/PLAN.md`
- `sinjoh-funding-bands/PONS_V2_COMPATIBILITY.md`
- `sinjoh-funding-bands/UI-INTEGRATION.md`
- `sinjoh-funding-bands/src/SinjohFundingBands.sol`
- `sinjoh-funding-bands/src/FundingBandMath.sol`
- `sinjoh-funding-bands/src/FundingBandV4.sol`
- `sinjoh-funding-bands/src/profiles/SinjohPonsV1LaunchVerifier.sol`
- `sinjoh-funding-bands/src/profiles/SinjohPonsV2LaunchVerifier.sol`
- `sinjoh-funding-bands/src/profiles/SinjohV3TwapBandPriceGuard.sol`
- all four Funding Bands test suites

The simulation figures are analytic outputs from the two internal runs described above. They are scenario estimates, not guarantees of live market behavior.
