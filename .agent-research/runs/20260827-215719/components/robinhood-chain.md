# Robinhood Chain

Version: unversioned
Disposition: MISS-unversioned
Primary source: https://docs.robinhood.com/chain/

## Verified facts

- Robinhood Chain is an EVM-compatible Arbitrum L2. Mainnet chain ID is 4663 and testnet chain ID is 46630. ETH is used for gas.
- The public RPC is rate limited and is not recommended for production; the official documentation recommends a production provider such as Alchemy.
- Robinhood Chain governance uses an eight-seat Security Council. Routine actions require six signatures and a seven-day timelock; emergency actions require seven signatures and no timelock.
- Official chain contracts include WETH `0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73` and USDG `0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168`.
- Robinhood brand rules prohibit using Robinhood Chain marks in NFT artwork, iconography, metadata, or contract attributes. Public copy must say “Stock Tokens,” not “tokenized stocks” or “tokenized equities.”

## Assumptions and inferences

- The collection needs at least two independent production RPC providers and event-indexer replay from a finalized checkpoint.
- Metadata and art must describe the asset system without Robinhood logos or look-alike branding.

## Risks

- **HIGH — Public infrastructure is not production-grade.** A design that depends on the public RPC for keepers, pricing, or redemptions can fail under rate limiting.
- **MEDIUM — L2 governance and validator dependency.** Emergency governance and the limited validator set are external trust assumptions for every NFT treasury.
- **MEDIUM — Brand misuse can block launch.** The original “stocks” language and any Robinhood-branded NFT art must be corrected before publication.

## Unresolved

- Unresolvable from public sources: an official Robinhood Chain sequencer-uptime feed address. The Chainlink and Robinhood oracle pages were checked.
