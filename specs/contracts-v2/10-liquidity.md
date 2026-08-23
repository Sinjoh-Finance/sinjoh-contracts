# Liquidity

## 1. Product decision

Contracts v2 does not redesign permanent liquidity. The current
[`sinjoh-liquidity-manager/SPEC.md`](../../sinjoh-liquidity-manager/SPEC.md) is the normative
functional specification. A v2 deployment may update project binding and the standard funding
interface, but must preserve pool resolution, guarded swaps, full-range position behavior,
permanent custody, fee disposition, and accounting.

Any change that makes liquidity withdrawable, changes position range, or adds governance control is
outside this specification.

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

The v2 manager stores/validates `projectId` and accepts:

```solidity
function fund(
    bytes32 projectId,
    address subject,
    address asset,
    uint256 amount,
    bytes calldata config
) external payable returns (uint256 received);
```

Router and Funding Bands may fund the registered Liquidity Manager. The first fund for an isolated
account freezes venue, quote asset, pool fee, tick spacing, hook, swap/guard route, swap share,
slippage/notional/interval bounds, and fee mode. Later calls must match the same canonical hash.

The project Registry provides the subject and canonical pool identity; the Liquidity Manager still
derives/verifies the pool through canonical exchange contracts and does not trust Registry metadata
alone.

## 4. Treasury and Basket relationship

Permanent liquidity is not Treasury or Basket principal. Neither Treasury governance nor a Basket
NFT burn can withdraw it. Position fees may be configured to:

- return to the funding Router for rerouting;
- go to creator or Treasury;
- recycle into the same permanent-liquidity account.

If Treasury receives fees and its basket policy is enabled, those Treasury receipts may then route
to the Basket through the normal Treasury flow. Liquidity Manager never funds a Basket directly.

## 5. V2 acceptance criteria

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

## 6. Out of scope

- withdrawable/project-owned liquidity;
- concentrated ranges other than permanent full range;
- governance-updated pool/route configuration;
- migration of existing positions;
- principal use by Treasury or Basket.
