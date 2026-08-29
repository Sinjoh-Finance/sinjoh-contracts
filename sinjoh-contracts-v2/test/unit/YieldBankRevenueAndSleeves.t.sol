// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { CollectionRevenueRouter } from "../../src/yield-banks/CollectionRevenueRouter.sol";
import { OperationsReserve } from "../../src/yield-banks/OperationsReserve.sol";
import { PriceHub } from "../../src/yield-banks/PriceHub.sol";
import { StrategyRegistry } from "../../src/yield-banks/StrategyRegistry.sol";
import {
    YieldBankProjectRevenueBridge
} from "../../src/yield-banks/YieldBankProjectRevenueBridge.sol";
import { CoreStockTokenSleeve } from "../../src/yield-banks/sleeves/CoreStockTokenSleeve.sol";
import { YieldBankIds } from "../../src/yield-banks/libraries/YieldBankIds.sol";
import {
    MockYieldBankAggregator,
    MockYieldBankAllocationReceiver,
    MockYieldBankAllocationRoute,
    MockYieldBankAsset,
    MockYieldBankCollectionReceiver,
    MockYieldBankEligibilityPolicy,
    MockYieldBankFundableReceiver,
    MockYieldBankTimelock
} from "../mocks/MockYieldBankIntegrations.sol";

contract YieldBankRevenueAndSleevesTest is Test {
    address private constant SOURCE = address(0x501);
    address private constant CREATOR = address(0xC0FFEE);
    address private constant SINJOH = address(0x51A70A);
    address private constant OPERATIONS = address(0x0F5);
    uint16 private constant PROJECT_NFT_BPS = 7_500;
    uint16 private constant PROJECT_CREATOR_BPS = 1_200;
    uint16 private constant PROJECT_SINJOH_BPS = 800;
    uint16 private constant PROJECT_OPERATIONS_BPS = 500;
    uint16 private constant ROYALTY_NFT_BPS = 6_000;
    uint16 private constant ROYALTY_CREATOR_BPS = 2_000;
    uint16 private constant ROYALTY_SINJOH_BPS = 1_000;
    uint16 private constant ROYALTY_OPERATIONS_BPS = 1_000;

    function testNftLegFailureDoesNotBlockCompletedRevenueLegs() external {
        MockYieldBankAsset input = new MockYieldBankAsset("Input", "IN");
        address[3] memory outputAddresses;
        for (uint256 i; i < 3; ++i) {
            outputAddresses[i] = address(new MockYieldBankAsset("Sleeve", "SLV"));
        }
        MockYieldBankAllocationReceiver allocator =
            new MockYieldBankAllocationReceiver(outputAddresses);
        MockYieldBankCollectionReceiver collection =
            new MockYieldBankCollectionReceiver(keccak256("COLLECTION"));
        CollectionRevenueRouter router = new CollectionRevenueRouter(
            address(collection),
            address(allocator),
            address(this),
            CREATOR,
            SINJOH,
            OPERATIONS,
            PROJECT_NFT_BPS,
            PROJECT_CREATOR_BPS,
            PROJECT_SINJOH_BPS,
            PROJECT_OPERATIONS_BPS,
            ROYALTY_NFT_BPS,
            ROYALTY_CREATOR_BPS,
            ROYALTY_SINJOH_BPS,
            ROYALTY_OPERATIONS_BPS
        );
        router.setSourceAuthorization(SOURCE, YieldBankIds.PROJECT_REVENUE, true);
        allocator.setShouldFail(true);
        input.mint(SOURCE, 1_000e18);
        vm.startPrank(SOURCE);
        input.approve(address(router), 1_000e18);
        router.fund(
            collection.collectionId(),
            address(input),
            1_000e18,
            YieldBankIds.PROJECT_REVENUE,
            "route"
        );
        vm.stopPrank();

        assertEq(input.balanceOf(CREATOR), 120e18);
        assertEq(input.balanceOf(SINJOH), 80e18);
        assertEq(input.balanceOf(OPERATIONS), 50e18);
        assertEq(router.failedNftAllocation(address(input), keccak256("route")), 750e18);
        assertEq(router.accountedEscrow(address(input)), 750e18);
        vm.expectRevert(CollectionRevenueRouter.NothingToRetry.selector);
        router.syncRoyalty(address(input), "route");

        allocator.setShouldFail(false);
        router.retryNftAllocation(address(input), "route");
        assertEq(router.failedNftAllocation(address(input), keccak256("route")), 0);
        assertEq(router.accountedEscrow(address(input)), 0);
        for (uint256 i; i < 3; ++i) {
            assertEq(collection.received(outputAddresses[i]), uint256(750e18) / 3);
        }
    }

    function testDirectRoyaltyTransferSynchronizesExactlyOnce() external {
        MockYieldBankAsset input = new MockYieldBankAsset("Input", "IN");
        address[3] memory outputAddresses;
        for (uint256 i; i < 3; ++i) {
            outputAddresses[i] = address(new MockYieldBankAsset("Sleeve", "SLV"));
        }
        MockYieldBankAllocationReceiver allocator =
            new MockYieldBankAllocationReceiver(outputAddresses);
        MockYieldBankCollectionReceiver collection =
            new MockYieldBankCollectionReceiver(keccak256("COLLECTION"));
        CollectionRevenueRouter router = new CollectionRevenueRouter(
            address(collection),
            address(allocator),
            address(this),
            CREATOR,
            SINJOH,
            OPERATIONS,
            PROJECT_NFT_BPS,
            PROJECT_CREATOR_BPS,
            PROJECT_SINJOH_BPS,
            PROJECT_OPERATIONS_BPS,
            ROYALTY_NFT_BPS,
            ROYALTY_CREATOR_BPS,
            ROYALTY_SINJOH_BPS,
            ROYALTY_OPERATIONS_BPS
        );
        input.mint(SOURCE, 1_000e18);
        vm.prank(SOURCE);
        assertTrue(input.transfer(address(router), 1_000e18));

        assertEq(router.syncRoyalty(address(input), "route"), 1_000e18);
        assertEq(input.balanceOf(CREATOR), 200e18);
        assertEq(input.balanceOf(SINJOH), 100e18);
        assertEq(input.balanceOf(OPERATIONS), 100e18);
        for (uint256 i; i < 3; ++i) {
            assertEq(collection.received(outputAddresses[i]), uint256(600e18) / 3);
        }
        vm.expectRevert(CollectionRevenueRouter.NothingToRetry.selector);
        router.syncRoyalty(address(input), "route");
    }

    function testOperationsReserveSourceAllocatesOneHundredPercentToNfts() external {
        MockYieldBankAsset input = new MockYieldBankAsset("Input", "IN");
        address[3] memory outputAddresses;
        for (uint256 i; i < 3; ++i) {
            outputAddresses[i] = address(new MockYieldBankAsset("Sleeve", "SLV"));
        }
        MockYieldBankAllocationReceiver allocator =
            new MockYieldBankAllocationReceiver(outputAddresses);
        MockYieldBankCollectionReceiver collection =
            new MockYieldBankCollectionReceiver(keccak256("COLLECTION"));
        CollectionRevenueRouter router = new CollectionRevenueRouter(
            address(collection),
            address(allocator),
            address(this),
            CREATOR,
            SINJOH,
            OPERATIONS,
            PROJECT_NFT_BPS,
            PROJECT_CREATOR_BPS,
            PROJECT_SINJOH_BPS,
            PROJECT_OPERATIONS_BPS,
            ROYALTY_NFT_BPS,
            ROYALTY_CREATOR_BPS,
            ROYALTY_SINJOH_BPS,
            ROYALTY_OPERATIONS_BPS
        );
        router.setSourceAuthorization(SOURCE, YieldBankIds.OPERATIONS_RESERVE_SWEEP, true);
        input.mint(SOURCE, 900e18);
        vm.startPrank(SOURCE);
        input.approve(address(router), 900e18);
        router.fund(
            collection.collectionId(),
            address(input),
            900e18,
            YieldBankIds.OPERATIONS_RESERVE_SWEEP,
            "route"
        );
        vm.stopPrank();

        assertEq(input.balanceOf(CREATOR), 0);
        assertEq(input.balanceOf(SINJOH), 0);
        assertEq(input.balanceOf(OPERATIONS), 0);
        for (uint256 i; i < 3; ++i) {
            assertEq(collection.received(outputAddresses[i]), 300e18);
        }
    }

    function testOperationsPrimaryReserveIsProtectedUntilPermissionlessSunset() external {
        MockYieldBankAsset asset = new MockYieldBankAsset("WETH", "WETH");
        // Reserve lifecycle test uses a fixed future product sunset.
        // forge-lint: disable-next-line(block-timestamp)
        uint48 sunset = uint48(block.timestamp + 30 days);
        MockYieldBankFundableReceiver receiver = new MockYieldBankFundableReceiver();
        OperationsReserve reserve = new OperationsReserve(
            address(asset),
            address(this),
            keccak256("COLLECTION"),
            address(receiver),
            address(this),
            sunset
        );
        asset.mint(address(reserve), 150e18);
        reserve.notifyPrimary(100e18);
        reserve.spend(OPERATIONS, 50e18, keccak256("audit"));
        assertEq(asset.balanceOf(OPERATIONS), 50e18);
        vm.expectRevert();
        reserve.spend(OPERATIONS, 1, keccak256("keeper"));
        vm.warp(sunset);
        reserve.sweepExpiredPrimary("reviewed route");
        assertEq(receiver.received(), 100e18);
        assertEq(asset.allowance(address(reserve), address(receiver)), 0);
    }

    function testProjectRevenueBridgeBindsIdentityAndClearsAllowances() external {
        bytes32 projectId = keccak256("PROJECT");
        bytes32 collectionId = keccak256("COLLECTION");
        MockYieldBankAsset input = new MockYieldBankAsset("Input", "IN");
        address[3] memory outputAddresses;
        for (uint256 i; i < 3; ++i) {
            outputAddresses[i] = address(new MockYieldBankAsset("Sleeve", "SLV"));
        }
        MockYieldBankAllocationReceiver allocator =
            new MockYieldBankAllocationReceiver(outputAddresses);
        MockYieldBankCollectionReceiver collection =
            new MockYieldBankCollectionReceiver(collectionId);
        CollectionRevenueRouter revenueRouter = new CollectionRevenueRouter(
            address(collection),
            address(allocator),
            address(this),
            CREATOR,
            SINJOH,
            OPERATIONS,
            PROJECT_NFT_BPS,
            PROJECT_CREATOR_BPS,
            PROJECT_SINJOH_BPS,
            PROJECT_OPERATIONS_BPS,
            ROYALTY_NFT_BPS,
            ROYALTY_CREATOR_BPS,
            ROYALTY_SINJOH_BPS,
            ROYALTY_OPERATIONS_BPS
        );
        MockYieldBankTimelock registry = new MockYieldBankTimelock();
        MockYieldBankTimelock subject = new MockYieldBankTimelock();
        MockYieldBankTimelock controller = new MockYieldBankTimelock();
        MockYieldBankTimelock projectRouter = new MockYieldBankTimelock();
        YieldBankProjectRevenueBridge bridge = new YieldBankProjectRevenueBridge(
            address(registry),
            projectId,
            address(subject),
            address(controller),
            address(projectRouter),
            address(revenueRouter),
            address(revenueRouter).codehash,
            collectionId
        );
        revenueRouter.setSourceAuthorization(address(bridge), YieldBankIds.PROJECT_REVENUE, true);

        input.mint(address(projectRouter), 1_000e18);
        vm.startPrank(address(projectRouter));
        input.approve(address(bridge), 1_000e18);
        uint256 reported =
            bridge.fund(projectId, address(subject), address(input), 1_000e18, "route");
        vm.stopPrank();

        assertEq(reported, 1_000e18);
        assertEq(input.balanceOf(address(bridge)), 0);
        assertEq(input.allowance(address(bridge), address(revenueRouter)), 0);
        assertEq(input.balanceOf(CREATOR), 120e18);
        assertEq(input.balanceOf(SINJOH), 80e18);
        assertEq(input.balanceOf(OPERATIONS), 50e18);
        for (uint256 i; i < 3; ++i) {
            assertEq(collection.received(outputAddresses[i]), uint256(750e18) / 3);
        }

        vm.startPrank(address(projectRouter));
        vm.expectRevert();
        bridge.fund(keccak256("WRONG"), address(subject), address(input), 1, "route");
        vm.stopPrank();
    }

    function testCoreSleeveInvestsConfiguredImmutableWeightsAndClearsAllowances() external {
        MockYieldBankAsset weth = new MockYieldBankAsset("WETH", "WETH");
        MockYieldBankEligibilityPolicy policy = new MockYieldBankEligibilityPolicy();
        PriceHub hub = new PriceHub(address(this), address(this));
        StrategyRegistry registry = new StrategyRegistry(address(this));
        MockYieldBankAggregator wethFeed = new MockYieldBankAggregator(8, 2_000e8);
        hub.configureFeed(address(weth), address(wethFeed), address(0), 1 days, 0, false, 100);
        CoreStockTokenSleeve sleeve = new CoreStockTokenSleeve(
            address(weth),
            address(this),
            address(this),
            address(this),
            address(hub),
            address(registry),
            address(policy),
            1,
            5_000,
            100
        );
        MockYieldBankAsset[3] memory stocks;
        MockYieldBankAllocationRoute[3] memory routes;
        uint16[3] memory weights = [uint16(3_333), uint16(3_333), uint16(3_334)];
        CoreStockTokenSleeve.ConstituentCall[] memory calls =
            new CoreStockTokenSleeve.ConstituentCall[](3);
        for (uint256 i; i < 3; ++i) {
            stocks[i] = new MockYieldBankAsset("Stock Token", "STOCK");
            routes[i] = new MockYieldBankAllocationRoute(address(weth), address(stocks[i]));
            MockYieldBankAggregator stockFeed = new MockYieldBankAggregator(8, 100e8);
            hub.configureFeed(
                address(stocks[i]), address(stockFeed), address(0), 1 days, 0, true, 100
            );
            sleeve.addConstituent(
                address(stocks[i]), address(routes[i]), address(routes[i]).codehash, weights[i]
            );
            calls[i] =
                CoreStockTokenSleeve.ConstituentCall({ minimumOutput: 3_000e18, routeData: "" });
        }
        weth.mint(address(this), 10_000e18);
        weth.approve(address(sleeve), 10_000e18);
        uint256 shares = sleeve.deposit(10_000e18, address(this), 1, abi.encode(calls));
        assertGt(shares, 0);
        assertEq(weth.balanceOf(address(sleeve)), 0);
        for (uint256 i; i < 3; ++i) {
            assertEq(weth.allowance(address(sleeve), address(routes[i])), 0);
            assertEq(stocks[i].balanceOf(address(sleeve)), uint256(weights[i]) * 1e18);
        }
    }
}
