<!-- BRAINBLAST:CACHE slug=viem version=2.55.19-ui-2.55.10-sdk fetched=2026-08-24 -->
# Viem

Version: UI 2.55.19 / SDK 2.55.10
Disposition: HIT — reused from cache fetched 2026-08-24
Sources: https://viem.sh/docs/contract/simulateContract,
https://viem.sh/docs/contract/writeContract,
https://viem.sh/docs/actions/public/waitForTransactionReceipt

Facts: `writeContract` only broadcasts; Viem recommends simulation first. Receipt handling must check
status and account for replacement. ABI tuple types are inferred from the supplied ABI.

Risks:
- **HIGH — Unsimulated or incorrectly ordered tuple calldata can revert or execute unintended values.**
  Yield Banks simulates using the connected account, writes the returned request, then checks receipt.
- **MEDIUM — Hash-only success reporting can hide a revert/replacement.** UI and keeper reconcile the
  canonical receipt before reporting completion.

No unresolved question.
