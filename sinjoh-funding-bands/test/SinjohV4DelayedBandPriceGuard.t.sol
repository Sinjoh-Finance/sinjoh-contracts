// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ISinjohLaunchVerifier } from "../src/interfaces/ISinjohLaunchVerifier.sol";
import { SinjohV4DelayedBandPriceGuard } from "../src/profiles/SinjohV4DelayedBandPriceGuard.sol";
import { TestBase } from "./TestBase.sol";
import { MockV4PoolManager, MockV4StateView } from "./mocks/MockInfrastructure.sol";

contract SinjohV4DelayedBandPriceGuardTest is TestBase {
    bytes32 internal constant POOL_ID = keccak256("pool");

    MockV4PoolManager internal poolManager;
    MockV4StateView internal stateView;
    SinjohV4DelayedBandPriceGuard internal guard;
    ISinjohLaunchVerifier.VerifiedLaunch internal launch;

    function setUp() public {
        vm.chainId(4663);
        poolManager = new MockV4PoolManager();
        stateView = new MockV4StateView(address(poolManager));
        guard = new SinjohV4DelayedBandPriceGuard(
            address(stateView), address(stateView).codehash, address(poolManager).codehash
        );
        launch = ISinjohLaunchVerifier.VerifiedLaunch({
            creatorAtLaunch: address(1),
            subject: address(2),
            venue: ISinjohLaunchVerifier.Venue.UNISWAP_V4,
            quoteAsset: address(3),
            pool: address(0),
            poolFee: 3_000,
            tickSpacing: 60,
            hooks: address(4),
            poolId: POOL_ID,
            launchSupply: 1e27
        });
    }

    function testValidatesBothDirectionsForEitherTokenOrder() public {
        stateView.setTick(900);
        guard.validateBelow(launch, 1_000, true, "");
        stateView.setTick(1_100);
        guard.validateAbove(launch, 1_000, true, "");

        stateView.setTick(-900);
        guard.validateBelow(launch, -1_000, false, "");
        stateView.setTick(-1_100);
        guard.validateAbove(launch, -1_000, false, "");
    }

    function testBoundaryIsStrictBelowAndInclusiveAbove() public {
        stateView.setTick(1_000);
        vm.expectRevert(SinjohV4DelayedBandPriceGuard.BoundaryNotCrossed.selector);
        guard.validateBelow(launch, 1_000, true, "");
        guard.validateAbove(launch, 1_000, true, "");
    }

    function testRejectsWrongSideAndGuardData() public {
        stateView.setTick(900);
        vm.expectRevert(SinjohV4DelayedBandPriceGuard.BoundaryNotCrossed.selector);
        guard.validateAbove(launch, 1_000, true, "");
        vm.expectRevert(SinjohV4DelayedBandPriceGuard.InvalidGuardData.selector);
        guard.validateBelow(launch, 1_000, true, hex"01");
    }

    function testRejectsUninitializedAndNonV4Launch() public {
        stateView.setSqrtPriceX96(0);
        vm.expectRevert(SinjohV4DelayedBandPriceGuard.PoolNotInitialized.selector);
        guard.validateBelow(launch, 1_000, true, "");

        stateView.setSqrtPriceX96(1 << 96);
        launch.venue = ISinjohLaunchVerifier.Venue.UNISWAP_V3;
        vm.expectRevert(SinjohV4DelayedBandPriceGuard.InvalidLaunch.selector);
        guard.validateBelow(launch, 1_000, true, "");
    }

    function testConstructorPinsCanonicalDependencies() public {
        vm.expectRevert(SinjohV4DelayedBandPriceGuard.InvalidAddress.selector);
        new SinjohV4DelayedBandPriceGuard(
            address(stateView), bytes32(uint256(1)), address(poolManager).codehash
        );
        vm.expectRevert(SinjohV4DelayedBandPriceGuard.InvalidAddress.selector);
        new SinjohV4DelayedBandPriceGuard(
            address(stateView), address(stateView).codehash, bytes32(uint256(1))
        );
    }
}
