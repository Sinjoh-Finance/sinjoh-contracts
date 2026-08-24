# Liquidity

## 1. Product decision

Contracts v2 does not redesign permanent liquidity. The current
[`sinjoh-liquidity-manager/SPEC.md`](../../sinjoh-liquidity-manager/SPEC.md) is the normative
functional specification. A v2 deployment may update project binding and the standard funding
interface, but must preserve pool resolution, guarded swaps, full-range position behavior,
permanent custody, fee disposition, and accounting.

Any change that makes liquidity withdrawable, changes position range, or adds governance control is
outside this specification. `ProjectLiquidityManagerV2` changes only the deployment and funding
boundary: one directly deployed manager is immutably bound to one Registry project, while its
accounts remain isolated by funding source.

## 2. Behavior that must remain unchanged

- one isolated account per `(funder, project subject)`;
- one immutable quote asset and canonical Uniswap v3/v4 pool configuration per account;
- a fixed bounded quote share swapped into subject under an immutable price guard;
- caller minima may strengthen but never weaken guard output;
- only full-range usable ticks;
- one permanent position per account; later mints increase it;
- permissionless mint/increase and zero-liquidity fee collection;
- principal liquidity can never be decreased, burned, transferred, approved, or withdrawn;
- failed pool initialization/hook execution leaves exact account credit for retry;
- fee modes for creator, Treasury, recycle, or funder;
- cumulative 1% protocol fee on collected position fees, not principal funding;
- exact per-account liabilities and measured balance deltas;
- no owner, upgrade, rescue, or arbitrary call.

## 3. V2 integration boundary

The v2 manager publishes immutable Registry, subject, and `projectId` identity and accepts:

```solidity
function fund(
    bytes32 projectId,
    address subject,
    address asset,
    uint256 amount,
    bytes calldata config
) external payable returns (uint256 received);
```

Every funding call must match the manager's project ID and subject before any transfer occurs.
Router and Funding Bands may fund the registered Liquidity Manager. The first fund for an isolated
account freezes venue, quote asset, pool fee, tick spacing, hook, swap/guard route, swap share,
slippage/notional/interval bounds, and fee mode. Later calls must match the same canonical hash.

The project Registry provides the subject and canonical pool identity; the Liquidity Manager still
derives/verifies the pool through canonical exchange contracts and does not trust Registry metadata
alone.

The common `fund` selector is identical to `IProjectFundable`. The manager's one-call
`accountStatus` view returns the funder, subject, complete frozen configuration, configuration hash,
pending balances, permanent position ID, last mint time, and configured state. `projectAccountId`
lets a client resolve the current project's account without re-supplying the subject.

The Launcher fixes the canonical v3/v4 infrastructure and protocol-fee recipient. Creators never
enter factory, PositionManager, Permit2, adapter, guard, hook, tick, or route addresses manually.
Those values come from the versioned audited deployment manifest and are verified again in the
launch preflight.

## 4. Creator and funder experience

The creator-facing launch form exposes only understandable choices:

- quote asset and supported v3/v4 pool profile;
- the bounded percentage swapped into the project token, shown as a simple liquidity split;
- minimum contribution, maximum contribution per mint, and optional mint cadence;
- position-fee destination: creator, Treasury, recycle into permanent liquidity, or return to the
  funding source.

Selecting creator or Treasury fills the canonical project address automatically. The zero address,
canonical burn address, and manager itself cannot be selected as a fee recipient. Before signing,
the interface shows that contributions are irreversible, the position is permanent full-range
liquidity, the 1% protocol charge applies only to collected LP fees, and pre-pool funding remains
credited but unusable until the canonical pool initializes.

After funding, keepers call `mint` or `collect` permissionlessly. A missing pool, rejecting hook,
expired quote, manipulated spot, slippage failure, or temporary external failure rolls the entire
attempt back and leaves the exact account credit available for retry. The funder does not approve a
position NFT, manage ticks, claim residuals, or perform a second binding transaction.

## 5. Treasury and Basket relationship

Permanent liquidity is not Treasury or Basket principal. Neither Treasury governance nor a Basket
NFT burn can withdraw it. Position fees may be configured to:

- return to the funding Router for rerouting;
- go to creator or Treasury;
- recycle into the same permanent-liquidity account.

If Treasury receives fees and its basket policy is enabled, those Treasury receipts may then route
to the Basket through the normal Treasury flow. Liquidity Manager never funds a Basket directly.

## 6. V2 acceptance criteria

1. Every required current Liquidity Manager test continues to pass.
2. Router funding initializes or adds to only the registered project/funder account.
3. Funding Bands cannot substitute another subject, pool, hook, or fee recipient.
4. Two project Routers funding the same subject cannot share credits or position ownership.
5. Position fees sent to Treasury become ordinary Treasury receipts and only route to a Basket under
   the active Treasury policy.
6. No governance proposal, Basket burn, or launcher call can decrease or transfer position
   principal.
7. The all-modules launch exercises funding, guarded swap, mint/increase, fee collection, and fee
   delivery on the selected canonical pool/hook in a mainnet fork.
8. The current Liquidity Manager repository's complete test suite passes unchanged, and the v2
   package adds project-identity, standard-funding, Registry, Router, fuzz, invariant, and retry
   coverage.
9. The canonical burn address cannot receive project or protocol position fees.
10. Frontends can discover the complete account configuration and financial state in one call.

## 7. Explicit trust and asset constraints

- Canonical v3/v4 factories, PositionManagers, PoolManager views, Permit2, adapters, guards, and
  hooks are deployment-manifest dependencies. A new runtime hash requires a new reviewed platform
  release; creators cannot substitute one.
- Project and quote ERC-20s must be non-rebasing and transfer-fee-free. Exact balance-delta checks
  reject incompatible transfers before accounting commits.
- A funded account cannot recover principal if its canonical pool never initializes or its immutable
  hook permanently refuses full-range liquidity. The launch UI must require explicit acknowledgement
  before allowing pre-pool funding.
- Sequencer timestamps gate short quote expiries and configured mint cadence; they never authorize
  custody withdrawal.

## 8. Out of scope

- withdrawable/project-owned liquidity;
- concentrated ranges other than permanent full range;
- governance-updated pool/route configuration;
- migration of existing positions;
- principal use by Treasury or Basket.
