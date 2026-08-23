# Vision Traceability

This matrix verifies the platform vision against the contracts-v2 specification as one system. It
is a coverage check, not a replacement for the protocol specifications.

## Routers

| Vision requirement | Spec result |
| --- | --- |
| route, swap, burn, add liquidity, airdrop, send, fund Raffle | typed actions in [Router](./03-router.md), each with fixed recipient/integration and measured accounting |
| send to creator, Treasury, or another address | `SEND`, `SWAP_AND_SEND`, and `FUND_TREASURY` |
| governance-updatable when enabled | complete route versions activated by the immutable project authority |
| stake-only airdrops when enabled | Router funds the registered Airdrop; immutable Airdrop mode applies automatically |

## Treasuries

| Vision requirement | Spec result |
| --- | --- |
| multisig or token-holder governance | same Treasury ABI, executor is Joint or token-governance Timelock |
| receive, swap, send assets | exact receipts, guarded typed swaps, governed sends |
| automatically route receipts to an index Basket when enabled | eligible receipts become reserved; permissionless keeper funds Treasury-owned primary Basket |

## Baskets

| Vision requirement | Spec result |
| --- | --- |
| NFT with own Treasury holding one/multiple approved yield assets | Basket NFT + per-token Basket Vault (the Basket's Treasury), one to eight audited adapters |
| defined at Treasury launch and NFT owned by Treasury | launch config mints primary Basket directly to Project Treasury |
| routed fees swapped into Basket assets | weighted guarded swaps and exact adapter deposits |
| reap every 24 hours or 7 days and airdrop dividends | immutable cadence; permissionless harvest funds registered Airdrop |
| optional stake-only dividends via PoS NFT | immutable Basket/Airdrop staker mode using staking checkpoints |
| assets locked until Basket burn | principal cannot leave Basket Vault before final burn settlement |
| unlocked assets go to NFT owner | current `ownerOf(tokenId)` receives every net redemption asset |
| optional burn tax to creator/Treasury/Router/Airdrop | immutable tax bps + one typed first-release tax destination |
| optional burn price in underlying project token | exact raw project-token amount pulled from NFT owner and burned at finalization |

## Staking

| Vision requirement | Spec result |
| --- | --- |
| optional per-project deployment | launcher deploys pool/NFT only when enabled |
| holders lock project tokens | immutable project lock duration, exact transfer into pool |
| one staking pool | one `ProjectStakingPoolV2` per project |
| PoS NFT represents position | one NFT per fixed amount/unlock timestamp; ownership carries eligibility/redemption right |
| burn NFT to unstake | full-position burn at/after unlock returns exact tokens |

## Airdrops

| Vision requirement | Spec result |
| --- | --- |
| Airdrop receives assets | standardized attributed funding from Router, Basket, Treasury, Bands, or EOA |
| holder or PoS-staker mode | immutable mode per funding account/instance and deterministic snapshot algorithm |
| proportional share of tokens or staked tokens | independent epoch formula based on total eligible weight |
| exclude burn address, LP, and Pons locker; creator included | canonical burn/custody/Pons exclusions are mandatory; creator is eligible normally |

## Raffle and Liquidity

| Vision requirement | Spec result |
| --- | --- |
| Raffle uses current implementation | current Raffle specification is normative; v2 adds project binding only |
| Liquidity uses current implementation | current permanent Liquidity specification is normative; v2 adds project binding only |

## Funding Bands

| Vision requirement | Spec result |
| --- | --- |
| create new/previously approved/crossed bands after launch while current cap is below bounds | creation checks current verified cap below lower bound; no historical-crossing prohibition |
| proceeds to creator | direct immutable creator destination |
| proceeds to Treasury | exact Treasury deposit |
| buyback and burn | guarded subject buy, then protocol burn |
| buyback and airdrop | guarded subject buy, then registered holder/staker Airdrop funding |
| proceeds to Router | standard Router funding |
| proceeds to Raffle rewards | normalization into immutable prize asset and registered Raffle funding |
| proceeds to Basket via Treasury | Treasury deposit marked for active primary Basket policy |

## Governance

| Vision requirement | Spec result |
| --- | --- |
| govern Treasuries and update Routers/Baskets | one project authority with typed capabilities for all three |
| multisig or token holders | exactly two launch modes: 2-of-3 Joint or Governor + Timelock |
| token governance may require staking via PoS NFT | immutable liquid/staked vote source; staking pool aggregates PoS position checkpoints directly |

## UX/DevX requirements derived from the vision

| Desired outcome | Spec mechanism |
| --- | --- |
| launch combinations work together | deterministic atomic launcher predicts, deploys, validates, and registers all enabled modules |
| no manual vote activation | v2 token/staking pool expose automatic raw-balance historical votes; no delegation/adapters |
| burned or burn-address tokens earn nothing | canonical burn address is excluded from liquid votes/supply, PoS ownership, Airdrop weights, and Raffle tickets |
| one place to discover a project | append-only Project Registry record with every enabled module |
| holders do not manually claim ordinary distributions | keeper pushes verified Airdrop/Raffle payments |
| automation is understandable | every due/retry state has views/events; keepers have no entitlement or configuration power |
| failures do not silently lose funds | per-route/per-recipient retry escrow and per-asset solvency invariants |
| future features do not compromise live deployments | non-upgradeable contracts; new audited factory versions for new behavior |

## Scope decisions made explicit

These decisions complete ambiguous implementation details without changing the requested product
behavior:

1. The first release has one primary Basket per project Treasury and one burn-tax destination per
   Basket. A future version may add more, but the first working deployment remains simple.
2. Basket NFT ownership is transferable; current ownership always determines redemption.
3. PoS NFTs are transferable; transfer moves future stake weight and preserves historical snapshots.
4. Airdrop epochs are independent rather than carrying unpaid entitlement into later epochs.
5. “Automatic” execution means permissionless keeper execution with fully on-chain due state;
   passive ERC-20 transfers cannot invoke contract code.
6. Band eligibility uses current verified market cap and a fixed launch `referenceSupply`, so burns
   cannot manipulate band boundaries and a historical crossing does not permanently disqualify a
   future band.
7. Raffle and Liquidity behavior are preserved rather than generalized under project governance.
