// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

import { SinjohUniswapV3SwapAdapter } from "../src/SinjohUniswapV3SwapAdapter.sol";
import { SinjohUniswapV4SwapAdapter } from "../src/SinjohUniswapV4SwapAdapter.sol";
import { SinjohV3TwapPriceGuard } from "../src/SinjohV3TwapPriceGuard.sol";
import { TestBase } from "./TestBase.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import {
    MockV3ExecutionFactory,
    MockV3ExecutionPool,
    MockV3ExecutionRouter,
    MockV3OraclePool,
    MockV4ExecutionPoolManager
} from "./mocks/MockSwapInfrastructure.sol";

contract SinjohExecutionComponentsTest is TestBase {
    uint24 internal constant FEE = 10_000;
    int24 internal constant SPACING = 200;

    MockERC20 internal subject;
    MockERC20 internal quote;

    function setUp() public {
        subject = new MockERC20("Subject", "SUB");
        quote = new MockERC20("Quote", "QUOTE");
        quote.mint(address(this), 1_000_000 ether);
    }

    function testV3AdapterExecutesOnlyItsExactRouteAndLeavesNoInput() public {
        (
            SinjohUniswapV3SwapAdapter adapter,
            MockV3ExecutionRouter router,
            MockV3ExecutionFactory factory
        ) = _deployV3Adapter();
        subject.mint(address(router), 1_000 ether);
        quote.approve(address(adapter), type(uint256).max);

        adapter.swap(address(quote), address(subject), 10 ether, 10 ether, abi.encode(uint160(0)));

        assertEq(quote.balanceOf(address(adapter)), 0);
        assertEq(subject.balanceOf(address(this)), 10 ether);
        assertTrue(address(factory) != address(0));

        vm.expectPartialRevert(SinjohUniswapV3SwapAdapter.InvalidRoute.selector);
        adapter.swap(address(subject), address(quote), 1 ether, 1 ether, abi.encode(uint160(0)));
    }

    function testV3AdapterRejectsPartialExactInputConsumption() public {
        (SinjohUniswapV3SwapAdapter adapter, MockV3ExecutionRouter router,) = _deployV3Adapter();
        subject.mint(address(router), 1_000 ether);
        quote.approve(address(adapter), type(uint256).max);
        router.setUseBps(9_000);

        vm.expectPartialRevert(SinjohUniswapV3SwapAdapter.UnexpectedBalanceDelta.selector);
        adapter.swap(address(quote), address(subject), 10 ether, 8 ether, abi.encode(uint160(0)));
        assertEq(quote.balanceOf(address(adapter)), 0);
        assertEq(subject.balanceOf(address(this)), 0);
    }

    function testV4AdapterSettlesExactDeltasAndAuthenticatesCallback() public {
        address token0 = address(subject) < address(quote) ? address(subject) : address(quote);
        address token1 = address(subject) < address(quote) ? address(quote) : address(subject);
        MockV4ExecutionPoolManager poolManager = new MockV4ExecutionPoolManager(token0, token1);
        SinjohUniswapV4SwapAdapter adapter = new SinjohUniswapV4SwapAdapter(
            address(poolManager), address(quote), address(subject), FEE, SPACING
        );
        subject.mint(address(poolManager), 1_000 ether);
        quote.approve(address(adapter), type(uint256).max);

        adapter.swap(address(quote), address(subject), 10 ether, 10 ether, abi.encode(uint160(0)));
        assertEq(quote.balanceOf(address(adapter)), 0);
        assertEq(subject.balanceOf(address(this)), 10 ether);

        vm.expectPartialRevert(SinjohUniswapV4SwapAdapter.InvalidCallback.selector);
        adapter.unlockCallback("");
    }

    function testTwapGuardBindsRouteAmountAndBothSpotPrices() public {
        (MockV3OraclePool pool, SinjohV3TwapPriceGuard guard, bytes32 routeHash) = _deployGuard();
        (uint256 minOut, uint48 validUntil) = guard.minimumOutput(
            address(subject), address(quote), address(subject), 10 ether, routeHash, ""
        );
        assertEq(minOut, 9.5 ether);
        assertTrue(validUntil > block.timestamp);
        guard.validatePoolPrice(
            address(subject), address(quote), address(subject), TickMath.getSqrtPriceAtTick(0)
        );

        vm.expectPartialRevert(SinjohV3TwapPriceGuard.InvalidAmount.selector);
        guard.minimumOutput(
            address(subject), address(quote), address(subject), 101 ether, routeHash, ""
        );

        pool.setTicks(1_000, 0);
        vm.expectPartialRevert(SinjohV3TwapPriceGuard.ExcessivePriceDeviation.selector);
        guard.minimumOutput(
            address(subject), address(quote), address(subject), 10 ether, routeHash, ""
        );
    }

    function testTwapGuardProtectsReverseSubjectToQuoteRoute() public {
        (, SinjohV3TwapPriceGuard guard, bytes32 routeHash) = _deployGuard();
        (uint256 minOut, uint48 validUntil) = guard.minimumOutput(
            address(subject), address(subject), address(quote), 10 ether, routeHash, ""
        );

        assertEq(minOut, 9.5 ether);
        assertTrue(validUntil > block.timestamp);
    }

    function testTwapGuardRejectsAssetsOutsideBoundPair() public {
        (, SinjohV3TwapPriceGuard guard, bytes32 routeHash) = _deployGuard();
        MockERC20 other = new MockERC20("Other", "OTHER");

        vm.expectPartialRevert(SinjohV3TwapPriceGuard.InvalidRoute.selector);
        guard.minimumOutput(
            address(subject), address(other), address(quote), 10 ether, routeHash, ""
        );
    }

    function testTwapGuardFailsClosedUntilHistoryExists() public {
        (MockV3OraclePool pool, SinjohV3TwapPriceGuard guard, bytes32 routeHash) = _deployGuard();
        pool.setCardinality(1);

        vm.expectPartialRevert(SinjohV3TwapPriceGuard.OracleNotReady.selector);
        guard.minimumOutput(
            address(subject), address(quote), address(subject), 10 ether, routeHash, ""
        );
    }

    function testTwapGuardRejectsV4VenuePriceAwayFromV3Anchor() public {
        (, SinjohV3TwapPriceGuard guard,) = _deployGuard();

        vm.expectPartialRevert(SinjohV3TwapPriceGuard.ExcessivePriceDeviation.selector);
        guard.validatePoolPrice(
            address(subject), address(quote), address(subject), TickMath.getSqrtPriceAtTick(1_000)
        );
    }

    function _deployV3Adapter()
        private
        returns (
            SinjohUniswapV3SwapAdapter adapter,
            MockV3ExecutionRouter router,
            MockV3ExecutionFactory factory
        )
    {
        factory = new MockV3ExecutionFactory();
        router = new MockV3ExecutionRouter();
        address token0 = address(subject) < address(quote) ? address(subject) : address(quote);
        address token1 = address(subject) < address(quote) ? address(quote) : address(subject);
        MockV3ExecutionPool pool =
            new MockV3ExecutionPool(address(factory), token0, token1, FEE, SPACING);
        factory.setPool(address(pool));
        adapter = new SinjohUniswapV3SwapAdapter(
            address(router), address(factory), address(pool), address(quote), address(subject), FEE
        );
    }

    function _deployGuard()
        private
        returns (MockV3OraclePool pool, SinjohV3TwapPriceGuard guard, bytes32 routeHash)
    {
        address token0 = address(subject) < address(quote) ? address(subject) : address(quote);
        address token1 = address(subject) < address(quote) ? address(quote) : address(subject);
        pool = new MockV3OraclePool(token0, token1);
        routeHash = keccak256(abi.encode(uint160(0)));
        guard = new SinjohV3TwapPriceGuard(
            address(pool),
            address(subject),
            address(quote),
            routeHash,
            60,
            500,
            500,
            60,
            100 ether,
            1 ether
        );
    }
}
