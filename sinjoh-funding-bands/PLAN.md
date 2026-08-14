# SinjohFundingBands implementation plan

## Architecture

- `SinjohFundingBands.sol` is the immutable custody, lifecycle, accounting, and
  v3/v4 execution contract. It has no owner, upgrade path, rescue path, or
  arbitrary-call surface.
- Launch profiles are frozen in the constructor. Each profile supplies an
  immutable launch verifier, manipulation-resistant price guard, and bounded
  v4 hook payload; the core never trusts caller-selected pools, ticks, hooks,
  hook data, or recipients.
- `FundingBandMath.sol` converts USD market caps and the snapshotted ETH/USD
  answer into token/WETH prices, then into correctly oriented usable ticks.
- `FundingBandV4.sol` performs v4 position actions as a linked library, keeping
  the immutable custody contract comfortably below EIP-170's runtime limit.
- Canonical v3 and v4 PositionManagers are the only NFT senders accepted. The
  manager mints one position per band, increases only that position, and closes
  it only after the profile guard validates the upper crossing.
- WETH and subject proceeds use pull delivery. Aggregate liabilities are
  updated before external transfers and checked against liquid balances.

## Build order

1. Add Foundry package configuration and immutable interface boundaries.
2. Implement market-cap math, registration, funding, v3/v4 position execution,
   settlement, cumulative 1% fee accounting, and permissionless delivery.
3. Add mock verifiers, guards, oracle, WETH, v3/v4 infrastructure, and unit/fuzz
   tests for lifecycle, authorization, price orientation, accounting, and
   failure isolation.
4. Add deployment configuration script and operator-facing README.
5. Run formatting, compile, tests, and diff review; record any launch profile
   that remains unavailable until an exact Robinhood mainnet fork fixture is
   verified.

## Activation gate

The Pons v2 verifier, signed-reference guard, and signed ETH/USD adapter now pass
both the local lifecycle suite and a disposable Robinhood mainnet fork against the
current deployed factory, hook, buyback adapter, PositionManager, StateView,
PoolManager, Permit2, and WETH. Pons v2 is mechanically compatible after
graduation, but production activation still requires the offchain reference-price
and ETH/USD publication service, signer custody/rotation procedures, an exact-input
deployment rehearsal, and independent audit signoff.

Pons v1 still requires a Robinhood fork fixture and exact-bytecode signoff.
pools.trade and letscash.fun require launch verifiers, hook-specific guards, and
their own live fork suites. A profile omitted from the constructor is unsupported
by construction.
