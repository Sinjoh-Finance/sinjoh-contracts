# Raffle

## 1. Product decision

Contracts v2 does not redesign the Raffle. The current
[`sinjoh-raffle-rewards/SPEC.md`](../../sinjoh-raffle-rewards/SPEC.md) is the normative functional
specification. A v2 deployment may update the project-binding/funding interface required by the new
launcher, but must preserve the raffle's economic, ticket, randomness, settlement, tax, solvency,
and failure behavior.

Any functional divergence requires a separately reviewed Raffle specification; it must not be
introduced as incidental contracts-v2 integration work. `ProjectRaffleV2` therefore changes the
deployment boundary, not the product: project identity and every raffle setting are frozen in one
atomic initialization instead of exposing a later creator-operated binding step.

## 2. Behavior that must remain unchanged

- one immutable Raffle per project launch;
- prize funding in one immutable asset;
- proportional whole-ticket weight:
  `tickets(holder) = floor(weight(holder) / tokensPerTicket)`;
- immutable snapshot or minimum-balance ticket basis;
- immutable complete exclusions for pools, curves, hooks, lockers, vesting, treasuries, escrows,
  and other subject-token custody addresses;
- automatic exclusion of the zero address and canonical burn address
  `0x000000000000000000000000000000000000dEaD` from ticket weight and total tickets;
- deterministic Merkle-sum ticket tree committed before randomness;
- prize reservation before the seed exists;
- verifiable randomness through the audited immutable randomness adapter;
- one to sixteen winners per round and per-slot single settlement;
- direct funding-asset payout or configured guarded mystery-stock payout;
- retryable winner credits and late funding-asset fallback for a permanently failed stock route;
- bounded failure isolation: an external token or payout recipient cannot force the Raffle to copy
  unbounded revert data and exhaust the settlement transaction;
- recipient/recycle payout-tax split under the current cap;
- cumulative 1% intake service fee;
- expiry and abandonment returning unpaid reserve to the prize pool;
- no owner, upgrade, rescue role, root replacement, arbitrary call, or mutable route.

Raffle eligibility remains holder-ticket based. Staking does not become a Raffle requirement in
contracts v2.

## 3. V2 integration boundary

The v2 Raffle instance additionally reports immutable `projectId` and registry address and accepts
the common funding shape:

```solidity
function fund(
    bytes32 projectId,
    address subject,
    address asset,
    uint256 amount,
    bytes calldata config
) external payable returns (uint256 received);
```

The Raffle verifies its project/subject/prize asset/config hash and otherwise follows the current
attributed-funding rules. Router and Funding Bands may fund it. Neither can change round settings,
exclusions, taxes, stock routes, or randomness.

The Launcher predicts the Raffle clone before token/pool creation when the launch profile requires
its address as a destination. Token construction may safely reference that predicted address. In
the same launch transaction, the Launcher clones the reviewed implementation and calls
`initialize(registry, subject, config)` exactly once. Initialization verifies the subject's
Registry-derived project identity and freezes a `configHash` over chain ID, Registry, subject, and
the complete configuration. The implementation contract is initialization-locked, and the
Registry records the clone as the project's Raffle. There is no deploy-then-bind period and no
creator binding transaction.

The common `fund` selector is identical to `IProjectFundable`. Empty funding configuration uses the
already-frozen settings; nonempty configuration must hash exactly to `configHash`. The Raffle
measures exact custody received and rejects transfer-tax or rebasing behavior that changes the
amount. Router and Funding Bands can therefore use the same typed destination integration as every
other v2 value sink.

## 4. Creator and holder experience

The launch surface presents product choices, not contract plumbing:

- prize asset, tickets per token amount, draw cadence, winner count, prize share/cap, ticket basis,
  optional payout tax, and optional reviewed stock rewards;
- a pre-launch summary of the effective 1% Raffle intake fee plus any upstream Router or Funding
  Band fee, so stacked fees are never hidden;
- automatic zero-address, burn-address, Raffle, and project-token exclusions;
- automatically assembled and visibly reviewed custody exclusions for pools, lockers, treasuries,
  routers, staking pools, baskets, vesting, and launch escrows;
- validation before signing for duplicate/unsorted exclusions, unsafe assets, invalid ranges, and
  unsupported routes.

After launch, keepers reconstruct eligibility, commit rounds, deliver randomness, submit winning
proofs, retry deferred transfers, and close timed-out rounds. Winners do not register, delegate,
sign, or claim. Frontends can read the frozen configuration, next prize, round status, liabilities,
and retryable credits without reconstructing storage.

## 5. Automation

The existing worker obligations remain normative:

1. reconstruct raw balances/minimum balance in canonical log order;
2. apply immutable exclusions and ticket math;
3. publish deterministic leaf/proof artifacts;
4. commit inside the L2 block-hash verification window;
5. seal/prove/deliver randomness through the selected adapter;
6. settle each winning slot and retry deferred payments;
7. expire or abandon stalled rounds;
8. monitor abnormal abandonment and randomness withholding.

No token-holder action is required to receive a prize; the keeper submits winning proofs.

## 6. V2 acceptance criteria

1. Every required test in the current Raffle specification continues to pass against the v2-bound
   implementation.
2. Router funding creates exactly one attributed prize deposit and charges no extra Raffle behavior
   beyond the documented module-local fee.
3. Funding Bands can fund the Raffle only through the registered project/prize configuration.
4. Predicted launch addresses produce a complete exclusion list before Raffle deployment.
5. A project with staking enabled has the same Raffle ticket behavior as a project without staking.
6. Factories, launcher, Router, Treasury, and governance cannot modify an initialized Raffle.
7. The canonical burn address always has zero tickets and is excluded from the committed ticket
   total even when it holds project tokens.
8. The current Raffle repository's complete test suite passes unchanged, and the v2 package adds
   unit, fuzz, invariant, Router-integration, initialization, and hostile-token failure tests.
9. A failed ERC-20 payout becomes an exact backed credit even if the token returns extremely large
   revert data.

## 7. Explicit trust and asset constraints

- Randomness liveness depends on the configured audited adapter and its upstream provider. The
  timeout returns reserved funds but cannot make a withholding provider produce randomness.
- The attestor/worker can delay a round but cannot alter a committed root, reroll a delivered seed,
  or spend the pool. Independent artifact verification remains required.
- Prize and stock assets must be platform-approved, non-rebasing, and transfer-fee-free. Exact
  balance-delta checks reject incompatible behavior at runtime; the Launcher should reject it
  before the creator signs.
- Mystery-stock routes use only immutable reviewed adapters and proof-approved price guards.

## 8. Out of scope

- new ticket formulas;
- staker-only Raffle mode;
- governance-controlled Raffle configuration;
- new randomness designs;
- multi-prize-asset pools.
