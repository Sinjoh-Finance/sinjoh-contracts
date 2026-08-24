// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { FundingBandDestination } from "../../src/bands/FundingBandTypes.sol";
import { ProjectFundingBandsV2 } from "../../src/bands/ProjectFundingBandsV2.sol";
import { FundingBandsTestBase } from "../FundingBandsTestBase.sol";

contract ProjectFundingBandsV2FuzzTest is FundingBandsTestBase {
    function setUp() public {
        _setUpFundingBands();
    }

    function testFuzzCreationUsesCurrentMarketCapOnly(uint128 rawAmount, uint128 rawMarketCap)
        public
    {
        uint128 amount = uint128(bound(uint256(rawAmount), 1, 100_000e18));
        uint256 marketCap = bound(uint256(rawMarketCap), 1, uint256(UPPER));
        assertTrue(subject.transfer(address(bands), amount));
        _setObservation(marketCap, keccak256(abi.encode("market-cap", marketCap)));

        if (marketCap < LOWER) {
            projectController.execute(
                address(bands),
                abi.encodeCall(
                    bands.createBand, (_config(amount, FundingBandDestination.CREATOR), bytes(""))
                )
            );
            (ProjectFundingBandsV2.Band memory active,) = bands.bandStatus(1);
            assertEq(active.committedSubject, amount);
        } else {
            vm.expectPartialRevert(ProjectFundingBandsV2.MarketCapNotBelowBand.selector);
            projectController.execute(
                address(bands),
                abi.encodeCall(
                    bands.createBand, (_config(amount, FundingBandDestination.CREATOR), bytes(""))
                )
            );
        }
    }

    function testFuzzSettlementChargesExactlyOnePercent(uint128 rawInventory, uint128 rawQuote)
        public
    {
        uint128 inventory = uint128(bound(uint256(rawInventory), 1, 100_000e18));
        uint256 grossQuote = bound(uint256(rawQuote), 1, 1_000_000e18);
        uint256 bandId = _createBand(inventory, FundingBandDestination.CREATOR);
        _setObservation(UPPER, keccak256("arm"));
        bands.armSettlement(bandId, "");
        vm.warp(block.timestamp + 15 minutes);
        _setObservation(UPPER, keccak256("settle"));
        positionAdapter.configureSettlement(0, grossQuote);
        quote.mint(address(positionAdapter), grossQuote);
        bands.settle(bandId, "");

        uint256 expectedFee = grossQuote * 100 / 10_000;
        assertEq(bands.protocolOwed(address(quote)), expectedFee);
        assertEq(quote.balanceOf(CREATOR), grossQuote - expectedFee);
    }

    function testFuzzSplitFundingPreservesExactCommittedInventory(
        uint128 rawInitial,
        uint128 rawAdditional
    ) public {
        uint128 initial = uint128(bound(uint256(rawInitial), 1, 400_000e18));
        uint128 additional = uint128(bound(uint256(rawAdditional), 1, 400_000e18));
        uint256 bandId = _createBand(initial, FundingBandDestination.CREATOR);
        assertTrue(subject.transfer(address(bands), additional));
        _setObservation(LOWER - 1, keccak256("increase"));
        projectController.execute(
            address(bands), abi.encodeCall(bands.increaseBand, (bandId, additional, bytes("")))
        );

        (ProjectFundingBandsV2.Band memory active,) = bands.bandStatus(bandId);
        assertEq(active.committedSubject, uint256(initial) + additional);
        assertEq(active.liquidity, uint256(initial) + additional);
        assertEq(positionAdapter.positionLiquidity(active.positionId), active.liquidity);
    }

    function testFuzzSplitSettlementCannotReduceCumulativeFee(uint128 rawFirst, uint128 rawSecond)
        public
    {
        uint256 first = bound(uint256(rawFirst), 1, 1_000_000e18);
        uint256 second = bound(uint256(rawSecond), 1, 1_000_000e18);
        _settleCreatorBand(first, keccak256("first"));
        _settleCreatorBand(second, keccak256("second"));

        assertEq(bands.protocolOwed(address(quote)), (first + second) * 100 / 10_000);
        assertLt(bands.feeRemainder(), 10_000);
    }

    function testFuzzTokenBurnCannotMoveReferenceSupplyOrBandBounds(uint128 rawBurn) public {
        uint256 burnAmount = bound(uint256(rawBurn), 1, subject.balanceOf(address(this)) / 2);
        subject.burn(burnAmount);

        assertEq(bands.referenceSupply(), referenceSupply);
        uint256 bandId = _createBand(1e18, FundingBandDestination.CREATOR);
        (ProjectFundingBandsV2.Band memory active,) = bands.bandStatus(bandId);
        assertEq(active.lowerMarketCapUsdE8, LOWER);
        assertEq(active.upperMarketCapUsdE8, UPPER);
    }

    function _settleCreatorBand(uint256 quoteAmount, bytes32 salt) private {
        uint256 bandId = _createBand(1e18, FundingBandDestination.CREATOR);
        _setObservation(UPPER, keccak256(abi.encode("arm", salt)));
        bands.armSettlement(bandId, "");
        vm.warp(vm.getBlockTimestamp() + 15 minutes);
        _setObservation(UPPER, keccak256(abi.encode("settle", salt)));
        positionAdapter.configureSettlement(0, quoteAmount);
        quote.mint(address(positionAdapter), quoteAmount);
        bands.settle(bandId, "");
    }
}
