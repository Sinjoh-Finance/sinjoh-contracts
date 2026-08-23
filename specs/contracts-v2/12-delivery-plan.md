# Delivery Plan

## 1. Implementation shape

Implement the new system as one auditable Foundry package, `sinjoh-contracts-v2`, with protocol
folders rather than retrofitting the existing deployed packages. Existing Raffle and Liquidity
tests/specifications are imported as compatibility suites; their source may be reused or versioned
only where project-binding interfaces require it.

Proposed source layout:

```text
sinjoh-contracts-v2/
  src/
    core/ProjectRegistryV2.sol
    core/ProjectLauncherV2.sol
    token/ProjectVotesToken.sol
    multisig/ProjectMultisigAccountV2.sol
    governance/ProjectGovernorV2.sol
    governance/ProjectTimelockV2.sol
    treasury/ProjectTreasuryVaultV2.sol
    router/ProjectRouterV2.sol
    staking/ProjectStakingPoolV2.sol
    staking/ProjectPoSNFT.sol
    airdrop/ProjectAirdropV2.sol
    basket/BasketManagerV2.sol
    basket/BasketNFTV2.sol
    basket/BasketVaultV2.sol
    bands/ProjectFundingBandsV2.sol
    raffle/ProjectRaffleV2.sol
    liquidity/ProjectLiquidityManagerV2.sol
    adapters/
    interfaces/
    libraries/
  test/
    unit/
    fuzz/
    invariant/
    integration/
    fork/
  script/
  deployments/
```

Shared interfaces/libraries are copied into this package and pinned. Production contracts do not
import implementations from legacy packages at runtime.

## 2. Dependency graph

```text
Phase 1: interfaces + accounting + project identity
  |
Phase 2: token checkpoints + staking/PoS NFT
  |\
  | +--> Phase 3A: independent Multisig Accounts --\
  +----> Phase 3B: independent Token Governance -----+--> Phase 4: Registry + Treasury Vault
                                                        |
                                                        +--> Phase 5A: Router + Airdrop
                                                        +--> Phase 5B: Basket
                                                        +--> Phase 5C: Funding Bands
                                                        +--> Phase 5D: Raffle/Liquidity binding
                                                                       |
                                                                       +--> Phase 6: Launcher
                                                                              |
                                                                              +--> Phase 7: full integration/fork/release
```

This order establishes historical eligibility and control before any custody module relies on
them. The Launcher is implemented after every module can self-report/validate its immutable project
binding.

## 3. Work packages

| Phase | Deliverable | Estimated engineering effort | Completion gate |
| --- | --- | ---: | --- |
| 1 | shared interfaces, exact-transfer/accounting/fee libraries, typed adapter boundaries | 4-6 days | unit/fuzz libraries and no arbitrary-call surface |
| 2 | automatic-vote token, staking pool, PoS NFT, checkpoint invariants | 7-10 days | mint/transfer/burn/stake/NFT transfer/unstake snapshot suite |
| 3A | independent 2-of-3 Multisig Accounts | 3-4 days | submit/confirm/revoke/expire/execute/signer-replacement suite |
| 3B | independent Governor/Timelock for both vote sources | 4-5 days | full propose/vote/queue/execute suites |
| 4 | Registry and narrow Treasury Vault including Basket NFT custody | 5-7 days | controller/asset/NFT custody invariants |
| 5A | Router and Airdrop plus worker fixtures | 10-14 days | all action types, failure escrow, both eligibility modes |
| 5B | Basket Manager/NFT/Vault and first production adapter | 12-18 days | loss/high-water mark, dividends, rebalance, resumable burn |
| 5C | Funding Bands and all proceeds destinations | 10-14 days | current-price retroactive creation and full settlement matrix |
| 5D | Raffle/Liquidity v2 binding with preserved suites | 5-8 days | zero regression against current normative tests |
| 6 | deterministic Launcher and module-combination matrix | 7-10 days | atomic all-modules launch and role/address proof |
| 7 | system invariants, mainnet forks, scripts/manifests, canary, audit remediation | 15-25 days + audit | every release gate in security specification |

Estimate: 75-119 engineering days plus independent audit time. Parallelism is safe only after
Phase 4 interfaces are frozen; the four Phase 5 tracks can then proceed concurrently.

## 4. Per-protocol definition of done

Every protocol implementation is complete only when it has:

1. source and copied interfaces with NatSpec;
2. canonical configuration encoding/hash and full readback views;
3. explicit access-control and external-call inventory;
4. unit, fuzz, and stateful invariant coverage;
5. cross-module integration tests for every documented input/output;
6. events sufficient for UI/indexer/keeper operation;
7. deterministic deployment script and manifest schema;
8. mainnet-fork evidence for every external integration;
9. audit scope entry and threat-model update;
10. UI handoff for launch configuration, irreversible decisions, pending work, and failure recovery.

## 5. UI/DevX deliverables

The contracts work is incomplete without generated ABIs/types and one project configuration API.
The UI should read one Registry record and then render only enabled modules.

Required flows:

- launch builder validates module dependencies before wallet submission;
- governance builder generates typed module actions and simulates them;
- portfolio shows liquid votes, staked votes, PoS positions/unlock times, Airdrop history, Basket
  holdings/yield/principal/loss, Band states, Raffle status, and permanent liquidity;
- keeper/operator page shows every due/retryable action and exact reason/state;
- irreversible actions—staking lock, permanent liquidity funding, Band funding, Basket burn/tax/
  price—require explicit final summaries;
- all percentages display basis points and effective stacked service fees for the selected path.

The SDK exposes `predictLaunch`, `validateLaunchConfig`, `encodeGovernanceAction`, `projectRecord`,
and per-module pending-work helpers. The SDK and Solidity canonical encodings share fixture tests.

## 6. Compatibility and do-not-touch list

- Do not modify deployed v1 storage, proxies, factories, or project state.
- Do not change Raffle ticket/randomness/tax/settlement behavior.
- Do not make permanent Liquidity withdrawable or governance-controlled.
- Do not add delegation, generic plugins, or arbitrary execution to satisfy an integration shortcut.
- Do not add manual post-launch wiring that the v2 Launcher can derive and verify atomically.
- Do not support incompatible tokens by silently weakening balance/checkpoint/accounting checks.

## 7. Implementation acceptance criteria

1. Every source file in the proposed layout has a corresponding test suite and specification link.
2. No implementation task must decide governance mode, vote semantics, module ownership, principal
   lock, destination behavior, or failure accounting; those choices are fixed by this specification.
3. All optional module combinations compile/deploy without dead placeholder modules.
4. A fresh engineer can reproduce the full testnet launch from a signed manifest without manual
   role assignment or address editing.
5. The implementation is not proposed for production until the independent audit and all release
   gates are complete.
