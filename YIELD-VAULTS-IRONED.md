# Yield Vaults — Ironed Product and Protocol Design

> **Superseded historical source:** use `YIELD-BANKS-DEVELOPMENT-PLAN.md` for the
> canonical Yield Banks architecture. Fixed supply and sale-finalization language below
> does not apply to the implementation.

## One-sentence product

Yield Banks is a configurable-supply collection of transferable NFTs, each permanently bound to its own onchain treasury containing Stock Tokens, shares of market-making strategies, and a USDG lending position; the treasury compounds while the NFT exists and can be claimed only by burning the NFT.

## The product decision

Each NFT gets a deterministic isolated vault. The vault holds real Stock Token balances, USDG, and ERC-20 strategy shares. Collection-level strategy contracts own and maintain the underlying Delta LP positions for those shares.

This hybrid is deliberate:

- the NFT still owns a specific, auditable treasury;
- the vault's balances travel automatically with the NFT;
- Delta positions can be harvested and rebalanced once per strategy instead of up to 3,000 times;
- one strategy failure cannot give an operator access to unrelated vault assets; and
- redemption remains exact and can return assets in kind.

A literal Delta position NFT for every Yield Vault is possible, but it should not be the default. Three thousand separate ranges would be costly to create, monitor, harvest, and rebalance.

## Fixed launch configuration

| Item | Decision |
|---|---|
| Supply | Positive immutable maximum configured per collection |
| NFT standard | ERC-721 bearer claim with standard transfers |
| Mint format | Fixed-price mint so every token begins with equal backing |
| Vault | One deterministic minimal-proxy vault per token, deployed and initialized at mint |
| Portfolio | Positive Core Stock Token, Delta LP, and USDG lending sleeve weights configured immutably per collection and totaling 100% |
| Stock sleeve | Three launch-approved Stock Tokens, equal-weighted inside the collection-configured Core sleeve |
| Delta sleeve | Two collection strategy-share tokens, equal-weighted inside the collection-configured Delta sleeve |
| USDG lending asset | USDG `0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168` |
| Input and reward asset | WETH `0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73` |
| Exit tax | 5% of assets redeemed, redistributed in kind to the remaining live NFTs |
| Last NFT | Exit tax is waived; it receives rounding dust and closes the collection |
| Performance fee | None from Sinjoh; Delta's documented 1% fee on claimed LP fees still applies |
| Bound-token burn | Disabled at launch; it can be enabled only as a disclosed immutable mint-time term |

The exact three Stock Tokens and two Delta pools must be selected immediately before deployment from verified contracts with sufficient liquidity and live price feeds. Their addresses belong in the immutable collection manifest, not in marketing copy drafted before deployment.

## Economic splits

### Primary mint payment

- The collection-configured backing share is assigned to that NFT's treasury.
- The collection-configured creator share goes to the collection creator.
- The collection-configured Sinjoh share goes to Sinjoh.
- The collection-configured operations share funds the disclosed collection operations reserve for audits, automation, and keeper bounties. It is explicitly not NFT backing, is controlled by a published multisig, and must publish every payment. Unused reserve after 12 months is routed to the NFT treasuries.

### Sinjoh secondary sale

The enforced royalty is 5% of sale price:

- 3.5% goes to all live NFT treasuries;
- 0.75% goes to the creator; and
- 0.75% goes to Sinjoh.

External marketplaces may not enforce royalties. The protocol must never forecast them as guaranteed revenue.

### Bound-project-token fees

Any project-token fee explicitly assigned to this collection is split:

- the collection-configured backing share to all live NFT treasuries;
- the collection-configured creator share to the creator;
- the collection-configured Sinjoh share to Sinjoh; and
- the collection-configured operations share to the collection operations reserve.

Voluntary approved-asset contributions go 100% to the live NFT treasuries.

## What each NFT owns

For token `i`, `vaultOf(i)` is deterministic from the chain ID, factory, collection address, and token ID. The vault contract—not the wallet—owns:

- three approved Stock Token balances;
- two Delta strategy-share balances;
- USDG lending shares or receipt tokens;
- any allocations earned but not yet settled from the distributor; and
- its portion of collected and still-unclaimed strategy rewards.

The wallet holding the ERC-721 owns the exclusive bearer right to transfer the entire package or begin redemption. The holder cannot withdraw one asset, change the allocation, or use the vault as collateral unless a future collection explicitly enables those rights.

## Contract ownership and authority

| Actor | Can do | Cannot do |
|---|---|---|
| NFT holder | Transfer to another wallet; inspect backing; settle pending allocations; begin and finalize redemption | Withdraw individual assets; redirect strategy funds; alter collection economics |
| NFT vault | Hold assets and strategy shares; approve only registered adapters during a guarded operation; release assets during final redemption | Pay an arbitrary recipient; call arbitrary contracts |
| Fee distributor | Invest routed fees once; attribute equal units to live token IDs; settle one or a bounded batch | Loop through all 3,000 NFTs; change ownership; use backing for operations |
| Delta strategy | Own and manage the underlying LP position; collect fees; compound; issue shares; redeem normally or in kind | Hold unrelated collection assets; send principal to an operator |
| Keeper | Call permissionless settle, harvest, rebalance, and exit-processing functions and earn a capped bounty | Choose arbitrary swaps, pools, ranges, recipients, or fees |
| Guardian multisig | Pause new investment or place a configured strategy into exit-only mode | Withdraw or redirect backing; activate a strategy; rewrite splits; block in-kind redemption permanently |
| Timelock | Approve a reviewed adapter/feed migration after seven days | Change supply, bearer ownership, primary splits, royalty split, or exit tax |

Operational migrations are necessary because pools, feeds, and external contracts can be deprecated. They are constrained migrations, not discretionary treasury management: funds may move only from an approved component to another approved component or to USDG/WETH reserve, never to an administrator.

## Complete movement of funds

### 1. Mint

1. The buyer pays the fixed WETH price.
2. The factory creates and initializes the deterministic vault for the token ID.
3. The payment router records the collection-configured creator, Sinjoh, and operations entitlements.
4. The collection-configured backing share remains in the proceeds vault until Sinjoh manually executes allocation, so market or feed availability never blocks minting.
5. If all market and oracle guards are live, the router can allocate the WETH atomically. Otherwise anyone can call `allocate(tokenId)` later to convert it through configured routes into the three Stock Tokens, the USDG lending sleeve, and two Delta strategy shares.
6. The ERC-721 is minted through SeaDrop after the proceeds vault receives and records the actual payment. Deferred allocation changes composition, never ownership or backing custody.

### 2. Delta investment

1. A Delta strategy accepts USDG or WETH as its single accounting/deposit asset.
2. It acquires the paired Stock Token and supplies both assets through the verified Delta v3 position builder at `0x6235cF6bd8419b34942F4EDDB39C880BD96dD700`.
3. The resulting Uniswap v3 position NFT is owned by the strategy contract, not a keeper or creator.
4. The strategy issues fungible shares to the depositing NFT vault or fee distributor.
5. Trading fees accrue inside the position. Claimed Delta rewards arrive as WETH and stream over seven days.
6. A keeper harvests after a profitability threshold, pays Delta's fee, converts according to the fixed strategy allocation, and compounds. Sinjoh takes no performance fee.

Each strategy is a separately auditable pool. A strategy share is a real pro-rata claim on that strategy's principal, current token inventory, uncollected fees, claimed rewards, and streamed-but-not-yet-claimable rewards. The wrapper must offer an in-kind emergency redemption extension; a two-asset LP must not pretend to be plain ERC-4626 without defining this behavior.

### 3. Ongoing collection and project revenue

1. An approved fee source sends WETH to the collection fee router.
2. The router applies the immutable source split.
3. The NFT portion is invested once into the same six portfolio assets; no transaction loops over 3,000 vaults.
4. For each received asset, the distributor increases a high-precision `accPerLiveNft` index by `received / liveSupply`.
5. Each token ID tracks an index debt. Its pending amount is the current index minus its debt.
6. Anyone can call `settle(tokenId)` or a bounded `settleBatch` to transfer the token's actual Stock Tokens, USDG, and strategy shares into its vault.
7. Pending rights are keyed to the token ID, so a sale transfers both settled assets and unclaimed allocations.

Pending strategy shares already earn their underlying fees while held by the distributor. Settlement changes custody location, not economic exposure.

### 4. Transfer

The ERC-721 moves to its recipient using standard transfer semantics. The vault address and all balances remain unchanged because they are bound to the token ID. The new holder receives all settled balances, pending allocations, and redemption rights.

### 5. Harvest and rebalance

- Harvest is permissionless and executes only when the expected recovered value exceeds gas plus a configured margin.
- Rebalance is allowed only when the price feed is fresh, the corporate-action pause is clear, the route TWAP agrees within tolerance, and the current range has remained outside policy for a delay.
- V1 uses wide ranges and at most one position per Delta strategy to reduce churn.
- Every swap has a deadline, nonzero minimum output, a maximum portfolio impact, and an approved router/pool.
- When a Stock Token feed is stale or paused, swaps and range changes stop. Holding, settlement, and in-kind redemption remain available.

### 6. Redemption and burn

Redemption is deliberately multi-step so one failed external call cannot strand the whole collection:

1. The holder calls `beginExit(tokenId)`. Transfers lock, ownership is snapshotted, and all pending allocations settle.
2. Anyone may call bounded `processExitLeg(tokenId, leg)` calls. Strategy shares redeem to their current two assets; fees and rewards are collected where possible.
3. If a strategy cannot unwind after the emergency delay, its strategy shares or canonical position assets can be delivered in kind instead of blocking the exit forever.
4. The holder calls `finalizeExit(tokenId)`. The contract burns the NFT, decrements live supply, and sends 95% of every resulting asset to the snapshotted owner.
5. The remaining 5% of each asset is added to the distributor indices for the remaining live NFTs.
6. If this was the final live NFT, no tax is charged; it receives all residual balances and rounding dust, and the collection enters `CLOSED` state.

No redemption quote is guaranteed in WETH. Normal Delta withdrawal returns the current pool assets, and forced conversion would add avoidable slippage.

## Valuation shown to users

The dashboard reports four separate numbers rather than one misleading “floor”:

- **Gross backing:** direct Stock Tokens, reserve, strategy principal, current LP inventory, and uncollected fees.
- **Pending revenue:** assets attributed by the distributor but not yet moved into the vault.
- **Unvested/streaming rewards:** earned Delta rewards that are not yet claimable.
- **Estimated net redemption:** gross backing minus the 5% exit tax, Delta's fee on claimed fees, and conservative unwind costs.

Stock Token valuation uses the multiplier-adjusted onchain Chainlink feed exactly once. The Robinhood REST price is metadata only. When feeds are stale, paused, or outside operating hours, the UI labels NAV stale and the contracts refuse price-dependent actions.

## Failure and emergency rules

- One failed target does not block settlement or exit of the other targets.
- A paused Delta strategy stops deposits and rebalances but permits harvest, withdrawal, or in-kind exit.
- Unauthorized ERC-20 transfers are quarantined and never counted as backing until governance explicitly accepts them through the timelock.
- The guardian can pause new deposits and rebalances or place a strategy into exit-only mode. It cannot move or redirect assets; the strategy's fixed exit path sends assets back to its sleeve.
- Reentrancy protection, checks-effects-interactions, per-call value caps, allowance clearing, and exact balance-delta accounting apply to every adapter.
- Every vault, strategy, asset, feed, router, and position ID is indexed and shown in the proof-of-backing dashboard.

## Security gates before production

1. Resolve the full address, ABI, custody, and call sequence for every Delta builder, stake, farm, zap, reward-stream, or manager contract the strategy uses.
2. Prove LP creation, staking, fee and reward collection, seven-day streaming, unstaking, and two-asset exit on a pinned Robinhood Chain fork.
3. The Stock Token asset/feed manifest must be verified immediately before deployment.
4. The missing Robinhood Chain sequencer-health mechanism must be resolved or replaced by an explicit circuit breaker.
5. The complete system needs invariant, fuzz, fork, failure-recovery, and independent audit coverage.

## The stronger product idea

Make every Yield Vault a **living endowment** rather than static profile art. Its visuals evolve from verifiable treasury facts: portfolio composition, cumulative fees earned, backing growth, and time in range. A proof-of-backing page lets anyone open a token ID and trace every balance, strategy share, underlying Delta position, pending allocation, and net redemption estimate.

The art must be original and must not incorporate Robinhood Chain marks. This turns the treasury from invisible infrastructure into the collection's identity without promising a fixed yield.

## Founder pitch

Yield Vaults is a 3,000-piece collection where the asset is not just the artwork—the asset owns an onchain endowment.

When someone mints, most of the purchase funds that exact NFT's permanent treasury. The treasury holds diversified Stock Token exposure, supplies liquidity through Delta, and lends USDG through the configured venue. Every sale and every connected project-token fee sends new capital back to all live vaults. Delta trading fees and rewards compound inside the strategies, and the NFT's artwork evolves with its actual backing.

Sell the NFT and the whole treasury moves with it. Hold it and its claim keeps accumulating. To take the assets out, the owner must destroy the NFT; a 5% exit tax is left behind for everyone who stays. No creator or operator can reach into a vault, and every dollar of backing is traceable onchain.

It is a collectible, a transparent portfolio, and a revenue-sharing engine in one object: **the NFT is the vault key, and burning the key opens the vault.**
