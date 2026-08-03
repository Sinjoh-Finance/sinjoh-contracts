# SinjohTreasuryVault Specification

`SinjohTreasuryVault` is an immutable treasury custody kernel controlled by exactly one
governor address. `SinjohJoint` is the Standard governor module: a 2-of-3 joint-account
(multi-signature) control system that also serves as the reusable owner primitive for other
Sinjoh protocols. Design rationale lives in [TREASURY_DESIGN.md](../TREASURY_DESIGN.md).

## Vault trust and control

- One mutable slot: `governor`. Only the governor can move assets or start a handoff.
- Governor changes are two-step and timelocked: nominate, wait `GOVERNOR_HANDOFF_DELAY`
  (frozen at deployment, never zero), then the successor accepts. The governor may cancel or
  overwrite a pending nomination at any time.
- Renunciation does not exist. Decentralization means handing the slot to a more decentralized
  module, never burning it.
- Optional dead-man recovery rail, elected irrevocably at deployment (`RECOVERY_ADDRESS` +
  `RECOVERY_INACTIVITY_PERIOD`, both zero when disabled, the recovery address may not equal the
  initial governor): after the inactivity period passes with no governor action, the recovery
  address may begin a handoff to itself through the same public delay. Any governor action —
  transfer, nomination, cancellation — restarts the inactivity clock, and a live governor
  cancels an unwanted recovery nomination like any other.
- Governance capability upgrades are governor handoffs to future modules or middleware.
  A deployed vault never migrates and is never extended in place.

## Vault asset behavior

- Anyone may send assets at any time; deposits are custody only and configure nothing.
- Native currency uses `address(0)` as its asset identifier.
- `transfer` is the only outflow: exactly one asset, one exact amount, one recipient per call.
  The recipient may be an individual address or another Sinjoh deployment, including another
  vault. ERC-20 transfers use `SafeERC20` and require the recipient's balance to increase by
  exactly the requested amount; fee-on-transfer and other under-delivering tokens revert.
- Zero amounts, insufficient balances, the zero address, and the vault itself as recipient all
  revert.
- Asset universe is native currency plus ERC-20 only. Anything else sent to the vault is
  unrecoverable; LP and other positions belong in dedicated sink protocols, never here.

## Vault excluded responsibilities

The vault performs no approvals, arbitrary calls, delegatecalls, swaps, batching, streaming,
yield, buybacks, or allocation policy. Spending policy (delays, rate caps, allowlists, pauses)
belongs in middleware holding the governor slot; capital deployment belongs in sink protocols
funded by plain transfers with return addresses hardwired to the vault.

## Joint trust and control

- Exactly three distinct signers, frozen count, execution threshold of two. Neither constant is
  configurable.
- Any signer may propose an arbitrary call (target, value, calldata); proposing confirms.
  Any second confirmation from the current signer set makes the proposal executable by any
  signer. Confirmations are counted against the signer set at execution time, so a rotated-out
  signer's stale confirmations never count.
- Proposals expire `PROPOSAL_TTL` seconds after creation (frozen at deployment, never zero).
  Expired proposals cannot be confirmed or executed. Signers may revoke confirmations while a
  proposal is live.
- Signer rotation happens only through an executed proposal targeting the Joint itself
  (`replaceSigner`), preserving three distinct signers at the 2-of-3 quorum. A compromised or
  lost key is replaced without touching owned protocols.
- Executed proposals that revert, revert the execution transaction; the proposal stays
  executable until it expires.
- With two of three keys lost the module is dead by design. Treasuries wanting an escape from
  that state elect the vault's dead-man recovery rail at deployment; the Joint deliberately has
  no lower-quorum path, because a one-signer rotation path would let a single compromised key
  capture the module.

## Standard preset

Standard = one `SinjohTreasuryVault` governed by one `SinjohJoint` (2-of-3). Reference
parameters: three-day governor handoff delay, thirty-day proposal lifetime, recovery rail
disabled unless the deployer names a recovery address at deployment.
