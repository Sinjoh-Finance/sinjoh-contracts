// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { AddressGovernanceController } from "../src/governance/AddressGovernanceController.sol";
import { IGovernanceController } from "../src/interfaces/IGovernanceController.sol";
import { DynamicFundingBands } from "../src/DynamicFundingBands.sol";
import { TestBase } from "./TestBase.sol";
import { MockERC20, MockTwapOracle } from "./mocks/Mocks.sol";

contract DynamicFundingBandsTest is TestBase {
    address private constant GUARDIAN = address(0xBEEF);
    address private constant PROTOCOL = address(0xFEE);
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);

    MockERC20 private subject;
    MockERC20 private funding;
    MockTwapOracle private oracle;
    DynamicFundingBands private bands;

    function setUp() public {
        AddressGovernanceController controller =
            new AddressGovernanceController(address(this), IGovernanceController.Mode.INDIVIDUAL);
        subject = new MockERC20();
        funding = new MockERC20();
        oracle = new MockTwapOracle();
        bands = new DynamicFundingBands(controller, GUARDIAN, oracle, 1 hours, PROTOCOL);
    }

    function testBelowMarketBandCanActivateAndRedeem() public {
        uint256 bandId = _create(10_000, 70e18, 90e18, 500);
        assertEq(bands.committedByAsset(address(funding)), 10_000);
        assertEq(bands.committedBySubject(address(subject), address(funding)), 10_000);
        vm.warp(1 hours + 1);
        bands.activate(bandId);
        oracle.setPrice(80e18);
        bands.observe(bandId);
        assertTrue(bands.confirmationExecutableAt(bandId) != 0);
        vm.warp(1 hours + 5 minutes + 1);
        oracle.setPrice(80e18);
        bands.redeem(bandId);
        assertEq(funding.balanceOf(ALICE), 9_900);
        assertEq(funding.balanceOf(PROTOCOL), 100);
        assertEq(bands.committedByAsset(address(funding)), 0);
    }

    function testRangeCannotStraddleCurrentPriceOrIgnoreMinimumDistance() public {
        _expectInvalid(10_000, 90e18, 110e18, 0);
        _expectInvalid(10_000, 104e18, 120e18, 500);
    }

    function testPendingCancellationAndExpiryReturnAllPrefunding() public {
        uint256 cancelled = _create(10_000, 110e18, 120e18, 500);
        bands.cancelPending(cancelled);
        assertEq(funding.balanceOf(BOB), 10_000);
        assertTrue(bands.bandStatus(cancelled) == DynamicFundingBands.BandStatus.CANCELLED);

        uint256 expired = _create(20_000, 110e18, 120e18, 500);
        vm.warp(8 days);
        bands.expire(expired);
        assertEq(funding.balanceOf(BOB), 30_000);
        assertEq(bands.totalCommitted(), 0);
    }

    function testOutOfRangeObservationDisarmsConfirmationClock() public {
        uint256 bandId = _create(10_000, 110e18, 130e18, 500);
        vm.warp(1 hours + 1);
        bands.activate(bandId);
        oracle.setPrice(120e18);
        bands.observe(bandId);
        assertTrue(bands.bandStatus(bandId) == DynamicFundingBands.BandStatus.ARMED);
        oracle.setPrice(140e18);
        bands.observe(bandId);
        assertTrue(bands.bandStatus(bandId) == DynamicFundingBands.BandStatus.ACTIVE);
        assertEq(bands.confirmationExecutableAt(bandId), 0);
    }

    function testConfirmationRestartsAfterAnObservationGap() public {
        uint256 bandId = _create(10_000, 110e18, 130e18, 500);
        vm.warp(1 hours + 1);
        bands.activate(bandId);
        oracle.setPrice(120e18);
        bands.observe(bandId);
        uint256 firstExecutableAt = bands.confirmationExecutableAt(bandId);
        vm.warp(block.timestamp + 5 minutes + 1);
        oracle.setPrice(120e18);
        bands.observe(bandId);
        assertTrue(bands.confirmationExecutableAt(bandId) > firstExecutableAt);
    }

    function testSelfFundedCreatorCanCancelBeforeActivation() public {
        DynamicFundingBands.BandInput memory template = DynamicFundingBands.BandInput({
            subject: address(subject),
            fundingAsset: address(funding),
            amount: 0,
            lowerPriceE18: 110e18,
            upperPriceE18: 120e18,
            activationDelay: 1 hours,
            lifetime: 7 days,
            confirmationPeriod: 5 minutes,
            twapWindow: 5 minutes,
            minimumDistanceBps: 500,
            recipient: ALICE,
            refundRecipient: BOB
        });
        funding.mint(BOB, 10_000);
        vm.startPrank(BOB);
        funding.approve(address(bands), 10_000);
        bands.fund(address(funding), 10_000, abi.encode(template));
        bands.cancelPending(1);
        vm.stopPrank();
        assertEq(funding.balanceOf(BOB), 10_000);
        assertTrue(bands.bandStatus(1) == DynamicFundingBands.BandStatus.CANCELLED);
    }

    function testProtocolFeeCannotBeAvoidedBySplittingRedemptions() public {
        uint256 first = _create(50, 110e18, 130e18, 500);
        uint256 second = _create(50, 110e18, 130e18, 500);
        vm.warp(1 hours + 1);
        bands.activate(first);
        bands.activate(second);
        oracle.setPrice(120e18);
        bands.observe(first);
        bands.observe(second);
        vm.warp(block.timestamp + 5 minutes);
        oracle.setPrice(120e18);
        bands.redeem(first);
        bands.redeem(second);
        assertEq(bands.cumulativeRedeemed(address(funding)), 100);
        assertEq(bands.cumulativeProtocolFee(address(funding)), 1);
        assertEq(funding.balanceOf(ALICE), 99);
        assertEq(funding.balanceOf(PROTOCOL), 1);
    }

    function testFuzzBandDistanceBoundary(uint16 rawDistanceBps) public {
        uint16 distanceBps = uint16(uint256(rawDistanceBps) % 5_001);
        uint256 lower = 100e18 + uint256(100e18) * uint256(distanceBps) / 10_000;
        if (distanceBps < 500) {
            _expectInvalid(10_000, lower, lower + 10e18, 500);
        } else {
            uint256 bandId = _create(10_000, lower, lower + 10e18, 500);
            assertTrue(bandId != 0);
        }
    }

    function _create(uint128 amount, uint256 lower, uint256 upper, uint16 distanceBps)
        private
        returns (uint256)
    {
        funding.mint(address(this), amount);
        funding.approve(address(bands), amount);
        return bands.createBand(
            DynamicFundingBands.BandInput({
                subject: address(subject),
                fundingAsset: address(funding),
                amount: amount,
                lowerPriceE18: uint128(lower),
                upperPriceE18: uint128(upper),
                activationDelay: 1 hours,
                lifetime: 7 days,
                confirmationPeriod: 5 minutes,
                twapWindow: 5 minutes,
                minimumDistanceBps: distanceBps,
                recipient: ALICE,
                refundRecipient: BOB
            })
        );
    }

    function _expectInvalid(uint128 amount, uint256 lower, uint256 upper, uint16 distanceBps)
        private
    {
        funding.mint(address(this), amount);
        funding.approve(address(bands), amount);
        vm.expectRevert(DynamicFundingBands.InvalidConfiguration.selector);
        bands.createBand(
            DynamicFundingBands.BandInput({
                subject: address(subject),
                fundingAsset: address(funding),
                amount: amount,
                lowerPriceE18: uint128(lower),
                upperPriceE18: uint128(upper),
                activationDelay: 1 hours,
                lifetime: 7 days,
                confirmationPeriod: 5 minutes,
                twapWindow: 5 minutes,
                minimumDistanceBps: distanceBps,
                recipient: ALICE,
                refundRecipient: BOB
            })
        );
    }
}
