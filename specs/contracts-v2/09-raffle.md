# Raffle

## 1. Product decision

Contracts v2 does not redesign the Raffle. The current
[`sinjoh-raffle-rewards/SPEC.md`](../../sinjoh-raffle-rewards/SPEC.md) is the normative functional
specification. A v2 deployment may update the project-binding/funding interface required by the new
launcher, but must preserve the raffle's economic, ticket, randomness, settlement, tax, solvency,
and failure behavior.

Any functional divergence requires a separately reviewed Raffle specification; it must not be
introduced as incidental contracts-v2 integration work.

## 2. Behavior that must remain unchanged

- one immutable Raffle per project launch;
- prize funding in one immutable asset;
- proportional whole-ticket weight:
  `tickets(holder) = floor(weight(holder) / tokensPerTicket)`;
- immutable snapshot or minimum-balance ticket basis;
- immutable complete exclusions for pools, curves, hooks, lockers, vesting, treasuries, escrows,
  and other subject-token custody addresses;
- deterministic Merkle-sum ticket tree committed before randomness;
- prize reservation before the seed exists;
- verifiable randomness through the audited immutable randomness adapter;
- one to sixteen winners per round and per-slot single settlement;
- direct funding-asset payout or configured guarded mystery-stock payout;
- retryable winner credits and late funding-asset fallback for a permanently failed stock route;
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

The Launcher predicts the Raffle before token/pool creation when the launch profile requires its
address as a destination. It supplies the complete predicted custody exclusion set and binds the
deployed subject exactly once. The Registry records the final binding.

## 4. Automation

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

## 5. V2 acceptance criteria

1. Every required test in the current Raffle specification continues to pass against the v2-bound
   implementation.
2. Router funding creates exactly one attributed prize deposit and charges no extra Raffle behavior
   beyond the documented module-local fee.
3. Funding Bands can fund the Raffle only through the registered project/prize configuration.
4. Predicted launch addresses produce a complete exclusion list before Raffle deployment.
5. A project with staking enabled has the same Raffle ticket behavior as a project without staking.
6. Factories, launcher, Router, Treasury, and governance cannot modify an initialized Raffle.

## 6. Out of scope

- new ticket formulas;
- staker-only Raffle mode;
- governance-controlled Raffle configuration;
- new randomness designs;
- multi-prize-asset pools.
