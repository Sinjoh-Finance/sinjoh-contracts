// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import {
    MockSynchronousYieldBankAdapter,
    MockYieldBankAggregator,
    MockYieldBankAsset,
    MockYieldBankEligibilityPolicy,
    MockYieldBankReferencePrice
} from "../mocks/MockYieldBankIntegrations.sol";
import { PriceHub } from "../../src/yield-banks/PriceHub.sol";
import { StrategyRegistry } from "../../src/yield-banks/StrategyRegistry.sol";
import { BaseSleeve } from "../../src/yield-banks/sleeves/BaseSleeve.sol";
import { USDGSleeve } from "../../src/yield-banks/sleeves/USDGSleeve.sol";
import { IPriceHub } from "../../src/yield-banks/interfaces/IPriceHub.sol";
import {
    YieldBankAdapterRedemptionCall
} from "../../src/yield-banks/interfaces/IYieldBankManagedSleeve.sol";
import { YieldBankAdapterState } from "../../src/yield-banks/YieldBankTypes.sol";
import { YieldBankIds } from "../../src/yield-banks/libraries/YieldBankIds.sol";

contract MockOraclePauseAsset {
    bool public oraclePaused;

    function setOraclePaused(bool paused) external {
        oraclePaused = paused;
    }
}

contract YieldBankStrategyAndOracleTest is Test {
    MockYieldBankAsset private usdg;
    MockYieldBankAsset private reward;
    MockYieldBankAggregator private feed;
    MockYieldBankReferencePrice private referencePrice;
    MockYieldBankEligibilityPolicy private eligibility;
    PriceHub private priceHub;
    StrategyRegistry private registry;
    USDGSleeve private sleeve;
    MockSynchronousYieldBankAdapter private adapter;

    function setUp() external {
        usdg = new MockYieldBankAsset("USDG", "USDG");
        reward = new MockYieldBankAsset("Reward", "RWD");
        feed = new MockYieldBankAggregator(8, 1e8);
        referencePrice = new MockYieldBankReferencePrice();
        eligibility = new MockYieldBankEligibilityPolicy();
        priceHub = new PriceHub(address(this), address(this));
        registry = new StrategyRegistry(address(this));

        // Feed freshness in the fixture is anchored to the current test timestamp.
        // forge-lint: disable-next-line(block-timestamp)
        referencePrice.setPrice(1e18, uint48(block.timestamp));
        priceHub.configureFeed(
            address(usdg), address(feed), address(referencePrice), 1 days, 0, false, 100
        );
        MockYieldBankAggregator rewardFeed = new MockYieldBankAggregator(8, 1e8);
        priceHub.configureFeed(
            address(reward), address(rewardFeed), address(0), 1 days, 0, false, 100
        );
        sleeve = new USDGSleeve(
            "Test USDG Sleeve",
            "T-USDG",
            address(usdg),
            address(this),
            address(this),
            address(this),
            address(priceHub),
            address(registry),
            address(eligibility),
            1,
            5_000,
            100
        );
        adapter =
            new MockSynchronousYieldBankAdapter(address(sleeve), address(usdg), address(reward));
        registry.register(address(adapter), YieldBankIds.USDG);
    }

    function testPriceHubNormalizesAndFailsClosed() external {
        (uint256 price, uint48 pricedAt, IPriceHub.FailureReason failure) =
            priceHub.quoteUsd18(address(usdg));
        assertEq(price, 1e18);
        assertGt(pricedAt, 0);
        assertEq(uint8(failure), uint8(IPriceHub.FailureReason.NONE));

        priceHub.setCorporateActionPaused(address(usdg), true);
        (price,, failure) = priceHub.quoteUsd18(address(usdg));
        assertEq(price, 0);
        assertEq(uint8(failure), uint8(IPriceHub.FailureReason.CORPORATE_ACTION_PAUSED));
        priceHub.setCorporateActionPaused(address(usdg), false);

        feed.setAnswer(1e8, 1);
        vm.warp(2 days);
        (price,, failure) = priceHub.quoteUsd18(address(usdg));
        assertEq(price, 0);
        assertEq(uint8(failure), uint8(IPriceHub.FailureReason.STALE_FEED));
    }

    function testPriceHubRejectsIncompleteAndInvalidRounds() external {
        feed.setRoundIdentity(2, 1);
        (uint256 price,, IPriceHub.FailureReason failure) = priceHub.quoteUsd18(address(usdg));
        assertEq(price, 0);
        assertEq(uint8(failure), uint8(IPriceHub.FailureReason.STALE_FEED));

        feed.setRoundIdentity(0, 0);
        (price,, failure) = priceHub.quoteUsd18(address(usdg));
        assertEq(price, 0);
        assertEq(uint8(failure), uint8(IPriceHub.FailureReason.STALE_FEED));

        feed.setRoundIdentity(3, 3);
        feed.setRound(1e8, block.timestamp, block.timestamp - 1);
        (price,, failure) = priceHub.quoteUsd18(address(usdg));
        assertEq(price, 0);
        assertEq(uint8(failure), uint8(IPriceHub.FailureReason.STALE_FEED));
    }

    function testPriceHubReadsStockTokenOraclePauseDirectly() external {
        MockOraclePauseAsset asset = new MockOraclePauseAsset();
        MockYieldBankAggregator assetFeed = new MockYieldBankAggregator(8, 100e8);
        priceHub.configureFeed(
            address(asset), address(assetFeed), address(0), 1 days, 0, true, true, 100
        );

        asset.setOraclePaused(true);
        (uint256 price,, IPriceHub.FailureReason failure) = priceHub.quoteUsd18(address(asset));
        assertEq(price, 0);
        assertEq(uint8(failure), uint8(IPriceHub.FailureReason.CORPORATE_ACTION_PAUSED));

        asset.setOraclePaused(false);
        (price,, failure) = priceHub.quoteUsd18(address(asset));
        assertEq(price, 100e18);
        assertEq(uint8(failure), uint8(IPriceHub.FailureReason.NONE));
    }

    function testPriceHubFailsClosedWhenFeedIdentityChanges() external {
        feed.setDescription("DIFFERENT / USD");
        (uint256 price,, IPriceHub.FailureReason failure) = priceHub.quoteUsd18(address(usdg));
        assertEq(price, 0);
        assertEq(uint8(failure), uint8(IPriceHub.FailureReason.FEED_IDENTITY_MISMATCH));

        feed.setDescription("MOCK / USD");
        vm.etch(address(referencePrice), hex"00");
        (price,, failure) = priceHub.quoteUsd18(address(usdg));
        assertEq(price, 0);
        assertEq(uint8(failure), uint8(IPriceHub.FailureReason.FEED_IDENTITY_MISMATCH));
    }

    function testUsdGSleeveHoldsUsdGDirectlyWithoutAnAdapter() external {
        usdg.mint(address(this), 1_000e18);
        usdg.approve(address(sleeve), 1_000e18);
        uint256 shares = sleeve.deposit(1_000e18, address(this), 999e18, "");

        assertEq(shares, 1_000e18);
        assertEq(usdg.balanceOf(address(sleeve)), 1_000e18);
        assertEq(sleeve.activeStrategyCount(), 0);
    }

    function testManualSynchronousAdapterLifecycle() external {
        usdg.mint(address(this), 1_000e18);
        usdg.approve(address(sleeve), 1_000e18);
        sleeve.deposit(1_000e18, address(this), 999e18, "");

        sleeve.addAdapter(address(adapter), 5_000);
        assertEq(uint8(sleeve.adapterState(address(adapter))), uint8(YieldBankAdapterState.ACTIVE));
        uint256 units = sleeve.depositToAdapter(address(adapter), 500e18, 500e18, "");
        assertEq(units, 500e18);
        assertEq(usdg.allowance(address(sleeve), address(adapter)), 0);

        vm.expectRevert(
            abi.encodeWithSelector(BaseSleeve.CapExceeded.selector, uint256(100), uint256(101))
        );
        sleeve.withdrawFromAdapter(address(adapter), 1e18, 101, "");
        assertEq(sleeve.withdrawFromAdapter(address(adapter), 100e18, 100, ""), 100e18);

        reward.mint(address(this), 25e18);
        reward.approve(address(adapter), 25e18);
        adapter.addRewards(25e18);
        (address[] memory assets, uint256[] memory amounts) =
            sleeve.collectAdapter(address(adapter), "");
        assertEq(assets[0], address(reward));
        assertEq(amounts[0], 25e18);
        assertEq(reward.balanceOf(address(sleeve)), 25e18);

        sleeve.pauseAdapterDeposits(address(adapter));
        vm.expectRevert();
        sleeve.depositToAdapter(address(adapter), 1e18, 1e18, "");
        sleeve.setExitOnly(address(adapter));
        sleeve.exitAdapter(address(adapter), 100, "");
        assertEq(adapter.totalManagedAssets(), 0);
        sleeve.retireAdapter(address(adapter));
        assertEq(uint8(sleeve.adapterState(address(adapter))), uint8(YieldBankAdapterState.RETIRED));
    }

    function testAdapterCapUsesWholeSleeveNavIncludingDirectInventory() external {
        usdg.mint(address(this), 1_000e18);
        usdg.approve(address(sleeve), 1_000e18);
        sleeve.deposit(1_000e18, address(this), 999e18, "");
        sleeve.addAdapter(address(adapter), 5_000);

        reward.mint(address(sleeve), 1_000e18);
        uint256 units = sleeve.depositToAdapter(address(adapter), 1_000e18, 1_000e18, "");

        assertEq(units, 1_000e18);
        assertEq(adapter.totalManagedAssets(), 1_000e18);
        (uint256 navUsd18,) = sleeve.totalAssetsUsd18();
        assertEq(navUsd18, 2_000e18);
    }

    function testManagedRedemptionUnwindsOnlyTheOwnersProRataAdapterPosition() external {
        usdg.mint(address(this), 1_000e18);
        usdg.approve(address(sleeve), 1_000e18);
        sleeve.deposit(1_000e18, address(this), 999e18, "");
        sleeve.addAdapter(address(adapter), 5_000);
        sleeve.depositToAdapter(address(adapter), 500e18, 500e18, "");

        uint256[] memory minimumOutputs = new uint256[](2);
        minimumOutputs[0] = 100e18;
        YieldBankAdapterRedemptionCall[] memory calls = new YieldBankAdapterRedemptionCall[](1);
        calls[0] =
            YieldBankAdapterRedemptionCall({ adapter: address(adapter), maxLossBps: 0, data: "" });
        (address[] memory assets, uint256[] memory amounts) =
            sleeve.redeemManaged(100e18, address(this), address(this), minimumOutputs, calls);

        assertEq(assets[0], address(usdg));
        assertEq(amounts[0], 100e18);
        assertEq(usdg.balanceOf(address(this)), 100e18);
        assertEq(sleeve.balanceOf(address(this)), 900e18);
        assertEq(sleeve.totalSupply(), 900e18);
        assertEq(adapter.totalManagedAssets(), 450e18);
        assertEq(usdg.balanceOf(address(sleeve)), 450e18);
    }

    function testFullManagedRedemptionReturnsAllAdapterAssetsAndSurplus() external {
        usdg.mint(address(this), 1_025e18);
        usdg.approve(address(sleeve), 1_000e18);
        uint256 shares = sleeve.deposit(1_000e18, address(this), 999e18, "");
        sleeve.addAdapter(address(adapter), 5_000);
        sleeve.depositToAdapter(address(adapter), 500e18, 500e18, "");
        usdg.transfer(address(adapter), 25e18);

        reward.mint(address(this), 20e18);
        reward.approve(address(adapter), 20e18);
        adapter.addRewards(20e18);

        uint256[] memory minimumOutputs = new uint256[](2);
        minimumOutputs[0] = 1_025e18;
        minimumOutputs[1] = 20e18;
        YieldBankAdapterRedemptionCall[] memory calls = new YieldBankAdapterRedemptionCall[](1);
        calls[0] =
            YieldBankAdapterRedemptionCall({ adapter: address(adapter), maxLossBps: 0, data: "" });
        (address[] memory assets, uint256[] memory amounts) =
            sleeve.redeemManaged(shares, address(this), address(this), minimumOutputs, calls);

        assertEq(assets[0], address(usdg));
        assertEq(assets[1], address(reward));
        assertEq(amounts[0], 1_025e18);
        assertEq(amounts[1], 20e18);
        assertEq(sleeve.totalSupply(), 0);
        assertEq(usdg.balanceOf(address(sleeve)), 0);
        assertEq(reward.balanceOf(address(sleeve)), 0);
        assertEq(usdg.balanceOf(address(adapter)), 0);
        assertEq(reward.balanceOf(address(adapter)), 0);
        assertEq(adapter.totalManagedAssets(), 0);
        assertEq(adapter.totalPositionUnits(), 0);
    }

    function testRegistryBindingPreventsAdapterReuseByAnotherSleeve() external {
        USDGSleeve otherSleeve = new USDGSleeve(
            "Other USDG Sleeve",
            "O-USDG",
            address(usdg),
            address(this),
            address(this),
            address(this),
            address(priceHub),
            address(registry),
            address(eligibility),
            1,
            5_000,
            100
        );
        vm.expectRevert();
        otherSleeve.addAdapter(address(adapter), 1_000);
    }

    function testAdapterCannotOmitTransferredInventoryFromItsReport() external {
        usdg.mint(address(this), 1_000e18);
        usdg.approve(address(sleeve), 1_000e18);
        sleeve.deposit(1_000e18, address(this), 999e18, "");
        sleeve.addAdapter(address(adapter), 5_000);

        reward.mint(address(this), 25e18);
        reward.approve(address(adapter), 25e18);
        adapter.addRewards(25e18);
        adapter.setOmitCollectReport(true);

        vm.expectRevert(abi.encodeWithSelector(BaseSleeve.InexactReceipt.selector, 0, 25e18));
        sleeve.collectAdapter(address(adapter), "");
        assertEq(reward.balanceOf(address(adapter)), 25e18);
        assertEq(reward.balanceOf(address(sleeve)), 0);
    }
}
