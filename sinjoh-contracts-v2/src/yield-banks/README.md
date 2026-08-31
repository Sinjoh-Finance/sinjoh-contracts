# Sinjoh Yield Banks

This directory contains the strategy-independent Sinjoh Yield Banks protocol core. Product,
contract, API, SDK, indexer, keeper, and UI naming consistently uses **Yield Banks**.

## Implemented protocol

- `YieldBankProtocolRegistry`: append-only factory, collection, and integration provenance.
- `YieldBankSystemFactoryDeployer`: governance-only CREATE3 deployment of a system factory from a reviewed factory salt.
- `YieldBankCollectionFactory`: CREATE2 deployment with pinned collection creation code.
- `YieldBankSystemFactory`: atomic, version-pinned CREATE3 deployment of eight mutually bound modules, including the account implementation, followed by CREATE2 collection deployment.
- `YieldBankCollection`: configurable immutable supply, SeaDrop mint coordination, settlement, and redemption.
- `YieldBankNFT`: OpenSea SeaDrop-compatible ERC-721 with standard Seaport approvals and EIP-2981.
- `YieldBankOnchainRenderer`: immutable data-URI metadata and SVG artwork using Yield Banks terminology.
- `YieldBankAccount`: deterministic, token-bound, eight-asset treasury clone.
- `YieldBankProceedsVault`: the collection-specific Sinjoh primary fee router and holding contract, with exact native-proceeds receipt accounting, immutable per-collection economics, no additional general-router fee, and operator-only manual allocation.
- `YieldBankDistributor`: RAY-precision per-live-token distributions without supply-sized loops.
- `CollectionRevenueRouter`: authenticated project revenue plus native/ERC-20 royalty ingress using immutable per-collection economics, retryable fee legs, and allocation-operator-only synchronization with fresh guarded route data.
- `YieldBankProjectRevenueBridge`: exact, identity-bound Project V2 `FUND_PROJECT_SINK` bridge into one collection revenue router.
- `CollectionPortfolioAllocator`: collection defaults for primary and ongoing allocation plus NFT-owner targets and operator-executed full-backing rebalances with exact route-input checks.
- `OperationsReserve` and `CollectionTimelock`: non-backing reserve sunset and fixed seven-day policy delay.
- `PriceHub` and `StrategyRegistry`: fail-closed 18-decimal pricing and adapter provenance.
- `CoreStockTokenSleeve`, `MarketMakingSleeve`, and `USDGSleeve`: capped ERC-20 share sleeves with in-kind redemption.
- `IStrategyAdapter`: a small synchronous extension boundary for separately reviewed future venues.
- `DeltaV3LPAdapter`: a codehash-bound, self-custodied `$INJOH`/WETH Delta ladder adapter with
  explicit manual entry, fee collection, partial withdrawal, full in-kind exit, and oracle-valued
  position accounting.

The core burn path settles pending assets, applies a 5% tax to each tracked asset while more than one
NFT remains, redistributes that tax using the post-burn live supply, and transfers the remainder to
the snapshotted holder. The final NFT pays no tax and receives every remaining accounted distributor
unit. It does not call an oracle, swap, lending market, or strategy adapter.
The burn proof is checked for both redemption and restricted-share receipt, and ordinary sleeve
redemption forwards its proof to the same eligibility policy instead of silently substituting an
empty proof. Standard NFT transfers remain address-state-only so Seaport can execute them.

Every configured external contract and asset is bound by address and runtime code hash. The account
salt binds the chain ID, collection address, collection ID, and token ID.
Only the configured allocation operator can enter or collect from adapters; the operator or guardian
can withdraw and exit. Calls cannot accept a loss above the immutable `maximumOperatorLossBps`
recorded for that sleeve in the release manifest.

Each current NFT owner can set a percentage target across tokenized equities, Delta `$INJOH`/WETH
LP, and USDG, including selecting a single sleeve. The owner also sets an adapter-withdrawal-loss
ceiling and an execution expiry; route swaps have separate per-transaction minimum outputs. The
request does not grant the holder direct strategy or adapter authority. The allocation operator
manually executes the exact pending revision: claim and settlement run first, every existing sleeve
position is redeemed pro rata, adapter positions are partially unwound with reviewed calldata and
loss limits, non-WETH assets use timelock-bound reverse routes, and all recovered WETH is deposited
at the owner target. Each revision is executable exactly once. An unexecuted request is bound to the
requesting owner and becomes unusable if the NFT transfers. Any later rebalance requires a new
owner-signed revision.

## Production inputs

The following production modules require the Phase-0 manifest and external review inputs described
in `.agent-research/runs/20260828-195505/final-report.md`:

- counsel-approved eligibility and transfer policy for the selected equity representation;
- the collection's reviewed tokenized-equity assets, explicit custody/income model, feeds, disclosure, and operational chain-health source; and
- the exact `$INJOH` token, `$INJOH`/WETH pool, both conversion routes, INJOH and WETH price feeds,
  per-adapter position limit and allocation cap.

The concrete Delta adapter is implemented in `adapters/DeltaV3LPAdapter.sol`. It binds the verified
Delta position builder `0x6235cF6bd8419b34942F4EDDB39C880BD96dD700`, factory
`0x1f7d7550B1b028f7571E69A784071F0205FD2EfA`, position manager
`0x73991a25C818Bf1f1128dEAaB1492D45638DE0D3`, selected pool, routes, sleeve, and PriceHub by exact
address and runtime code hash. It owns ordinary V3 position NFTs itself and rejects unsolicited
NFTs. The operator chooses ladder rungs and slippage limits per transaction; none are hard-coded.

Primary minting is hosted by OpenSea and sends native ETH through pinned SeaDrop to the collection's
proceeds vault. That vault is the Yield Bank's Sinjoh Fee Router: it releases the exact configured
creator, Sinjoh, and operations amounts in native ETH and wraps only the backing amount at manual
allocation. There is no extra one-percent general-router fee. There is no sale
success, refund, deadline, sellout release, or automatic investment transition. Missing
external integrations fail closed: no address, route, feed, venue, pool, or ABI is inferred.
SeaDrop public, token-gated, and signed stages must preserve both a positive mint price and a
positive creator payout. Nonempty SeaDrop Merkle allow lists are rejected because SeaDrop does not
expose the leaf price or fee basis points to the NFT callback; a signed paid stage must be used for
address-gated access so an unbacked free mint cannot be authorized.

The ERC-2981 secondary royalty percentage is immutable but configurable per collection and the
receiver is permanently the collection revenue router. ERC-2981 is a payment signal, not a payment
guarantee. Native and ERC-20 royalties are synchronized only by the allocation operator using fresh
minimum-output/deadline data; the underlying routes remain timelock-bound and runtime-codehash-pinned.

Do not deploy the mocks from `test/mocks/MockYieldBankIntegrations.sol`. Production configuration
must pin the Robinhood Chain WETH contract
`0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73`, the USDG contract
`0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168`, reviewed sleeve contracts, and their complete runtime
code hashes. Robinhood mainnet deployments must additionally pin SeaDrop
`0x00005EA00Ac477B1030CE78506496e8C2dE24bf5` and Seaport 1.6
`0x0000000000000068F116a894984e2DB1123eB395` with their verified runtime hashes.

## Verification

Run from `sinjoh-contracts-v2`:

```sh
forge test --match-contract YieldBankCollectionTest
forge test --match-contract YieldBankStrategyAndOracleTest
forge test --match-contract YieldBankCollectionInvariantTest
forge test --match-contract DeltaV3LPAdapterTest
forge test
forge build --sizes
```
