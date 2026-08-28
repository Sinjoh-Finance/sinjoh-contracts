# Chainlink Data Feeds on Robinhood Chain

Version: unversioned
Disposition: MISS-unversioned
Primary sources: https://docs.robinhood.com/chain/oracles-and-price-feeds/ and https://docs.chain.link/data-feeds/l2-sequencer-feeds

## Verified facts

- Robinhood Chain Stock Token feeds expose the standard Chainlink `AggregatorV3Interface`.
- Consumers must read the feed decimals, reject nonpositive answers, and enforce a feed-specific heartbeat/staleness threshold.
- Robinhood documents 24/5 Stock Token updates, corporate-action oracle pausing, and recommends checking L2 sequencer health plus a recovery grace period.
- Chainlink's current L2 sequencer-feed page says it is no longer expanding these feeds to additional networks and does not list Robinhood Chain.
- Robinhood's Data Streams verifier proxy is `0xcE73c8ad08CBDEaCa6078BF0627C8fe0a9a536E7`; Data Streams availability does not itself establish a sequencer-uptime feed.

## Assumptions and inferences

- Price-dependent swaps and rebalances should fail closed when a feed is stale, paused, negative, or operational chain status is uncertain.
- In-kind redemption should remain possible without an oracle because it does not establish an exchange rate.

## Risks

- **HIGH — Missing sequencer-feed address.** Robinhood recommends a check for which Chainlink does not publish a Robinhood Chain feed address, leaving a safety dependency unspecified.
- **HIGH — Stale-price misuse.** Treating the last 24/5 answer as a live weekend price can cause bad range placement, swaps, and NAV reporting.

## Unresolved

- Unresolvable from public sources: a Robinhood Chain Chainlink sequencer-uptime feed contract. Both providers' official documentation was checked; launch requires written confirmation or an explicit alternative circuit breaker.
