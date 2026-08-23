# Shared Security, Testing, and Release

## 1. Security objective

Contracts v2 must preserve ownership, control, eligibility, and accounting across the complete
project—not merely prove each contract in isolation. Unit tests are required, but deployment is
blocked until all enabled-module combinations and full user journeys pass integration and mainnet-
fork testing.

## 2. Trust boundaries

| Boundary | Trusted for | Not trusted for |
| --- | --- | --- |
| project controller | explicit configuration and Treasury Vault decisions | changing historical votes/eligibility or bypassing typed module limits |
| optional guardian | pausing specified risky paths | transfers, resume, configuration, voting, unstaking |
| Airdrop/Raffle attestor | faithful off-chain snapshot construction | overspending funding, replacing roots, redirecting valid proofs |
| randomness adapter | unpredictable seed delivery under its published assumptions | custody or Raffle configuration |
| swap adapter | execution of one immutable route | prices, recipient choice, retained allowances/funds |
| price/oracle guard | minimum output and price validity | custody or arbitrary calls |
| yield adapter | custody/accounting inside one Basket position | Basket ownership, external recipient selection, principal distribution |
| keeper | timely permissionless execution | entitlement, destinations, fees, or configuration |
| Registry/Launcher factories | correct atomic deployment | continuing project control or custody |

Every external adapter/provider must have a documented failure mode, runtime hash, testnet/mainnet-
fork evidence, and audit status in the release manifest.

## 3. Role matrix

| Capability | Creator | Multisig/Timelock | Guardian | Attestor | Keeper | Factory |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| receive proportional holder/staker value | eligibility only | eligibility only | no | no | no | no |
| Treasury send/swap | no | yes | no | no | execute queued only | no |
| Router/Basket config | no | yes | pause only where selected | no | no | no |
| create/fund Band | no | yes | pause new funding only | no | arm/settle only | no |
| commit Airdrop/Raffle root | no | no | no | yes | no | no |
| push/harvest/retry/settle | no special power | no special power | no | no special power | permissionless | no |
| withdraw stake after maturity | position owner/approved | no | cannot block | no | no | no |
| unlock Basket principal | NFT owner through burn | only if controller operates owner Treasury | cannot block final recovery | no | process steps only | no |

The creator has no implicit admin power unless it is one of the selected multisig signers or owns
eligible tokens/positions.

## 4. Global invariants

The implementation must encode these as unit/fuzz assertions and stateful invariant tests:

1. **Project binding:** a module never accepts funds/configuration for another project ID or subject.
2. **No retained factory power:** launcher/factories hold no control, mint, pause, attestor,
   adapter, or withdrawal role after launch.
3. **Controller consistency:** every controlled module stores the same immutable controller.
4. **Vote conservation:** liquid/staked owner voting units and eligible voting supply update once per
   mint/transfer/burn/stake/NFT transfer/unstake.
5. **Burn-address exclusion:** the canonical burn address contributes zero to liquid/staked votes,
   eligible voting supply, Airdrop weight, and Raffle tickets; it cannot receive a PoS position.
6. **Stake backing:** staking-pool subject balance is at least active position amount and surplus is
   never counted as stake.
7. **Treasury backing:** reserved Basket routing never exceeds Treasury balance and is excluded from
   ordinary available balance.
8. **Router conservation:** pending + route escrow + protocol owed is fully backed per asset; a
   batch's successful + failed shares equal the net batch amount.
9. **Airdrop conservation:** uncommitted + committed unpaid + retry credits + protocol owed is fully
   backed per reward asset.
10. **Basket ownership:** only Basket NFT burn finalization releases principal, and net owner proceeds
   plus tax equals every measured unlocked amount.
11. **Basket yield:** cumulative dividends never exceed cumulative realized yield after loss recovery.
12. **Band conservation:** position proceeds are delivered or escrowed exactly once after position
   close; settlement/delivery retry cannot re-charge fees.
13. **Raffle/Liquidity preservation:** every invariant in their existing normative specifications
   remains true under v2 funding/binding.
14. **Fee integrity:** every 1% service fee equals the floor of cumulative fee base, with remainder
   carry preventing transaction-splitting avoidance.
15. **No arbitrary execution:** no module can call an unapproved target/selector or retain unlimited
   allowance.
16. **Cross-module conservation:** every asset leaving one module is measured as receipt, recipient
   credit, burn, permanent position principal, or explicit retryable failure in the next module.

## 5. Asset compatibility

Core project, funding, and reward assets must be standard ERC-20s with exact transfer behavior.
Before state/accounting commitment, every receipt/spend verifies balance deltas. Unsupported
behaviors include:

- fee-on-transfer or reflection;
- positive/negative rebases during accounting;
- callback/reentrancy semantics such as ERC-777 hooks;
- tokens that can block specific protocol recipients without a retryable-credit path;
- unbounded decimals/math that overflows configured conversions.

Native currency is supported only by entrypoints that explicitly accept it and verify exact
`msg.value`.

## 6. Swap/oracle requirements

1. Route, pair, recipient, adapter, guard, and venue are committed before execution.
2. Guard output is fresh, positive, route-bound, and independent of caller minima.
3. Spot/TWAP deviation is validated before and after price-sensitive execution where appropriate.
4. Approvals are exact and cleared.
5. Input spend and output receipt are measured, not trusted from return values.
6. Mainnet-fork tests cover manipulated spot, stale oracle, low liquidity, hook rejection, route
   expiry, and zero-output behavior.
7. If a platform-approved adapter/guard is later found unsafe, project governance can pause new use
   but cannot silently rewrite immutable historical routes/entitlements.

## 7. Snapshot requirements

Airdrop and Raffle workers must:

- use the chain's canonical L2 height/hash interface, not Solidity parent-chain `block.number`;
- commit within the verifiable block-hash window after the configured confirmation depth;
- cross-check the snapshot hash through two independent RPC endpoints;
- reconstruct events in strict `(blockNumber, transactionIndex, logIndex)` order;
- publish versioned deterministic artifacts and complete proofs;
- reconcile on-chain historical supply/stake totals;
- reject duplicate holders and include the immutable exclusion set/config hash.

Attestor and randomness signing keys must be distinct. Deep reorganizations and randomness
withholding remain disclosed external risks and must be monitored.

## 8. Testing pyramid

Minimum suites for the first complete implementation:

| Layer | Required coverage | Minimum |
| --- | --- | ---: |
| unit | constructor/config bounds, access control, math, state transitions, events/views | 15 tests per new protocol |
| fuzz | allocation math, checkpoint updates, proofs, fee remainder, tax splits, market-cap/tick conversion | 5 properties per protocol |
| invariant | all invariants in section 4, multi-actor/multi-asset sequences | 1 suite per custody module + 2 system suites |
| integration | every standard cross-module route/destination and every valid launch combination | 25 flows |
| end-to-end | creator launch through holder outcome for liquid and staked projects | 8 journeys |
| mainnet fork | selected DEX/hook/oracle/yield/randomness/launch profile behaviors | every production integration |
| deployment | address prediction, runtime hashes, roles, manifests, source verification | testnet + mainnet rehearsal |

These are floors, not caps. Existing Raffle and Liquidity required tests are additive.

## 9. Required end-to-end journeys

1. all-modules launch with multisig governance;
2. all-modules launch with liquid token governance, proposal/vote/queue/execute;
3. all-modules launch with staked governance, stake/NFT transfer/snapshot/vote/execute;
4. Router intake split among creator, Treasury, Airdrop, Raffle, and Liquidity with one failed action
   escrowed/retried;
5. Treasury receipt automatically reserved/funded into its owned Basket;
6. Basket funding -> yield -> 24h/7d harvest -> holder/staker push distribution;
7. post-launch Band creation below lower bound -> crossing -> settle through every destination;
8. Basket begin/process/finalize burn -> token burn price -> tax -> assets to current NFT owner.

Each journey asserts balances, ownership, control, emitted state, keeper work, and no retained
factory role.

## 10. Static and manual review

Before audit:

- formatting, compiler warnings, lints, tests, coverage, and contract-size checks pass;
- storage/layout reports are retained even though contracts are non-upgradeable;
- Slither or equivalent findings are dispositioned;
- privileged functions/selectors and external-call graph are generated/reviewed;
- all `unchecked`, assembly, low-level calls, callbacks, approvals, oracle conversions, and token
  decimal assumptions receive manual review;
- deployed bytecode matches audited source and compiler settings.

Independent audit scope must include the all-modules integration package, launch scripts,
off-chain snapshot algorithms/fixtures, and every production adapter—not just core Solidity files.

## 11. Deployment manifest

Every launch/release manifest records:

- git commit, compiler, optimizer settings, source/build hashes;
- chain ID and canonical external contract addresses/runtime hashes;
- factory/implementation/adapter/guard/oracle/randomness hashes;
- project launch config hash and predicted/deployed module addresses;
- creator, controller model/address, vote source, guardian, attestor;
- protocol fee recipient and every module-local fee/tax;
- token supply/allocation/voting exclusions;
- Router routes, Treasury basket policy, Basket targets, Band configs, Raffle and Liquidity configs;
- role readbacks and bootstrap-role renunciations;
- fork/testnet evidence references and audit report version.

The launch script refuses an uncommitted worktree, wrong chain, unverified runtime hash, missing
role renunciation, incomplete optional-module wiring, or address prediction mismatch.

## 12. Release and rollback

Contracts are non-upgradeable. Pre-funding rollback is to discard the candidate factories and
deploy a corrected version. After funding, response is module-specific pause/retry/recovery under
the immutable rules; there is no proxy upgrade or platform seizure.

Release gates:

1. complete unit/fuzz/invariant/integration/fork suites;
2. independent security audit and resolved findings;
3. testnet all-modules canary using production-shaped adapters;
4. verified deployment manifest and source publication;
5. smallest practical mainnet canary project/funding;
6. keeper/attestor/randomness monitoring and alerting active before accepting material funds;
7. public disclosure of governance, fees, exclusions, adapter/oracle risks, and irreversible locks.

## 13. Security acceptance criteria

1. No deployment proceeds with an unresolved critical/high audit finding.
2. Stateful invariants run at least 256 sequences per seed configuration and record reproducible
   seeds for failures.
3. All eight end-to-end journeys pass against testnet and the applicable mainnet fork.
4. A generated role report proves launcher/factories/deployer have no retained project controller
   power.
5. A generated asset-flow reconciliation proves no unmatched asset decrease across an all-modules
   run.
6. Production runtime hashes and configuration exactly match the signed release manifest.
