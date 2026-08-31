// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IDeltaPositionBuilder } from "../../src/yield-banks/interfaces/IDeltaPositionBuilder.sol";
import { DeltaV3LPAdapter } from "../../src/yield-banks/adapters/DeltaV3LPAdapter.sol";
import { PriceHub } from "../../src/yield-banks/PriceHub.sol";
import { StrategyRegistry } from "../../src/yield-banks/StrategyRegistry.sol";
import { MarketMakingSleeve } from "../../src/yield-banks/sleeves/MarketMakingSleeve.sol";
import { YieldBankRedemptionMode } from "../../src/yield-banks/YieldBankTypes.sol";
import { YieldBankIds } from "../../src/yield-banks/libraries/YieldBankIds.sol";
import {
    MockYieldBankAggregator,
    MockYieldBankAllocationRoute,
    MockYieldBankAsset,
    MockYieldBankEligibilityPolicy
} from "../mocks/MockYieldBankIntegrations.sol";
import {
    IMockDeltaPositionManager,
    MockDeltaPositionBuilder,
    MockDeltaV3Factory,
    MockDeltaV3Pool,
    MockDeltaV3PositionManager
} from "../mocks/MockDeltaIntegrations.sol";

contract DeltaV3LPAdapterTest is Test {
    address private constant HOLDER = address(0xB0B);

    MockYieldBankAsset private weth;
    MockYieldBankAsset private pairedAsset;
    MockYieldBankEligibilityPolicy private eligibility;
    PriceHub private priceHub;
    StrategyRegistry private registry;
    MarketMakingSleeve private sleeve;
    MockDeltaV3Factory private factory;
    MockDeltaV3Pool private pool;
    MockDeltaV3PositionManager private manager;
    MockDeltaPositionBuilder private builder;
    MockYieldBankAllocationRoute private entryRoute;
    MockYieldBankAllocationRoute private exitRoute;
    DeltaV3LPAdapter private adapter;

    function setUp() external {
        weth = new MockYieldBankAsset("Wrapped Ether", "WETH");
        pairedAsset = new MockYieldBankAsset("Paired Asset", "PAIR");
        eligibility = new MockYieldBankEligibilityPolicy();
        priceHub = new PriceHub(address(this), address(this));
        registry = new StrategyRegistry(address(this));
        sleeve = new MarketMakingSleeve(
            address(weth),
            address(this),
            address(this),
            address(this),
            address(priceHub),
            address(registry),
            address(eligibility),
            1,
            10_000,
            500
        );
        factory = new MockDeltaV3Factory();
        pool = new MockDeltaV3Pool(address(factory), address(weth), address(pairedAsset), 3_000, 60);
        factory.setPool(address(weth), address(pairedAsset), 3_000, address(pool));
        manager = new MockDeltaV3PositionManager(address(factory), address(weth), address(pool));
        builder = new MockDeltaPositionBuilder(address(factory), address(manager), address(weth));
        entryRoute = new MockYieldBankAllocationRoute(address(weth), address(pairedAsset));
        exitRoute = new MockYieldBankAllocationRoute(address(pairedAsset), address(weth));

        MockYieldBankAggregator wethFeed = new MockYieldBankAggregator(8, 1e8);
        MockYieldBankAggregator pairedAssetFeed = new MockYieldBankAggregator(8, 1e8);
        priceHub.configureFeed(address(weth), address(wethFeed), address(0), 1 days, 0, false, 100);
        priceHub.configureFeed(
            address(pairedAsset), address(pairedAssetFeed), address(0), 1 days, 0, false, 100
        );

        adapter = new DeltaV3LPAdapter(
            DeltaV3LPAdapter.Config({
                sleeve: address(sleeve),
                weth: address(weth),
                pairedAsset: address(pairedAsset),
                priceHub: address(priceHub),
                pool: address(pool),
                positionManager: address(manager),
                positionBuilder: address(builder),
                entryRoute: address(entryRoute),
                exitRoute: address(exitRoute),
                poolCodeHash: address(pool).codehash,
                factoryCodeHash: address(factory).codehash,
                positionManagerCodeHash: address(manager).codehash,
                positionBuilderCodeHash: address(builder).codehash,
                entryRouteCodeHash: address(entryRoute).codehash,
                exitRouteCodeHash: address(exitRoute).codehash,
                maximumPositions: 4
            })
        );
        registry.register(address(adapter), YieldBankIds.MARKET_MAKING);
        sleeve.addAdapter(address(adapter), 10_000);

        weth.mint(address(this), 1_000e18);
        weth.approve(address(sleeve), 1_000e18);
        sleeve.deposit(1_000e18, address(this), 999e18, "");
    }

    function testManualDeltaDepositBindsAndValuesPosition() external {
        uint256 units = _depositPosition();
        assertGt(units, 0);
        uint256[] memory ids = adapter.positionIds();
        assertEq(ids.length, 1);
        assertEq(manager.ownerOf(ids[0]), address(adapter));
        assertTrue(adapter.isPositionTracked(ids[0]));
        assertApproxEqAbs(adapter.totalManagedAssets(), 500e18, 10);
        assertEq(weth.allowance(address(adapter), address(builder)), 0);
        assertEq(pairedAsset.allowance(address(adapter), address(builder)), 0);
        assertEq(weth.allowance(address(adapter), address(entryRoute)), 0);
    }

    function testCollectsBothPoolAssetsIntoSleeve() external {
        _depositPosition();
        uint256 tokenId = adapter.positionIds()[0];
        manager.addFees(tokenId, 12e18, 7e18);
        uint256 wethBefore = weth.balanceOf(address(sleeve));
        uint256 pairedAssetBefore = pairedAsset.balanceOf(address(sleeve));

        uint256[] memory ids = new uint256[](1);
        ids[0] = tokenId;
        (address[] memory assets, uint256[] memory amounts) =
            sleeve.collectAdapter(address(adapter), abi.encode(ids));

        assertEq(assets[0], address(weth));
        assertEq(assets[1], address(pairedAsset));
        assertEq(amounts[0], 12e18);
        assertEq(amounts[1], 7e18);
        assertEq(weth.balanceOf(address(sleeve)) - wethBefore, 12e18);
        assertEq(pairedAsset.balanceOf(address(sleeve)) - pairedAssetBefore, 7e18);
    }

    function testPendingPoolFeesAreIncludedInManagedAssets() external {
        _depositPosition();
        uint256 beforeValue = adapter.totalManagedAssets();

        pool.setFeeGrowth(1 << 128, 1 << 128);

        uint256 afterValue = adapter.totalManagedAssets();
        assertGt(afterValue, beforeValue);
    }

    function testManualWithdrawalCanUnwindAndConvertToWeth() external {
        _depositPosition();
        uint256 tokenId = adapter.positionIds()[0];
        (,,, uint128 liquidity,,,,) = _position(tokenId);
        (uint256 position0, uint256 position1) = manager.positionAmounts(tokenId);
        uint256 pairedAssetToConvert = pairedAsset.balanceOf(address(adapter)) + position1;
        uint256 available = weth.balanceOf(address(adapter)) + position0 + pairedAssetToConvert;

        DeltaV3LPAdapter.LiquidityAction[] memory actions =
            new DeltaV3LPAdapter.LiquidityAction[](1);
        actions[0] = DeltaV3LPAdapter.LiquidityAction(tokenId, liquidity, 1, 1);
        DeltaV3LPAdapter.WithdrawalParams memory params = DeltaV3LPAdapter.WithdrawalParams({
            actions: actions,
            pairedAssetToConvert: pairedAssetToConvert,
            minimumWethOut: pairedAssetToConvert,
            wethToReturn: available,
            routeData: "",
            // Test execution uses the current timestamp as an explicit operator deadline.
            // forge-lint: disable-next-line(block-timestamp)
            deadline: block.timestamp
        });

        uint256 returned =
            sleeve.withdrawFromAdapter(address(adapter), available, 0, abi.encode(params));
        assertEq(returned, available);
        assertEq(adapter.positionIds().length, 0);
        assertEq(adapter.totalManagedAssets(), 0);
        assertEq(pairedAsset.allowance(address(adapter), address(exitRoute)), 0);
    }

    function testExitAllReturnsBothAssetsInKind() external {
        _depositPosition();
        uint256 tokenId = adapter.positionIds()[0];
        (,,, uint128 liquidity,,,,) = _position(tokenId);
        manager.addFees(tokenId, 3e18, 2e18);
        sleeve.pauseAdapterDeposits(address(adapter));
        sleeve.setExitOnly(address(adapter));

        DeltaV3LPAdapter.LiquidityAction[] memory actions =
            new DeltaV3LPAdapter.LiquidityAction[](1);
        actions[0] = DeltaV3LPAdapter.LiquidityAction(tokenId, liquidity, 1, 1);
        DeltaV3LPAdapter.ExitParams memory params = DeltaV3LPAdapter.ExitParams({
            actions: actions,
            // Test execution uses the current timestamp as an explicit operator deadline.
            // forge-lint: disable-next-line(block-timestamp)
            deadline: block.timestamp
        });
        uint256 wethBefore = weth.balanceOf(address(sleeve));
        uint256 pairedAssetBefore = pairedAsset.balanceOf(address(sleeve));
        (address[] memory assets, uint256[] memory amounts) =
            sleeve.exitAdapter(address(adapter), 1, abi.encode(params));

        assertEq(assets[0], address(weth));
        assertEq(assets[1], address(pairedAsset));
        assertEq(weth.balanceOf(address(sleeve)) - wethBefore, amounts[0]);
        assertEq(pairedAsset.balanceOf(address(sleeve)) - pairedAssetBefore, amounts[1]);
        assertEq(adapter.positionIds().length, 0);
        assertEq(adapter.totalManagedAssets(), 0);
    }

    function testHolderRedeemsProRataAssetsIncludingAccruedDeltaFees() external {
        _depositPosition();
        uint256 tokenId = adapter.positionIds()[0];
        uint256 managedBeforeFees = adapter.totalManagedAssets();
        manager.addFees(tokenId, 12e18, 8e18);
        assertEq(adapter.totalManagedAssets() - managedBeforeFees, 20e18);

        (,,, uint128 liquidity,,,,) = _position(tokenId);
        sleeve.pauseAdapterDeposits(address(adapter));
        sleeve.setExitOnly(address(adapter));
        DeltaV3LPAdapter.LiquidityAction[] memory actions =
            new DeltaV3LPAdapter.LiquidityAction[](1);
        actions[0] = DeltaV3LPAdapter.LiquidityAction(tokenId, liquidity, 1, 1);
        DeltaV3LPAdapter.ExitParams memory params = DeltaV3LPAdapter.ExitParams({
            actions: actions,
            // Test execution uses the current timestamp as an explicit operator deadline.
            // forge-lint: disable-next-line(block-timestamp)
            deadline: block.timestamp
        });
        sleeve.exitAdapter(address(adapter), 1, abi.encode(params));

        uint256 supply = sleeve.totalSupply();
        uint256 holderShares = supply / 2;
        sleeve.transferWithProof(HOLDER, holderShares, "");
        uint256 expectedWeth = weth.balanceOf(address(sleeve)) * holderShares / supply;
        uint256 expectedPaired = pairedAsset.balanceOf(address(sleeve)) * holderShares / supply;
        uint256[] memory minimumOutputs = new uint256[](2);
        minimumOutputs[0] = expectedWeth;
        minimumOutputs[1] = expectedPaired;

        vm.prank(HOLDER);
        sleeve.redeem(
            holderShares, HOLDER, HOLDER, YieldBankRedemptionMode.IN_KIND, minimumOutputs, ""
        );

        assertEq(weth.balanceOf(HOLDER), expectedWeth);
        assertEq(pairedAsset.balanceOf(HOLDER), expectedPaired);
        assertGt(expectedWeth + expectedPaired, 500e18);
    }

    function testGuardianInKindExitStillWorksWhenPriceHubIsPaused() external {
        _depositPosition();
        uint256 tokenId = adapter.positionIds()[0];
        (,,, uint128 liquidity,,,,) = _position(tokenId);
        sleeve.pauseAdapterDeposits(address(adapter));
        sleeve.setExitOnly(address(adapter));
        priceHub.setGuardianPaused(true);

        DeltaV3LPAdapter.LiquidityAction[] memory actions =
            new DeltaV3LPAdapter.LiquidityAction[](1);
        actions[0] = DeltaV3LPAdapter.LiquidityAction(tokenId, liquidity, 1, 1);
        DeltaV3LPAdapter.ExitParams memory params = DeltaV3LPAdapter.ExitParams({
            actions: actions,
            // forge-lint: disable-next-line(block-timestamp)
            deadline: block.timestamp
        });
        (address[] memory assets, uint256[] memory amounts) =
            sleeve.emergencyExitAdapterInKind(address(adapter), abi.encode(params));

        assertEq(assets[0], address(weth));
        assertEq(assets[1], address(pairedAsset));
        assertGt(amounts[0] + amounts[1], 0);
        assertEq(adapter.positionIds().length, 0);
    }

    function testRejectsUnsolicitedPositionNFT() external {
        weth.mint(address(this), 1e18);
        pairedAsset.mint(address(this), 1e18);
        weth.approve(address(manager), 1e18);
        pairedAsset.approve(address(manager), 1e18);
        // Test execution uses the current timestamp as an explicit operator deadline.
        // forge-lint: disable-next-line(block-timestamp)
        uint256 deadline = block.timestamp;
        (uint256 tokenId,,,) = manager.mint(
            IMockDeltaPositionManager.MintParams({
                token0: address(weth),
                token1: address(pairedAsset),
                fee: 3_000,
                tickLower: -600,
                tickUpper: 600,
                amount0Desired: 1e18,
                amount1Desired: 1e18,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: deadline
            })
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                DeltaV3LPAdapter.UnexpectedNFT.selector, address(manager), address(this), tokenId
            )
        );
        manager.safeTransferFrom(address(this), address(adapter), tokenId);
        assertFalse(adapter.isPositionTracked(tokenId));
    }

    function testEntryRouteRuntimeMutationFailsClosed() external {
        bytes memory mutatedRuntime = hex"60006000f3";
        vm.etch(address(entryRoute), mutatedRuntime);
        vm.expectRevert();
        _depositPosition();
    }

    function testOnlyBoundSleeveCanMoveOrCollectBacking() external {
        vm.expectRevert(abi.encodeWithSelector(DeltaV3LPAdapter.OnlySleeve.selector, address(this)));
        adapter.deposit(1, 1, "");

        vm.expectRevert(abi.encodeWithSelector(DeltaV3LPAdapter.OnlySleeve.selector, address(this)));
        adapter.collect(address(this), abi.encode(new uint256[](0)));

        vm.expectRevert(abi.encodeWithSelector(DeltaV3LPAdapter.OnlySleeve.selector, address(this)));
        adapter.exitAll(address(this), 0, "");
    }

    function _depositPosition() private returns (uint256 units) {
        IDeltaPositionBuilder.Rung[] memory rungs = new IDeltaPositionBuilder.Rung[](1);
        rungs[0] = IDeltaPositionBuilder.Rung({
            tickLower: -600,
            tickUpper: 600,
            amount0: 250e18,
            amount1: 250e18,
            amount0Min: 1,
            amount1Min: 1
        });
        DeltaV3LPAdapter.DepositParams memory params = DeltaV3LPAdapter.DepositParams({
            wethToConvert: 250e18,
            minimumPairedAssetOut: 250e18,
            routeData: "",
            rungs: rungs,
            minimumCurrentTick: -60,
            maximumCurrentTick: 60,
            // Test execution uses the current timestamp as an explicit operator deadline.
            // forge-lint: disable-next-line(block-timestamp)
            deadline: block.timestamp
        });
        units = sleeve.depositToAdapter(address(adapter), 500e18, 1, abi.encode(params));
    }

    function _position(uint256 tokenId)
        private
        view
        returns (
            address token0,
            address token1,
            uint24 fee,
            uint128 liquidity,
            int24 tickLower,
            int24 tickUpper,
            uint128 owed0,
            uint128 owed1
        )
    {
        (
            ,, token0, token1, fee, tickLower, tickUpper, liquidity,,, owed0, owed1
        ) = manager.positions(tokenId);
    }
}
