# Component: @letscashfun/sdk

**Date checked:** 2026-09-05  
**Version:** 0.5.0  
**Disposition:** MISS-changed

**Sources:**

- Registry metadata: https://registry.npmjs.org/@letscashfun%2Fsdk/0.5.0
- Official repository: https://github.com/letscashfun/sdk/blob/main/README.md
- Live factory: https://robinhoodchain.blockscout.com/address/0x5bd1Fbe78a78fe8236fa00CF48fbEBA74ae34661

## Facts

- Version `0.5.0` requires Node 20+, has no runtime dependencies, peers on viem `^2.21.0`, publishes provenance attestations, and runs no install script. Source: https://registry.npmjs.org/@letscashfun%2Fsdk/0.5.0
- The official SDK states that a custom-supply factory upgrade added `supply` to `TokenParams`, moving the selectors for `launchWithFeeSplit`, `mineSalt`, and every other tuple-taking launch function while the factory proxy address stayed fixed. Source: https://github.com/letscashfun/sdk/blob/main/README.md
- The SDK documents that bounded `mineSalt` windows can be exhausted and must be retried. Source: https://github.com/letscashfun/sdk/blob/main/README.md
- The stable proxy is `0x5bd1Fbe78a78fe8236fa00CF48fbEBA74ae34661`. Its live EIP-1967 implementation is `0x40250b4C73FC30f8F6ad077744B0124B3f111C28`, with runtime hash `0xc420573f11b2c4fab419118e0e6fc167cc3902c62a3e41fd4495c5db0ea30532`.
- Omitting a custom supply is encoded as `supply = 0`, which selects the reviewed config row's existing immutable supply. Source: https://github.com/letscashfun/sdk/blob/main/README.md

## Assumptions

- Sinjoh should preserve its staged transaction checkpointing and server-side route authorization instead of delegating the complete write lifecycle to the SDK client.

## Inferences

- SDK `0.2.1` and Sinjoh's hand-transcribed old tuple both call selectors absent from the upgraded implementation, so every letscash.fun launch reverts before token creation.
- Updating the dependency, tuple ABI, implementation pin, server verifier, bounded-search retry, and lifecycle canary together restores the current dialect without weakening route authorization.

## Risks

**CRITICAL — Proxy upgrade silently changes all launch selectors**

The factory address and proxy runtime remain unchanged while the implementation tuple gains a field. An integration that verifies only the proxy still looks healthy but every salt and launch call reverts. The active implementation address/codehash and ABI dialect must be pinned and exercised by a full launch canary.

**HIGH — A normal salt-search miss can abort a launch**

Vanity salt search is probabilistic and a bounded window can exhaust. The UI must continue with a new window only for a decoded contract revert and must still surface RPC or transport errors.

## Resolved Questions

**Does standard supply change after adding the new tuple field?**

No. Passing `supply = 0` selects the immutable supply in the chosen launch config.

**Can the old ABI remain because the proxy address did not change?**

No. The tuple change creates different selectors, and the current implementation does not expose the old selector set.
