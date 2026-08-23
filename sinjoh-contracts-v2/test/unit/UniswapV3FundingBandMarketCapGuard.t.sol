// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { FundingBandObservation } from "../../src/bands/FundingBandTypes.sol";
import {
    UniswapV3FundingBandMarketCapGuard
} from "../../src/bands/UniswapV3FundingBandMarketCapGuard.sol";
import { MockERC20 } from "../mocks/liquidity/MockERC20.sol";
import {
    MockFundingBandQuoteUsdOracle,
    MockV3BandFactory,
    MockV3BandPool
} from "../mocks/MockUniswapV3BandPosition.sol";

contract UniswapV3FundingBandMarketCapGuardTest is Test {
    uint256 private constant REFERENCE_SUPPLY = 1_000_000e18;
    uint128 private constant LOWER = 2_000_000e8;
    uint128 private constant UPPER = 3_000_000e8;

    MockERC20 private subject;
    MockERC20 private quote;
    MockV3BandFactory private factory;
    MockV3BandPool private pool;

    function setUp() public {
        subject = new MockERC20("Subject", "SUB");
        quote = new MockERC20("Quote USD", "QUSD");
        factory = new MockV3BandFactory();
        address token0 = address(subject) < address(quote) ? address(subject) : address(quote);
        address token1 = address(subject) < address(quote) ? address(quote) : address(subject);
        pool = new MockV3BandPool(address(factory), token0, token1, 3_000, 10);
        factory.setPool(token0, token1, 3_000, address(pool));
        vm.warp(1_000_000);
    }

    function testFixedUsdTwapReturnsFdvAndStableEffectiveTicks() public {
        UniswapV3FundingBandMarketCapGuard guard = _deploy(address(0), 1e8, 1 hours);
        FundingBandObservation memory observation = guard.observe(LOWER, UPPER, "");
        assertEq(observation.marketCapUsdE8, 1_000_000e8);
        assertEq(observation.observedAt, block.timestamp);
        assertNotEq(observation.observationId, bytes32(0));
        assertLt(observation.effectiveLowerTick, observation.effectiveUpperTick);
        assertEq(observation.effectiveLowerTick % pool.tickSpacing(), 0);
        assertEq(observation.effectiveUpperTick % pool.tickSpacing(), 0);
        assertEq(guard.marketCapAtTick(0, 1e8), 1_000_000e8);

        (int24 lower, int24 upper) = guard.effectiveTicks(LOWER, UPPER);
        assertEq(lower, observation.effectiveLowerTick);
        assertEq(upper, observation.effectiveUpperTick);
    }

    function testLiveQuoteOracleChangesFdvWithoutMovingFundedTickRanges() public {
        MockFundingBandQuoteUsdOracle oracle = new MockFundingBandQuoteUsdOracle(address(quote));
        oracle.setObservation(2e8, uint48(block.timestamp), bytes32(uint256(1)));
        UniswapV3FundingBandMarketCapGuard guard = _deploy(address(oracle), 1e8, 1 hours);
        FundingBandObservation memory first = guard.observe(LOWER, UPPER, "");
        assertEq(first.marketCapUsdE8, 2_000_000e8);

        vm.warp(block.timestamp + 60);
        oracle.setObservation(3e8, uint48(block.timestamp), bytes32(uint256(2)));
        FundingBandObservation memory second = guard.observe(LOWER, UPPER, "");
        assertEq(second.marketCapUsdE8, 3_000_000e8);
        assertEq(second.effectiveLowerTick, first.effectiveLowerTick);
        assertEq(second.effectiveUpperTick, first.effectiveUpperTick);
        assertNotEq(second.observationId, first.observationId);
    }

    function testStaleQuoteAndUnreadyPoolFailClosed() public {
        MockFundingBandQuoteUsdOracle oracle = new MockFundingBandQuoteUsdOracle(address(quote));
        oracle.setObservation(1e8, uint48(block.timestamp - 61), bytes32(uint256(1)));
        vm.expectRevert(UniswapV3FundingBandMarketCapGuard.InvalidQuoteUsdObservation.selector);
        _deploy(address(oracle), 1e8, 60);

        pool.setObservationCardinality(1);
        UniswapV3FundingBandMarketCapGuard fixedGuard = _deploy(address(0), 1e8, 1 hours);
        vm.expectRevert(UniswapV3FundingBandMarketCapGuard.OracleNotReady.selector);
        fixedGuard.observe(LOWER, UPPER, "");
        fixedGuard.preparePoolOracle();
        assertEq(pool.observationCardinalityNext(), 2);
    }

    function testRejectsCallerSuppliedObservationDataAndCollapsedBounds() public {
        UniswapV3FundingBandMarketCapGuard guard = _deploy(address(0), 1e8, 1 hours);
        vm.expectRevert(UniswapV3FundingBandMarketCapGuard.InvalidObservationData.selector);
        guard.observe(LOWER, UPPER, hex"01");

        vm.expectPartialRevert(UniswapV3FundingBandMarketCapGuard.EffectiveTicksCollapsed.selector);
        guard.effectiveTicks(1_000_000e8, 1_000_001e8);
    }

    function _deploy(address oracle, uint256 referenceQuoteUsdE8, uint48 maximumOracleAge)
        private
        returns (UniswapV3FundingBandMarketCapGuard)
    {
        if (oracle == address(0)) {
            MockFundingBandQuoteUsdOracle deployedOracle =
                new MockFundingBandQuoteUsdOracle(address(quote));
            deployedOracle.setObservation(
                referenceQuoteUsdE8, uint48(block.timestamp), keccak256("QUOTE")
            );
            oracle = address(deployedOracle);
        }
        return new UniswapV3FundingBandMarketCapGuard(
            address(0xB4D5),
            address(subject),
            address(quote),
            address(pool),
            address(factory),
            REFERENCE_SUPPLY,
            15 minutes,
            oracle,
            maximumOracleAge
        );
    }
}
