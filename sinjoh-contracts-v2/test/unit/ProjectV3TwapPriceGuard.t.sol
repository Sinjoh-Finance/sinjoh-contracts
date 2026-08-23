// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { ProjectV3TwapPriceGuard } from "../../src/integrations/ProjectV3TwapPriceGuard.sol";
import { MockBasketAsset } from "../mocks/MockBasketIntegrations.sol";
import { MockV3BandFactory, MockV3BandPool } from "../mocks/MockUniswapV3BandPosition.sol";

contract ProjectV3TwapPriceGuardTest is Test {
    MockBasketAsset private tokenA;
    MockBasketAsset private tokenB;
    MockV3BandFactory private factory;
    MockV3BandPool private pool;
    ProjectV3TwapPriceGuard private guard;

    function setUp() public {
        vm.warp(1_000_000);
        tokenA = new MockBasketAsset("Token A", "A");
        tokenB = new MockBasketAsset("Token B", "B");
        factory = new MockV3BandFactory();
        factory.setFeeAmountTickSpacing(3_000, 60);
        (address token0, address token1) = address(tokenA) < address(tokenB)
            ? (address(tokenA), address(tokenB))
            : (address(tokenB), address(tokenA));
        pool = new MockV3BandPool(address(factory), token0, token1, 3_000, 60);
        factory.setPool(address(tokenA), address(tokenB), 3_000, address(pool));
        guard = new ProjectV3TwapPriceGuard(
            address(factory), 3_000, 15 minutes, 1_000, 750, 5 minutes, 1 ether
        );
    }

    function testReturnsTwapFloorBoundToExactFeeRoute() public view {
        (uint256 minimumOut, uint48 validUntil) = guard.minimumOutput(
            address(tokenA),
            address(tokenB),
            1 ether,
            keccak256(abi.encode(uint24(3_000))),
            bytes("")
        );
        assertEq(minimumOut, 0.925 ether);
        assertEq(validUntil, block.timestamp + 5 minutes);
    }

    function testRejectsWrongRouteInsufficientHistoryAndSpotDeviation() public {
        bytes32 routeHash = guard.routeHash();
        vm.expectRevert(ProjectV3TwapPriceGuard.InvalidRoute.selector);
        guard.minimumOutput(address(tokenA), address(tokenB), 1 ether, bytes32(0), bytes(""));

        pool.setObservationCardinality(1);
        vm.expectRevert(ProjectV3TwapPriceGuard.OracleNotReady.selector);
        guard.minimumOutput(address(tokenA), address(tokenB), 1 ether, routeHash, bytes(""));

        pool.setObservationCardinality(2);
        pool.setTwapTick(0);
        pool.setCurrentTick(5_000);
        vm.expectPartialRevert(ProjectV3TwapPriceGuard.ExcessivePriceDeviation.selector);
        guard.minimumOutput(address(tokenA), address(tokenB), 1 ether, routeHash, bytes(""));
    }

    function testPrimeRaisesNextObservationCardinality() public {
        assertEq(guard.prime(address(tokenA), address(tokenB), 16), address(pool));
        assertEq(pool.observationCardinalityNext(), 16);
    }
}
