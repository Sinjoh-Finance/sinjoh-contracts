# Component: Flap Portal

**Date checked:** 2026-09-05  
**Version:** v5.21.2  
**Disposition:** MISS-changed

**Sources:**

- Documentation index: https://docs.flap.sh/llms.txt
- Robinhood integration guide: https://docs.flap.sh/flap/developers/token-launcher-developers/robinhood-integration-guide.md
- Portal launch interface: https://docs.flap.sh/flap/developers/token-launcher-developers/launch-token-through-portal.md
- Live Portal: https://robinhoodchain.blockscout.com/address/0x26605f322f7fF986f381bB9A6e3f5DAb0bEaEb09

## Facts

- Flap identifies `0x26605f322f7fF986f381bB9A6e3f5DAb0bEaEb09` as the Robinhood Chain Portal and `0x7777C8743C88B3aff3cf262135beF2c8b2e83333` as the Tax Token V3 implementation. The guide says Tax Token V3 launches use `newTokenV6`, `TOKEN_TAXED_V3`, `V2_MIGRATOR`, native ETH, and the `FOUR_FIFTHS` threshold. Source: https://docs.flap.sh/flap/developers/token-launcher-developers/robinhood-integration-guide.md
- Flap recommends `TOKEN_TAXED_V3` for new tax-token integrations and documents the `NewTokenV6Params` ABI used by Sinjoh. Source: https://docs.flap.sh/flap/developers/token-launcher-developers/launch-token-through-portal.md
- A live `version()` call on 2026-09-05 returned `v5.21.2`; the same call at the reviewed historical snapshot returned `v5.15.2`. The live contract is visible at https://robinhoodchain.blockscout.com/address/0x26605f322f7fF986f381bB9A6e3f5DAb0bEaEb09
- Live and historical `getQuoteTokenConfiguration(address(0))` calls both returned `(1, 25, 25, 0, 0)`, and the Portal proxy runtime code hash remained `0xcecb292d9c022858199c9348abf0d5836f9ea4dab5cf03710e1dcf41fd9a4c35`. The Flap guide explicitly tells integrators to confirm this live configuration. Source: https://docs.flap.sh/flap/developers/token-launcher-developers/robinhood-integration-guide.md
- Sinjoh's resulting live commitment is `0xd11206f76d4086d0aab6f96707b25806347b07d7ef45197bf15699765ef975d3`; the prior commitment was `0xb789978b5db7d4d20b60a96ac19d9b9f4a667f2182a2d833a3dfb02459fbb713`.

## Assumptions

- The upstream version bump is intended and compatible only after a full forked launch, revenue-routing, binding, and payout proof succeeds.

## Inferences

- Because the proxy runtime and native-quote configuration are unchanged while `version()` changed, the commitment drift is caused by the reported Portal version, not by an RPC returning corrupted configuration.
- Keeping an old fixed commitment in the UI and launch scripts causes a visible, fail-closed launch rejection. Replacing it without a full lifecycle test would risk accepting an incompatible upstream release.

## Risks

**CRITICAL — Mutable upstream version can stop every Flap launch**

The Portal is upgradeable and its reported version participates in Sinjoh's launch commitment. A legitimate upstream upgrade makes the old commitment reject every launch. The correct response is to verify the exact live configuration and full lifecycle, then update all production pins together; the guard must not be removed or made dynamic at signing time.

**LOW — Public version documentation can lag live state**

The live version is authoritative onchain. Static documentation and source comments can remain on an older version and must not be used alone for production approval.

## Resolved Questions

**Did the native-quote route or Portal proxy bytecode change?**

No. Live calls returned the same native-quote tuple and runtime code hash as the reviewed snapshot.

**Should Sinjoh stop checking the Portal commitment?**

No. The check prevented an unreviewed upstream version from being used. The fix is a synchronized reviewed pin plus a full production-fork proof.
