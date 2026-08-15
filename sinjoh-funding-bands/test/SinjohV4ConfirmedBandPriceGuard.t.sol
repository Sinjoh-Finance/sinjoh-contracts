// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ISinjohLaunchVerifier } from "../src/interfaces/ISinjohLaunchVerifier.sol";
import {
    SinjohV4ConfirmedBandPriceGuard
} from "../src/profiles/SinjohV4ConfirmedBandPriceGuard.sol";
import { SinjohV4DelayedBandPriceGuard } from "../src/profiles/SinjohV4DelayedBandPriceGuard.sol";
import { TestBase } from "./TestBase.sol";
import { MockV4PoolManager, MockV4StateView } from "./mocks/MockInfrastructure.sol";

contract SinjohV4ConfirmedBandPriceGuardTest is TestBase {
    uint256 internal constant OBSERVER_KEY = uint256(keccak256("funding-bands-observer"));
    address internal constant GOVERNANCE = address(0xA11CE);
    bytes32 internal constant POOL_ID = keccak256("confirmed-pool");
    int24 internal constant BOUNDARY = 1_000;

    MockV4PoolManager internal poolManager;
    MockV4StateView internal stateView;
    SinjohV4ConfirmedBandPriceGuard internal guard;
    ISinjohLaunchVerifier.VerifiedLaunch internal launch;

    function setUp() public {
        vm.chainId(4663);
        vm.warp(1_000_000);
        poolManager = new MockV4PoolManager();
        stateView = new MockV4StateView(address(poolManager));
        guard = new SinjohV4ConfirmedBandPriceGuard(
            address(stateView),
            address(stateView).codehash,
            address(poolManager).codehash,
            GOVERNANCE,
            vm.addr(OBSERVER_KEY)
        );
        launch = ISinjohLaunchVerifier.VerifiedLaunch({
            creatorAtLaunch: address(1),
            subject: address(2),
            venue: ISinjohLaunchVerifier.Venue.UNISWAP_V4,
            quoteAsset: address(0),
            pool: address(0),
            poolFee: 0,
            tickSpacing: 200,
            hooks: address(4),
            poolId: POOL_ID,
            launchSupply: 1e27
        });
    }

    function testBelowBandAndArmChecksUseCanonicalSpot() public {
        stateView.setTick(900);
        guard.validateBelow(launch, BOUNDARY, true, "");
        vm.expectRevert(SinjohV4DelayedBandPriceGuard.BoundaryNotCrossed.selector);
        guard.validateArm(launch, BOUNDARY, true, "");
        stateView.setTick(1_000);
        guard.validateArm(launch, BOUNDARY, true, "");
    }

    function testThirtyContinuousSecondsFinalizeSettlementPermanently() public {
        _expectPending(POOL_ID, true, BOUNDARY);
        guard.validateAbove(launch, BOUNDARY, true, "");

        _observe(true);
        (uint48 armedAt, uint48 confirmedAt) = _confirmation();
        assertEq(armedAt, 1_000_000);
        assertEq(confirmedAt, 0);

        vm.warp(block.timestamp + 30 seconds - 1);
        _observe(true);
        (, confirmedAt) = _confirmation();
        assertEq(confirmedAt, 0);

        vm.warp(block.timestamp + 1);
        _observe(true);
        (, confirmedAt) = _confirmation();
        assertEq(confirmedAt, block.timestamp);
        guard.validateAbove(launch, BOUNDARY, true, "");

        _observe(false);
        uint48 stillConfirmedAt;
        (armedAt, stillConfirmedAt) = _confirmation();
        assertEq(armedAt, 1_000_000);
        assertEq(stillConfirmedAt, confirmedAt);
        guard.validateAbove(launch, BOUNDARY, true, "");

        stateView.setTick(900);
        bytes32 key = guard.confirmationKey(address(this), POOL_ID, true, BOUNDARY);
        vm.expectRevert(
            abi.encodeWithSelector(
                SinjohV4ConfirmedBandPriceGuard.ConfirmationFinalized.selector, key
            )
        );
        guard.validateBelow(launch, BOUNDARY, true, "");
    }

    function testDipDisarmsAndLaterCrossingStartsFreshWindow() public {
        _observe(true);
        vm.warp(block.timestamp + 20 seconds);
        _observe(false);
        (uint48 armedAt,) = _confirmation();
        assertEq(armedAt, 0);

        vm.warp(block.timestamp + 1);
        _observe(true);
        (armedAt,) = _confirmation();
        assertEq(armedAt, block.timestamp);
        vm.warp(block.timestamp + 30 seconds);
        _observe(true);
        guard.validateAbove(launch, BOUNDARY, true, "");
    }

    function testConfirmationIsBoundToManagerPoolOrientationAndBoundary() public {
        _observe(true);
        vm.warp(block.timestamp + 30 seconds);
        _observe(true);

        _expectPending(POOL_ID, true, BOUNDARY + 200);
        guard.validateAbove(launch, BOUNDARY + 200, true, "");
        _expectPending(POOL_ID, false, BOUNDARY);
        guard.validateAbove(launch, BOUNDARY, false, "");

        ISinjohLaunchVerifier.VerifiedLaunch memory otherPool = launch;
        otherPool.poolId = keccak256("other-pool");
        _expectPending(otherPool.poolId, true, BOUNDARY);
        guard.validateAbove(otherPool, BOUNDARY, true, "");
    }

    function testOnlyObserverCanMutateAndGuardDataMustBeEmpty() public {
        SinjohV4ConfirmedBandPriceGuard.Observation[] memory observations = _observations(true);
        vm.expectRevert(
            abi.encodeWithSelector(
                SinjohV4ConfirmedBandPriceGuard.UnauthorizedObserver.selector, address(this)
            )
        );
        guard.observe(observations);

        _observe(true);
        vm.warp(block.timestamp + 30 seconds);
        _observe(true);
        vm.expectRevert(SinjohV4ConfirmedBandPriceGuard.UnexpectedGuardData.selector);
        guard.validateAbove(launch, BOUNDARY, true, hex"01");
    }

    function testBatchBoundsAndInvalidManagersAreRejected() public {
        vm.prank(vm.addr(OBSERVER_KEY));
        vm.expectRevert(SinjohV4ConfirmedBandPriceGuard.InvalidObservation.selector);
        guard.observe(new SinjohV4ConfirmedBandPriceGuard.Observation[](0));

        SinjohV4ConfirmedBandPriceGuard.Observation[] memory tooMany =
            new SinjohV4ConfirmedBandPriceGuard.Observation[](65);
        vm.prank(vm.addr(OBSERVER_KEY));
        vm.expectRevert(SinjohV4ConfirmedBandPriceGuard.InvalidObservation.selector);
        guard.observe(tooMany);

        SinjohV4ConfirmedBandPriceGuard.Observation[] memory invalid = _observations(true);
        invalid[0].manager = address(0xBEEF);
        vm.prank(vm.addr(OBSERVER_KEY));
        vm.expectRevert(SinjohV4ConfirmedBandPriceGuard.InvalidObservation.selector);
        guard.observe(invalid);
    }

    function testOrderedBatchDipAndRecrossRestartsAtSubmissionTime() public {
        _observe(true);
        vm.warp(block.timestamp + 29 seconds);
        SinjohV4ConfirmedBandPriceGuard.Observation[] memory observations =
            new SinjohV4ConfirmedBandPriceGuard.Observation[](3);
        observations[0] = _observations(true)[0];
        observations[1] = _observations(false)[0];
        observations[2] = _observations(true)[0];
        vm.prank(vm.addr(OBSERVER_KEY));
        guard.observe(observations);

        (uint48 armedAt, uint48 confirmedAt) = _confirmation();
        assertEq(armedAt, block.timestamp);
        assertEq(confirmedAt, 0);
        vm.warp(block.timestamp + 30 seconds);
        _observe(true);
        guard.validateAbove(launch, BOUNDARY, true, "");
    }

    function testGovernanceCanRotateObserverWithoutChangingFinalizedState() public {
        _observe(true);
        vm.warp(block.timestamp + 30 seconds);
        _observe(true);

        address nextObserver = address(0xB0B);
        vm.prank(GOVERNANCE);
        guard.setQuoteSigner(nextObserver);
        vm.prank(vm.addr(OBSERVER_KEY));
        vm.expectRevert(
            abi.encodeWithSelector(
                SinjohV4ConfirmedBandPriceGuard.UnauthorizedObserver.selector, vm.addr(OBSERVER_KEY)
            )
        );
        guard.observe(_observations(false));

        vm.prank(nextObserver);
        guard.observe(_observations(false));
        guard.validateAbove(launch, BOUNDARY, true, "");
    }

    function _observe(bool above) private {
        vm.prank(vm.addr(OBSERVER_KEY));
        guard.observe(_observations(above));
    }

    function _expectPending(bytes32 poolId, bool subjectIsToken0, int24 boundaryTick) private {
        bytes32 key = guard.confirmationKey(address(this), poolId, subjectIsToken0, boundaryTick);
        vm.expectRevert(
            abi.encodeWithSelector(
                SinjohV4ConfirmedBandPriceGuard.ConfirmationPending.selector, key
            )
        );
    }

    function _observations(bool above)
        private
        view
        returns (SinjohV4ConfirmedBandPriceGuard.Observation[] memory observations)
    {
        observations = new SinjohV4ConfirmedBandPriceGuard.Observation[](1);
        observations[0] = SinjohV4ConfirmedBandPriceGuard.Observation({
            manager: address(this),
            poolId: POOL_ID,
            subjectIsToken0: true,
            boundaryTick: BOUNDARY,
            above: above
        });
    }

    function _confirmation() private view returns (uint48 armedAt, uint48 confirmedAt) {
        SinjohV4ConfirmedBandPriceGuard.Confirmation memory value =
            guard.confirmation(address(this), POOL_ID, true, BOUNDARY);
        return (value.armedAt, value.confirmedAt);
    }
}
