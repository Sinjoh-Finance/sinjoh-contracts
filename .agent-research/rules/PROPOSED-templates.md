# Proposed Brainblast rule templates

## SeaDrop paid-stage callback binding

The current bundled rule templates cannot express the critical SeaDrop trap found in the
2026-09-03 research run. A future checker should detect a SeaDrop-compatible `mintSeaDrop` callback
paired with nonempty allowlists and verify that the implementation enforces a configured stage
supply boundary, stage-local wallet count, nonzero expected gross value during the callback, and an
exact expected net payout in the proceeds receiver.

Suggested checker kind: `seadrop-paid-stage-binding`
Suggested test kind: `seadrop-free-leaf-rollback`

## Pons Project graduation custody

The critical custody trap does not fit the bundled positional-argument or required-call templates.
A future checker should identify Pons Project launch construction and require the final sorted
`additionalCustodyExclusions` set to contain:

- the predicted Project adapter;
- the predicted Pons bonding curve;
- the Pons factory's `locker()` result; and
- the Pons factory's `poolManager()` result.

Its test template should reject omission or substitution of any one address and accept any
case-normalized, sorted unique representation of the exact four addresses.
