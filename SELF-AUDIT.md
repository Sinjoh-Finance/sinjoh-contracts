# Self-audit — launchpad-agnostic router and adapters

Adversarial pass over my own changes on this branch. **This is not a substitute for
an external audit**; it is the review I would want done before asking for one.

Scope: `SinjohFeeRouter`, `RouterTypes`, `SinjohFeeRouterFactory`,
`SinjohPonsV2Adapter`, `SinjohPonsV1LaunchAdapter` and both adapter factories.

## Findings fixed

### F1 — `isIntakeAsset` advertised an asset that `sync` rejects (medium)

`_bind` set `isIntakeAsset[subject] = true` unconditionally, but `sync` accepts only
assets with a configured normalization route. A launch whose fees arrive purely in a
quote asset has no subject route, so the public mapping claimed the subject was an
intake asset while `sync(subject)` reverted `UnsupportedAsset`.

Not exploitable — no value at risk — but the mapping exists precisely so off-chain
consumers can decide what to call, and a keeper reading it would have burned gas on a
guaranteed revert. A pons v2 native launch hits this on every poll.

Fixed: WETH is marked directly, and everything else is marked only by the
normalization loop, so the mapping and `sync` now share one source of truth.
Regression: `testIntakeAssetMapAgreesWithWhatSyncAccepts`.

### F2 — normalization ran with no slippage floor (medium)

`sync` called `_executeSwap(..., minAmountOut: 0)`. `_executeSwap` only rejects a
*zero* output, so any non-zero return was accepted. `processBucket` already took a
caller floor; normalization was the single unprotected leg.

This predates my changes for the subject-token case, but generalizing intake from
"the subject token" to "any quote asset" widened it materially — a 6-decimal asset
like USDG normalizing into 18-decimal WETH is exactly where a sandwich is most
profitable and a mispriced floor least obvious.

Fixed: added `sync(address asset, uint256 minAmountOut)`. `sync(address)` is retained,
delegating with a zero floor, so existing callers are unaffected and can migrate
deliberately. Regressions: `testSyncFloorRejectsAnUnderpricedNormalization`,
`testSyncFloorAcceptsAnAdequateNormalization`, `testWethSyncIgnoresTheFloor`.

**Follow-up for the keeper:** it currently calls `sync(asset)`. It should compute a
floor in the input asset's own decimals and call the two-argument form. Until it does,
the protection exists but is unused.

### F3 — v1 adapter could strand native value (low)

`launch` forwards the whole `msg.value` to `launchToken`. If v1 hands part of it back
— a first buy consuming less than was sent — that ETH lands in the adapter, which has
no native forwarding path because v1 pays fees in pool assets. It would sit there
permanently.

Fixed: any residual native balance is returned to the creator in the launch
transaction, before fees can accrue and be confused with it. Mirrors the v2 adapter's
clamp refund.

## Reviewed and accepted

**Reentrancy.** Every value-moving entrypoint on both adapters and the router is
`nonReentrant`. `bind` is not, and does not need to be: it makes no external calls —
`_resolve` reads memory and the loops touch only storage. The adapter's `launch` is
guarded and sets `launched = true` before any external call, so a malicious launchpad
cannot re-enter to launch twice.

**Balance-delta assertions.** `forward` asserts both that the adapter's balance went
to zero and that the router received exactly the stated amount. `_executeSwap` asserts
exact input spend. `_sendExact` asserts both sides. Fee-on-transfer assets therefore
revert rather than silently under-deliver, which is the documented, intended posture.

**Allowances.** The router approves a swap adapter for exactly `amountIn` and resets
to zero immediately. The v2 adapter's developer-buy pull — the one `transferFrom` in
either adapter — is creator-only, exact-amount, `launch`-only, delta-asserted, and
resets its curve allowance to zero before returning. Verified by
`test_adapterHoldsNoAllowanceOutsideLaunch`, which leaves a standing max approval and
confirms nothing is drawn when there is no developer buy.

**Access control.** `launch` is creator-only and one-shot on both adapters. Adapter
factory `deploy` is creator-only, which is what replaces the salt-level binding
guarantee that the circular dependency made impossible. `bind` accepts the creator or
the named adapter and nobody else. `bindAndSendLaunchBuy` stays creator-only — binding
is delegable, moving value to the creator is not — verified by
`testBindAndSendLaunchBuyIsCreatorOnly`.

**Immutability.** No upgrade, rescue, sweep, `delegatecall`, or self-destruct path in
any new contract. Neither adapter exposes its launchpad's fee-recipient transfer, so
the routing binding cannot be revoked from the Sinjoh side.

**Config bounds.** Normalizations are capped at 8 and buckets at 8, so every loop in
`_bind` and `initialize` is bounded. Duplicate resolved assets revert `DuplicateAsset`,
which also catches a `FIXED_ERC20` entry that happens to equal the subject.

**Pinned-dependency self-consistency.** Each adapter's constructor asks its pinned
launch factory to name its own escrow (v2) or locker (v1) and reverts on mismatch, so
a wrong pin cannot be deployed rather than being discovered when fees go missing.

## Known limitations, not defects

- **`_trySweepCurve` and `_tryCollect` use empty catch blocks.** They deliberately
  absorb the upstream "nothing accrued" reverts, and will also absorb an
  out-of-gas inside the call. The caller controls the gas it supplies, and the
  consequence is a no-op rather than a loss.
- **Everything normalizes to WETH.** A launchpad whose fee asset has no viable route
  to WETH cannot be served without a design change. This is a Sinjoh product decision,
  not launchpad coupling.
- **Native intake is unsupported.** Adapters wrap before forwarding. Deliberate: it
  keeps intake uniformly ERC-20 and every balance measured the same way.
- **v1 fee redirects are revocable upstream.** The v1 launch deployer can repoint fees
  away from the adapter. `feeRedirectIntact()` exposes this so interfaces can mark
  future fee flow inactive; Sinjoh's guarantee begins where value arrives and cannot
  extend past the launchpad's own controls.
- **The already-deployed `SinjohPonsV1Adapter` stays outside `ISinjohLaunchpadAdapter`.**
  Its instances are immutable, have no launch entrypoint, and its `collect()` returns
  nothing. It cannot be brought under the interface and is not redeployed.

## Test coverage

| Suite | Tests | What it proves |
|---|---|---|
| `sinjoh-fee-router` unit | 29 | routing, accounting, access control, normalization |
| `sinjoh-fee-router` invariant | 4 (16,384 calls) | liabilities never exceed balances; fee is exactly 1% |
| `sinjoh-launchpad-adapters` unit | 34 | v2 adapter guards, developer buy, clamp refunds, collect/forward |
| `PonsV2Mainnet.fork` | 10 | v2 adapter against live pons v2 contracts |
| `RouterIntegration.fork` | 9 | **real router + real adapter + real pons v1**, launch to payout |

The last row is the one that matters most: until it existed, every adapter test bound
a `MockRouter`, so the router and the adapters had never executed together.
