// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { SinjohSharedV3TwapPriceGuard } from "../src/SinjohSharedV3TwapPriceGuard.sol";

interface VmRafflePriceGuardsMainnet {
    function envOr(string calldata name, uint256 defaultValue) external returns (uint256);
    function startBroadcast() external;
    function stopBroadcast() external;
    function readCallers() external returns (uint8 callerMode, address msgSender, address txOrigin);
}

interface IWrappedEtherMainnet {
    function deposit() external payable;
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IRaffleSwapAdapter {
    function swap(
        address assetIn,
        address assetOut,
        uint256 amountIn,
        uint256 minAmountOut,
        bytes calldata routeData
    ) external payable;
}

interface IV3PoolMainnet {
    function slot0() external view returns (uint160, int24, uint16, uint16, uint16, uint8, bool);
}

/// @notice One-command remediation for the mystery-stock routes on Robinhood Chain mainnet:
/// deploys the three immutable five-minute guards, primes every route pool below the target
/// observation capacity, and writes one seed observation into each pool that was deficient.
///
/// @dev After this broadcasts, wait five minutes (the TWAP window must fill with real time), then
/// verify with the raffle package's preflight — that gate, not this script, decides readiness:
///
/// ```sh
/// cd ../sinjoh-raffle-rewards
/// RAFFLE_GUARD_500=<low> RAFFLE_GUARD_3000=<medium> RAFFLE_GUARD_10000=<high> MAX_PRIZE=<wei> \
///   forge script script/PreflightStockRoutes.s.sol:PreflightStockRoutes \
///   --rpc-url https://rpc.mainnet.chain.robinhood.com
/// ```
///
/// Chain-locked to mainnet, deployer-locked, and factory-hash-locked, like its testnet sibling.
/// Priming is permissionless and monotonic; re-running never shrinks a pool's buffer. Seed swaps
/// spend `SEED_SWAP_WEI` (default 0.0005 ether) of the deployer's ETH per deficient pool.
contract DeployRafflePriceGuardsMainnet {
    uint256 internal constant ROBINHOOD_MAINNET_CHAIN_ID = 4_663;
    address internal constant EXPECTED_DEPLOYER = 0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49;

    address internal constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    address internal constant V3_FACTORY = 0x1f7d7550B1b028f7571E69A784071F0205FD2EfA;
    bytes32 internal constant V3_FACTORY_HASH =
        0xec72b1abd1f2faee020cfea9c646bd8994f9fb389054f6e574f103a895091739;
    address internal constant SWAP_ADAPTER = 0xc9F600ebaf9EE1F4a24568D2e4Af9E8df1e07D7B;

    uint24 internal constant LOW_FEE = 500;
    uint24 internal constant MEDIUM_FEE = 3_000;
    uint24 internal constant HIGH_FEE = 10_000;
    uint32 internal constant TWAP_WINDOW = 5 minutes;
    uint16 internal constant MAX_SPOT_DEVIATION_BPS = 1_000;
    uint16 internal constant MAX_OUTPUT_SLIPPAGE_BPS = 750;
    uint48 internal constant VALIDITY_PERIOD = 5 minutes;
    uint128 internal constant COMPARISON_AMOUNT = 1 ether;

    /// @dev Matches the capacity the already-primed route pools carry. Overridable with
    /// `RAFFLE_POOL_CARDINALITY`; Uniswap ignores targets at or below a pool's current one.
    uint16 internal constant DEFAULT_CARDINALITY = 1_500;
    uint256 internal constant DEFAULT_SEED_SWAP_WEI = 0.0005 ether;
    /// @dev The guard's own MIN_OBSERVATION_CARDINALITY: the threshold a seeded pool must clear.
    uint16 internal constant MIN_SEEDED_CARDINALITY = 2;
    /// @dev Doubling from the base size, the final attempt is 32x. A pool so deep that 32x moves
    /// no tick does not have a stale-oracle problem worth seeding.
    uint256 internal constant MAX_SEED_ATTEMPTS = 6;

    VmRafflePriceGuardsMainnet internal constant vm =
        VmRafflePriceGuardsMainnet(address(uint160(uint256(keccak256("hevm cheat code")))));

    error WrongChain(uint256 actual);
    error WrongDeployer(address actual);
    error DependencyHashMismatch(address dependency, bytes32 expected, bytes32 actual);
    error DeploymentFailed(uint24 fee);
    error PrimingFailed(address pool, uint16 target);
    error SeedingFailed(address pool);

    /// @dev The production route set. `sinjoh-raffle-rewards/script/StockRouteManifest.sol` is the
    /// source of truth; the preflight run after this script catches any drift between the two.
    struct RoutePool {
        address asset;
        uint24 fee;
    }

    function routePools() public pure returns (RoutePool[] memory list) {
        list = new RoutePool[](8);
        list[0] = RoutePool(0x05b37Fb53A299a1b874A619e1c4C404D52C36F4C, HIGH_FEE); // RDDT
        list[1] = RoutePool(0x1b0E319c6A659F002271B69dB8A7df2F911c153E, LOW_FEE); // GME
        list[2] = RoutePool(0x2e0847E8910a9732eB3fb1bb4b70a580ADAD4FE3, LOW_FEE); // GOOGL
        list[3] = RoutePool(0x322F0929c4625eD5bAd873c95208D54E1c003b2d, MEDIUM_FEE); // TSLA
        list[4] = RoutePool(0x6330D8C3178a418788dF01a47479c0ce7CCF450b, MEDIUM_FEE); // COIN
        list[5] = RoutePool(0xaF3D76f1834A1d425780943C99Ea8A608f8a93f9, LOW_FEE); // AAPL
        list[6] = RoutePool(0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC, MEDIUM_FEE); // NVDA
        list[7] = RoutePool(0xec262a75e413fAfD0dF80480274532C79D42da09, HIGH_FEE); // MSTR
    }

    function run()
        external
        returns (
            SinjohSharedV3TwapPriceGuard lowFeeGuard,
            SinjohSharedV3TwapPriceGuard mediumFeeGuard,
            SinjohSharedV3TwapPriceGuard highFeeGuard
        )
    {
        // Signing comes from forge's own --account/--ledger machinery; the key never enters an
        // environment variable. The identity assertion still holds: a wrong keystore account
        // reverts here before any transaction is sent.
        vm.startBroadcast();
        (, address deployer,) = vm.readCallers();
        if (deployer != EXPECTED_DEPLOYER) revert WrongDeployer(deployer);

        (lowFeeGuard, mediumFeeGuard, highFeeGuard) = execute(
            // forge-lint: disable-next-line(unsafe-typecast)
            uint16(vm.envOr("RAFFLE_POOL_CARDINALITY", uint256(DEFAULT_CARDINALITY))),
            vm.envOr("SEED_SWAP_WEI", DEFAULT_SEED_SWAP_WEI)
        );
        vm.stopBroadcast();
    }

    /// @notice The full remediation, separated from env and broadcast so a fork test can run it.
    function execute(uint16 cardinality, uint256 seedSwapWei)
        public
        returns (
            SinjohSharedV3TwapPriceGuard lowFeeGuard,
            SinjohSharedV3TwapPriceGuard mediumFeeGuard,
            SinjohSharedV3TwapPriceGuard highFeeGuard
        )
    {
        if (block.chainid != ROBINHOOD_MAINNET_CHAIN_ID) revert WrongChain(block.chainid);
        if (V3_FACTORY.codehash != V3_FACTORY_HASH) {
            revert DependencyHashMismatch(V3_FACTORY, V3_FACTORY_HASH, V3_FACTORY.codehash);
        }

        lowFeeGuard = _deploy(LOW_FEE);
        mediumFeeGuard = _deploy(MEDIUM_FEE);
        highFeeGuard = _deploy(HIGH_FEE);
        _assertDeployment(lowFeeGuard, LOW_FEE);
        _assertDeployment(mediumFeeGuard, MEDIUM_FEE);
        _assertDeployment(highFeeGuard, HIGH_FEE);

        RoutePool[] memory pools = routePools();
        for (uint256 i; i < pools.length; ++i) {
            SinjohSharedV3TwapPriceGuard guard = pools[i].fee == LOW_FEE
                ? lowFeeGuard
                : pools[i].fee == MEDIUM_FEE ? mediumFeeGuard : highFeeGuard;
            address pool = guard.poolFor(WETH, pools[i].asset);
            (,,, uint16 current, uint16 next,,) = IV3PoolMainnet(pool).slot0();

            // Priming reserves capacity. Growth happens on the pool's next observation write,
            // which organic trading provides once capacity exists.
            if (next < cardinality) {
                guard.prime(WETH, pools[i].asset, cardinality);
                (,,,, uint16 primedNext,,) = IV3PoolMainnet(pool).slot0();
                if (primedNext < cardinality) revert PrimingFailed(pool, cardinality);
            }

            // A pool stuck at cardinality 1 is unusable regardless of capacity — the guard
            // rejects it outright — and cannot be waited out, because growth requires a written
            // observation and a pool only writes one when a swap actually moves its tick. Seed
            // with escalating sizes until the write demonstrably happened. Not a priced trade:
            // the guard cannot quote until the window fills, which is the circularity this
            // breaks.
            if (current >= MIN_SEEDED_CARDINALITY) continue;
            uint256 amount = seedSwapWei;
            for (uint256 attempt; attempt < MAX_SEED_ATTEMPTS; ++attempt) {
                IWrappedEtherMainnet(WETH).deposit{ value: amount }();
                IWrappedEtherMainnet(WETH).approve(SWAP_ADAPTER, amount);
                IRaffleSwapAdapter(SWAP_ADAPTER)
                    .swap(WETH, pools[i].asset, amount, 0, abi.encode(pools[i].fee));
                (,,, current,,,) = IV3PoolMainnet(pool).slot0();
                if (current >= MIN_SEEDED_CARDINALITY) break;
                amount *= 2;
            }
            if (current < MIN_SEEDED_CARDINALITY) revert SeedingFailed(pool);
        }
    }

    function _deploy(uint24 fee) private returns (SinjohSharedV3TwapPriceGuard guard) {
        guard = new SinjohSharedV3TwapPriceGuard(
            V3_FACTORY,
            fee,
            TWAP_WINDOW,
            MAX_SPOT_DEVIATION_BPS,
            MAX_OUTPUT_SLIPPAGE_BPS,
            VALIDITY_PERIOD,
            COMPARISON_AMOUNT
        );
    }

    function _assertDeployment(SinjohSharedV3TwapPriceGuard guard, uint24 fee) private view {
        if (
            address(guard).code.length == 0 || guard.factory() != V3_FACTORY
                || guard.poolFee() != fee || guard.twapWindow() != TWAP_WINDOW
                || guard.maxSpotDeviationBps() != MAX_SPOT_DEVIATION_BPS
                || guard.maxOutputSlippageBps() != MAX_OUTPUT_SLIPPAGE_BPS
                || guard.validityPeriod() != VALIDITY_PERIOD
                || guard.comparisonAmount() != COMPARISON_AMOUNT
        ) revert DeploymentFailed(fee);
    }
}
