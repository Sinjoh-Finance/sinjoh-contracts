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

    /// All stocks use 18 decimals (verified on-chain 2026-09-05). `payoutAmount` values
    /// are raw units; a display layer must additionally apply the token's `uiMultiplier()`.
    uint8 internal constant STOCK_DECIMALS = 18;

    uint16 internal constant BPS = 10_000;

    struct Route {
        string symbol;
        address asset;
        uint24 fee;
    }

    /// @notice The routes that passed the live 0.01 WETH preflight on 2026-09-05, in the
    /// ascending asset order the raffle requires.
    function routes() internal pure returns (Route[] memory list) {
        list = new Route[](26);
        list[0] = Route("AMC", 0x05a3d1Cd21d0C88145E82600E62e7E496e0F222B, 10_000);
        list[1] = Route("RDDT", 0x05b37Fb53A299a1b874A619e1c4C404D52C36F4C, 10_000);
        list[2] = Route("SPY", 0x117cc2133c37B721F49dE2A7a74833232B3B4C0C, 500);
        list[3] = Route("GME", 0x1b0E319c6A659F002271B69dB8A7df2F911c153E, 500);
        list[4] = Route("DJT", 0x1D11f0496982706C5e14A514D4E79F2e6BdE4516, 500);
        list[5] = Route("TSLA", 0x322F0929c4625eD5bAd873c95208D54E1c003b2d, 3_000);
        list[6] = Route("BB", 0x48E39E56aCdbA37b09020C0b734A613C9a2f100A, 10_000);
        list[7] = Route("SPCX", 0x4a0E65A3EcceC6dBe60AE065F2e7bb85Fae35eEa, 500);
        list[8] = Route("COST", 0x4EA005168D7F09a7A0Ba9D1DEf21a479950E44C2, 10_000);
        list[9] = Route("TSM", 0x58FfE4a942d3885bAa22D7520691F611EF09e7AA, 3_000);
        list[10] = Route("COIN", 0x6330D8C3178a418788dF01a47479c0ce7CCF450b, 3_000);
        list[11] = Route("LLY", 0x8005d266423c7ea827372c9c864491e5786600ea, 3_000);
        list[12] = Route("BE", 0x822CC93fFD030293E9842c30BBD678F530701867, 3_000);
        list[13] = Route("SGOV", 0x92FD66527192E3e61d4DDd13322Aa222DE86F9B5, 10_000);
        list[14] = Route("INDA", 0xACEF2e09adb47aD6aBeBAD9fF06689E60615C2B6, 3_000);
        list[15] = Route("AAPL", 0xaF3D76f1834A1d425780943C99Ea8A608f8a93f9, 500);
        list[16] = Route("SNDK", 0xB90A19fF0Af67f7779afF50A882A9CfF42446400, 3_000);
        list[17] = Route("META", 0xc0D6457C16Cc70d6790Dd43521C899C87ce02f35, 3_000);
        list[18] = Route("GLD", 0xC9a981FEE1F9DEc688bb123ccDeCc63D0deBFC4e, 500);
        list[19] = Route("HIMS", 0xCceE82fE024c36fA15E1005edE3E9e4787e23D09, 3_000);
        list[20] = Route("NVDA", 0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC, 500);
        list[21] = Route("QQQ", 0xD5f3879160bc7c32ebb4dC785F8a4F505888de68, 3_000);
        list[22] = Route("CRCL", 0xdF0992E440dD0be65BD8439b609d6D4366bf1CB5, 10_000);
        list[23] = Route("MSTR", 0xec262a75e413fAfD0dF80480274532C79D42da09, 10_000);
        list[24] = Route("RBLX", 0xF0C4BF4C582cb3836e98394b1d4e7B7281101bE8, 3_000);
        list[25] = Route("MU", 0xfF080c8ce2E5feadaCa0Da81314Ae59D232d4afD, 10_000);
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
