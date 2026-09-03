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
import { CoreStockTokenSleeve } from "../../src/yield-banks/sleeves/CoreStockTokenSleeve.sol";
import { MarketMakingSleeve } from "../../src/yield-banks/sleeves/MarketMakingSleeve.sol";
import { USDGSleeve } from "../../src/yield-banks/sleeves/USDGSleeve.sol";
import { DeltaPoolController } from "../../src/yield-banks/DeltaPoolController.sol";
import { PriceHub } from "../../src/yield-banks/PriceHub.sol";
import { StrategyRegistry } from "../../src/yield-banks/StrategyRegistry.sol";
import { YieldBankRedemptionMode } from "../../src/yield-banks/YieldBankTypes.sol";
import { YieldBankIds } from "../../src/yield-banks/libraries/YieldBankIds.sol";
import {
    MockYieldBankAggregator,
    MockYieldBankEligibilityPolicy
} from "../mocks/MockYieldBankIntegrations.sol";

interface IForkWETH is IERC20 {
    function deposit() external payable;
}

contract ForkDeltaPoolAllocatorSource {
    address public immutable allocationOperator;
    address public immutable collection;

    constructor(address allocationOperator_) {
        allocationOperator = allocationOperator_;
        collection = address(1);
    }
}

/// @notice Opt-in proof against the reviewed live Robinhood mainnet Delta deployment.
contract DeltaV3LPAdapterForkTest is Test {
    uint256 private constant ROBINHOOD_MAINNET_CHAIN_ID = 4_663;

    address private constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    address private constant USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;
    address private constant POOL = 0x52e65B17fB6E5BA00Ed806f37Afcd2DaA50271Ca;
    address private constant INJOH = 0x2cC0FAC44B8252f6B10208B091aFf2c94B4da77D;
    address private constant INJOH_POOL = 0xB09fa4f04032b9d9e690ac4a1d29523b5f9A72DC;
    address private constant NVDA = 0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC;
    address private constant NVDA_POOL = 0x62AB521f71431f78ac374CdbadC6cda3c8916b6C;
    address private constant FACTORY = 0x1f7d7550B1b028f7571E69A784071F0205FD2EfA;
    address private constant POSITION_MANAGER = 0x73991a25C818Bf1f1128dEAaB1492D45638DE0D3;
    address private constant POSITION_BUILDER = 0x6235cF6bd8419b34942F4EDDB39C880BD96dD700;
    address private constant WETH_USD_FEED = 0x78F3556b67E17Df817D51Ef5a990cDaF09E8d3A9;

    bytes32 private constant POOL_CODE_HASH =
        0x3298b5dd4e6f115074c526a55ad05a36fd73a0034ac22ec6cbaab32cc9c1e8d2;
    bytes32 private constant INJOH_POOL_CODE_HASH =
        0xfae0473dfc8dbfe849e964297fb68e7bbb2a0d588c457f0b74d2e93572c08eb0;
    bytes32 private constant NVDA_POOL_CODE_HASH =
        0xce2cc8d0b5f2124c8f4994e1fa6cd567e3af933d860acffb8c08dc8b99b97e04;
    bytes32 private constant FACTORY_CODE_HASH =
        0xec72b1abd1f2faee020cfea9c646bd8994f9fb389054f6e574f103a895091739;
    bytes32 private constant POSITION_MANAGER_CODE_HASH =
        0x0a493d1af3d0f25fed8efa205244ebee14114267a08647fc38c515c7cd6ead4f;
    bytes32 private constant POSITION_BUILDER_CODE_HASH =
        0xb9b462897f26b3d9082e6db057e363ea01cee5931f39bc62d52eeaa4aa7a9039;
    bytes32 private constant WETH_USD_FEED_CODE_HASH =
        0xbd6f524cdc4268b6bd1bb6f77a8821faeea9c52ee9e0afa0b6d948ce82c966c2;

    function testLiveControllerDiscoversCanonicalPoolsWithoutSharedPoolHashOrPoolList() external {
        string memory rpcUrl = vm.envOr("ROBINHOOD_MAINNET_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) vm.skip(true);
        vm.createSelectFork(rpcUrl);

        PriceHub priceHub = new PriceHub(address(this), address(this));
        StrategyRegistry registry = new StrategyRegistry(address(this));
        MockYieldBankEligibilityPolicy eligibility = new MockYieldBankEligibilityPolicy();
        ForkDeltaPoolAllocatorSource allocator = new ForkDeltaPoolAllocatorSource(address(this));
        DeltaPoolController controller = new DeltaPoolController(
            address(allocator),
            address(this),
            address(this),
            WETH,
            address(priceHub),
            address(registry),
            address(eligibility),
            10_000,
            1_000,
            1 days,
            1 days,
            5 minutes,
            1_000,
            1_000,
            "Test Delta Liquidity Sleeve",
            "T-DELTA"
        );
        controller.configureInfrastructure(
            FACTORY,
            DeltaPoolController.InfrastructureConfig({
                positionManager: POSITION_MANAGER,
                positionBuilder: POSITION_BUILDER,
                factoryRuntimeCodeHash: FACTORY_CODE_HASH,
                positionManagerRuntimeCodeHash: POSITION_MANAGER_CODE_HASH,
                positionBuilderRuntimeCodeHash: POSITION_BUILDER_CODE_HASH,
                routeCreationCodeHash: keccak256(type(DeltaV3SinglePoolRoute).creationCode),
                sleeveCreationCodeHash: keccak256(type(MarketMakingSleeve).creationCode),
                adapterCreationCodeHash: keccak256(type(DeltaV3LPAdapter).creationCode),
                feedCreationCodeHash: keccak256(type(DeltaV3TwapUsdFeed).creationCode)
            })
        );

        assertNotEq(POOL.codehash, INJOH_POOL.codehash);
        assertTrue(controller.isSelectablePool(POOL));
        assertTrue(controller.isSelectablePool(INJOH_POOL));
        assertEq(controller.pairedAssetOf(POOL), USDG);
        assertEq(controller.pairedAssetOf(INJOH_POOL), INJOH);
    }

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
            "Test Delta Liquidity Sleeve",
            "T-DELTA",
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

    function testLiveInjohPoolIdentityRouteAndBuilderMint() external {
        string memory rpcUrl = vm.envOr("ROBINHOOD_MAINNET_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) vm.skip(true);
        vm.createSelectFork(rpcUrl);
        assertEq(block.chainid, ROBINHOOD_MAINNET_CHAIN_ID);

        IYieldBankV3Pool injohPool = IYieldBankV3Pool(INJOH_POOL);
        assertEq(INJOH_POOL.codehash, INJOH_POOL_CODE_HASH);
        assertEq(injohPool.factory(), FACTORY);
        assertEq(injohPool.token0(), WETH);
        assertEq(injohPool.token1(), INJOH);
        assertEq(injohPool.fee(), 10_000);
        assertEq(injohPool.tickSpacing(), 200);
        assertGt(injohPool.liquidity(), 0);
        (, int24 currentTick,,,,, bool unlocked) = injohPool.slot0();
        assertTrue(unlocked);

        DeltaV3SinglePoolRoute entryRoute = new DeltaV3SinglePoolRoute(
            INJOH_POOL, FACTORY, WETH, INJOH, INJOH_POOL_CODE_HASH, FACTORY_CODE_HASH
        );
        vm.deal(address(this), 0.01 ether);
        IForkWETH(WETH).deposit{ value: 0.004 ether }();
        IERC20(WETH).approve(address(entryRoute), 0.001 ether);
        uint256 injohAmount = entryRoute.convert(0.001 ether, 1, address(this), "");
        assertGt(injohAmount, 0);

        IERC20(WETH).approve(POSITION_BUILDER, 0.002 ether);
        IERC20(INJOH).approve(POSITION_BUILDER, injohAmount);
        int24 alignedTick = currentTick / 200 * 200;
        IDeltaPositionBuilder.Rung[] memory rungs = new IDeltaPositionBuilder.Rung[](1);
        rungs[0] = IDeltaPositionBuilder.Rung({
            tickLower: alignedTick - 200,
            tickUpper: alignedTick + 400,
            amount0: 0.002 ether,
            amount1: injohAmount,
            amount0Min: 1,
            amount1Min: 1
        });
        // forge-lint: disable-next-line(block-timestamp)
        uint256 deadline = block.timestamp + 5 minutes;
        uint256[] memory tokenIds = IDeltaPositionBuilder(POSITION_BUILDER)
            .mintLadder(INJOH_POOL, rungs, currentTick - 5, currentTick + 5, deadline);
        assertEq(tokenIds.length, 1);
        IYieldBankV3PositionManager manager = IYieldBankV3PositionManager(POSITION_MANAGER);
        assertEq(manager.ownerOf(tokenIds[0]), address(this));
        (,, address token0, address token1, uint24 fee,,, uint128 liquidity,,,,) =
            manager.positions(tokenIds[0]);
        assertEq(token0, WETH);
        assertEq(token1, INJOH);
        assertEq(fee, 10_000);
        assertGt(liquidity, 0);

        manager.decreaseLiquidity(
            IYieldBankV3PositionManager.DecreaseLiquidityParams({
                tokenId: tokenIds[0],
                liquidity: liquidity,
                amount0Min: 1,
                amount1Min: 1,
                deadline: deadline
            })
        );
        manager.collect(
            IYieldBankV3PositionManager.CollectParams({
                tokenId: tokenIds[0],
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
        manager.burn(tokenIds[0]);
    }

    /// @dev These addresses are fork assertions for reviewed live dependencies, not protocol
    ///      defaults. The production contracts receive every asset, pool, and route via config.
    function testLiveStockTokenAndUsdgSleeveRoutesDepositRedeemAndRoundTrip() external {
        string memory rpcUrl = vm.envOr("ROBINHOOD_MAINNET_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) vm.skip(true);
        vm.createSelectFork(rpcUrl);
        assertEq(block.chainid, ROBINHOOD_MAINNET_CHAIN_ID);

        assertEq(NVDA_POOL.codehash, NVDA_POOL_CODE_HASH);
        assertEq(WETH_USD_FEED.codehash, WETH_USD_FEED_CODE_HASH);
        assertEq(IYieldBankV3Pool(NVDA_POOL).factory(), FACTORY);
        assertEq(IYieldBankV3Pool(NVDA_POOL).token0(), WETH);
        assertEq(IYieldBankV3Pool(NVDA_POOL).token1(), NVDA);
        assertEq(IYieldBankV3Pool(NVDA_POOL).fee(), 500);
        assertGt(IYieldBankV3Pool(NVDA_POOL).liquidity(), 0);

        PriceHub priceHub = new PriceHub(address(this), address(this));
        DeltaV3TwapUsdFeed nvdaFeed = new DeltaV3TwapUsdFeed(
            NVDA,
            WETH,
            NVDA_POOL,
            FACTORY,
            WETH_USD_FEED,
            NVDA_POOL_CODE_HASH,
            FACTORY_CODE_HASH,
            WETH_USD_FEED_CODE_HASH,
            60,
            2_000,
            1e18,
            1,
            "NVDA / USD (Delta V3 TWAP)"
        );
        DeltaV3TwapUsdFeed usdgFeed = new DeltaV3TwapUsdFeed(
            USDG,
            WETH,
            POOL,
            FACTORY,
            WETH_USD_FEED,
            POOL_CODE_HASH,
            FACTORY_CODE_HASH,
            WETH_USD_FEED_CODE_HASH,
            60,
            2_000,
            1e6,
            1,
            "USDG / USD (Delta V3 TWAP)"
        );
        (uint80 nvdaRound, int256 nvdaPrice,,, uint80 nvdaAnsweredInRound) =
            nvdaFeed.latestRoundData();
        (uint80 usdgRound, int256 usdgPrice,,, uint80 usdgAnsweredInRound) =
            usdgFeed.latestRoundData();
        assertGt(nvdaPrice, 0);
        assertGe(nvdaAnsweredInRound, nvdaRound);
        assertGt(usdgPrice, 0);
        assertGe(usdgAnsweredInRound, usdgRound);

        priceHub.configureFeed(WETH, WETH_USD_FEED, address(0), 1 days, 1 days, false, 100);
        priceHub.configureFeed(NVDA, address(nvdaFeed), address(0), 1 days, 1 days, false, 100);
        priceHub.configureFeed(USDG, address(usdgFeed), address(0), 1 days, 1 days, false, 100);

        StrategyRegistry registry = new StrategyRegistry(address(this));
        MockYieldBankEligibilityPolicy eligibility = new MockYieldBankEligibilityPolicy();
        CoreStockTokenSleeve stockSleeve = new CoreStockTokenSleeve(
            "Live Stock Route Test",
            "T-STOCK",
            WETH,
            address(this),
            address(this),
            address(this),
            address(priceHub),
            address(registry),
            address(eligibility),
            0,
            0,
            0
        );
        USDGSleeve usdgSleeve = new USDGSleeve(
            "Live USDG Route Test",
            "T-USDG",
            USDG,
            address(this),
            address(this),
            address(this),
            address(priceHub),
            address(registry),
            address(eligibility),
            0,
            0,
            0
        );

        DeltaV3SinglePoolRoute wethToNvda = new DeltaV3SinglePoolRoute(
            NVDA_POOL, FACTORY, WETH, NVDA, NVDA_POOL_CODE_HASH, FACTORY_CODE_HASH
        );
        DeltaV3SinglePoolRoute nvdaToWeth = new DeltaV3SinglePoolRoute(
            NVDA_POOL, FACTORY, NVDA, WETH, NVDA_POOL_CODE_HASH, FACTORY_CODE_HASH
        );
        DeltaV3SinglePoolRoute wethToUsdg = new DeltaV3SinglePoolRoute(
            POOL, FACTORY, WETH, USDG, POOL_CODE_HASH, FACTORY_CODE_HASH
        );
        DeltaV3SinglePoolRoute usdgToWeth = new DeltaV3SinglePoolRoute(
            POOL, FACTORY, USDG, WETH, POOL_CODE_HASH, FACTORY_CODE_HASH
        );
        stockSleeve.addConstituent(NVDA, address(wethToNvda), address(wethToNvda).codehash, 10_000);

        vm.deal(address(this), 0.02 ether);
        IForkWETH(WETH).deposit{ value: 0.01 ether }();

        CoreStockTokenSleeve.ConstituentCall[] memory constituentCalls =
            new CoreStockTokenSleeve.ConstituentCall[](1);
        constituentCalls[0].minimumOutput = 1;
        IERC20(WETH).approve(address(stockSleeve), 0.003 ether);
        uint256 stockShares =
            stockSleeve.deposit(0.003 ether, address(this), 1, abi.encode(constituentCalls));
        uint256 nvdaInSleeve = IERC20(NVDA).balanceOf(address(stockSleeve));
        assertGt(stockShares, 0);
        assertGt(nvdaInSleeve, 0);

        uint256[] memory stockMinimums = new uint256[](2);
        stockMinimums[1] = nvdaInSleeve;
        stockSleeve.redeem(
            stockShares,
            address(this),
            address(this),
            YieldBankRedemptionMode.IN_KIND,
            stockMinimums,
            ""
        );
        uint256 nvdaReceived = IERC20(NVDA).balanceOf(address(this));
        assertEq(nvdaReceived, nvdaInSleeve);
        IERC20(NVDA).approve(address(nvdaToWeth), nvdaReceived);
        assertGt(nvdaToWeth.convert(nvdaReceived, 1, address(this), ""), 0);

        IERC20(WETH).approve(address(wethToUsdg), 0.003 ether);
        uint256 usdgReceived = wethToUsdg.convert(0.003 ether, 1, address(this), "");
        IERC20(USDG).approve(address(usdgSleeve), usdgReceived);
        uint256 usdgShares = usdgSleeve.deposit(usdgReceived, address(this), 1, "");
        assertGt(usdgShares, 0);
        assertEq(IERC20(USDG).balanceOf(address(usdgSleeve)), usdgReceived);

        uint256[] memory usdgMinimums = new uint256[](1);
        usdgMinimums[0] = usdgReceived;
        usdgSleeve.redeem(
            usdgShares,
            address(this),
            address(this),
            YieldBankRedemptionMode.IN_KIND,
            usdgMinimums,
            ""
        );
        assertEq(IERC20(USDG).balanceOf(address(this)), usdgReceived);
        IERC20(USDG).approve(address(usdgToWeth), usdgReceived);
        assertGt(usdgToWeth.convert(usdgReceived, 1, address(this), ""), 0);
    }
}
