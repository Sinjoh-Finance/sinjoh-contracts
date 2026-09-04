# Research plan

1. OpenSea SeaDrop: inspect the canonical source, token-deployment guide, allowlist leaf
   definition, mint callback order, wallet-limit accounting, stage-supply checks, payout split,
   and current repository state.
2. OpenSea Drops: inspect `llms.txt`, current drop-settings documentation, presale/public-stage
   behavior, fee documentation, and the publish workflow.
3. OpenZeppelin Contracts 5.6.1: reuse the cached official-source review and re-check the locally
   installed ERC-721 extension points used by the existing contract.
4. Robinhood Chain: no new chain integration is introduced; verify the repository-pinned chain ID
   and SeaDrop address at deployment time rather than embedding either in collection logic.
