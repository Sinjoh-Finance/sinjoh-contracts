# Sinjoh On-Chain Treasuries — Research & Brainstorm

Research date: 2026-07-29. No code; design exploration only. Four parallel research
sweeps (Safe ecosystem, non-Safe frameworks, futarchy, frontier features) feed this
document. Source links inline.

---

## 1. Ground truth

### Chain facts (verified July 2026)

- Robinhood Chain: Arbitrum Orbit L2 settling directly to Ethereum, chain ID 4663,
  ETH gas, **no native chain token**, ~100ms blocks, centralized Robinhood sequencer.
  Mainnet launched **July 1, 2026**.
- Day-one ecosystem: **Uniswap v4**, **Morpho** (powers "Robinhood Earn", ~7% on USDG),
  Arcus, Lighter, 1inch, Chainlink, LayerZero. **Safe is live from day one**
  ([Safe Labs announcement](https://x.com/SafeLabs_/status/2072411833260970071)).
- Cash asset: **USDG** (Paxos). ~95 tokenized equities ("Stock Tokens" —
  Robinhood-issued tokenized debt securities, dividend pass-through, no shareholder
  rights, not available to US persons), usable as DeFi collateral.
- **Not on the chain yet**: CoW Protocol, reality.eth, Kleros, UMA, tokenized T-bills
  (BUIDL/USDY/OUSG), EigenLayer. Any design depending on these is a fast-follow, not
  a launch feature.

### Sinjoh constraints (from STRATEGY.md)

- Brand over standalone, immutable protocols. No shared custody layer, no upgradeable
  core, no administrator. Composition = copied interfaces + ordinary asset transfers.
- Everything frozen at deployment or first registration; no ambient-balance inference.
- Fine-grained failure isolation (a failed recipient never blocks unrelated work).

A Sinjoh treasury therefore cannot be "a platform." It has to be **another standalone,
immutable protocol** that other Sinjoh pieces merely *point at* — and its governance
layer must be a *replaceable address*, not an upgradeable contract.

### Existing plug-in points in the Sinjoh stack

1. **Fee router allocations** — each bucket pays fixed sinks; a treasury is just an
   allocation address (and `creatorMayRepoint` allocations can migrate to one later).
2. **Revenue collector** — `Ownable2Step` owner *is* governance; the `processor` slot
   is explicitly reserved for the future 40/20/20/15/5 revenue processor. A treasury
   can be the processor; a governance system can be the owner. This is the cleanest
   hook: **the treasury's decision layer becomes the owner of the revenue collector.**
3. **Airdrop distributor** — a treasury outflow: fund holder distributions.
4. **Liquidity manager** — a treasury outflow: fund permanent full-range liquidity.

Key structural insight: Sinjoh already separates *money movement* (immutable) from
*policy selection* (a single governance-held address slot). The treasury product line
should preserve exactly that split: **immutable vault kernel + swappable decision
module, where "swappable" means changing one address via the decision module itself.**

---

## 2. Landscape: what exists and what it teaches

### 2.1 Safe + Zodiac (the incumbent stack)

- **Safe v1.5.0** (final July 2025, Certora + Ackee audits) — the headline feature is
  **module guards**: guards now check module-initiated transactions too, closing the
  historic "any module = god mode" bypass. Prefer 1.5.0 over 1.4.1 for treasuries.
- **Zodiac Roles Modifier v2** — the serious delegation primitive: role keys with
  target allowlists → function selectors → parameter-level condition trees, plus
  built-in rate-limited numeric allowances. This is how kpk (ex-karpatkey) manages
  ENS/Aave/Lido/Arbitrum treasuries non-custodially. [docs.roles.gnosisguild.org](https://docs.roles.gnosisguild.org)
- **Delay Modifier** — cooldown + veto window on module transactions.
- **Exit Module** — Moloch-style rage-quit: redeem a token for pro-rata Safe assets.
- **Dead/dying, do not build on**: Safe{Core} Protocol (abandoned alpha),
  UMA **oSnap (service ended Dec 15, 2025)**, Connext module, Bridge module (no AMB
  on Robinhood Chain), Metropolis pods.
- **Bybit hack lesson (Feb 2025, $1.5B)**: contracts held; the *front-end + blind
  signing pipeline* failed (malicious JS flipped a transfer into a delegatecall that
  rewrote the masterCopy slot). Baseline hygiene now: block/guard delegatecall,
  independent hash verification, monitor masterCopy/module/guard slots, treat any
  hosted UI as untrusted.

**Teaching for Sinjoh:** Safe is the right *ops container* for humans and role-scoped
delegates, but a Safe is mutable-by-quorum by construction (owners can enable modules,
delegatecall, migrate). It conflicts with Sinjoh's immutability brand if used as *the*
treasury. Better: Sinjoh-immutable vault contracts, with Safes appearing only as
*role-holders* (e.g., an ops Safe holding a bounded spending lane).

### 2.2 Token-holder frameworks

- **OZ Governor v5 + TimelockController** — still the default spine, now with
  fractional counting (v5.1), delegate-override voting (v5.2), super-quorum early
  execution (~v5.4), late-quorum extension, timestamp clocks for L2s. No oracle
  dependencies — works on a fresh chain day one.
- **Aragon OSx v1.4** — strongest modular alternative; its
  **optimistic-token-voting plugin** (council proposes → passes unless token holders
  veto) powers Taiko and Polygon's governance. Pattern worth stealing even without Aragon.
- **Moloch v3 (Baal)** — shares vs loot, ragequit, guild kick, "shamans" as privileged
  minters. Done software, minimal dev velocity; the rage-quit *idea* matters more than
  the framework.
- **Nouns** — the best-tested collective exit: **fork mechanism** (20% escrow →
  fork DAO takes pro-rata treasury), plus pragmatic payment rails (TokenBuyer/Payer
  debt-registry for USDC obligations, Streamer with predictable stream addresses).
- **Lido Dual Governance (live June 30, 2025)** — the state of the art in constituency
  protection: stakers locking >1% of stETH trigger a 5–45 day dynamic timelock on all
  DAO execution; >10% triggers rage-quit state where **nothing executes until every
  dissenter has exited at full value**. Audited by Statemind, OZ, Certora, RV.
- **Squads v4 (Solana, for contrast)** — multisig with protocol-native time locks,
  spending limits, sub-accounts, roles; program itself immutable and formally
  verified. Notable: it treats "immutable program + rich built-in policy" as the
  product — philosophically the closest thing to what a Sinjoh treasury should be.
- Ecosystem weather: **Tally shut down** (Mar 2026, app now run by ScopeLift) — do not
  couple to hosted governance UIs; **Uniswap UNIfication** (Dec 2025) and
  **Aave Aavenomics 3.0** (June 2026) made automated revenue→buyback engines the
  mainstream treasury behavior; **GnosisDAO fired kpk** (Nov 2025) — external manager
  concentration is a governance liability.

### 2.3 Futarchy (deep dive)

- **MetaDAO (Solana)** is the only production-grade implementation. Mechanism:
  - Conditional vaults: deposit TOKEN/USDC → mint pass- and fail-conditional tokens;
    two AMM markets (pTOKEN/pUSDC, fTOKEN/fUSDC); losing side's trades revert.
  - Decision rule: **capped-step "lagging observation" TWAP** (each observation can
    move only a bounded amount per update, so manipulation cost scales with duration),
    24h recording delay, ~3-day trading window, pass if pass-TWAP beats fail-TWAP by
    a threshold (**+3% for outsider proposals, −3% for team proposals**).
  - Execution: the **autocrat** program stores the treasury instruction at proposal
    time and CPI-executes it automatically on pass. No human in the loop.
  - Battle scars: a $250K manipulation attempt (Proposal 6/7) *failed* — counter-traders
    faded the whale and he ate losses. Real problems were mundane: thin liquidity
    (~$100K/proposal must be subsidized), trader apathy on obvious proposals, and
    "only price-material decisions produce signal."
  - 2025 pivot: futarchy-governed **launchpad** (every launched token gets a
    market-governed treasury; Umbra ICO drew ~$150M commitments); Q1 2026 treasury
    $12.2M; executed a futarchy-governed *liquidation* returning $5M to holders —
    proof that market governance can wind a project down ("unruggable" in practice).
- **EVM futarchy exists but is younger**: futarchy.fi (Gnosis-backed, live markets on
  real GnosisDAO decisions), Seer (CTF + Kleros, futarchy market type), Butter's
  Conditional Funding Markets.
- **Grant-allocation futarchy has real data**:
  - Optimism Futarchy v1 (2025, play money): futarchy picks beat the Grants Council
    by ~$32.5M aggregate TVL growth, but calibration was terrible (~8x overprediction)
    — play money was the diagnosed failure.
  - Uniswap Foundation Unichain CFM (July 2025, real money): market-selected Morpho;
    outcome beat forecast by 11.8%; main problems were insider-dominated pricing and
    UX burden.
- **Theory caveat** (Othman–Sandholm): deterministic decision rules are not fully
  incentive-compatible — every live futarchy accepts this and leans on counter-trading
  capital, TWAP caps, and thresholds.
- **Vitalik's "info finance" frame (Nov 2024)**: AI traders collapse minimum viable
  market size — micro-markets per proposal become feasible where human-only liquidity
  failed. Directly relevant to making per-decision futarchy affordable.
- What asset futarchy buys on a fresh L2: the welfare metric (subject-token TWAP) is
  **fully on-chain — no oracle needed**. That is a huge deal on a chain where UMA,
  reality.eth, and Kleros don't exist. Futarchy is arguably *easier* to deploy
  trust-minimized on Robinhood Chain than optimistic-oracle governance.

### 2.4 Value-return & yield mechanics worth copying

- **Hyperliquid Assistance Fund**: 97% of fees → continuous automated buybacks; $1.3B+
  deployed; the benchmark for "the treasury is an engine, not a wallet."
- **Sky Smart Burn Engine**: ~$1M/day surplus-triggered buyback above a buffer floor;
  governance throttled it in Mar 2026 — argues for **bounded-parameter dials** rather
  than hardcoded rates.
- **Uniswap v4 TWAMM hook**: per-block execution of long-duration orders — a native,
  MEV-resistant streaming-buyback venue, and **Uniswap v4 is on Robinhood Chain**.
  No marquee DAO runs its buyback through TWAMM yet: open frontier.
- **Gnosis EasyAuction / batch auctions**: boring-reliable episodic buybacks.
- **Morpho vaults**: the realistic idle-USDG yield leg on this chain today.
- **Splits (0xSplits)**: immutable, fee-less splitters — hyperstructure-grade, matches
  Sinjoh's ethos for revenue fan-out.
- **Streaming**: Sablier Lockup/Flow, Superfluid (ENS grant streams; cancel = clawback
  of unstreamed funds), Nouns Streamer (predictable addresses, no pre-funding).
- **CLARITY Act tailwind**: admin-keyless, immutable design directly strengthens the
  "no unilateral control" decentralization certification. Sinjoh's brand is
  accidentally a legal strategy.

---

## 3. Design space: three treasury archetypes for Sinjoh

All three share the Sinjoh split: **immutable vault kernel** whose only mutable state
is (a) bounded policy dials and (b) one `decider` address slot, changeable only by the
current decider through a timelock that is longer than the exit window.

### Archetype A — "Warden": assigned-address treasury (creator/team controlled)

The minimum viable product. A per-project treasury where named addresses hold scoped
powers — no token vote at all.

- Immutable vault with **lanes**: each lane = (role address, asset allowlist, rate
  limit per epoch, destination allowlist). Think Zodiac Roles v2 semantics compiled
  down to a purpose-built immutable contract instead of a general interpreter.
- Lane examples: ops lane (≤X USDG/week to allowlisted payees), LP lane (only callable
  into the Sinjoh liquidity manager), airdrop lane (only funds the airdrop
  distributor), buyback lane (only executes TWAMM/auction orders on the subject token).
- A Safe can *hold* a lane role — Safe as operator, never as custodian.
- Every lane action is permissionless to *settle* but authorized to *initiate*
  (matches the keeper model Sinjoh already runs).
- Escape hatch even here: holders of the subject token can trigger a **freeze vote**
  if lanes are abused.

### Archetype B — "Agora": token-holder treasury

- OZ Governor v5-style voting (fractional counting, timestamp clock, late-quorum
  guard) but *compiled into an immutable, minimal implementation* — parameters live in
  bounded ranges set at deployment (Sky lesson), not behind an upgradeable proxy.
- Optimistic mode as the default lane (Aragon/Taiko pattern): a proposer role
  (creator team, or a lane from Archetype A) queues actions that execute after N days
  **unless token holders veto** above a threshold. Full votes reserved for big items.
  This keeps small-treasury governance cheap and low-attention.
- **Dual-governance protection** (Lido pattern, scaled down): a veto-escrow where
  holders lock subject tokens to stretch the timelock; past a second threshold, the
  treasury enters rage-quit mode and dissenters exit pro-rata before execution resumes.

### Archetype C — "Oracle-of-Delphi": futarchy treasury

The forward-thinking flagship — and genuinely differentiated: **nobody has shipped
production asset-futarchy on an EVM L2.** MetaDAO proved the mechanism on Solana; the
EVM attempts (futarchy.fi, Seer) live on Gnosis Chain and don't do autonomous
execution. First-mover slot is open.

- Port the MetaDAO architecture to Solidity, Sinjoh-style (immutable, standalone):
  1. **Conditional vault pair** per proposal: deposit SUBJECT or USDG, mint
     pass/fail conditional ERC-20s; losing side redeems to original deposit.
  2. **Two conditional AMM pools** (pSUBJECT/pUSDG, fSUBJECT/fUSDG) — could be
     bespoke constant-product pools with a built-in capped-step TWAP, or Uniswap v4
     pools with a truncated-oracle-style hook (v4 is on-chain already).
  3. **Autocrat**: stores the proposal's calldata (against an allowlisted action set —
     MetaDAO's "arbitrary instruction" audit burden is avoidable), compares TWAPs at
     expiry, executes automatically on pass.
- Starting parameters (empirically grounded): 3–7 day window, 24h pre-TWAP delay,
  +3–5% pass threshold (asymmetric for team proposals), capped TWAP steps sized so
  full-window manipulation costs a multiple of the action's value, ~$50–100K
  subsidized liquidity per proposal, proposer bond for spam control.
- Welfare metric = subject-token TWAP vs USDG. **No external oracle.** For grant-style
  decisions where a KPI counterfactual matters, add Butter-style scalar CFMs later —
  but those need an oracle, so they're fast-follow.
- Scope futarchy to **treasury actions only** (spend, buy back, fund liquidity,
  liquidate) — MetaDAO's launchpad DAOs converged on exactly this scope.
- Hybrid ladders (pick per project at deploy time):
  - *Advisory*: markets run, humans decide (GnosisDAO 2020 — historically decays;
    offer but don't default).
  - *Futarchy-with-veto*: market decides, a veto council (or veto-escrow) can block
    within the timelock.
  - *Full autocrat*: market decides and executes. The MetaDAO liquidation case shows
    this can even govern shutdown credibly.

The three archetypes are not competitors — they're a **progressive decentralization
ramp**: launch on Warden, graduate to Agora, opt into Delphi lanes for capital
allocation. Because the decider is one address slot, graduation = one timelocked
address change, no migration of funds.

---

## 4. Feature brainstorm (the cool/powerful stuff)

### 4.1 Revenue engine, not wallet

- **Auto-buyback lane**: fee-router allocation → treasury → continuous TWAMM order on
  the subject token (Hyperliquid model, executed via the v4 hook). Optional burn or
  re-deposit into the airdrop distributor ("buyback-and-redistribute" — holders get
  the bought tokens via the existing Merkle push rail instead of a burn).
- **Surplus-buffer waterfall** (Sky model): revenue fills a USDG buffer to a floor;
  overflow splits by immutable bps into buyback / liquidity / airdrop / grants lanes.
  This *is* the 40/20/20/15/5 processor the revenue collector spec anticipates —
  the treasury and the revenue processor can be the same deployment.
- **Buyback circuit dials**: rate bounded in [min, max] at deploy; decider moves the
  dial inside the range only. Immutable code, tunable throttle.

### 4.2 Book-value floor & exit rights (the trust product)

- **Pro-rata redemption**: burn subject-treasury claim tokens to withdraw a slice of
  treasury assets at book value (Nouns/Moloch lineage; see also "Debt-Aware Bonding
  Curves," IACR 2026/483, for non-decreasing floor invariants). This single feature
  makes a token **unruggable-by-construction** and is the strongest marketing story:
  "the floor is on-chain."
- **Redemption as governance backstop**: every governance power is paired with an exit
  window longer than the execution timelock (Lido DG principle). Disagree → leave at
  full book value *before* the decision lands.
- **Collective fork** (Nouns): above an escrow threshold, dissenters spawn a sibling
  treasury with pro-rata assets rather than just cashing out — preserves communities,
  not just capital.

### 4.3 Native integration features (only Sinjoh can do these)

- **Treasury as fee-router sink**: zero-integration onboarding — point an allocation
  at the vault.
- **Treasury as revenue-collector owner + processor**: governance of upstream policy
  and custody of downstream funds in one immutable unit.
- **Airdrop-distributor outflow lane**: distributions to holders reuse the audited
  Merkle-sum rail instead of new payout code.
- **Liquidity-manager outflow lane**: "deepen permanent liquidity" as a one-vote (or
  one-market) action.
- **Cross-project patronage**: STRATEGY.md's "one project directs revenue to another"
  — treasuries holding *each other's* subject tokens, with futarchy markets pricing
  whether patronage raises the patron's own token. An on-chain index of aligned
  projects emerges.

### 4.4 Stock-token-native treasury (nobody else has this)

- Diversification lanes into tokenized equities (NVDA, AAPL…) — a memecoin treasury
  holding dividend-passing equity exposure, 24/7, on the chain it lives on.
- Dividend pass-through routed into the buyback or airdrop lane: **equities fund
  holder distributions**.
- Stock tokens as Morpho collateral: borrow USDG against the equity sleeve for
  operating expenses without selling.
- Futarchy question upgrade: markets deciding *portfolio allocation* ("does shifting
  10% of treasury into the equity sleeve raise SUBJECT/USDG TWAP?").
- Caveat to carry: Stock Tokens are Robinhood-issued debt instruments with issuer
  risk and no shareholder rights; excluded from US persons. A treasury holding them
  inherits that jurisdictional surface.

### 4.5 Yield lanes (realistic on this chain today)

- Idle USDG → **Morpho vault** deposit lane (bounded % of treasury, curated vault
  allowlist fixed at deploy).
- LP lane → own-token/USDG or ETH/USDG full-range positions via the existing
  liquidity manager (fees compound the treasury).
- Fast-follow allowlist slots for tokenized T-bills (USDY is the likely first
  arrival) — pre-declared asset slots that only activate if/when the asset exists at
  a pre-committed address pattern, keeping immutability intact.

### 4.6 Execution quality

- **Dutch-auction spend module**: episodic large swaps via batch auction rather than
  AMM market orders.
- **TWAP execution for everything large** (in and out) — the treasury never crosses
  the spread in size; CoW-style programmatic orders once CoW arrives, TWAMM/v4 until
  then.
- **Keeper-driven settlement**: all recurring actions (buffer sweeps, buyback ticks,
  stream top-ups) are permissionless-to-poke, matching the existing sinjoh-keeper
  operational model.

### 4.7 Payments & grants

- **Streaming grants with clawback**: cancel-stream-recovers-unstreamed-funds
  (Superfluid/ENS pattern) as the default grant instrument — milestone enforcement
  without arbitration.
- **Debt-registry payments** (Nouns TokenBuyer/Payer): proposals promise USDG the
  treasury doesn't hold yet; revenue retires the debt FIFO. Lets small treasuries make
  credible commitments.
- **Split-everything**: immutable Splits-style fan-outs for team/collaborator revenue
  shares hanging off any lane.
- **Conditional funding markets for grants** (Butter/UF pattern) once an optimistic
  oracle exists on-chain — measured, counterfactual grant allocation with real-money
  precedent (Morpho/Unichain case).

### 4.8 AI-agent treasurer lane (forward-thinking, immutability-compatible)

- An **agent lane** = assigned-address lane whose holder is an AI agent's smart
  account: hardcoded caps (≤X% rebalance/week, venue allowlist, per-tx max), all
  actions subject to a Delay-style veto window. The agent proposes and executes
  *inside an on-chain envelope*; humans (or the market) own the envelope.
- Robinhood is marketing the chain as AI-native ("Agentic Accounts") — an agent-ready
  treasury lane rides that narrative with real guardrails (ERC-7715-style scoped
  permissions; keys in TEEs, never in agent code).
- Futarchy synergy (Vitalik's info-finance point): AI market-makers can be the
  liquidity that makes small per-proposal futarchy markets viable. The treasury can
  *pay* for that liquidity explicitly — "payment for information" as a budget line.

### 4.9 Safety rails (post-Bybit, post-oSnap world)

- **No delegatecall anywhere** in the treasury kernel; action set is typed
  operations, not arbitrary calldata (kills the Bybit vector and MetaDAO's
  audit-the-instruction burden at once).
- **Freeze vote**: token holders can halt all lanes with a bounded-duration emergency
  freeze (deposit-weighted, slashing-free) — a circuit breaker that can't steal, only
  pause.
- **Sequencer-liveness posture**: Robinhood runs the only sequencer; all timelocks and
  TWAP windows should be denominated in L1-verifiable time and be long enough that a
  sequencer outage can't expire a veto window silently.
- **No hosted-UI dependency** (Tally shutdown, Bybit lesson): every treasury action
  reproducible from a CLI/script; UIs are conveniences.
- **No external-oracle dependency at launch**: asset futarchy and Governor voting both
  qualify; UMA/reality/Kleros patterns don't (not deployed, and oSnap is dead anyway).

### 4.10 Weirder / further out

- **Futarchy-priced parameter dials**: instead of discrete proposals, a standing
  conditional market per dial (e.g., buyback rate) that continuously nudges the
  parameter inside its bounds — "market-tuned tokenomics."
- **Treasury-of-treasuries index**: an immutable index vault holding claim tokens of
  many Sinjoh project treasuries — a passive "Sinjoh economy" exposure product that
  needs no admin because every underlying is floor-backed.
- **Private voting fast-follow**: MACI is chain-agnostic Solidity + off-chain
  coordinator; plausible for veto/freeze votes where bribery resistance matters.
  Private *execution* (Railgun-style) is a non-starter on a broker-operated chain.
- **Cross-chain stance**: keep *authority* single-chain (bridged governance re-imports
  admin keys via the bridge's upgrade keys); use ERC-7683 intents for *asset*
  movement only, if ever.
- **DUNA wrapper option** (Uniswap precedent): a Wyoming DUNA around a project
  treasury gives it legal personhood for off-chain contracts; pairs unusually well
  with admin-keyless design under the CLARITY Act's decentralization certification.

---

## 5. What NOT to do (dead ends confirmed by research)

1. **Don't make Safe the treasury.** Owner quorums can enable modules/migrate the
   singleton — incompatible with the immutability brand. Safe = operator container only.
2. **Don't design around oSnap** (dead), **Safe{Core} Protocol** (abandoned),
   **Metropolis pods** (dead), **Connext/Bridge modules** (dead/no AMB), or hosted
   governance UIs (Tally precedent).
3. **Don't use play money or points for futarchy** — the single clearest failure in
   the Optimism experiment (8x overprediction). Real collateral or nothing.
4. **Don't let futarchy govern non-price-material decisions** — no signal (MetaDAO's
   own finding). Route small ops through lanes/optimistic governance instead.
5. **Don't import external treasury managers as a dependency** (GnosisDAO/kpk
   divorce) — delegation must be revocable-by-design (lanes already are).
6. **Don't freeze unverifiable assumptions** — same discipline STRATEGY.md applies to
   pons v2: no immutable slots pointing at T-bill tokens, CoW, or oracles that aren't
   on the chain yet; use pre-declared conditional slots or leave it to a later deployment.

---

## 6. Candidate product shape (synthesis)

1. **Vault kernel** (one immutable contract family): lanes, dials-in-bounds, buffer
   waterfall, redemption floor, freeze rail. Governance = one `decider` slot.
2. **Decider options** (each standalone, each immutable, any of them can hold the slot):
   - assigned-address council (Warden),
   - token voting with optimistic lane + veto escrow (Agora),
   - futarchy autocrat with conditional vaults + capped-TWAP markets (Delphi).
3. **Outflow adapters** targeting the existing Sinjoh rails: airdrop distributor,
   liquidity manager, TWAMM buyback, streaming grants, splits.
4. **Inflow points**: fee-router allocation sink; revenue-collector processor (and the
   40/20/20/15/5 allocation lives here as the buffer waterfall).

Differentiators no competitor currently offers, in one product: on-chain book-value
floor + market-governed (futarchy) capital allocation + stock-token treasury sleeve +
fully immutable, admin-keyless construction — on the first brokerage-operated L2.

Sequencing intuition (not a commitment): Warden lanes + buffer waterfall + redemption
floor first (they de-risk everything else and complete the revenue-processor story);
Agora optimistic governance second; Delphi futarchy as the flagship differentiator
once conditional-AMM TWAP design is validated against manipulation modeling.

*Note: superseded in part by [TREASURY_DESIGN.md](./TREASURY_DESIGN.md) Rev 2, which
moved lanes/dials/waterfall out of the kernel into governor modules, middleware, and
sinks, and kept only the redemption + dead-man rails kernel-resident.*

---

## 7. Open questions

1. **Claim-token design for the redemption floor**: is the subject token itself the
   claim (Nouns-style), or a separate staked/treasury-share token (Moloch
   shares/loot)? Affects whether the floor props the traded price directly.
2. **Futarchy market venue**: bespoke conditional CPMM with built-in lagging TWAP vs
   Uniswap v4 pools + truncated-oracle hook. The bespoke pool is more auditable; the
   v4 route reuses battle-tested swap code.
3. **Liquidity subsidy economics**: who funds the ~$50–100K per futarchy proposal on
   small treasuries — the treasury itself, the proposer, or a shared Sinjoh
   subsidy pool (the last conflicts with "no shared layer")?
4. **Typed action set**: which treasury operations make the enum at v1?
   Everything excluded is excluded forever per deployment.
5. **Freeze-vote weighting**: subject-token deposits (plutocratic but sybil-proof) vs
   claim-token deposits vs hybrid — and what freeze duration can't be griefed.
6. **Legal posture on Stock-Token sleeves and futarchy markets** for US-adjacent
   users — futarchy conditional tokens look like event contracts; CLARITY Act
   trajectory matters here.

---

## Appendix: source highlights

- Safe v1.5.0 module guards: https://safefoundation.org/blog/introducing-safe-v1-5-0-module-guards-enhanced-smart-account-features
- Zodiac Roles v2: https://docs.roles.gnosisguild.org · kpk DeFi Kit: https://github.com/karpatkey/defi-kit
- oSnap deprecation: https://docs.uma.xyz/resources/osnap
- Bybit post-mortem (Sygnia): https://www.sygnia.co/blog/sygnia-investigation-bybit-hack/
- Lido Dual Governance: https://blog.lido.fi/dual-governance-101-explainer/ · https://github.com/lidofinance/dual-governance
- Nouns fork & payment rails: https://github.com/nounsDAO/token-buyer · https://github.com/nounsDAO/streamer
- MetaDAO docs (TWAP, markets, launches): https://docs.metadao.fi · programs: https://github.com/metaDAOproject/programs
- MetaDAO analysis: https://www.helius.dev/blog/futarchy-and-governance-prediction-markets-meet-daos-on-solana · bear case: https://greshamscode.substack.com/p/metadao-the-bear-case
- Optimism Futarchy v1 findings: https://gov.optimism.io/t/futarchy-v1-preliminary-findings/10062
- Unichain CFM case study: https://www.uniswapfoundation.org/blog/unichain-cfm-pilot-case-study
- Butter CFM mechanism: https://github.com/buttermarkets/ggresearch/blob/main/topic/gov-designs/conditional-funding-markets.md
- Decision-market incentive theory: https://www.cs.cmu.edu/~sandholm/decision%20rules%20and%20decision%20markets.AAMAS10.pdf
- Vitalik, info finance: https://vitalik.eth.limo/general/2024/11/09/infofinance.html
- Uniswap v4 TWAMM hook: https://blog.uniswap.org/v4-twamm-hook
- Sky Smart Burn Engine: https://developers.sky.money/core-protocol/smart-burn-engine/
- UNIfication: https://blog.uniswap.org/unification
- Robinhood Chain mainnet: https://blog.arbitrum.io/robinhood-chain-mainnet/ · Arbitrum DAO factsheet: https://forum.arbitrum.foundation/t/arbitrumdao-factsheet-robinhood-chain-mainnet-launch/31041
- Safe live on Robinhood Chain: https://x.com/SafeLabs_/status/2072411833260970071
- Trail of Bits immutability maturity model: https://blog.trailofbits.com/2025/06/25/maturing-your-smart-contracts-beyond-private-key-risk/
- Debt-aware bonding curves (floor invariants): https://eprint.iacr.org/2026/483.pdf
- Squads v4: https://squads.so · SPL Governance/Realms: https://realms.today
