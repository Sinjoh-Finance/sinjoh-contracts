<!-- BRAINBLAST:CACHE slug=envio-hyperindex version=3.2.1 fetched=2026-08-24 -->
# Envio HyperIndex

Version: 3.2.1
Disposition: HIT — reused from cache fetched 2026-08-24
Sources: https://docs.envio.dev/llms.txt,
https://docs.envio.dev/docs/HyperIndex/configuration-file.md,
https://docs.envio.dev/docs/HyperIndex/event-handlers.md

Facts: only configured event signatures are indexed; configuration/schema changes require codegen;
address and start block determine historical coverage; hosted deployments reindex from the start.

Risks:
- **HIGH — A missing or wrong event declaration silently omits state.** Yield Banks config and handler
  tests bind allocation, withdrawal, transfer, and strategy events.
- **HIGH — Wrong address/start block yields incomplete history.** Activation requires canonical
  deployment receipts before hosted rollout.
- **MEDIUM — v3.2.1 lacks documented v3.3 custom RPC headers.** Provider configuration must remain
  within supported v3.2.1 mechanisms or be upgraded separately.

No unresolved question.
