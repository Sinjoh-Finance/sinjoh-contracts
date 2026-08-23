// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import {
    FundingBandV3IntegrationConfig,
    FundingBandV3IntegrationFactory
} from "../../src/bands/FundingBandV3IntegrationFactory.sol";
import {
    UniswapV3FundingBandMarketCapGuard
} from "../../src/bands/UniswapV3FundingBandMarketCapGuard.sol";
import {
    UniswapV3FundingBandPositionAdapter
} from "../../src/bands/UniswapV3FundingBandPositionAdapter.sol";
import { MockERC20 } from "../mocks/liquidity/MockERC20.sol";
import {
    MockFundingBandQuoteUsdOracle,
    MockV3BandFactory,
    MockV3BandPool,
    MockV3BandPositionManager
} from "../mocks/MockUniswapV3BandPosition.sol";

contract FundingBandV3IntegrationFactoryTest is Test {
    function testPredictionDeploymentAndRepeatCallAreDeterministic() public {
        MockERC20 subject = new MockERC20("Subject", "SUB");
        MockERC20 quote = new MockERC20("Quote", "USD");
        MockV3BandFactory v3Factory = new MockV3BandFactory();
        address token0 = address(subject) < address(quote) ? address(subject) : address(quote);
        address token1 = address(subject) < address(quote) ? address(quote) : address(subject);
        MockV3BandPool pool = new MockV3BandPool(address(v3Factory), token0, token1, 3_000, 60);
        v3Factory.setPool(token0, token1, 3_000, address(pool));
        MockV3BandPositionManager manager = new MockV3BandPositionManager(address(v3Factory));
        FundingBandV3IntegrationFactory integrationFactory =
            new FundingBandV3IntegrationFactory(address(v3Factory), address(manager));
        MockFundingBandQuoteUsdOracle oracle = new MockFundingBandQuoteUsdOracle(address(quote));
        oracle.setObservation(1e8, uint48(block.timestamp), keccak256("QUOTE"));
        FundingBandV3IntegrationConfig memory config = FundingBandV3IntegrationConfig({
            bandsContract: address(0xB4D5),
            subject: address(subject),
            quoteAsset: address(quote),
            canonicalPool: address(pool),
            referenceSupply: 1_000_000e18,
            twapWindow: 15 minutes,
            quoteUsdOracle: address(oracle),
            maximumOracleAge: 1 hours
        });

        (address predictedGuard, address predictedAdapter) = integrationFactory.predict(config);
        (address guard, address adapter) = integrationFactory.deploy(config);
        assertEq(guard, predictedGuard);
        assertEq(adapter, predictedAdapter);
        assertEq(UniswapV3FundingBandMarketCapGuard(guard).bandsContract(), config.bandsContract);
        assertEq(
            UniswapV3FundingBandMarketCapGuard(guard).referenceSupply(), config.referenceSupply
        );
        assertEq(UniswapV3FundingBandPositionAdapter(adapter).bandsContract(), config.bandsContract);
        assertEq(UniswapV3FundingBandPositionAdapter(adapter).positionManager(), address(manager));

        (address repeatedGuard, address repeatedAdapter) = integrationFactory.deploy(config);
        assertEq(repeatedGuard, guard);
        assertEq(repeatedAdapter, adapter);
    }
}
