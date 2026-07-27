# SinjohRevenueCollector Specification

`SinjohRevenueCollector` is the stable recipient for Sinjoh protocol revenue. It accepts native
currency and arbitrary ERC-20s, then forwards them without an additional fee to one
governance-selected processor.

## Trust and control

- Governance is managed with OpenZeppelin `Ownable2Step`.
- Ownership renunciation is disabled so processor control cannot be permanently stranded.
- Only governance can replace `processor`.
- Anyone may call `forward` or `forwardAll`; the caller cannot choose the destination.
- The zero address and the collector itself cannot be configured as the processor.

## Asset behavior

- Native currency uses `address(0)` as its asset identifier.
- ERC-20 forwarding uses `SafeERC20` and requires the processor's balance to increase by exactly
  the requested amount.
- Fee-on-transfer and other under-delivering tokens revert.
- Zero-amount and insufficient-balance forwarding revert.

## Excluded responsibilities

The collector does not perform swaps, approvals, arbitrary calls, token burns, LP management, or
the future 40/20/20/15/5 Sinjoh revenue allocation. Those behaviors belong in a downstream revenue
processor that governance can configure later without changing upstream protocol deployments.
