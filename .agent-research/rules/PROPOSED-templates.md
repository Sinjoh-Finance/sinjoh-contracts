# Proposed Brainblast checker template

## SeaDrop callback stage ambiguity

Detect contracts implementing `mintSeaDrop(address,uint256)` with a staged policy, then require
either mutually exclusive time windows or an authenticated single-use stage context. Also flag
simultaneously enabled public, token-gated, signed, and allowlist routes because SeaDrop's callback
does not identify the route or selected parameters. No existing Brainblast checker/test template
models Solidity callback context or reads deployed SeaDrop configuration, so no executable local
rule was authored.
