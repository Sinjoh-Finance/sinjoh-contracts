// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IDeltaPositionBuilder } from "../../src/yield-banks/interfaces/IDeltaPositionBuilder.sol";
import {
    IYieldBankV3Pool,
    IYieldBankV3PositionManager
} from "../../src/yield-banks/interfaces/IYieldBankV3.sol";
import { DeltaV3LPAdapter } from "../../src/yield-banks/adapters/DeltaV3LPAdapter.sol";
import { DeltaV3SinglePoolRoute } from "../../src/yield-banks/adapters/DeltaV3SinglePoolRoute.sol";
import { DeltaV3TwapUsdFeed } from "../../src/yield-banks/adapters/DeltaV3TwapUsdFeed.sol";
import { MarketMakingSleeve } from "../../src/yield-banks/sleeves/MarketMakingSleeve.sol";
import { PriceHub } from "../../src/yield-banks/PriceHub.sol";
import { StrategyRegistry } from "../../src/yield-banks/StrategyRegistry.sol";
import { YieldBankIds } from "../../src/yield-banks/libraries/YieldBankIds.sol";
import {
    MockYieldBankAggregator,
    MockYieldBankEligibilityPolicy
} from "../mocks/MockYieldBankIntegrations.sol";

interface IForkWETH is IERC20 {
    function deposit() external payable;
}

/// @notice Opt-in proof against the reviewed live Robinhood mainnet Delta deployment.
contract DeltaV3LPAdapterForkTest is Test {
    uint256 private constant ROBINHOOD_MAINNET_CHAIN_ID = 4_663;

    address private constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    address private constant USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;
    address private constant POOL = 0x52e65B17fB6E5BA00Ed806f37Afcd2DaA50271Ca;
    address private constant FACTORY = 0x1f7d7550B1b028f7571E69A784071F0205FD2EfA;
    address private constant POSITION_MANAGER = 0x73991a25C818Bf1f1128dEAaB1492D45638DE0D3;
    address private constant POSITION_BUILDER = 0x6235cF6bd8419b34942F4EDDB39C880BD96dD700;

    bytes32 private constant POOL_CODE_HASH =
        0x3298b5dd4e6f115074c526a55ad05a36fd73a0034ac22ec6cbaab32cc9c1e8d2;
    bytes32 private constant FACTORY_CODE_HASH =
        0xec72b1abd1f2faee020cfea9c646bd8994f9fb389054f6e574f103a895091739;
    bytes32 private constant POSITION_MANAGER_CODE_HASH =
        0x0a493d1af3d0f25fed8efa205244ebee14114267a08647fc38c515c7cd6ead4f;
    bytes32 private constant POSITION_BUILDER_CODE_HASH =
        0xb9b462897f26b3d9082e6db057e363ea01cee5931f39bc62d52eeaa4aa7a9039;

    function testLiveBuilderMintsTracksValuesAndExitsPosition() external {
        string memory rpcUrl = vm.envOr("ROBINHOOD_MAINNET_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) vm.skip(true);
        vm.createSelectFork(rpcUrl);
        assertEq(block.chainid, ROBINHOOD_MAINNET_CHAIN_ID);

        assertEq(POOL.codehash, POOL_CODE_HASH);
        assertEq(FACTORY.codehash, FACTORY_CODE_HASH);
        assertEq(POSITION_MANAGER.codehash, POSITION_MANAGER_CODE_HASH);
        assertEq(POSITION_BUILDER.codehash, POSITION_BUILDER_CODE_HASH);
        assertEq(IDeltaPositionBuilder(POSITION_BUILDER).uniFactory(), FACTORY);
        assertEq(IDeltaPositionBuilder(POSITION_BUILDER).positionManager(), POSITION_MANAGER);
        assertEq(IDeltaPositionBuilder(POSITION_BUILDER).weth(), WETH);
        assertEq(IYieldBankV3PositionManager(POSITION_MANAGER).factory(), FACTORY);
        assertEq(IYieldBankV3PositionManager(POSITION_MANAGER).WETH9(), WETH);
        assertEq(IYieldBankV3Pool(POOL).token0(), WETH);
        assertEq(IYieldBankV3Pool(POOL).token1(), USDG);
        assertEq(IYieldBankV3Pool(POOL).fee(), 100);
        assertEq(IYieldBankV3Pool(POOL).tickSpacing(), 1);

        MockYieldBankAggregator derivedWethFeed = new MockYieldBankAggregator(8, 2_500e8);
        DeltaV3TwapUsdFeed derivedUsdgFeed = new DeltaV3TwapUsdFeed(
            USDG,
            WETH,
            POOL,
            FACTORY,
            address(derivedWethFeed),
            POOL_CODE_HASH,
            FACTORY_CODE_HASH,
            address(derivedWethFeed).codehash,
            60,
            500,
            1e6,
            1,
            "USDG / USD (Delta V3 TWAP)"
        );
        (, int256 derivedUsdgUsd,,,) = derivedUsdgFeed.latestRoundData();
        assertGt(derivedUsdgUsd, 0);

        uint256 wethToConvert = 0.002 ether;
        DeltaV3SinglePoolRoute entryRoute = new DeltaV3SinglePoolRoute(
            POOL, FACTORY, WETH, USDG, POOL_CODE_HASH, FACTORY_CODE_HASH
        );
        DeltaV3SinglePoolRoute exitRoute = new DeltaV3SinglePoolRoute(
            POOL, FACTORY, USDG, WETH, POOL_CODE_HASH, FACTORY_CODE_HASH
        );

        vm.deal(address(this), 0.02 ether);
        IForkWETH(WETH).deposit{ value: 0.012 ether }();
        IERC20(WETH).approve(address(entryRoute), 0.001 ether);
        uint256 roundTripUsdg = entryRoute.convert(0.001 ether, 1e6, address(this), "");
        IERC20(USDG).approve(address(exitRoute), roundTripUsdg);
        uint256 roundTripWeth = exitRoute.convert(roundTripUsdg, 1, address(this), "");
        assertGt(roundTripWeth, 0);
        assertEq(IERC20(WETH).balanceOf(address(entryRoute)), 0);
        assertEq(IERC20(USDG).balanceOf(address(exitRoute)), 0);

        PriceHub priceHub = new PriceHub(address(this), address(this));
        MockYieldBankAggregator wethFeed = new MockYieldBankAggregator(8, 2_500e8);
        MockYieldBankAggregator usdgFeed = new MockYieldBankAggregator(8, 1e8);
        priceHub.configureFeed(WETH, address(wethFeed), address(0), 1 days, 0, false, 100);
        priceHub.configureFeed(USDG, address(usdgFeed), address(0), 1 days, 0, false, 100);
        StrategyRegistry registry = new StrategyRegistry(address(this));
        MockYieldBankEligibilityPolicy eligibility = new MockYieldBankEligibilityPolicy();
        MarketMakingSleeve sleeve = new MarketMakingSleeve(
            WETH,
            address(this),
            address(this),
            address(this),
            address(priceHub),
            address(registry),
            address(eligibility),
            1,
            10_000,
            100
        );
        DeltaV3LPAdapter adapter = new DeltaV3LPAdapter(
            DeltaV3LPAdapter.Config({
                sleeve: address(sleeve),
                weth: WETH,
                pairedAsset: USDG,
                priceHub: address(priceHub),
                pool: POOL,
                positionManager: POSITION_MANAGER,
                positionBuilder: POSITION_BUILDER,
                entryRoute: address(entryRoute),
                exitRoute: address(exitRoute),
                poolCodeHash: POOL_CODE_HASH,
                factoryCodeHash: FACTORY_CODE_HASH,
                positionManagerCodeHash: POSITION_MANAGER_CODE_HASH,
                positionBuilderCodeHash: POSITION_BUILDER_CODE_HASH,
                entryRouteCodeHash: address(entryRoute).codehash,
                exitRouteCodeHash: address(exitRoute).codehash,
                maximumPositions: 1
            })
        );
        registry.register(address(adapter), YieldBankIds.MARKET_MAKING);
        sleeve.addAdapter(address(adapter), 10_000);

        IERC20(WETH).approve(address(sleeve), 0.01 ether);
        sleeve.deposit(0.01 ether, address(this), 1, "");

        (, int24 currentTick,,,,,) = IYieldBankV3Pool(POOL).slot0();
        IDeltaPositionBuilder.Rung[] memory rungs = new IDeltaPositionBuilder.Rung[](1);
        rungs[0] = IDeltaPositionBuilder.Rung({
            tickLower: currentTick - 1_000,
            tickUpper: currentTick + 1_000,
            amount0: 0.008 ether,
            amount1: 1e6,
            amount0Min: 1,
            amount1Min: 1
        });
        // The live fork transaction uses a deliberately short operator deadline.
        // forge-lint: disable-next-line(block-timestamp)
        uint256 deadline = block.timestamp + 5 minutes;
        DeltaV3LPAdapter.DepositParams memory depositParams = DeltaV3LPAdapter.DepositParams({
            wethToConvert: wethToConvert,
            minimumPairedAssetOut: 1e6,
            routeData: "",
            rungs: rungs,
            minimumCurrentTick: currentTick - 5,
            maximumCurrentTick: currentTick + 5,
            deadline: deadline
        });
        uint256 units =
            sleeve.depositToAdapter(address(adapter), 0.01 ether, 1, abi.encode(depositParams));
        assertGt(units, 0);
        uint256[] memory positionIds = adapter.positionIds();
        assertEq(positionIds.length, 1);
        assertEq(
            IYieldBankV3PositionManager(POSITION_MANAGER).ownerOf(positionIds[0]), address(adapter)
        );
        assertTrue(adapter.isPositionTracked(positionIds[0]));
        assertGt(adapter.totalManagedAssets(), 0);

        (,,,,,,, uint128 liquidity,,,,) =
            IYieldBankV3PositionManager(POSITION_MANAGER).positions(positionIds[0]);
        DeltaV3LPAdapter.LiquidityAction[] memory actions =
            new DeltaV3LPAdapter.LiquidityAction[](1);
        actions[0] = DeltaV3LPAdapter.LiquidityAction(positionIds[0], liquidity, 1, 1);
        sleeve.pauseAdapterDeposits(address(adapter));
        sleeve.setExitOnly(address(adapter));
        DeltaV3LPAdapter.ExitParams memory exitParams =
            DeltaV3LPAdapter.ExitParams({ actions: actions, deadline: deadline });
        sleeve.exitAdapter(address(adapter), 100, abi.encode(exitParams));
        assertEq(adapter.positionIds().length, 0);
        assertEq(adapter.totalManagedAssets(), 0);
    }
}
