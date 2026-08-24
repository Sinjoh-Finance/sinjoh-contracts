// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { FundingBandConfig, FundingBandDestination } from "../../src/bands/FundingBandTypes.sol";
import { FundingBandsTestBase } from "../FundingBandsTestBase.sol";

contract ProjectFundingBandsDestinationsV2IntegrationTest is FundingBandsTestBase {
    function setUp() public {
        _setUpFundingBands();
    }

    function testE2EPostLaunchBandsSettleThroughEveryTypedDestination() public {
        _createAndSettle(_destinationConfig(FundingBandDestination.CREATOR, ""));
        _createAndSettle(_destinationConfig(FundingBandDestination.TREASURY, ""));
        _createAndSettle(_destinationConfig(FundingBandDestination.ROUTER, ""));
        _createAndSettle(_destinationConfig(FundingBandDestination.RAFFLE, hex"1234"));
        _createAndSettle(_destinationConfig(FundingBandDestination.BASKET_VIA_TREASURY, ""));

        subject.mint(address(swapAdapter), 990e18);
        uint256 supplyBeforeBurn = subject.totalSupply();
        swapAdapter.configure(990e18, type(uint256).max, false);
        priceGuard.setQuote(990e18, uint48(block.timestamp + 1 days));
        _createAndSettle(_buybackConfig(FundingBandDestination.BUYBACK_BURN, ""));
        assertEq(subject.totalSupply(), supplyBeforeBurn - 1_000e18);

        subject.mint(address(swapAdapter), 990e18);
        swapAdapter.configure(990e18, type(uint256).max, false);
        priceGuard.setQuote(990e18, uint48(block.timestamp + 1 days));
        _createAndSettle(_buybackConfig(FundingBandDestination.BUYBACK_AIRDROP, hex"cafe"));

        assertEq(bands.nextBandId(), 8);
        assertEq(bands.liveBandCount(), 0);
        assertGt(quote.balanceOf(CREATOR), 0);
        assertGt(treasury.funded(address(quote)), 0);
        assertGt(treasury.basketRouted(address(quote)), 0);
        assertGt(router.funded(address(quote)), 0);
        assertGt(raffle.funded(address(quote)), 0);
        assertEq(airdrop.funded(address(subject)), 1_000e18);
        assertEq(bands.protocolOwed(address(quote)), 70e18);
    }
}
