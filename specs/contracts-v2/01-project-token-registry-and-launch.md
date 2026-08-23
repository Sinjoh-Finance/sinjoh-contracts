# Project Token, Registry, and Launch

## 1. Objective

The launch layer makes compatible projects the default. It creates the token and every enabled
protocol together, predicts addresses needed by exclusions and routes, verifies the complete
wiring, and publishes one canonical project record.

## 2. ProjectVotesToken

Every token created by `ProjectLauncherV2` is a fixed-supply ERC-20 with automatic historical
wallet-balance checkpoints.

Required behavior:

- fixed supply minted exactly once according to launch allocation;
- no post-launch mint authority;
- standard transfers, permits, and burns;
- non-rebasing and no transfer tax;
- timestamp-based ERC-6372 clock;
- `getVotes(account)` equals the account's current eligible wallet balance;
- `getPastVotes(account, timepoint)` equals the eligible wallet balance at the historical
  timepoint;
- `getPastTotalSupply(timepoint)` equals historical voting supply, excluding immutable system
  custody addresses;
- `delegates(account)` returns `account`;
- `delegate` accepts only self and changes no state; `delegateBySig` is unsupported.

This makes liquid voting automatic. A holder who received tokens before a proposal snapshot can
vote; there is no self-delegation transaction or separate votes adapter.

### Voting exclusions

The token receives an immutable sorted exclusion list at construction. Balances held by these
addresses have zero voting power and are removed from voting supply:

- zero and dead addresses;
- the project token itself;
- predicted treasury, router, staking pool, airdrop, raffle, liquidity manager, bands, and basket
  vault addresses;
- the canonical liquidity pool/PoolManager and launch curve/locker addresses used by the launch;
- the Pons locker `0xda4bCee76B29EFEc9697Fcf663601c2042043968`;
- any other protocol custody address predicted by the selected launch profile.

The list is frozen to prevent governance from disenfranchising wallets later. Sending tokens to a
frozen custody address reduces voting supply; sending them back restores it at the next checkpoint.

## 3. ProjectRegistryV2

The registry is append-only for project identity and versioned for a small set of operational
metadata.

```solidity
struct ProjectRecord {
    bytes32 projectId;
    address subject;
    address creator;
    address authority;
    address treasury;
    address router;
    address stakingPool;
    address posNft;
    address airdrop;
    address raffle;
    address liquidityManager;
    address fundingBands;
    address basketManager;
    uint256 primaryBasketId;
    address canonicalPool;
    uint256 referenceSupply;
    uint64 launchedAt;
    uint32 protocolVersion;
    uint256 enabledModules;
}
```

Rules:

1. only the launcher may create a record;
2. one subject may have one v2 project record;
3. module addresses are either a deployed contract or zero when disabled;
4. all enabled modules must report the same `projectId`, subject, and authority before registration;
5. creator, token, authority, treasury, reference supply, protocol version, and launch time never
   change;
6. operational metadata updates are limited to adding a canonical pool address created after the
   token and publishing replacement UI metadata URIs; these updates require project governance and
   do not change contract authority or eligibility;
7. the registry never custodies project assets and has no transfer functions.

## 4. Launch configuration

```solidity
enum GovernanceMode { MULTISIG, TOKEN_HOLDER }
enum VoteSource { LIQUID, STAKED }

struct ModuleSelection {
    bool treasury;
    bool router;
    bool staking;
    bool airdrop;
    bool basket;
    bool fundingBands;
    bool raffle;
    bool liquidity;
}

struct LaunchConfig {
    address creator;
    string name;
    string symbol;
    uint256 totalSupply;
    bytes32 salt;
    GovernanceMode governanceMode;
    VoteSource voteSource;
    ModuleSelection modules;
    bytes governanceConfig;
    bytes treasuryConfig;
    bytes routerConfig;
    bytes stakingConfig;
    bytes airdropConfig;
    bytes basketConfig;
    bytes bandsConfig;
    bytes raffleConfig;
    bytes liquidityConfig;
    bytes launchProfileConfig;
}
```

Validation:

- creator, supply, name, and symbol are nonzero/nonempty;
- `STAKED` governance requires staking;
- basket requires treasury and airdrop;
- treasury automatic basket routing requires basket;
- staker-only airdrops require staking;
- raffle and liquidity configs satisfy their preserved specifications;
- all allocation percentages independently and collectively sum to their required total;
- config byte lengths are bounded and a canonical `launchConfigHash` is emitted.

## 5. Deterministic deployment flow

`ProjectLauncherV2.launch(config)` performs one atomic transaction:

1. validate the canonical launch config;
2. predict every CREATE2 module address from `(creator, salt, launchConfigHash, version)`;
3. compute the full immutable system/voting/airdrop exclusion set;
4. deploy the subject token with the predicted exclusions;
5. deploy staking/PoS NFT first when staked votes are selected;
6. deploy the selected authority, using the token or staking pool as its vote source;
7. deploy the treasury and every selected module with the same project bindings;
8. mint a configured Basket NFT directly to the treasury when basket is enabled;
9. create/resolve the canonical pool required by the launch profile;
10. verify all module readbacks, roles, and code hashes;
11. register the project;
12. renounce every bootstrap role and emit `ProjectLaunched` with all addresses.

Any failure reverts the complete launch. There is no half-launched project and no temporary factory
governance that must be cleaned up later.

## 6. Module combinations

| Selection | Required result |
| --- | --- |
| treasury only | governed receive/send/swap vault |
| router + raffle | raffle is a valid route sink and exclusions include all launch custody |
| router + liquidity | permanent-liquidity route is fully configured |
| treasury + basket + airdrop | Basket NFT owned by treasury; harvests fund project airdrop |
| staking + airdrop | staker-mode eligibility available |
| staking + token governance | staking pool is direct vote source |
| all modules | every route/destination resolves from the same project record |

The launcher must have an integration test for every row and for all enabled modules together.

## 7. Existing-token registration

Greenfield launch is the supported default. A separate `registerExistingToken` path may be
implemented only when the token is non-rebasing, fee-free, and exposes the exact automatic
historical vote interface required here. It must fail during preflight rather than deploy a partial
project. Existing-token support is not required for the first contracts-v2 release.

## 8. Events and views

Required events:

- `ProjectLaunched(projectId, subject, creator, authority, launchConfigHash, enabledModules)`;
- `ProjectModules(projectId, treasury, router, stakingPool, posNft, airdrop, raffle,
  liquidityManager, fundingBands, basketManager, primaryBasketId)`;
- `CanonicalPoolRecorded(projectId, pool)`;
- `ProjectMetadataUpdated(projectId, metadataHash)`.

Views must return the complete record, resolve `projectId` by subject, expose predicted addresses,
and validate a module's membership without array scans.

## 9. Acceptance criteria

1. Predicted and deployed addresses match for every optional module combination.
2. Reusing a creator/salt/config tuple cannot create a second project.
3. A staked-governance launch without staking reverts before any deployment.
4. Every new v2 token returns correct past wallet balances and past eligible voting supply across
   mint, transfer, burn, and transfers into/out of excluded custody.
5. No holder must call `delegate` before liquid voting power appears.
6. The project record cannot be overwritten or assigned to a different subject.
7. Factories, launcher, and deployer retain no authority after a successful launch.
8. The all-modules integration test funds the router, treasury, raffle, liquidity, basket, and
   bands without manually setting a missing project address.

## 10. Out of scope

- migrations from v1 launch records;
- mutable project-token voting exclusions;
- token inflation or elastic supply;
- launchpad-specific compatibility adapters not included in the selected v2 release manifest.
