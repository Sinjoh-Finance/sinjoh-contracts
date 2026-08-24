# Project Control Integration

## 1. Objective

Contracts v2 separates project control from every controlled protocol. A launch selects exactly one
independent controller protocol:

- a Multisig Account; or
- Token Governance, consisting of a Governor and Timelock.

Treasury Vaults, Routers, Baskets, Funding Bands, and other controlled modules contain neither
multisig nor voting logic. They store one immutable `controller` address and authorize typed
mutations with `msg.sender == controller`.

## 2. Controller resolution

| Selected protocol | User-facing account | Module controller |
| --- | --- | --- |
| Multisig Accounts | `ProjectMultisigAccountV2` | the same Multisig Account |
| Token Governance | `ProjectGovernorV2` | `ProjectTimelockV2` |

The distinction matters only at launch and in the Registry. A controlled module never calls into a
controller to ask whether a caller is authorized and never branches on the controller model.

## 3. Shared controlled-module surface

```solidity
interface IProjectControlled {
    function projectId() external view returns (bytes32);
    function controller() external view returns (address);
}
```

Rules:

1. `controller` is nonzero, has the predicted runtime code, and is immutable after construction.
2. A controlled function performs a direct caller comparison; it does not perform an external
   authorization callback.
3. The launcher, factories, creator, and Registry receive no implicit controller power.
4. Replacing Multisig Accounts with Token Governance, or the reverse, requires a new project
   deployment in this first release.
5. The controller may call only explicit functions exposed by a module. Controlled custody modules
   do not expose generic arbitrary-call entrypoints.

## 4. Registry discovery

The Registry records the selected model and explicit addresses:

- `controller`;
- `multisigAccount`, nonzero only for Multisig Accounts;
- `tokenGovernor`, `tokenTimelock`, and `voteSource`, nonzero only for Token Governance.

This lets the UI render the correct workflow from one record without probing bytecode or decoding a
generic authority adapter.

## 5. Governed capabilities

Either controller protocol may use the same typed module ABI:

| Module | Controlled operations |
| --- | --- |
| Treasury Vault | send assets, guarded swap, basket-routing policy, owned Basket NFT operations |
| Router | activate a complete route version, pause/resume, recover failed route escrow |
| Basket | approved asset/weight, adapter, cadence, and pause configuration |
| Funding Bands | create/fund an eligible band and cancel a pending unfunded band |
| Registry | publish allowed operational metadata and canonical-pool metadata |

Control cannot mint project tokens, rewrite historical votes, seize PoS positions, redirect an
existing Airdrop entitlement, replace a committed Raffle root, or withdraw permanent liquidity.

## 6. Guardian separation

An optional project guardian is a separate pause-only address. It cannot act as the controller,
resume a paused path, transfer value, change configuration, cancel votes, or block matured
unstaking and already-earned distributions. The immutable controller resumes paused paths.

## 7. Acceptance criteria

1. A Treasury Vault deployed with a Multisig Account and one deployed with a Token Governance
   Timelock expose the same asset-operation ABI.
2. No Treasury Vault, Router, Basket, or Funding Bands contract imports either controller
   implementation.
3. Direct calls from the Governor, token holders, multisig signers, creator, or launcher fail when
   the caller is not the module's exact controller.
4. Changing signers or voting participation does not change any controlled module address or
   storage.
5. The Registry exposes all controller addresses without implementation probing.

## 8. Out of scope

- changing controller model after launch;
- controller adapters or delegation layers;
- a platform recovery administrator;
- module-specific duplicates of multisig or token-voting logic.
