# Treasury Vaults

## 1. Objective

`ProjectTreasuryVaultV2` is the project's controlled vault. It receives native assets, ERC-20s, and
the project's Basket NFTs; sends assets; performs guarded swaps; and, when enabled, routes
designated receipts into the Treasury-owned basket.

The Treasury is deliberately narrow. It has no generic arbitrary-call executor.

## 2. Controller and deployment

One immutable controller controls the Treasury Vault:

- `ProjectMultisigAccountV2` in multisig mode; or
- `ProjectTimelockV2` in token-holder mode.

The Vault stores that address directly and contains no multisig, proposal, voting, or Timelock
logic. It is deployed with immutable project ID, subject, creator, controller, registry, and
approved integration root. It has no recovery owner, controller handoff, proxy admin, or factory
role.

## 3. Receiving assets

The Treasury accepts:

- native currency through `receive` and `depositNative`;
- exact ERC-20 receipts through `deposit(asset, amount, routeToBasket)`;
- raw ERC-20 transfers, visible as ordinary balance after `syncAsset(asset)`;
- Basket NFTs only from the project's registered Basket Manager or from an address explicitly
  transferred by the controller.

Every receipt emits its sender, asset, amount, and whether it was marked for basket routing.
Receiving an asset never invokes a swap or external protocol inside the transfer callback.

## 4. Sending assets

```solidity
function send(address asset, uint256 amount, address recipient) external onlyGovernance;
```

Rules:

- nonzero recipient and amount;
- available measured balance is sufficient;
- amount reserved for a pending basket route cannot be sent until the route is disabled/cancelled;
- outgoing balance delta equals amount;
- recipient balance delta equals amount for supported ERC-20s;
- native transfer failure reverts without changing accounting.

Governance may send to the creator, Router, Airdrop, Raffle, another address, or any other valid
recipient. The Treasury never infers a recipient from `msg.sender`.

## 5. Guarded swaps

```solidity
function swap(
    address adapter,
    address priceGuard,
    address assetIn,
    address assetOut,
    uint256 amountIn,
    uint256 callerMinOut,
    bytes calldata routeData,
    bytes calldata guardData
) external onlyGovernance returns (uint256 amountOut);
```

The adapter, guard, pair, and route hash must be included in the project's immutable approval root.
The guard provides an unexpired minimum output. The Treasury enforces the stronger of guard and
caller minima, exact input spend, measured output receipt, exact allowances, and no `msg.value`
mismatch. Swap output stays in the Treasury.

The Treasury cannot call an unapproved DEX, lend funds, grant a standing allowance, or forward
arbitrary calldata.

## 6. Automatic basket routing

Basket routing is optional and controller-controlled.

```solidity
struct BasketRoute {
    bool enabled;
    uint16 allocationBps;
    uint256 basketId;
    address[] assets;
}
```

Rules:

- basket must be registered to the same project and its NFT must be owned by the Treasury;
- allocation is 1 to 10,000 basis points;
- asset list is sorted, unique, and bounded;
- route activation emits a canonical config hash;
- disabling the route stops future reservations and releases unexecuted reservations back to
  ordinary treasury balance.

When `deposit(..., routeToBasket=true)` receives an eligible asset, it reserves the configured
share. A raw transfer can be marked later by the controller or by permissionless
`syncAndReserve` under the active policy. Anyone may call `executeBasketRoute(asset, maxAmount)`,
which funds the Basket through its standard `fund` function.

This is operationally automatic through the keeper. Passive ERC-20 transfers cannot run code, so
the contract exposes pending routeable amounts and the keeper executes them. Failure leaves the
exact reservation in the Treasury for retry; it never falls through to an unrelated recipient.

## 7. Basket NFT operations

The Treasury implements ERC-721 receiving and only accepts registered Basket NFTs. Governance may:

- transfer a Basket NFT to another nonzero address;
- call the registered Basket Manager to update the owned basket's governed configuration;
- initiate/finalize burn of an owned Basket NFT;
- pay the configured project-token burn price from Treasury balance;
- receive all unlocked basket assets net of burn tax.

These are typed operations against the registered Basket Manager. The Treasury cannot invoke an
arbitrary method on an NFT contract.

## 8. Accounting and native assets

```text
available(asset) = measuredBalance(asset) - reservedForBasket(asset)
measuredBalance(asset) >= reservedForBasket(asset)
```

There are no depositor shares or withdrawal entitlements; assets belong to the governed project
Treasury. Direct transfers are ordinary project assets after sync. Basket assets are not Treasury
balances until the Basket NFT is burned and redemption transfers them back.

## 9. Events and views

Events:

- `AssetReceived(asset, sender, amount, basketRequested)`;
- `AssetSynced(asset, surplus)`;
- `AssetSent(asset, recipient, amount)`;
- `TreasurySwap(assetIn, assetOut, amountIn, amountOut, routeHash)`;
- `BasketRouteConfigured(configHash, basketId, allocationBps)`;
- `BasketRouteReserved(asset, amount)` and `BasketRouteExecuted(asset, amount, basketId)`;
- `BasketNftReceived/Transferred/Burned(tokenId, ...)`.

Views return available/reserved balance by asset, active basket policy, pending keeper work,
registered Basket NFTs, and approved swap integrations.

## 10. Invariants

1. Basket reservations are fully backed by Treasury balances.
2. A send cannot spend reserved basket funds.
3. A failed basket funding call changes neither reservation nor available balance.
4. Swap output is measured and remains owned by the Treasury.
5. Only the immutable controller can send, swap, configure, transfer, or burn.
6. The Treasury cannot approve or transfer an unregistered NFT through its typed Basket functions.

## 11. Acceptance criteria

1. Both controller protocols can receive, send, and swap Treasury assets through the same ABI.
2. A Router deposit marked for basket routing becomes visible as pending and is deposited by a
   permissionless keeper.
3. Disabling a basket policy releases only unexecuted reservations.
4. Treasury ownership is reported by `ownerOf(primaryBasketId)` after an all-modules launch.
5. Burning the owned Basket NFT returns unlocked assets to the Treasury, not the proposal caller.
6. An unapproved swap adapter, price guard, route, or NFT contract is rejected.
7. No function permits arbitrary `(target, data)` execution.

## 12. Out of scope

- depositor shares or public withdrawals;
- generic ERC-721 portfolio management;
- loans, leverage, or unapproved protocol deposits;
- controller replacement/recovery.
