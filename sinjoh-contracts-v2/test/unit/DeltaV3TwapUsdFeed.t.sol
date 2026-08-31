// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { DeltaV3TwapUsdFeed } from "../../src/yield-banks/adapters/DeltaV3TwapUsdFeed.sol";
import { PriceHub } from "../../src/yield-banks/PriceHub.sol";
import { IPriceHub } from "../../src/yield-banks/interfaces/IPriceHub.sol";
import { MockDeltaV3Factory, MockDeltaV3Pool } from "../mocks/MockDeltaIntegrations.sol";
import {
    MockYieldBankAggregator,
    MockYieldBankAsset
} from "../mocks/MockYieldBankIntegrations.sol";

contract MockSixDecimalWeth is MockYieldBankAsset {
    constructor() MockYieldBankAsset("Wrong Wrapped Ether", "WWETH") { }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

contract DeltaV3TwapUsdFeedTest is Test {
    MockYieldBankAsset private weth;
    MockYieldBankAsset private pairedAsset;
    MockYieldBankAggregator private wethUsdFeed;
    MockDeltaV3Factory private factory;
    MockDeltaV3Pool private pool;
    DeltaV3TwapUsdFeed private feed;

    function setUp() external {
        vm.warp(2 days);
        weth = new MockYieldBankAsset("Wrapped Ether", "WETH");
        pairedAsset = new MockYieldBankAsset("Project Token", "PROJECT");
        wethUsdFeed = new MockYieldBankAggregator(8, 2_500e8);
        factory = new MockDeltaV3Factory();
        pool = new MockDeltaV3Pool(address(factory), address(weth), address(pairedAsset), 3_000, 60);
        factory.setPool(address(weth), address(pairedAsset), 3_000, address(pool));
        feed = new DeltaV3TwapUsdFeed(
            address(pairedAsset),
            address(weth),
            address(pool),
            address(factory),
            address(wethUsdFeed),
            address(pool).codehash,
            address(factory).codehash,
            address(wethUsdFeed).codehash,
            30 minutes,
            500,
            1e18,
            1e12,
            "PROJECT / USD (Delta V3 TWAP)"
        );
    }

    function testDerivesPairedAssetUsdFromTwapAndWethUsd() external view {
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();
        assertEq(roundId, 1);
        assertEq(answer, 2_500e18);
        assertGt(startedAt, 0);
        assertEq(updatedAt, startedAt);
        assertEq(answeredInRound, roundId);
    }

    function testIntegratesWithPriceHubWithoutApplyingMultiplier() external {
        PriceHub hub = new PriceHub(address(this), address(this));
        hub.configureFeed(address(pairedAsset), address(feed), address(0), 1 days, 0, false, 500);
        (uint256 price,, IPriceHub.FailureReason failure) = hub.quoteUsd18(address(pairedAsset));
        assertEq(price, 2_500e18);
        assertEq(uint8(failure), uint8(IPriceHub.FailureReason.NONE));
    }

    function testRejectsSpotPriceThatDivergesFromTwap() external {
        pool.setPrice(TickMath.getSqrtPriceAtTick(1_000), 1_000);
        vm.expectPartialRevert(DeltaV3TwapUsdFeed.ExcessivePriceDeviation.selector);
        feed.latestRoundData();
    }

    function testRejectsUnderlyingFeedIdentityDrift() external {
        wethUsdFeed.setDescription("WRONG / USD");
        vm.expectRevert(
            abi.encodeWithSelector(
                DeltaV3TwapUsdFeed.DependencyChanged.selector, address(wethUsdFeed)
            )
        );
        feed.latestRoundData();
    }

    function testRequiresCardinalityAndAgedObservationHistory() external {
        pool.setObservationState(1, false);
        vm.expectRevert(DeltaV3TwapUsdFeed.OracleNotReady.selector);
        feed.latestRoundData();

        feed.preparePoolOracle();
        vm.expectRevert(DeltaV3TwapUsdFeed.OracleNotReady.selector);
        feed.latestRoundData();

        pool.setObservationState(2, true);
        (, int256 answer,,,) = feed.latestRoundData();
        assertGt(answer, 0);
    }

    function testRejectsPoolBelowReviewedMinimumLiquidity() external {
        pool.setLiquidity(1e12 - 1);
        vm.expectRevert(DeltaV3TwapUsdFeed.OracleNotReady.selector);
        feed.latestRoundData();
    }

    function testRejectsNon18DecimalWethBecauseValuationUsesWei() external {
        MockSixDecimalWeth wrongWeth = new MockSixDecimalWeth();
        MockDeltaV3Pool wrongPool = new MockDeltaV3Pool(
            address(factory), address(wrongWeth), address(pairedAsset), 3_000, 60
        );
        factory.setPool(address(wrongWeth), address(pairedAsset), 3_000, address(wrongPool));
        vm.expectRevert(DeltaV3TwapUsdFeed.InvalidConfiguration.selector);
        new DeltaV3TwapUsdFeed(
            address(pairedAsset),
            address(wrongWeth),
            address(wrongPool),
            address(factory),
            address(wethUsdFeed),
            address(wrongPool).codehash,
            address(factory).codehash,
            address(wethUsdFeed).codehash,
            30 minutes,
            500,
            1e18,
            1e12,
            "PROJECT / USD (Delta V3 TWAP)"
        );
    }
}
