# System Architecture

## 1. System boundary

Contracts v2 is a collection of independent, non-upgradeable project modules connected by a
canonical registry and a common funding interface. One launch may enable all modules or any valid
subset. Factories deploy implementations; they never govern projects or custody project funds.

```text
ProjectLauncherV2
  |
  +-- ProjectVotesToken
  +-- MultisigAccount ---------\
  |                             +-> immutable project controller
  +-- Governor -> Timelock ----/
  |                                  |-> TreasuryVaultV2
  |                                  |-> RouterV2
  |                                  |-> BasketManager/BasketVault
  |                                  +-> FundingBandsV2
  +-- StakingPool + PoS NFT ----> votes and/or airdrop eligibility
  +-- AirdropV2 <--------------- Router, Basket harvests, Bands
  +-- Raffle ------------------- Router, Bands
  +-- LiquidityManager --------- Router, Bands
  +-- ProjectRegistryV2 <------- canonical addresses and immutable launch facts
```

## 2. Separation of concerns

The implementation must keep four concepts separate:

| Concern | Source of truth |
| --- | --- |
| control | immutable Multisig Account or Token Governance Timelock address |
| ownership | ERC-20 balances, PoS NFT ownership, Basket NFT ownership |
| eligibility | historical liquid or staked balance at a snapshot |
| asset flow | explicit `fund`, `send`, `swap`, `harvest`, `settle`, or `burn` operation |

Owning a Basket NFT does not create votes. Holding a PoS NFT does not grant Treasury Vault
controller power. The controller may configure a module, but it cannot rewrite historical
eligibility.

The canonical burn address `0x000000000000000000000000000000000000dEaD` is never an eligible
participant. Its balances contribute zero to Airdrop rewards, Raffle tickets, liquid or staked
votes, and the corresponding eligible-supply denominators. Protocol burns still use the project
token's burn function rather than treating a transfer to this address as a supply-reducing burn.

## 3. Shared project identity

Every module stores immutable `projectId` and `subject` values and must verify that a referenced
module belongs to the same registry record. The project ID is:

```solidity
projectId = keccak256(abi.encode(block.chainid, address(registry), subject));
```

No module accepts a caller-supplied creator, treasury, or subject after initialization. Cross-module
configuration resolves those values from its immutable project record.

## 4. Standard funding interface

Every routeable value sink implements:

```solidity
interface IProjectFundable {
    function fund(
        bytes32 projectId,
        address subject,
        address asset,
        uint256 amount,
        bytes calldata config
    ) external payable returns (uint256 received);
}
```

Rules:

1. `projectId` and `subject` must match the sink's immutable binding.
2. ERC-20 funding measures balance before and after `transferFrom` and requires `received == amount`.
3. Native funding requires `asset == address(0)` and `msg.value == amount`.
4. `config` is empty for an already-configured sink or hashes to its expected route configuration.
5. The return value is informational; the caller verifies its own balance decrease.
6. A raw ERC-20 transfer is never attributed automatically. A module may expose `sync()` only when
   its specification defines an unambiguous owner for the surplus.

## 5. Controller interface

Controlled modules store one immutable controller address directly:

```solidity
interface IProjectControlled {
    function projectId() external view returns (bytes32);
    function controller() external view returns (address);
}
```

Module authorization is `msg.sender == controller`. For Multisig Accounts, the controller is the
account itself. For Token Governance, it is the Timelock. Modules never import or call either
controller implementation, and the controller cannot be replaced.

## 6. Mutability model

The contracts are non-upgradeable. Mutability is limited to product configuration explicitly
allowed by each module:

- router route versions;
- treasury basket-routing settings;
- basket target allocations and approved adapters;
- funding-band creation before the market reaches a band's lower bound;
- pause/resume of risky execution paths.

Token identity, project creator, controller model, vote source, Treasury Vault, fee recipient,
Basket NFT redemption rules, and protocol implementations are immutable.

Configuration changes must be emitted with the previous and new configuration hashes. A caller can
read the full active configuration and its activation timestamp without reconstructing calldata.

## 7. Platform approval without a project super-admin

DEX executors, price guards, randomness adapters, yield adapters, and launchpad integrations are
external trust boundaries. Contracts v2 does not add a mutable platform operator that can change a
live project's integrations.

Each factory deployment pins a set of audited implementation/runtime hashes in its release
manifest. A project may select only from those implementations at launch. Later project-governed
changes may select another implementation only if it was included in that project's immutable
factory approval root. Supporting a new implementation requires a new factory version.

## 8. Automation

Contracts do not wake themselves up. The following operations are permissionless and intended for
keepers:

- execute ready router allocations and retry failed allocations;
- route eligible treasury balances to a basket;
- commit/push airdrop epochs through the authorized attestor workflow;
- harvest a basket when its interval has elapsed;
- arm/settle funding bands;
- commit, draw, settle, expire, or abandon raffle rounds;
- mint/increase permanent liquidity and collect fees.

Every due time, pending amount, failure reason hash, and retry state must be available through a
view and event. Lack of keeper activity delays execution but must not transfer value to an operator
or change entitlement.

## 9. Pausing

Only external-integration paths are pausable: swaps, new yield allocations, harvests, and new band
funding. Receiving assets, governance voting, unstaking after lock expiry, claiming/delivering
already-earned value, and Basket NFT redemption into recoverable assets cannot be permanently
disabled by a guardian.

The project controller controls pause/resume. A factory-level guardian is not retained.
Where a fast guardian is desired, it must be a distinct, project-selected address with pause-only
power and no transfer/configuration power.

## 10. Fee policy

Contracts v2 does not invent a new fee schedule:

- Router, Airdrop, Raffle, and Funding Bands preserve the existing cumulative 1% service fee at
  their documented accounting point.
- Liquidity preserves its existing 1% fee on collected position fees, not on principal funding.
- Treasury, governance, and staking charge no protocol fee.
- Basket charges no protocol harvest fee. Its only project-configurable fee is the optional burn
  tax described in the Basket specification.

Fee calculation carries remainders so splitting transactions cannot reduce cumulative fees. Fees
are module-local and may stack when value passes through multiple paid modules; the UI must show
the expected path before execution.

## 11. Common failure rules

1. Never use a global contract balance as one account's spendable amount.
2. Every token amount belongs to a project/account liability or is explicitly recorded surplus.
3. One failing recipient creates a retryable credit or route escrow; it does not redirect funds.
4. Caller-provided swap output minima may strengthen, never weaken, a platform guard.
5. Exact allowances are cleared after use.
6. All external value-moving entrypoints are reentrancy guarded.
7. Events are sufficient to reconstruct module state and keeper work from the deployment block.

## 12. Architecture acceptance criteria

1. Cross-project funding reverts even when the asset and module types match.
2. A factory or launcher cannot call a governed mutation after launch.
3. Pausing one integration does not pause unrelated modules or matured unstaking.
4. Every permissionless automation call is idempotent or rejects a completed state without changing
   accounting.
5. A failed external transfer preserves the exact recipient/asset liability for retry.
6. No production contract contains `delegatecall` or an unrestricted `(target, value, data)` call.
