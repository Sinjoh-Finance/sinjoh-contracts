// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

import { SinjohUniswapV3MultiHopSwapAdapter } from "../src/SinjohUniswapV3MultiHopSwapAdapter.sol";
import { SinjohUniswapV3SwapAdapter } from "../src/SinjohUniswapV3SwapAdapter.sol";
import { SinjohV3RouteExecutionFactory } from "../src/SinjohV3RouteExecutionFactory.sol";
import { SinjohV3RouteGuardDeployer } from "../src/SinjohV3RouteGuardDeployer.sol";
import { SinjohV3RouteTwapPriceGuard } from "../src/SinjohV3RouteTwapPriceGuard.sol";
import { DeployV3RouteExecutionFactory } from "../script/DeployV3RouteExecutionFactory.s.sol";
import { DeployV3RouteGuardDeployer } from "../script/DeployV3RouteGuardDeployer.s.sol";
import { TestBase } from "./TestBase.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import {
    MockV3MultiHopRouter,
    MockV3MultiPoolFactory,
    MockV3OraclePool
} from "./mocks/MockSwapInfrastructure.sol";

/// @notice Covers the execution dependencies an "another token" or RWA fee
/// bucket needs: the subject normalises through the quote asset in one atomic
/// two-hop swap, and quote-asset fees take the direct pool.
contract SinjohRouteExecutionTest is TestBase {
    uint256 internal constant EIP170_LIMIT = 24_576;
    address internal constant PINNED_GUARD_DEPLOYER = 0xd9A2F73d97fb6EbAe65FEA981afe3BD252C8b530;
    address internal constant PINNED_FACTORY = 0x3c40C6B72630cdB07EBB5487A38fF0677E1360DB;

    uint24 internal constant SUBJECT_FEE = 10_000;
    uint24 internal constant ASSET_FEE = 3_000;

    MockERC20 internal subject;
    MockERC20 internal quote;
    MockERC20 internal asset;

    MockV3MultiPoolFactory internal v3Factory;
    MockV3MultiHopRouter internal router;
    MockV3OraclePool internal subjectPool;
    MockV3OraclePool internal assetPool;

    SinjohV3RouteExecutionFactory internal executionFactory;

    function setUp() public {
        subject = new MockERC20("Subject", "SUB");
        quote = new MockERC20("Wrapped", "WETH");
        asset = new MockERC20("Tokenised NVDA", "NVDA");

        v3Factory = new MockV3MultiPoolFactory();
        router = new MockV3MultiHopRouter();
        subjectPool = _pool(address(subject), address(quote), SUBJECT_FEE);
        assetPool = _pool(address(quote), address(asset), ASSET_FEE);
        executionFactory =
            new SinjohV3RouteExecutionFactory(address(new SinjohV3RouteGuardDeployer()));
    }

    // ---------------------------------------------------------------- factory

    function testFactoryPredeploysEveryAssetBucketDependencyDeterministically() public {
        SinjohV3RouteExecutionFactory.AssetRoute memory route = _futureRoute();
        bytes32 userSalt = keccak256("future-asset-bucket");

        SinjohV3RouteExecutionFactory.AssetRouteDependencies memory predicted =
            executionFactory.predictAssetRoute(address(this), userSalt, route);
        SinjohV3RouteExecutionFactory.AssetRouteDependencies memory deployed =
            executionFactory.deployAssetRoute(address(this), userSalt, route);

        assertEq(predicted.subjectAdapter, deployed.subjectAdapter);
        assertEq(predicted.subjectGuard, deployed.subjectGuard);
        assertEq(predicted.quoteAdapter, deployed.quoteAdapter);
        assertEq(predicted.quoteGuard, deployed.quoteGuard);

        // All four exist, all four are inert until the pool really exists.
        assertTrue(deployed.subjectAdapter.code.length != 0);
        assertTrue(deployed.subjectGuard.code.length != 0);
        assertTrue(deployed.quoteAdapter.code.length != 0);
        assertTrue(deployed.quoteGuard.code.length != 0);
        assertTrue(!SinjohUniswapV3MultiHopSwapAdapter(deployed.subjectAdapter).active());
        assertTrue(!SinjohV3RouteTwapPriceGuard(deployed.subjectGuard).active());
        assertTrue(!SinjohUniswapV3SwapAdapter(deployed.quoteAdapter).active());
        assertTrue(!SinjohV3RouteTwapPriceGuard(deployed.quoteGuard).active());

        // Re-sending the identical call is a no-op, so a launch can resume.
        SinjohV3RouteExecutionFactory.AssetRouteDependencies memory again =
            executionFactory.deployAssetRoute(address(this), userSalt, route);
        assertEq(again.subjectAdapter, deployed.subjectAdapter);
        assertEq(again.quoteGuard, deployed.quoteGuard);
    }

    function testPredictionDependsOnCreatorAndSalt() public {
        SinjohV3RouteExecutionFactory.AssetRoute memory route = _futureRoute();

        address base =
            executionFactory.predictAssetRoute(address(this), keccak256("a"), route).subjectAdapter;
        address otherSalt =
            executionFactory.predictAssetRoute(address(this), keccak256("b"), route).subjectAdapter;
        address otherCreator =
            executionFactory.predictAssetRoute(address(0xBEEF), keccak256("a"), route)
        .subjectAdapter;

        assertTrue(base != otherSalt);
        assertTrue(base != otherCreator);
    }

    /// @dev A factory carries its children's creation code in its own runtime,
    /// which is what pushed an earlier single-contract version over EIP-170.
    /// `forge test` does not enforce that limit, so assert it directly: the
    /// chain does, and a deployment over it burns the deployer's gas for
    /// nothing.
    function testEveryDeployedContractFitsWithinTheEip170Limit() public {
        address guardDeployer = address(new SinjohV3RouteGuardDeployer());
        address factory = address(new SinjohV3RouteExecutionFactory(guardDeployer));
        SinjohV3RouteExecutionFactory.AssetRouteDependencies memory dependencies = _liveRoute();

        assertTrue(factory.code.length <= EIP170_LIMIT);
        assertTrue(guardDeployer.code.length <= EIP170_LIMIT);
        assertTrue(dependencies.subjectAdapter.code.length <= EIP170_LIMIT);
        assertTrue(dependencies.subjectGuard.code.length <= EIP170_LIMIT);
        assertTrue(dependencies.quoteAdapter.code.length <= EIP170_LIMIT);
        assertTrue(dependencies.quoteGuard.code.length <= EIP170_LIMIT);
    }

    /// @dev The UI pins this address before the deployment exists, so any
    /// source change that would move it must fail here first.
    function testDeploymentAddressMatchesTheAddressPinnedInTheManifest() public {
        DeployV3RouteExecutionFactory deployment = new DeployV3RouteExecutionFactory();
        (address guardDeployer, address factory) = deployment.predict();
        DeployV3RouteGuardDeployer guardDeployment = new DeployV3RouteGuardDeployer();

        assertEq(guardDeployer, PINNED_GUARD_DEPLOYER);
        assertEq(guardDeployment.predict(), PINNED_GUARD_DEPLOYER);
        assertEq(factory, PINNED_FACTORY);

        // The factory address commits to the full creation code and the guard
        // deployer constructor argument. The fork suite separately pins the
        // deployed runtime hash after immutable implementation addresses are
        // resolved from this exact deployment address.
    }

    function testFactoryRejectsDegenerateRoutes() public {
        SinjohV3RouteExecutionFactory.AssetRoute memory route = _futureRoute();
        route.asset = route.quoteAsset;

        vm.expectPartialRevert(SinjohV3RouteExecutionFactory.InvalidRoute.selector);
        executionFactory.predictAssetRoute(address(this), keccak256("bad"), route);
    }

    function testFactoryActivatesEveryDependencyAndIsResumable() public {
        SinjohV3RouteExecutionFactory.AssetRouteDependencies memory dependencies = _liveRoute();

        assertTrue(SinjohUniswapV3MultiHopSwapAdapter(dependencies.subjectAdapter).active());
        assertTrue(SinjohV3RouteTwapPriceGuard(dependencies.subjectGuard).active());
        assertTrue(SinjohUniswapV3SwapAdapter(dependencies.quoteAdapter).active());
        assertTrue(SinjohV3RouteTwapPriceGuard(dependencies.quoteGuard).active());

        // Both pools were grown to a TWAP-capable ring buffer.
        assertEq(subjectPool.cardinalityNext(), 2);
        assertEq(assetPool.cardinalityNext(), 2);

        // Activating again skips what is already active instead of reverting.
        executionFactory.activate(_dependencyList(dependencies));
    }

    function testActivationFailsClosedWhileThePoolIsStillCounterfactual() public {
        SinjohV3RouteExecutionFactory.AssetRoute memory route = _futureRoute();
        SinjohV3RouteExecutionFactory.AssetRouteDependencies memory dependencies =
            executionFactory.deployAssetRoute(address(this), keccak256("early"), route);

        vm.expectPartialRevert(SinjohV3RouteExecutionFactory.ActivationFailed.selector);
        executionFactory.activate(_dependencyList(dependencies));
    }

    function testActivationRejectsAPoolTheFactoryDoesNotCanonicalise() public {
        SinjohV3RouteExecutionFactory.AssetRoute memory route = _realRoute();
        SinjohV3RouteExecutionFactory.AssetRouteDependencies memory dependencies =
            executionFactory.deployAssetRoute(address(this), keccak256("uncanonical"), route);

        // The second pool exists and self-reports correctly, but the factory
        // no longer points at it.
        v3Factory.setPool(address(quote), address(asset), ASSET_FEE, address(0xDEAD));

        vm.expectPartialRevert(SinjohV3RouteExecutionFactory.ActivationFailed.selector);
        executionFactory.activate(_dependencyList(dependencies));
    }

    // ---------------------------------------------------------------- adapter

    function testMultiHopAdapterSubmitsOnlyItsFrozenPath() public {
        SinjohV3RouteExecutionFactory.AssetRouteDependencies memory dependencies = _liveRoute();
        SinjohUniswapV3MultiHopSwapAdapter adapter =
            SinjohUniswapV3MultiHopSwapAdapter(dependencies.subjectAdapter);

        subject.mint(address(this), 100 ether);
        asset.mint(address(router), 1_000 ether);
        subject.approve(address(adapter), type(uint256).max);

        adapter.swap(address(subject), address(asset), 10 ether, 10 ether, adapter.path());

        assertEq(asset.balanceOf(address(this)), 10 ether);
        assertEq(subject.balanceOf(address(adapter)), 0);
        assertEq(quote.balanceOf(address(adapter)), 0);
        assertEq(uint256(keccak256(router.lastPath())), uint256(keccak256(adapter.path())));
    }

    function testMultiHopAdapterRejectsAnyRouteDataThatIsNotItsPath() public {
        SinjohV3RouteExecutionFactory.AssetRouteDependencies memory dependencies = _liveRoute();
        SinjohUniswapV3MultiHopSwapAdapter adapter =
            SinjohUniswapV3MultiHopSwapAdapter(dependencies.subjectAdapter);

        subject.mint(address(this), 100 ether);
        asset.mint(address(router), 1_000 ether);
        subject.approve(address(adapter), type(uint256).max);
        bytes memory frozenPath = adapter.path();

        // A path through a different fee tier is not this adapter's route.
        bytes memory forged = abi.encodePacked(
            address(subject), SUBJECT_FEE, address(quote), uint24(500), address(asset)
        );
        vm.expectPartialRevert(SinjohUniswapV3MultiHopSwapAdapter.InvalidRoute.selector);
        adapter.swap(address(subject), address(asset), 10 ether, 10 ether, forged);

        // Nor is the reverse direction, or a different pair.
        vm.expectPartialRevert(SinjohUniswapV3MultiHopSwapAdapter.InvalidRoute.selector);
        adapter.swap(address(asset), address(subject), 10 ether, 10 ether, frozenPath);
    }

    function testMultiHopAdapterRejectsPartialInputConsumption() public {
        SinjohV3RouteExecutionFactory.AssetRouteDependencies memory dependencies = _liveRoute();
        SinjohUniswapV3MultiHopSwapAdapter adapter =
            SinjohUniswapV3MultiHopSwapAdapter(dependencies.subjectAdapter);

        subject.mint(address(this), 100 ether);
        asset.mint(address(router), 1_000 ether);
        subject.approve(address(adapter), type(uint256).max);
        router.setUseBps(9_000);
        bytes memory frozenPath = adapter.path();

        vm.expectPartialRevert(SinjohUniswapV3MultiHopSwapAdapter.UnexpectedBalanceDelta.selector);
        adapter.swap(address(subject), address(asset), 10 ether, 1 ether, frozenPath);
    }

    function testMultiHopAdapterRejectsStrandedIntermediate() public {
        SinjohV3RouteExecutionFactory.AssetRouteDependencies memory dependencies = _liveRoute();
        SinjohUniswapV3MultiHopSwapAdapter adapter =
            SinjohUniswapV3MultiHopSwapAdapter(dependencies.subjectAdapter);

        subject.mint(address(this), 100 ether);
        asset.mint(address(router), 1_000 ether);
        quote.mint(address(router), 1_000 ether);
        subject.approve(address(adapter), type(uint256).max);
        router.setStrandedMid(address(quote), 100);
        bytes memory frozenPath = adapter.path();

        vm.expectPartialRevert(
            SinjohUniswapV3MultiHopSwapAdapter.UnexpectedIntermediateDelta.selector
        );
        adapter.swap(address(subject), address(asset), 10 ether, 1 ether, frozenPath);
    }

    function testMultiHopAdapterRefusesToRunBeforeActivation() public {
        SinjohV3RouteExecutionFactory.AssetRoute memory route = _realRoute();
        SinjohV3RouteExecutionFactory.AssetRouteDependencies memory dependencies =
            executionFactory.deployAssetRoute(address(this), keccak256("inactive"), route);
        SinjohUniswapV3MultiHopSwapAdapter adapter =
            SinjohUniswapV3MultiHopSwapAdapter(dependencies.subjectAdapter);

        subject.mint(address(this), 100 ether);
        subject.approve(address(adapter), type(uint256).max);
        bytes memory frozenPath = adapter.path();

        vm.expectPartialRevert(SinjohUniswapV3MultiHopSwapAdapter.NotActive.selector);
        adapter.swap(address(subject), address(asset), 10 ether, 1 ether, frozenPath);
    }

    // ------------------------------------------------------------------ guard

    function testSubjectGuardQuotesBothHopsUnderOneBound() public {
        SinjohV3RouteExecutionFactory.AssetRouteDependencies memory dependencies = _liveRoute();
        SinjohV3RouteTwapPriceGuard guard = SinjohV3RouteTwapPriceGuard(dependencies.subjectGuard);

        // Hop one halves, hop two halves again: a two-hop quote must compound.
        _setTicks(subjectPool, -6_932, -6_932);
        _setTicks(assetPool, -6_932, -6_932);

        uint256 oneHop = _quoteAtTick(-6_932, 1 ether, address(subject), address(quote));
        uint256 both = guard.quoteAtTwap(1 ether);
        assertTrue(both < oneHop);

        (uint256 minOut, uint48 validUntil) = guard.minimumOutput(
            address(subject), address(subject), address(asset), 1 ether, guard.routeHash(), ""
        );
        assertEq(minOut, both * (10_000 - 500) / 10_000);
        assertTrue(validUntil > block.timestamp);
    }

    function testGuardBindsTheRouterSubjectSeparatelyFromTheTradedPair() public {
        SinjohV3RouteExecutionFactory.AssetRouteDependencies memory dependencies = _liveRoute();
        SinjohV3RouteTwapPriceGuard guard = SinjohV3RouteTwapPriceGuard(dependencies.quoteGuard);
        bytes32 routeHash = guard.routeHash();

        // The router always passes its own bound subject, which is on neither
        // side of a quote-asset conversion. That has to be accepted.
        (uint256 minOut,) = guard.minimumOutput(
            address(subject), address(quote), address(asset), 1 ether, routeHash, ""
        );
        assertTrue(minOut != 0);

        // A router bound to some other subject must not reuse this guard.
        vm.expectPartialRevert(SinjohV3RouteTwapPriceGuard.InvalidRoute.selector);
        guard.minimumOutput(address(0xABCD), address(quote), address(asset), 1 ether, routeHash, "");
    }

    function testGuardIsOneDirectionalAndRouteHashBound() public {
        SinjohV3RouteExecutionFactory.AssetRouteDependencies memory dependencies = _liveRoute();
        SinjohV3RouteTwapPriceGuard guard = SinjohV3RouteTwapPriceGuard(dependencies.quoteGuard);
        bytes32 routeHash = guard.routeHash();

        vm.expectPartialRevert(SinjohV3RouteTwapPriceGuard.InvalidRoute.selector);
        guard.minimumOutput(
            address(subject), address(asset), address(quote), 1 ether, routeHash, ""
        );

        vm.expectPartialRevert(SinjohV3RouteTwapPriceGuard.InvalidAmount.selector);
        guard.minimumOutput(
            address(subject), address(quote), address(asset), 1 ether, keccak256("other"), ""
        );

        vm.expectPartialRevert(SinjohV3RouteTwapPriceGuard.InvalidAmount.selector);
        guard.minimumOutput(
            address(subject), address(quote), address(asset), 1_000_000 ether, routeHash, ""
        );
    }

    function testSubjectGuardFailsClosedWhenEitherPoolDislocates() public {
        SinjohV3RouteExecutionFactory.AssetRouteDependencies memory dependencies = _liveRoute();
        SinjohV3RouteTwapPriceGuard guard = SinjohV3RouteTwapPriceGuard(dependencies.subjectGuard);

        _setTicks(subjectPool, 1_000, 0);
        vm.expectPartialRevert(SinjohV3RouteTwapPriceGuard.ExcessivePriceDeviation.selector);
        guard.quoteAtTwap(1 ether);

        _setTicks(subjectPool, 0, 0);
        _setTicks(assetPool, 1_000, 0);
        vm.expectPartialRevert(SinjohV3RouteTwapPriceGuard.ExcessivePriceDeviation.selector);
        guard.quoteAtTwap(1 ether);
    }

    function testSubjectGuardFailsClosedUntilBothPoolsHaveHistory() public {
        SinjohV3RouteExecutionFactory.AssetRouteDependencies memory dependencies = _liveRoute();
        SinjohV3RouteTwapPriceGuard guard = SinjohV3RouteTwapPriceGuard(dependencies.subjectGuard);

        assetPool.setCardinality(1);
        vm.expectPartialRevert(SinjohV3RouteTwapPriceGuard.OracleNotReady.selector);
        guard.quoteAtTwap(1 ether);
    }

    function testTwoHopGuardRefusesToAnchorAnExternalVenue() public {
        SinjohV3RouteExecutionFactory.AssetRouteDependencies memory dependencies = _liveRoute();
        SinjohV3RouteTwapPriceGuard guard = SinjohV3RouteTwapPriceGuard(dependencies.subjectGuard);

        vm.expectPartialRevert(SinjohV3RouteTwapPriceGuard.InvalidRoute.selector);
        guard.validatePoolPrice(
            address(subject), address(subject), address(asset), TickMath.getSqrtPriceAtTick(0)
        );
    }

    function testDirectGuardAnchorsAnExternalVenueWithinItsBound() public {
        SinjohV3RouteExecutionFactory.AssetRouteDependencies memory dependencies = _liveRoute();
        SinjohV3RouteTwapPriceGuard guard = SinjohV3RouteTwapPriceGuard(dependencies.quoteGuard);

        guard.validatePoolPrice(
            address(subject), address(quote), address(asset), TickMath.getSqrtPriceAtTick(0)
        );

        vm.expectPartialRevert(SinjohV3RouteTwapPriceGuard.ExcessivePriceDeviation.selector);
        guard.validatePoolPrice(
            address(subject), address(quote), address(asset), TickMath.getSqrtPriceAtTick(1_000)
        );
    }

    // ---------------------------------------------------------------- helpers

    function _pool(address tokenA, address tokenB, uint24 fee)
        private
        returns (MockV3OraclePool pool)
    {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        pool = new MockV3OraclePool(address(v3Factory), token0, token1, fee);
        v3Factory.setPool(tokenA, tokenB, fee, address(pool));
    }

    function _setTicks(MockV3OraclePool pool, int24 spotTick, int24 twapTick) private {
        pool.setTicks(spotTick, twapTick);
        pool.setSqrtPrice(TickMath.getSqrtPriceAtTick(spotTick));
    }

    /// @dev The shape the UI freezes before the subject or its pool exists.
    function _futureRoute() private view returns (SinjohV3RouteExecutionFactory.AssetRoute memory) {
        return SinjohV3RouteExecutionFactory.AssetRoute({
            router: address(router),
            factory: address(v3Factory),
            subject: address(0x1234),
            quoteAsset: address(quote),
            asset: address(asset),
            subjectPool: address(0x5678),
            assetPool: address(assetPool),
            subjectPoolFee: SUBJECT_FEE,
            assetPoolFee: ASSET_FEE,
            twapWindow: 60,
            maxSpotDeviationBps: 500,
            maxOutputSlippageBps: 500,
            validityPeriod: 60,
            maxAmountIn: 100 ether,
            comparisonAmount: 1 ether
        });
    }

    /// @dev The same shape once the launch has really happened.
    function _realRoute() private view returns (SinjohV3RouteExecutionFactory.AssetRoute memory) {
        SinjohV3RouteExecutionFactory.AssetRoute memory route = _futureRoute();
        route.subject = address(subject);
        route.subjectPool = address(subjectPool);
        return route;
    }

    function _liveRoute()
        private
        returns (SinjohV3RouteExecutionFactory.AssetRouteDependencies memory dependencies)
    {
        SinjohV3RouteExecutionFactory.AssetRoute memory route = _realRoute();
        dependencies = executionFactory.deployAssetRoute(address(this), keccak256("live"), route);
        executionFactory.activate(_dependencyList(dependencies));
    }

    function _dependencyList(SinjohV3RouteExecutionFactory.AssetRouteDependencies memory deps)
        private
        pure
        returns (address[] memory list)
    {
        list = new address[](4);
        list[0] = deps.subjectAdapter;
        list[1] = deps.subjectGuard;
        list[2] = deps.quoteAdapter;
        list[3] = deps.quoteGuard;
    }

    function _quoteAtTick(int24 tick, uint128 baseAmount, address baseToken, address quoteToken)
        private
        pure
        returns (uint256)
    {
        uint160 sqrtRatioX96 = TickMath.getSqrtPriceAtTick(tick);
        uint256 ratioX192 = uint256(sqrtRatioX96) * sqrtRatioX96;
        return baseToken < quoteToken
            ? _mulDiv(ratioX192, baseAmount, 1 << 192)
            : _mulDiv(1 << 192, baseAmount, ratioX192);
    }

    function _mulDiv(uint256 a, uint256 b, uint256 denominator) private pure returns (uint256) {
        unchecked {
            return a / denominator * b + a % denominator * b / denominator;
        }
    }
}
