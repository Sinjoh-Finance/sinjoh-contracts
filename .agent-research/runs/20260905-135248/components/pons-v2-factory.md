<!-- BRAINBLAST:CACHE slug=pons-v2-factory version=0x89a27da6f703e0a7cdd4f233e7cb57604ff75b164530962d3ff7cf8483a67d84 fetched=2026-09-05 -->
# Pons V2 Factory

Status: fresh this run.

Official/live source: Robinhood Chain RPC at `https://rpc.mainnet.chain.robinhood.com`.

Facts:

- Factory: `0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e`.
- Deployment scan starts at block `26841846`.
- Runtime codehash is `0x89a27da6f703e0a7cdd4f233e7cb57604ff75b164530962d3ff7cf8483a67d84`.
- The complete approval history contains 57 events and folds to 55 active pair tokens.
- 53 active pair tokens join exactly to the canonical Robinhood stock/ETF registry. The other two
  are USDG `0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168` and cbBTC
  `0xCEC185eB182c47d1bA1EFc84e6959e18cd620Be4`.
- The newest 13-stock approval batch was transaction
  `0xb4aaf027b105aba6268762cdb68dc7fc363b8432d344ee6900536cf36f44183f` at block
  `54419544` on 2026-09-04.
- Sinjoh's launch adapters already validate the live `approvedPairTokens` flag and do not impose a
  contract allowlist. The launch UI's static candidate list is the limiting layer.

Risk:

- HIGH — a hand-maintained UI list silently hides valid launch pairs after Pons adds them.
- MEDIUM — accepting a token only by ticker or name can select a counterfeit address; the factory
  approval and canonical registry address must be the identity.

