# Proposed Brainblast Checker Templates

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
