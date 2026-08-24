# Component: viem

**Date checked:** 2026-08-24
**Sources:**
- Documentation index: https://viem.sh/llms.txt
- `encodeFunctionData`: https://viem.sh/docs/contract/encodeFunctionData
- `simulateContract`: https://viem.sh/docs/contract/simulateContract

## Facts

- The official docs identify the inspected release as 2.55.19.
- `encodeFunctionData` returns the four-byte selector and ABI-encoded arguments, with TypeScript argument types inferred from the ABI.
- `simulateContract` validates a write through a public-client call, returns revert information, consumes no gas, and does not change chain state.
- The docs recommend pairing a successful simulation request with the wallet write.

## Assumptions

- The ABI supplied by `@sinjoh/abis` is generated from the same reviewed Solidity source as the deployed target.

## Inferences

- ABI encoding alone does not protect the target address or native value; the application must compare `to`, `data`, and `value` immediately before signing.
- A simulation cannot replace a wallet-signed canary because it makes no persistent state transition.

## Risks

**MEDIUM — Simulation can be mistaken for launch proof**

A successful `eth_call` proves the current payload would execute against current state, but it neither proves wallet UX nor persists the launch. Exact payload verification and a real wallet-signed canary remain separate gates.

## Resolved questions

**Does simulation mutate the chain?**

No. The official 2.55.19 docs explicitly say it does not change blockchain state.
