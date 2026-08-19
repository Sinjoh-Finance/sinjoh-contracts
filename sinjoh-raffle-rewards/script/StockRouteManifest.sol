// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

/// @notice The production mystery-stock route set, as compiled constants.
///
/// @dev This is the source of truth for `ROBINHOOD_STOCKS.md`, not a copy of it. The route table
/// used to live only in prose, where a fee tier could drift from the guard that prices it and
/// nothing would notice until an immutable raffle was already deployed. Changing a route is now a
/// reviewed code change that `PreflightStockRoutes` re-checks against live chain state.
///
/// Every address here is pinned. Guard addresses are deliberately absent: the production
/// five-minute guards do not exist yet, so the preflight takes them from the environment and
/// verifies their parameters rather than trusting an address.
library StockRouteManifest {
    uint256 internal constant ROBINHOOD_MAINNET_CHAIN_ID = 4_663;

    address internal constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    address internal constant V3_FACTORY = 0x1f7d7550B1b028f7571E69A784071F0205FD2EfA;

    /// @dev The reviewed mainnet deployment. Its superseded v1-router deployment must not be used.
    address internal constant SWAP_ADAPTER = 0xc9F600ebaf9EE1F4a24568D2e4Af9E8df1e07D7B;
    bytes32 internal constant SWAP_ADAPTER_CODEHASH =
        0x17b8eecc60ff9af5768240b0384e96c4e54fd8611355297e45146303294c6ac6;

    /// Required immutable guard configuration. A guard that differs on any of these prices a
    /// different risk than the one that was reviewed.
    uint32 internal constant REQUIRED_TWAP_WINDOW = 300;
    uint16 internal constant REQUIRED_MAX_SPOT_DEVIATION_BPS = 1_000;
    uint16 internal constant REQUIRED_MAX_OUTPUT_SLIPPAGE_BPS = 750;
    uint48 internal constant REQUIRED_VALIDITY_PERIOD = 300;
    uint128 internal constant REQUIRED_COMPARISON_AMOUNT = 1 ether;

    /// @dev The guard rejects any pool below this, so a pool at cardinality 1 can never quote no
    /// matter how much history it appears to hold.
    uint16 internal constant MIN_OBSERVATION_CARDINALITY = 2;

    /// Every approved tokenized stock is the same `BeaconProxy` (identical runtime bytecode)
    /// pointing at one shared beacon, whose implementation Robinhood can upgrade at any time.
    /// Pinning the proxy's codehash is therefore meaningless; the reviewed IMPLEMENTATION is
    /// what behavior was verified against: standard raw-balance ERC-20 transfers (splits move a
    /// separate UI multiplier, never balances), a discretionary role-set pause, no transfer fee.
    /// The preflight fails when the beacon points anywhere else, so an upstream upgrade forces a
    /// re-review instead of silently changing what an immutable raffle delivers.
    address internal constant STOCK_BEACON = 0xe10b6f6B275de231345c20D14Ab812db62151b00;
    address internal constant REVIEWED_STOCK_IMPLEMENTATION =
        0xb35490d6f9163DE4F80d88dc75c3516eb64C5aE2;
    bytes32 internal constant REVIEWED_STOCK_IMPLEMENTATION_CODEHASH =
        0xdc07e86ee482f99641bdafb9a0d772846b167401e094d90a666b94dbdcd1eec7;
    /// EIP-1967 beacon slot: keccak256("eip1967.proxy.beacon") - 1.
    bytes32 internal constant EIP1967_BEACON_SLOT =
        0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    /// All eight stocks use 18 decimals (verified on-chain 2026-08-04). `payoutAmount` values
    /// are raw units; a display layer must additionally apply the token's `uiMultiplier()`.
    uint8 internal constant STOCK_DECIMALS = 18;

    uint16 internal constant BPS = 10_000;

    struct Route {
        string symbol;
        address asset;
        uint24 fee;
    }

    /// @notice The eight approved routes, in the ascending asset order the raffle requires.
    function routes() internal pure returns (Route[] memory list) {
        list = new Route[](8);
        list[0] = Route("RDDT", 0x05b37Fb53A299a1b874A619e1c4C404D52C36F4C, 10_000);
        list[1] = Route("GME", 0x1b0E319c6A659F002271B69dB8A7df2F911c153E, 500);
        list[2] = Route("GOOGL", 0x2e0847E8910a9732eB3fb1bb4b70a580ADAD4FE3, 500);
        list[3] = Route("TSLA", 0x322F0929c4625eD5bAd873c95208D54E1c003b2d, 3_000);
        list[4] = Route("COIN", 0x6330D8C3178a418788dF01a47479c0ce7CCF450b, 3_000);
        list[5] = Route("AAPL", 0xaF3D76f1834A1d425780943C99Ea8A608f8a93f9, 500);
        list[6] = Route("NVDA", 0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC, 3_000);
        list[7] = Route("MSTR", 0xec262a75e413fAfD0dF80480274532C79D42da09, 10_000);
    }

    /// @notice `routeData` for the swap adapter. It decodes exactly one `uint24` fee, and that fee
    /// selects the pool the swap executes in — which must be the pool the guard prices.
    function routeData(uint24 fee) internal pure returns (bytes memory) {
        return abi.encode(fee);
    }

    /// @notice The largest net a single slot can ever send through one swap.
    /// @dev Slot 0 carries the division remainder, so it is the largest share. Both tax shares are
    /// floored independently, matching `SinjohRaffleRewards._settleSlot`.
    function maxSlotNet(
        uint256 maxPrize,
        uint8 winnersPerRound,
        uint16 recipientTaxBps,
        uint16 recycleTaxBps
    ) internal pure returns (uint256) {
        uint256 share =
            maxPrize / winnersPerRound + maxPrize % winnersPerRound;
        return share - (share * recipientTaxBps) / BPS - (share * recycleTaxBps) / BPS;
    }
}
