# Component: Delta position builder

**Date checked:** 2026-08-31
**Version:** unversioned live deployment
**Disposition:** MISS-unversioned

## Sources

- https://robinhoodchain.blockscout.com/address/0x6235cF6bd8419b34942F4EDDB39C880BD96dD700
- live JSON-RPC at https://rpc.mainnet.chain.robinhood.com
- https://github.com/Uniswap/contracts/blob/main/deployments/4663.md

## Facts

- Live calls to `0x6235cF6bd8419b34942F4EDDB39C880BD96dD700` return factory
  `0x1f7d7550B1b028f7571E69A784071F0205FD2EfA`, position manager
  `0x73991a25C818Bf1f1128dEAaB1492D45638DE0D3`, and WETH
  `0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73`.
- The same factory, position manager, and WETH appear in Uniswap's official chain-4663 deployment
  record.
- The live runtime hashes on 2026-08-31 were builder
  `0xb9b462897f26b3d9082e6db057e363ea01cee5931f39bc62d52eeaa4aa7a9039`, factory
  `0xec72b1abd1f2faee020cfea9c646bd8994f9fb389054f6e574f103a895091739`, and position manager
  `0x0a493d1af3d0f25fed8efa205244ebee14114267a08647fc38c515c7cd6ead4f`.
- The builder accepts the target pool as call data. It does not require a Sinjoh manifest record.

## Assumptions

- The product term “Delta” refers to this builder operating over the official chain-4663 Uniswap
  V3 deployment.

## Inferences

- Delta infrastructure must be approved as a versioned tuple. Pool identity can then be resolved
  from its factory without a governance action for every pool.
- Existing positions should remain bound to their original infrastructure version during an
  upgrade; replacement adapters can be introduced without mutating custody contracts in place.

## Risks

**HIGH — Unversioned builder replacement or drift.** The builder has no published semantic version.
Each approved generation must bind its address, reported dependencies, and runtime code hashes.

**MEDIUM — Incompatible future generation.** A new Delta deployment may change its interface or
position model. Governance must add a new adapter generation rather than repointing existing
immutable adapters.

## Resolved questions

**Can governance support a future Delta deployment?**

Yes. Governance can approve another infrastructure generation. Existing positions remain on the
old generation until manually exited or rebalanced.
