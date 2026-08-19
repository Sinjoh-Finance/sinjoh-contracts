// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

import { SinjohUniswapV3SwapAdapter } from "../src/SinjohUniswapV3SwapAdapter.sol";
import { SinjohUniswapV4SwapAdapter } from "../src/SinjohUniswapV4SwapAdapter.sol";
import { SinjohUniswapV4HookedSwapAdapter } from "../src/SinjohUniswapV4HookedSwapAdapter.sol";
import { SinjohV3TwapPriceGuard } from "../src/SinjohV3TwapPriceGuard.sol";
import { SinjohV3ExecutionFactory } from "../src/SinjohV3ExecutionFactory.sol";
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

    function testHookedV4AdapterRejectsPartialInputConsumption() public {
        address token0 = address(subject) < address(quote) ? address(subject) : address(quote);
        address token1 = address(subject) < address(quote) ? address(quote) : address(subject);
        MockV4ExecutionPoolManager manager = new MockV4ExecutionPoolManager(token0, token1);
        manager.setUseBps(5_000);
        SinjohUniswapV4HookedSwapAdapter adapter = new SinjohUniswapV4HookedSwapAdapter(
            address(manager), address(this), address(quote), address(subject), 0, SPACING
        );
        subject.mint(address(manager), 100 ether);
        quote.approve(address(adapter), 10 ether);

        vm.expectPartialRevert(SinjohUniswapV4HookedSwapAdapter.InvalidAmount.selector);
        adapter.swap(address(quote), address(subject), 10 ether, 1, abi.encode(uint160(0)));
    }

    function testExecutionFactoryPredeploysInactiveDependenciesDeterministically() public {
        SinjohV3ExecutionFactory executionFactory = new SinjohV3ExecutionFactory();
        MockV3ExecutionFactory v3Factory = new MockV3ExecutionFactory();
        MockV3ExecutionRouter router = new MockV3ExecutionRouter();
        address futureSubject = address(0x1234);
        address futurePool = address(0x5678);
        bytes32 userSalt = keccak256("future-route");
        bytes32 routeHash = keccak256(abi.encode(uint160(0)));

        address predictedAdapter = executionFactory.predictSwapAdapter(
            address(this),
            userSalt,
            address(router),
            address(v3Factory),
            futurePool,
            address(quote),
            futureSubject,
            FEE
        );
        address adapter = executionFactory.deploySwapAdapter(
            address(this),
            userSalt,
            address(router),
            address(v3Factory),
            futurePool,
            address(quote),
            futureSubject,
            FEE
        );
        assertEq(adapter, predictedAdapter);
        assertTrue(adapter.code.length != 0);
        assertTrue(!SinjohUniswapV3SwapAdapter(adapter).active());
        vm.expectPartialRevert(SinjohUniswapV3SwapAdapter.InvalidAddress.selector);
        SinjohUniswapV3SwapAdapter(adapter).activate();
        assertEq(
            executionFactory.deploySwapAdapter(
                address(this),
                userSalt,
                address(router),
                address(v3Factory),
                futurePool,
                address(quote),
                futureSubject,
                FEE
            ),
            adapter
        );

        address predictedGuard = executionFactory.predictPriceGuard(
            address(this),
            userSalt,
            futurePool,
            address(v3Factory),
            futureSubject,
            address(quote),
            FEE,
            routeHash,
            60,
            500,
            500,
            60,
            100 ether,
            1 ether
        );
        address guard = executionFactory.deployPriceGuard(
            address(this),
            userSalt,
            futurePool,
            address(v3Factory),
            futureSubject,
            address(quote),
            FEE,
            routeHash,
            60,
            500,
            500,
            60,
            100 ether,
            1 ether
        );
        assertEq(guard, predictedGuard);
        assertTrue(guard.code.length != 0);
        assertTrue(!SinjohV3TwapPriceGuard(guard).active());
        vm.expectPartialRevert(SinjohV3TwapPriceGuard.InvalidAddress.selector);
        SinjohV3TwapPriceGuard(guard).activate();
    }

    function testExecutionFactoryActivatesCanonicalDependenciesAndIsResumable() public {
        SinjohV3ExecutionFactory executionFactory = new SinjohV3ExecutionFactory();
        MockV3ExecutionFactory v3Factory = new MockV3ExecutionFactory();
        MockV3ExecutionRouter router = new MockV3ExecutionRouter();
        address token0 = address(subject) < address(quote) ? address(subject) : address(quote);
        address token1 = address(subject) < address(quote) ? address(quote) : address(subject);
        MockV3ExecutionPool pool =
            new MockV3ExecutionPool(address(v3Factory), token0, token1, FEE, SPACING);
        v3Factory.setPool(address(pool));
        bytes32 userSalt = keccak256("canonical-route");
        bytes32 routeHash = keccak256(abi.encode(uint160(0)));

        SinjohV3ExecutionFactory.V3RouteConfig memory route = SinjohV3ExecutionFactory.V3RouteConfig({
            router: address(router),
            factory: address(v3Factory),
            pool: address(pool),
            subject: address(subject),
            quoteAsset: address(quote),
            poolFee: FEE,
            routeHash: routeHash,
            twapWindow: 60,
            maxSpotDeviationBps: 500,
            maxOutputSlippageBps: 500,
            validityPeriod: 60,
            maxAmountIn: 100 ether,
            comparisonAmount: 1 ether
        });
        (address forwardAdapter, address reverseAdapter, address guard) =
            executionFactory.deployRoute(address(this), userSalt, route);
        assertEq(
            forwardAdapter,
            executionFactory.predictSwapAdapter(
                address(this),
                userSalt,
                address(router),
                address(v3Factory),
                address(pool),
                address(quote),
                address(subject),
                FEE
            )
        );
        assertEq(
            reverseAdapter,
            executionFactory.predictSwapAdapter(
                address(this),
                userSalt,
                address(router),
                address(v3Factory),
                address(pool),
                address(subject),
                address(quote),
                FEE
            )
        );
        address[] memory dependencies = new address[](3);
        dependencies[0] = forwardAdapter;
        dependencies[1] = reverseAdapter;
        dependencies[2] = guard;

        executionFactory.activate(dependencies);
        assertTrue(SinjohUniswapV3SwapAdapter(forwardAdapter).active());
        assertTrue(SinjohUniswapV3SwapAdapter(reverseAdapter).active());
        assertTrue(SinjohV3TwapPriceGuard(guard).active());

        executionFactory.activate(dependencies);
        assertTrue(SinjohUniswapV3SwapAdapter(forwardAdapter).active());
        assertTrue(SinjohUniswapV3SwapAdapter(reverseAdapter).active());
        assertTrue(SinjohV3TwapPriceGuard(guard).active());
    }

    function testExecutionFactoryActivationRollsBackIfAnyDependencyIsInvalid() public {
        SinjohV3ExecutionFactory executionFactory = new SinjohV3ExecutionFactory();
        MockV3ExecutionFactory v3Factory = new MockV3ExecutionFactory();
        MockV3ExecutionRouter router = new MockV3ExecutionRouter();
        address token0 = address(subject) < address(quote) ? address(subject) : address(quote);
        address token1 = address(subject) < address(quote) ? address(quote) : address(subject);
        MockV3ExecutionPool pool =
            new MockV3ExecutionPool(address(v3Factory), token0, token1, FEE, SPACING);
        v3Factory.setPool(address(pool));
        bytes32 userSalt = keccak256("rollback-route");

        address adapter = executionFactory.deploySwapAdapter(
            address(this),
            userSalt,
            address(router),
            address(v3Factory),
            address(pool),
            address(quote),
            address(subject),
            FEE
        );
        address invalidGuard = executionFactory.deployPriceGuard(
            address(this),
            userSalt,
            address(0x5678),
            address(v3Factory),
            address(subject),
            address(quote),
            FEE,
            keccak256(abi.encode(uint160(0))),
            60,
            500,
            500,
            60,
            100 ether,
            1 ether
        );
        address[] memory dependencies = new address[](2);
        dependencies[0] = adapter;
        dependencies[1] = invalidGuard;

        vm.expectPartialRevert(SinjohV3ExecutionFactory.ActivationFailed.selector);
        executionFactory.activate(dependencies);
        assertTrue(!SinjohUniswapV3SwapAdapter(adapter).active());
        assertTrue(!SinjohV3TwapPriceGuard(invalidGuard).active());
    }

    function testTwapGuardRejectsNoncanonicalFactoryBinding() public {
        MockV3ExecutionFactory canonicalFactory = new MockV3ExecutionFactory();
        MockV3ExecutionFactory wrongFactory = new MockV3ExecutionFactory();
        address token0 = address(subject) < address(quote) ? address(subject) : address(quote);
        address token1 = address(subject) < address(quote) ? address(quote) : address(subject);
        MockV3ExecutionPool pool =
            new MockV3ExecutionPool(address(canonicalFactory), token0, token1, FEE, SPACING);
        canonicalFactory.setPool(address(pool));
        wrongFactory.setPool(address(pool));
        SinjohV3TwapPriceGuard guard = new SinjohV3TwapPriceGuard(
            address(pool),
            address(wrongFactory),
            address(subject),
            address(quote),
            FEE,
            keccak256(abi.encode(uint160(0))),
            60,
            500,
            500,
            60,
            100 ether,
            1 ether
        );

        vm.expectPartialRevert(SinjohV3TwapPriceGuard.InvalidRoute.selector);
        guard.activate();
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

    function testTwapGuardActivationGrowsFreshPoolObservationCapacity() public {
        address token0 = address(subject) < address(quote) ? address(subject) : address(quote);
        address token1 = address(subject) < address(quote) ? address(quote) : address(subject);
        MockV3ExecutionFactory factory = new MockV3ExecutionFactory();
        MockV3OraclePool pool = new MockV3OraclePool(address(factory), token0, token1, FEE);
        pool.setCardinality(1);
        factory.setPool(address(pool));
        bytes32 routeHash = keccak256(abi.encode(uint160(0)));
        SinjohV3TwapPriceGuard guard = new SinjohV3TwapPriceGuard(
            address(pool),
            address(factory),
            address(subject),
            address(quote),
            FEE,
            routeHash,
            60,
            500,
            500,
            60,
            100 ether,
            1 ether
        );

        guard.activate();

        assertEq(pool.cardinality(), 1);
        assertEq(pool.cardinalityNext(), 2);
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
        adapter.activate();
    }

    function _deployGuard()
        private
        returns (MockV3OraclePool pool, SinjohV3TwapPriceGuard guard, bytes32 routeHash)
    {
        address token0 = address(subject) < address(quote) ? address(subject) : address(quote);
        address token1 = address(subject) < address(quote) ? address(quote) : address(subject);
        MockV3ExecutionFactory factory = new MockV3ExecutionFactory();
        pool = new MockV3OraclePool(address(factory), token0, token1, FEE);
        factory.setPool(address(pool));
        routeHash = keccak256(abi.encode(uint160(0)));
        guard = new SinjohV3TwapPriceGuard(
            address(pool),
            address(factory),
            address(subject),
            address(quote),
            FEE,
            routeHash,
            60,
            500,
            500,
            60,
            100 ether,
            1 ether
        );
        guard.activate();
    }
}
