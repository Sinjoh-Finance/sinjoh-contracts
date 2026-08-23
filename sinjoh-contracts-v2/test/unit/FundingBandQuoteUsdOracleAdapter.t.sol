// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import {
    FundingBandQuoteUsdOracleAdapter
} from "../../src/bands/FundingBandQuoteUsdOracleAdapter.sol";
import { MockBasketAsset } from "../mocks/MockBasketIntegrations.sol";

contract MockQuoteUsdAggregator {
    uint8 public constant decimals = 8;
    uint80 public roundId;
    int256 public answer;
    uint256 public startedAt;
    uint256 public updatedAt;
    uint80 public answeredInRound;

    function setRound(
        uint80 roundId_,
        int256 answer_,
        uint256 startedAt_,
        uint256 updatedAt_,
        uint80 answeredInRound_
    ) external {
        roundId = roundId_;
        answer = answer_;
        startedAt = startedAt_;
        updatedAt = updatedAt_;
        answeredInRound = answeredInRound_;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}

contract FundingBandQuoteUsdOracleAdapterTest is Test {
    MockBasketAsset private quote;
    MockQuoteUsdAggregator private aggregator;
    FundingBandQuoteUsdOracleAdapter private oracle;

    function setUp() public {
        vm.warp(1_000_000);
        quote = new MockBasketAsset("Quote", "QUOTE");
        aggregator = new MockQuoteUsdAggregator();
        oracle = new FundingBandQuoteUsdOracleAdapter(address(quote), address(aggregator));
    }

    function testReturnsCompleteEightDecimalObservation() public {
        aggregator.setRound(7, 3_500e8, block.timestamp - 20, block.timestamp - 10, 7);
        (uint256 price, uint48 observedAt, bytes32 observationId) = oracle.latestPriceUsdE8();
        assertEq(price, 3_500e8);
        assertEq(observedAt, block.timestamp - 10);
        assertNotEq(observationId, bytes32(0));
    }

    function testRejectsIncompleteNonpositiveAndFutureRounds() public {
        aggregator.setRound(7, 0, block.timestamp - 20, block.timestamp - 10, 7);
        vm.expectRevert(FundingBandQuoteUsdOracleAdapter.InvalidObservation.selector);
        oracle.latestPriceUsdE8();

        aggregator.setRound(7, 3_500e8, block.timestamp - 20, block.timestamp - 10, 6);
        vm.expectRevert(FundingBandQuoteUsdOracleAdapter.InvalidObservation.selector);
        oracle.latestPriceUsdE8();

        aggregator.setRound(7, 3_500e8, block.timestamp, block.timestamp + 1, 7);
        vm.expectRevert(FundingBandQuoteUsdOracleAdapter.InvalidObservation.selector);
        oracle.latestPriceUsdE8();
    }

    function testRejectsDependencyCodeDrift() public {
        vm.etch(address(quote), hex"00");
        vm.expectRevert(
            abi.encodeWithSelector(
                FundingBandQuoteUsdOracleAdapter.DependencyChanged.selector, address(quote)
            )
        );
        oracle.latestPriceUsdE8();
    }
}
