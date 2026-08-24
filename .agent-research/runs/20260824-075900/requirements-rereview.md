# Requirements Re-review

## Missing constraints

- Every Pons Project token must finalize voting/eligibility exclusions for the predicted curve, Project adapter, live Pons locker, and live v4 PoolManager.
- Production needs a provider-backed RPC path; Robinhood's public endpoint is not a Production dependency.
- The 2.1.0 SDK, ABI, and deployment packages must be published together before a clean Preview or Production build.
- Production and canary domains must be present in Reown's project-domain configuration.

## Wrong assumptions

- GovTest did not prove post-graduation safety: its immutable exclusion set omitted `0x1006fA85294A9c38AA4214d52c86CC970Ddc5647` and `0x8366a39CC670B4001A1121B8F6A443A643e40951`.
- A Uniswap v4 pool is not a standalone pool contract address; it is PoolId-addressed state inside PoolManager.
- A locally installed SDK tarball does not make a Vercel deployment reproducible.

## Underspecified decisions

- Which provider and quota policy will serve Production browser reads and launch simulation?
- Which final multisig will own Pons Production?
- Will the hardened adapter/core release be deployed before launch, or will the first safe client payload and fresh canary precede that defense-in-depth deployment?

## Immutable choices

- Token voting exclusions finalize once.
- Adapter factories and Project release integrations bind once.
- The Project launch configuration hash and predicted module addresses change when custody exclusions change.

## Sound requirements

- The same Pons ERC-20 remains the Project subject before and after graduation.
- The wallet must receive one exact assembled payload only after prediction, validation, and simulation.
- Production must stay unchanged until the release gates clear.
