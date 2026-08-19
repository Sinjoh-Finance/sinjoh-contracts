// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { SinjohSignedFloor } from "../src/libraries/SinjohSignedFloor.sol";
import {
    SinjohPonsV2PairBuybackAdapter,
    SinjohPonsV2PairBuybackPriceGuard
} from "../src/SinjohPonsV2PairBuybackAdapter.sol";
import {
    MockBondingCurve,
    MockERC20,
    MockFeeEscrow,
    MockLaunchFactory,
    MockPoolManager,
    MockWETH
} from "./mocks/PonsV2Mocks.sol";

contract MockMemeHook { }

/// @dev SwapRouter02-shaped stand-in for the pons v3 DEX router: pulls the
/// input and mints the output at a fixed rate. `starve` simulates a hop that
/// produces nothing.
contract MockV3SwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    uint256 public rate = 3;
    bool public starve;
    uint24 public lastFee;

    function setRate(uint256 rate_) external {
        rate = rate_;
    }

    function setStarve(bool starve_) external {
        starve = starve_;
    }

    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        returns (uint256 amountOut)
    {
        lastFee = params.fee;
        MockERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn);
        amountOut = starve ? 0 : params.amountIn * rate;
        if (amountOut != 0) MockERC20(params.tokenOut).mint(params.recipient, amountOut);
    }
}

/// @notice Unit coverage for the pair-capable pons v2 buyback route: native
/// launches keep the deployed adapter's exact behavior, custom-pair launches
/// add the frozen v3 hop and ERC20 v4 settlement. The mainnet fork suite
/// proves the pons model these mocks encode is the real one.
contract SinjohPonsV2PairBuybackAdapterTest is TestBase {
    uint256 private constant SIGNER_KEY = uint256(keccak256("sinjoh-pons-v2-pair-buyback-signer"));
    uint256 private constant AMOUNT = 1 ether;
    uint24 private constant PAIR_FEE = 3000;
    bytes private constant PAIR_ROUTE = abi.encode(uint24(3000));

    uint8 private constant PHASE_NOT_GRADUATED = 0;
    uint8 private constant PHASE_SWEPT = 1;
    uint8 private constant PHASE_POOL_CREATED = 2;
    uint8 private constant PHASE_RESCUED = 3;

    MockWETH private weth;
    MockFeeEscrow private escrow;
    MockLaunchFactory private factory;
    MockMemeHook private hook;
    MockPoolManager private poolManager;
    MockV3SwapRouter private v3Router;
    MockERC20 private token;
    MockERC20 private pair;
    MockBondingCurve private nativeCurve;
    MockERC20 private nativeToken;
    MockBondingCurve private pairCurve;
    SinjohPonsV2PairBuybackAdapter private adapter;
    SinjohPonsV2PairBuybackPriceGuard private guard;

    function setUp() public {
        vm.warp(1_000);
        weth = new MockWETH();
        escrow = new MockFeeEscrow();
        factory = new MockLaunchFactory(address(escrow));
        hook = new MockMemeHook();
        poolManager = new MockPoolManager();
        v3Router = new MockV3SwapRouter();
        factory.setGraduationInfrastructure(address(hook), address(poolManager));

        // A native-quote launch, to prove the deployed adapter's behavior
        // carried over unchanged.
        nativeToken = new MockERC20("Native Launch", "NLNCH", 18);
        nativeCurve = new MockBondingCurve(address(0), address(this), address(this), escrow);
        nativeCurve.initialize(address(nativeToken));
        factory.registerLaunch(
            address(nativeToken), address(nativeCurve), address(0), 0, 200, PHASE_NOT_GRADUATED
        );

        // A custom-pair launch: 6 decimals, USDG-style.
        token = new MockERC20("Pair Launch", "PLNCH", 18);
        pair = new MockERC20("USD Stable", "USDG", 6);
        factory.approvePair(address(pair), 6);
        pairCurve = new MockBondingCurve(address(pair), address(this), address(this), escrow);
        pairCurve.initialize(address(token));
        factory.registerLaunch(
            address(token), address(pairCurve), address(pair), 0, 200, PHASE_NOT_GRADUATED
        );

        adapter = new SinjohPonsV2PairBuybackAdapter(
            address(factory),
            address(poolManager),
            address(weth),
            address(v3Router),
            address(factory).codehash,
            address(poolManager).codehash,
            address(weth).codehash,
            address(v3Router).codehash
        );
        guard = new SinjohPonsV2PairBuybackPriceGuard(
            address(factory),
            address(weth),
            address(factory).codehash,
            address(weth).codehash,
            vm.addr(SIGNER_KEY)
        );

        vm.deal(address(this), 100 ether);
        weth.deposit{ value: 20 ether }();
        weth.approve(address(adapter), type(uint256).max);
    }

    receive() external payable { }

    // ------------------------------------------------------------------
    // Native launches: parity with the deployed adapter
    // ------------------------------------------------------------------

    function test_nativeCurveBuyMatchesDeployedBehavior() public {
        uint256 wethBefore = weth.balanceOf(address(this));
        adapter.swap(address(weth), address(nativeToken), AMOUNT, 1, "");

        assertEq(nativeToken.balanceOf(address(this)), AMOUNT * nativeCurve.rate());
        assertEq(weth.balanceOf(address(this)), wethBefore - AMOUNT);
        assertEq(weth.balanceOf(address(adapter)), 0);
        assertEq(address(adapter).balance, 0);
    }

    function test_nativeLaunchRejectsRouteData() public {
        vm.expectRevert(SinjohPonsV2PairBuybackAdapter.InvalidRoute.selector);
        adapter.swap(address(weth), address(nativeToken), AMOUNT, 1, PAIR_ROUTE);
    }

    function test_nativeGraduatedSwapsThroughThePool() public {
        factory.setPhase(address(nativeToken), PHASE_POOL_CREATED);
        adapter.swap(address(weth), address(nativeToken), AMOUNT, 1, "");
        assertEq(nativeToken.balanceOf(address(this)), AMOUNT * poolManager.rate());
        (address currency0, address currency1,,,) = poolManager.lastKey();
        assertEq(currency0, address(0));
        assertEq(currency1, address(nativeToken));
        assertTrue(poolManager.lastZeroForOne());
    }

    // ------------------------------------------------------------------
    // Custom-pair launches: the v3 hop plus the curve
    // ------------------------------------------------------------------

    function test_pairCurveBuyRunsBothHops() public {
        uint256 wethBefore = weth.balanceOf(address(this));
        adapter.swap(address(weth), address(token), AMOUNT, 1, PAIR_ROUTE);

        // Hop one: WETH * v3 rate in pair units; hop two: curve rate.
        uint256 pairOut = AMOUNT * v3Router.rate();
        assertEq(token.balanceOf(address(this)), pairOut * pairCurve.rate());
        assertEq(weth.balanceOf(address(this)), wethBefore - AMOUNT);
        assertEq(v3Router.lastFee(), PAIR_FEE);
        // Nothing rests on the adapter in any asset.
        assertEq(weth.balanceOf(address(adapter)), 0);
        assertEq(pair.balanceOf(address(adapter)), 0);
        assertEq(token.balanceOf(address(adapter)), 0);
        assertEq(address(adapter).balance, 0);
    }

    function test_pairLaunchRequiresItsFeeTier() public {
        vm.expectRevert(SinjohPonsV2PairBuybackAdapter.InvalidRoute.selector);
        adapter.swap(address(weth), address(token), AMOUNT, 1, "");

        vm.expectRevert(SinjohPonsV2PairBuybackAdapter.InvalidRoute.selector);
        adapter.swap(address(weth), address(token), AMOUNT, 1, abi.encode(uint24(0)));
    }

    function test_pairHopProducingNothingFailsAtomically() public {
        v3Router.setStarve(true);
        vm.expectRevert(SinjohPonsV2PairBuybackAdapter.InvalidSwapDelta.selector);
        adapter.swap(address(weth), address(token), AMOUNT, 1, PAIR_ROUTE);
    }

    function test_floorBindsTheFullPath() public {
        // The floor travels into the curve, whose own slippage check fires
        // first; the adapter's InsufficientOutput remains the backstop for
        // markets that cannot enforce it themselves.
        uint256 expected = AMOUNT * v3Router.rate() * pairCurve.rate();
        vm.expectRevert("slippage");
        adapter.swap(address(weth), address(token), AMOUNT, expected + 1, PAIR_ROUTE);
    }

    function test_pairCurveClampFailsAtomically() public {
        // A partial curve fill refunds pair tokens; the adapter must refuse
        // the fill rather than hold the refund.
        pairCurve.setClamp((AMOUNT * v3Router.rate()) / 2);
        vm.expectRevert(SinjohPonsV2PairBuybackAdapter.UnexpectedBalance.selector);
        adapter.swap(address(weth), address(token), AMOUNT, 1, PAIR_ROUTE);
    }

    // ------------------------------------------------------------------
    // Custom-pair launches: the graduated v4 pool, both sort orders
    // ------------------------------------------------------------------

    function test_pairGraduatedSwapsWithErc20SettlementBothSortOrders() public {
        // Deploy launch tokens until both orderings against the pair exist;
        // sequential CREATE addresses make both appear within a few tries.
        MockERC20 below;
        MockERC20 above;
        for (
            uint256 i = 0;
            i < 32 && (address(below) == address(0) || address(above) == address(0));
            i++
        ) {
            MockERC20 candidate = new MockERC20("Sortable", "SORT", 18);
            if (address(candidate) < address(pair) && address(below) == address(0)) {
                below = candidate;
            } else if (address(candidate) > address(pair) && address(above) == address(0)) {
                above = candidate;
            }
        }
        assertTrue(address(below) != address(0) && address(above) != address(0));

        MockERC20[2] memory tokens = [below, above];
        for (uint256 i = 0; i < 2; i++) {
            MockERC20 launchToken = tokens[i];
            MockBondingCurve curve =
                new MockBondingCurve(address(pair), address(this), address(this), escrow);
            curve.initialize(address(launchToken));
            factory.registerLaunch(
                address(launchToken), address(curve), address(pair), 0, 200, PHASE_POOL_CREATED
            );

            adapter.swap(address(weth), address(launchToken), AMOUNT, 1, PAIR_ROUTE);

            uint256 pairIn = AMOUNT * v3Router.rate();
            assertEq(launchToken.balanceOf(address(this)), pairIn * poolManager.rate());
            (address currency0, address currency1,,,) = poolManager.lastKey();
            bool pairIsCurrency0 = address(pair) < address(launchToken);
            assertEq(currency0, pairIsCurrency0 ? address(pair) : address(launchToken));
            assertEq(currency1, pairIsCurrency0 ? address(launchToken) : address(pair));
            assertTrue(poolManager.lastZeroForOne() == pairIsCurrency0);
            // The ERC20 settlement delivered the pair tokens to the manager.
            assertEq(pair.balanceOf(address(poolManager)), pairIn * (i + 1));
            assertEq(pair.balanceOf(address(adapter)), 0);
        }
    }

    function test_partialV4FillFailsAtomicallyOnPairPool() public {
        factory.setPhase(address(token), PHASE_POOL_CREATED);
        poolManager.setSpendOverride((AMOUNT * v3Router.rate()) / 2);
        vm.expectRevert(SinjohPonsV2PairBuybackAdapter.InvalidSwapDelta.selector);
        adapter.swap(address(weth), address(token), AMOUNT, 1, PAIR_ROUTE);
    }

    // ------------------------------------------------------------------
    // Shared refusals
    // ------------------------------------------------------------------

    function test_sweptAndRescuedPhasesHaveNoMarket() public {
        factory.setPhase(address(token), PHASE_SWEPT);
        vm.expectRevert(
            abi.encodeWithSelector(SinjohPonsV2PairBuybackAdapter.NoMarket.selector, PHASE_SWEPT)
        );
        adapter.swap(address(weth), address(token), AMOUNT, 1, PAIR_ROUTE);

        factory.setPhase(address(token), PHASE_RESCUED);
        vm.expectRevert(
            abi.encodeWithSelector(SinjohPonsV2PairBuybackAdapter.NoMarket.selector, PHASE_RESCUED)
        );
        adapter.swap(address(weth), address(token), AMOUNT, 1, PAIR_ROUTE);
    }

    function test_unknownLaunchIsRefused() public {
        MockERC20 stranger = new MockERC20("Stranger", "STRG", 18);
        vm.expectRevert(
            abi.encodeWithSelector(
                SinjohPonsV2PairBuybackAdapter.UnknownLaunch.selector, address(stranger)
            )
        );
        adapter.swap(address(weth), address(stranger), AMOUNT, 1, "");
    }

    function test_rejectsNonWethInputAndZeroAmounts() public {
        vm.expectRevert(SinjohPonsV2PairBuybackAdapter.InvalidAmount.selector);
        adapter.swap(address(pair), address(token), AMOUNT, 1, PAIR_ROUTE);
        vm.expectRevert(SinjohPonsV2PairBuybackAdapter.InvalidAmount.selector);
        adapter.swap(address(weth), address(token), 0, 1, PAIR_ROUTE);
        vm.expectRevert(SinjohPonsV2PairBuybackAdapter.InvalidAmount.selector);
        adapter.swap(address(weth), address(token), AMOUNT, 0, PAIR_ROUTE);
    }

    function test_unlockCallbackOnlyDuringOwnSwap() public {
        vm.expectRevert(SinjohPonsV2PairBuybackAdapter.InvalidCallback.selector);
        adapter.unlockCallback(abi.encode(address(0), address(token), uint24(0), int24(0), 0, 0));
    }

    // ------------------------------------------------------------------
    // Guard
    // ------------------------------------------------------------------

    function _guardData(address subject, uint256 amountIn, bytes32 routeHash, uint256 minimum)
        private
        returns (bytes memory)
    {
        uint48 validAfter = uint48(block.timestamp - 1);
        uint48 validUntil = uint48(block.timestamp + 100);
        bytes32 digest = guard.floorDigest(
            address(this),
            subject,
            address(weth),
            subject,
            amountIn,
            routeHash,
            minimum,
            validAfter,
            validUntil
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            SIGNER_KEY, keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", digest))
        );
        return abi.encode(minimum, validAfter, validUntil, abi.encodePacked(r, s, v));
    }

    function test_guardAcceptsNativeAndPairRouteShapes() public {
        (uint256 minimum,) = guard.minimumOutput(
            address(nativeToken),
            address(weth),
            address(nativeToken),
            AMOUNT,
            keccak256(""),
            _guardData(address(nativeToken), AMOUNT, keccak256(""), 123)
        );
        assertEq(minimum, 123);

        bytes32 pairRouteHash = keccak256(PAIR_ROUTE);
        (minimum,) = guard.minimumOutput(
            address(token),
            address(weth),
            address(token),
            AMOUNT,
            pairRouteHash,
            _guardData(address(token), AMOUNT, pairRouteHash, 456)
        );
        assertEq(minimum, 456);
    }

    function test_guardEnforcesRouteShapeParity() public {
        // A pair launch with an empty route, and a native launch with one,
        // are both routes the adapter would refuse — the guard mirrors that.
        // Guard data is prepared first so expectRevert binds to minimumOutput.
        bytes memory emptyRouteData = _guardData(address(token), AMOUNT, keccak256(""), 1);
        vm.expectRevert(SinjohPonsV2PairBuybackPriceGuard.InvalidRoute.selector);
        guard.minimumOutput(
            address(token), address(weth), address(token), AMOUNT, keccak256(""), emptyRouteData
        );
        bytes32 pairRouteHash = keccak256(PAIR_ROUTE);
        bytes memory pairRouteData = _guardData(address(nativeToken), AMOUNT, pairRouteHash, 1);
        vm.expectRevert(SinjohPonsV2PairBuybackPriceGuard.InvalidRoute.selector);
        guard.minimumOutput(
            address(nativeToken),
            address(weth),
            address(nativeToken),
            AMOUNT,
            pairRouteHash,
            pairRouteData
        );
    }

    function test_guardRejectsWrongSigner() public {
        uint48 validAfter = uint48(block.timestamp - 1);
        uint48 validUntil = uint48(block.timestamp + 100);
        bytes32 digest = guard.floorDigest(
            address(this),
            address(nativeToken),
            address(weth),
            address(nativeToken),
            AMOUNT,
            keccak256(""),
            1,
            validAfter,
            validUntil
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            uint256(keccak256("not-the-signer")),
            keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", digest))
        );
        vm.expectRevert(SinjohSignedFloor.InvalidSignature.selector);
        guard.minimumOutput(
            address(nativeToken),
            address(weth),
            address(nativeToken),
            AMOUNT,
            keccak256(""),
            abi.encode(uint256(1), validAfter, validUntil, abi.encodePacked(r, s, v))
        );
    }
}
