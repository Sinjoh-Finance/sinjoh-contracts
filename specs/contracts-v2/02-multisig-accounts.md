# Multisig Accounts

## 1. Objective

`ProjectMultisigAccountV2` is an independent project smart account controlled by exactly three
signers. Any two current signers may approve a transaction, after which anyone may execute it before
expiry. The account may control a Treasury Vault, Router, Basket, Funding Bands, or another typed
project module through the module's immutable `controller` address.

The Multisig Account is not a Treasury Vault. It may receive native currency for transaction gas
and call value, but project assets are intended to remain in the controlled Treasury Vault.

## 2. Immutable project binding

The account stores immutable Registry, project ID, and subject token bindings. Its `controller()`
view returns its own address. It does not depend on a Treasury Vault and remains valid when the
project launches without one.

## 3. Signer model

First-release rules:

- exactly three unique nonzero signer addresses;
- approval threshold fixed at two current signers;
- signer order is canonical and discoverable;
- one address contributes at most one confirmation;
- transaction lifetime fixed at seven days from submission;
- confirmations may be revoked before execution;
- signer replacement requires a threshold-approved call from the account to itself.

When a signer is replaced, that address's confirmations stop counting immediately. Confirmation
counts are derived from the three current signers, so a removed signer cannot help execute an old
pending transaction. The replacement signer may confirm an existing unexpired transaction.

## 4. Transaction lifecycle

```text
SUBMITTED -> READY -> EXECUTED
     |          |
     +----------+-> EXPIRED
```

The submitting signer automatically records the first confirmation. A transaction contains one to
ten ordered actions with equal-length `targets`, `values`, and `calldatas` arrays. Its ID commits to
the chain ID, account, sequential nonce, and complete batch.

Rules:

1. only a current signer may submit, confirm, or revoke;
2. targets are nonzero and aggregate calldata is bounded;
3. execution requires two current-signer confirmations and `block.timestamp <= expiresAt`;
4. execution is permissionless once ready;
5. batch execution is atomic and preserves action order;
6. a failed action reverts the full execution and leaves the transaction retryable until expiry;
7. the executed flag is set exactly once and duplicate execution reverts;
8. no off-chain signature format is required in the first release.

## 5. Signer replacement

```solidity
function replaceSigner(address oldSigner, address newSigner) external onlySelf;
```

The old signer must be current. The new signer must be nonzero, unique, and not the canonical burn
address. The call can succeed only as an action inside a normal two-confirmation transaction. The
account cannot change its threshold, add a fourth signer, or replace all signers in one hidden
configuration operation.

## 6. Execution boundary

The Multisig Account is a general controller account, so an approved transaction commits to target,
native value, and calldata. This execution surface is restricted by the two-of-three approval
lifecycle; no EOA can invoke it directly. Controlled custody modules remain typed and expose no
generic executor.

The account implements ERC-721 receiving so it can hold a Basket or PoS NFT if deliberately sent,
but receiving an NFT grants no special project power beyond ordinary ownership.

## 7. Events and views

Events:

- `MultisigAccountCreated(projectId, account, signer0, signer1, signer2)`;
- `TransactionSubmitted(transactionId, nonce, submitter, expiresAt, actionsHash)`;
- `TransactionConfirmed(transactionId, signer)`;
- `ConfirmationRevoked(transactionId, signer)`;
- `TransactionExecuted(transactionId, executor)`;
- `SignerReplaced(oldSigner, newSigner)`.

Views return current signers, threshold, transaction metadata, action hashes/full actions,
confirmation status, current confirmation count, readiness, expiry, and execution status.

## 8. Security invariants

1. Fewer than two current signers can never execute a transaction.
2. Duplicate confirmation by one signer never increases the count.
3. A removed signer contributes zero to every pending transaction.
4. A failed batch changes no external or internal action state.
5. A transaction can execute at most once.
6. No launcher, factory, creator, or Registry role can submit or confirm unless it is explicitly a
   current signer.

## 9. Acceptance criteria

1. Submission by signer A plus confirmation by signer B makes the transaction ready.
2. One confirmation, duplicate confirmation, or a non-signer confirmation cannot execute.
3. A confirmation may be revoked before execution and readiness updates immediately.
4. An expired transaction cannot execute.
5. A reverting second action rolls back a successful first action and leaves the batch retryable.
6. A two-confirmation self-call replaces one signer without changing project control addresses.
7. The account can operate every typed controlled module without Treasury-specific logic.

## 10. Out of scope

- configurable signer count or threshold;
- signature aggregation, EIP-4337, session keys, or social recovery;
- delegation or weighted signers;
- arbitrary platform/operator override;
- treating the Multisig Account as the project Treasury Vault.
