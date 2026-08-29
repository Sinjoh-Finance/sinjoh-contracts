# Yield Banks production activation

The deployment pipeline must reject activation until every required manifest entry satisfies
`yield-banks-manifest.schema.json` and its live runtime code hash matches.

Verified chain constants that must appear by their complete address:

- Robinhood Chain WETH: `0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73`
- USDG: `0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168`
- SeaDrop 1.0: `0x00005EA00Ac477B1030CE78506496e8C2dE24bf5`
- SeaDrop 1.0 runtime hash: `0x53e4b9339cf624803c9a7d0195576cca5b917920813508d86b3eb93dcbabeb5c`
- Seaport 1.6: `0x0000000000000068F116a894984e2DB1123eB395`
- Seaport 1.6 runtime hash: `0x95809b70c9659c30188db5fdd87103e24b1a55379af8c851fca393aba0224a00`
- Delta position builder: `0x6235cF6bd8419b34942F4EDDB39C880BD96dD700`

Still required from the operator and review process:

1. creator, Sinjoh, operations, allocation-operator, guardian, proposer, and timelock recipients;
2. the collection's selected Stock Token contracts and their eligibility classification;
3. every Chainlink/reference feed and heartbeat;
4. every approved pool, route, position manager, Delta lifecycle dependency, and ABI;
5. for Delta activation, the exact `$INJOH` token, `$INJOH`/WETH pool, entry route, position parameters,
   valuation method, and complete-exit behavior;
6. runtime hashes, source commit, dependency lock hash, deployment transaction hashes, and audit hashes;
7. immutable collection-specific `maxSupply`, per-sleeve strategy count/cap/operator-loss limits,
   and the disclosed reserve sunset; and
8. timelock authorization of the operations reserve for `YIELD_BANK_OPERATIONS_RESERVE_SWEEP`
   and each Project V2 revenue bridge for `YIELD_BANK_PROJECT_REVENUE`.

`YieldBankSystemFactoryDeployer` uses governance-only CREATE3 so the system-factory address is
fixed by the reviewed `factorySalt`, independent of factory init code. The system factory then uses
CREATE3 for the seven collection components so constructor wiring can be
planned without an init-code address cycle. The pinned deployment plan must order dependencies so
sleeves deploy before the portfolio allocator, and the portfolio allocator deploys before the
revenue router. The collection follows through CREATE2 after every component runtime hash passes.
The reserve sweep must call `sweepExpiredPrimary` with current reviewed allocation calldata; direct
ERC-20 transfers to the revenue router are reserved for EIP-2981 royalty synchronization.

The deployment input must validate against `yield-banks-deployment-plan.schema.json`. It must
contain the full encoded component init code and collection configuration—never environment-derived
addresses. Execute it with:

```sh
YIELD_BANK_DEPLOYMENT_PLAN=/absolute/path/to/reviewed-plan.json \
  forge script script/DeployYieldBanks.s.sol:DeployYieldBanks \
  --rpc-url "$YIELD_BANK_RPC_URL" --account "$FOUNDRY_ACCOUNT" --broadcast
```

After source verification and OpenSea configuration, complete every provenance and transaction
field in a manifest conforming to `yield-banks-manifest.schema.json`, then verify all runtime code,
factory/configuration commitments, supply, SeaDrop, proceeds-vault, and operator bindings:

```sh
node script/verify-yield-banks-manifest.mjs \
  /absolute/path/to/yield-banks-manifest.json "$YIELD_BANK_RPC_URL"
```

The release manifest records the factory and collection salts, full collection configuration hash,
system plan hash, collection creation-code hash, metadata base URI and contract URI with their
hashes, and per-address version, provenance, deployment transaction, verification transaction, and
runtime code hash.

Publish the manifest's exact collection overview URL to the public API as an address-keyed JSON
object in `YIELD_BANK_OPENSEA_COLLECTIONS_JSON`. The API rejects non-OpenSea hosts, non-overview
paths, queries, fragments, and invalid collection addresses. It does not invent an asset URL when
the reviewed slug is absent.

No placeholder address is valid. OpenSea Drop publishing and creator payout configuration must be
completed as an operational canary after the custom NFT is deployed. Until the list is complete,
Delta and external venue activation remain unavailable while minting, proceeds custody, manual
allocation, distributor, sleeve, SDK, indexer, API, and UI code can be
tested against reviewed mocks.

The canary must use a positive-priced public, token-gated, or signed SeaDrop stage with fee basis
points below 10,000. Use signed mint validation for address-gated access. The NFT intentionally
rejects nonempty SeaDrop Merkle allow lists because their leaf-level price and fee are not visible
to the NFT callback and therefore cannot enforce the protocol's paid-mint invariant.
