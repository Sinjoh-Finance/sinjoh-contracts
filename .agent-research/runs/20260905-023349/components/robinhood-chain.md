# Component: Robinhood Chain

**Date checked:** 2026-09-05  
**Version:** 4663  
**Disposition:** MISS-new

**Sources:**

- Network configuration: https://docs.robinhood.com/chain/connecting/
- Network overview: https://docs.robinhood.com/chain/

## Facts

- Robinhood documents mainnet chain ID `4663`, ETH as the native gas token, and https://robinhoodchain.blockscout.com as the explorer. Source: https://docs.robinhood.com/chain/connecting/
- Robinhood labels its public RPC rate-limited and not recommended for production, and lists authenticated providers for production use. Source: https://docs.robinhood.com/chain/connecting/
- Robinhood Chain is an EVM-compatible Arbitrum Layer 2. Source: https://docs.robinhood.com/chain/

## Assumptions

- The protected authenticated archive RPC used by CI continues to serve historical and latest state for chain `4663`.

## Inferences

- Production certification must use an authenticated archive endpoint and must verify the returned chain ID before tests begin.

## Risks

**MEDIUM — A missing RPC environment alias can prevent registered canaries from running**

Different fork tests consume `ROBINHOOD_RPC_URL`, `ROBINHOOD_MAINNET_RPC_URL`, `RH_RPC_URL`, or `SINJOH_RPC_PRIMARY`. The runner must expose the same already-validated protected URL under every registered alias or the suite stops before raffle coverage.

## Resolved Questions

**Is chain `4663` the intended production network?**

Yes. Robinhood's network documentation identifies `4663` as Robinhood Chain mainnet.
