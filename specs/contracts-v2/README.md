# Sinjoh Contracts v2 Specifications

Status: implementation specification

Target: new deployments on Robinhood Chain (`4663`; testnet `46630`)

Legacy migration: out of scope

## Product objective

Contracts v2 is one coherent launch system. A project selects optional modules at launch, and the
launcher deploys and connects those modules in one transaction. Each deployed module is bound to
the same project token, creator, governance authority, treasury, and project record.

The system must deliver the following user experience:

- every enabled feature works immediately after launch;
- token-holder voting requires no delegation or manual vote activation;
- staking creates one visible Proof of Stake NFT per position;
- project governance can operate the treasury and update enabled routers and baskets;
- routes, bands, baskets, raffles, liquidity, and airdrops compose without launch-specific glue;
- a failed optional destination cannot silently lose funds or stop unrelated routes;
- interfaces can discover the complete project configuration from one registry record.

These are greenfield specifications. Existing contracts are evidence for preserved behavior, not
constraints on the new architecture. Raffle and liquidity behavior are intentionally preserved;
the other protocols are specified around the product vision rather than retrofitted into v1.

## Specifications

| Document | Scope |
| --- | --- |
| [00-system-architecture.md](./00-system-architecture.md) | system boundaries, shared interfaces, asset flow, authority, automation |
| [01-project-token-registry-and-launch.md](./01-project-token-registry-and-launch.md) | automatic vote-compatible token, registry, deterministic launch orchestration |
| [02-governance.md](./02-governance.md) | multisig and liquid/staked token-holder governance |
| [03-router.md](./03-router.md) | routing, swaps, burn, liquidity, airdrop, raffle, treasury, and direct sends |
| [04-treasury.md](./04-treasury.md) | governed custody, sends, swaps, and optional basket routing |
| [05-staking-and-pos-nft.md](./05-staking-and-pos-nft.md) | single staking pool, locked positions, PoS NFTs, vote checkpoints |
| [06-airdrop.md](./06-airdrop.md) | proportional holder or staker distributions with automatic delivery |
| [07-basket.md](./07-basket.md) | treasury-owned Basket NFTs, yield assets, harvests, and redemption by burn |
| [08-funding-bands.md](./08-funding-bands.md) | post-launch market-cap bands and standardized proceeds destinations |
| [09-raffle.md](./09-raffle.md) | preserved holder raffle behavior and v2 integration boundary |
| [10-liquidity.md](./10-liquidity.md) | preserved permanent-liquidity behavior and v2 integration boundary |
| [11-security-testing-and-release.md](./11-security-testing-and-release.md) | shared invariants, tests, deployment manifests, audit and release gates |
| [12-delivery-plan.md](./12-delivery-plan.md) | implementation packages, dependency order, and completion gates |
| [13-vision-traceability.md](./13-vision-traceability.md) | requirement-by-requirement coverage across the full platform vision |

## Product rules locked by this specification

1. A project has exactly one canonical registry record and one governance authority.
2. Governance mode is either multisig or token holder. Delegation is not supported.
3. Token-holder governance chooses one immutable vote source: liquid wallet balances or staked
   balances.
4. Tokens created through the v2 launcher always expose automatic historical balance checkpoints.
   Holders do not delegate to themselves before voting.
5. Enabled modules are optional, but every selected combination is deployed and wired atomically.
6. The treasury owns every basket created with that treasury. Burning the Basket NFT is the only
   operation that unlocks basket principal.
7. Holder and staker airdrops are proportional. The creator participates normally when eligible;
   liquidity pools and the Pons locker are ineligible.
8. The first release creates at most one primary Basket per project Treasury; the Basket Manager
   may serve many different projects/Basket NFTs.
9. Raffle and permanent-liquidity product behavior remains unchanged.
10. Contracts are non-upgradeable. A new audited factory/implementation version is used for future
   behavior changes.
11. No protocol exposes an unrestricted arbitrary-call function.

## Terminology

- **Project token**: the ERC-20 launched for one project.
- **Governance authority**: either a 2-of-3 multisig or a token-governance timelock.
- **PoS NFT**: the ERC-721 token representing one locked staking position.
- **Holder mode**: weight equals eligible project-token wallet balance at a snapshot.
- **Staker mode**: weight equals eligible project-token amount locked in PoS NFT positions at a
  snapshot.
- **Sink**: a contract that accepts attributed funds through the standard `fund` interface.
- **Platform-approved**: an implementation/runtime hash admitted by the platform deployment
  manifest after audit and integration testing. It is not a mutable super-admin allowlist.

## Global acceptance criteria

1. A launch enabling every module produces one registry record containing the token, governance,
   treasury, router, staking/PoS NFT, airdrop, basket, funding bands, raffle, and liquidity addresses.
2. The same launch with any optional subset succeeds without placeholder addresses or later manual
   wiring.
3. A newly launched token can create a proposal and vote using wallet balances without delegation.
4. A staked-governance launch can create a proposal and vote using aggregate PoS NFT position
   balances without a separate adapter deployment.
5. All governed state changes authenticate the project authority recorded at launch.
6. All value-moving operations use measured balance deltas and maintain per-asset solvency.
7. Unsupported fee-on-transfer or rebasing behavior fails before accounting is committed.
8. Deployment scripts emit a machine-readable manifest, verify runtime hashes, renounce bootstrap
   privileges, and leave the launcher/factories with no project authority.

## Explicitly out of scope

- upgrading or migrating deployed v1 contracts;
- governance delegation, liquid democracy, veto councils, or vote multipliers;
- cross-chain governance or bridging;
- permissionless yield-adapter admission;
- fee-on-transfer, rebasing, or ERC-777 project/funding assets;
- a generic arbitrary-call executor in any custody contract.
