// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import {
    SinjohPonsV2BuybackAdapter,
    SinjohPonsV2BuybackPriceGuard
} from "../src/SinjohPonsV2BuybackAdapter.sol";
import { SinjohSignedFloor } from "../src/libraries/SinjohSignedFloor.sol";
import {
    MockBondingCurve,
    MockERC20,
    MockFeeEscrow,
    MockLaunchFactory,
    MockPoolManager,
    MockWETH
} from "./mocks/PonsV2Mocks.sol";

contract MockMemeHook { }

/// @notice Unit coverage for the pons v2 buyback route: the adapter's
/// phase-routed swap and the signed-floor guard. The mainnet fork suite proves
/// the pons model these mocks encode is the real one.
contract SinjohPonsV2BuybackAdapterTest is TestBase {
    uint256 private constant SIGNER_KEY = uint256(keccak256("sinjoh-pons-v2-buyback-signer"));
    uint256 private constant AMOUNT = 1 ether;

    uint8 private constant PHASE_NOT_GRADUATED = 0;
    uint8 private constant PHASE_SWEPT = 1;
    uint8 private constant PHASE_POOL_CREATED = 2;
    uint8 private constant PHASE_RESCUED = 3;

    MockWETH private weth;
    MockFeeEscrow private escrow;
    MockLaunchFactory private factory;
    MockMemeHook private hook;
    MockPoolManager private poolManager;
    MockERC20 private token;
    MockBondingCurve private curve;
    SinjohPonsV2BuybackAdapter private adapter;
    SinjohPonsV2BuybackPriceGuard private guard;

    function setUp() public {
        vm.warp(1_000);
        weth = new MockWETH();
        escrow = new MockFeeEscrow();
        factory = new MockLaunchFactory(address(escrow));
        hook = new MockMemeHook();
        poolManager = new MockPoolManager();
        factory.setGraduationInfrastructure(address(hook), address(poolManager));

        token = new MockERC20("Launch", "LNCH", 18);
        curve = new MockBondingCurve(address(0), address(this), address(this), escrow);
        curve.initialize(address(token));
        factory.registerLaunch(
            address(token), address(curve), address(0), 0, 200, PHASE_NOT_GRADUATED
        );

        adapter = new SinjohPonsV2BuybackAdapter(
            address(factory),
            address(poolManager),
            address(weth),
            address(factory).codehash,
            address(poolManager).codehash,
            address(weth).codehash
        );
        guard = new SinjohPonsV2BuybackPriceGuard(
            address(factory),
            address(weth),
            address(factory).codehash,
            address(weth).codehash,
            vm.addr(SIGNER_KEY)
        );

        vm.deal(address(this), 100 ether);
        weth.deposit{ value: 10 ether }();
        weth.approve(address(adapter), type(uint256).max);
    }

    receive() external payable { }

    // ------------------------------------------------------------------
    // Construction
    // ------------------------------------------------------------------

    function test_constructorRejectsMismatchedCodehash() public {
        vm.expectRevert(SinjohPonsV2BuybackAdapter.InvalidAddress.selector);
        new SinjohPonsV2BuybackAdapter(
            address(factory),
            address(poolManager),
            address(weth),
            bytes32(uint256(1)),
            address(poolManager).codehash,
            address(weth).codehash
        );
    }

    function test_constructorRejectsPoolManagerTheFactoryDoesNotUse() public {
        MockPoolManager other = new MockPoolManager();
        vm.expectRevert(SinjohPonsV2BuybackAdapter.InvalidAddress.selector);
        new SinjohPonsV2BuybackAdapter(
            address(factory),
            address(other),
            address(weth),
            address(factory).codehash,
            address(other).codehash,
            address(weth).codehash
        );
    }

    function test_constructorRequiresLiveMemeHook() public {
        MockLaunchFactory bare = new MockLaunchFactory(address(escrow));
        bare.setGraduationInfrastructure(address(0), address(poolManager));
        vm.expectRevert(SinjohPonsV2BuybackAdapter.InvalidAddress.selector);
        new SinjohPonsV2BuybackAdapter(
            address(bare),
            address(poolManager),
            address(weth),
            address(bare).codehash,
            address(poolManager).codehash,
            address(weth).codehash
        );
    }

    function test_constructorPinsHookFromFactory() public view {
        assertEq(adapter.memeHook(), address(hook));
        assertTrue(adapter.memeHookCodehash() == address(hook).codehash);
    }

    // ------------------------------------------------------------------
    // Pre-graduation: the bonding curve
    // ------------------------------------------------------------------

    function test_buysOnTheCurveBeforeGraduation() public {
        uint256 wethBefore = weth.balanceOf(address(this));
        adapter.swap(address(weth), address(token), AMOUNT, 1, "");

        assertEq(token.balanceOf(address(this)), AMOUNT * curve.rate());
        assertEq(weth.balanceOf(address(this)), wethBefore - AMOUNT);
        assertEq(weth.balanceOf(address(adapter)), 0);
        assertEq(token.balanceOf(address(adapter)), 0);
        assertEq(address(adapter).balance, 0);
    }

    function test_curveClampFailsAtomically() public {
        // The crossing buy near graduation fills partially and refunds. The
        // router debits the full input, so the adapter must refuse the fill
        // rather than hold the refund.
        curve.setClamp(AMOUNT / 2);
        vm.expectRevert(SinjohPonsV2BuybackAdapter.UnexpectedBalance.selector);
        adapter.swap(address(weth), address(token), AMOUNT, 1, "");
    }

    function test_curveSlippageBubbles() public {
        uint256 unreachable = AMOUNT * curve.rate() + 1;
        vm.expectRevert();
        adapter.swap(address(weth), address(token), AMOUNT, unreachable, "");
    }

    // ------------------------------------------------------------------
    // Post-graduation: the v4 pool
    // ------------------------------------------------------------------

    function test_swapsThroughThePoolOnceGraduated() public {
        factory.setPhase(address(token), PHASE_POOL_CREATED);
        adapter.swap(address(weth), address(token), AMOUNT, 1, "");

        assertEq(token.balanceOf(address(this)), AMOUNT * poolManager.rate());
        assertEq(token.balanceOf(address(adapter)), 0);
        assertEq(address(adapter).balance, 0);

        // The derived key must be the one the factory builds at graduation:
        // native quote first, launch fee and spacing from the record, the
        // factory's hook.
        (address currency0, address currency1, uint24 fee, int24 tickSpacing, address hooks) =
            poolManager.lastKey();
        assertEq(currency0, address(0));
        assertEq(currency1, address(token));
        assertEq(uint256(fee), 0);
        assertEq(uint256(int256(tickSpacing)), 200);
        assertEq(hooks, address(hook));
        assertTrue(poolManager.lastZeroForOne());
        assertEq(uint256(-poolManager.lastAmountSpecified()), AMOUNT);
    }

    function test_poolPartialFillIsRefused() public {
        factory.setPhase(address(token), PHASE_POOL_CREATED);
        poolManager.setSpendOverride(AMOUNT / 2);
        vm.expectRevert(SinjohPonsV2BuybackAdapter.InvalidSwapDelta.selector);
        adapter.swap(address(weth), address(token), AMOUNT, 1, "");
    }

    function test_poolOutputBelowFloorIsRefused() public {
        factory.setPhase(address(token), PHASE_POOL_CREATED);
        poolManager.setOutputOverride(5);
        vm.expectRevert(
            abi.encodeWithSelector(
                SinjohPonsV2BuybackAdapter.InsufficientOutput.selector, uint256(6), uint256(5)
            )
        );
        adapter.swap(address(weth), address(token), AMOUNT, 6, "");
    }

    function test_unlockCallbackOnlyDuringOwnSwap() public {
        vm.expectRevert(SinjohPonsV2BuybackAdapter.InvalidCallback.selector);
        adapter.unlockCallback("");

        vm.prank(address(poolManager));
        vm.expectRevert(SinjohPonsV2BuybackAdapter.InvalidCallback.selector);
        adapter.unlockCallback("");
    }

    // ------------------------------------------------------------------
    // Phases with no market
    // ------------------------------------------------------------------

    function test_sweptAndRescuedPhasesHaveNoMarket() public {
        factory.setPhase(address(token), PHASE_SWEPT);
        vm.expectRevert(
            abi.encodeWithSelector(SinjohPonsV2BuybackAdapter.NoMarket.selector, PHASE_SWEPT)
        );
        adapter.swap(address(weth), address(token), AMOUNT, 1, "");

        factory.setPhase(address(token), PHASE_RESCUED);
        vm.expectRevert(
            abi.encodeWithSelector(SinjohPonsV2BuybackAdapter.NoMarket.selector, PHASE_RESCUED)
        );
        adapter.swap(address(weth), address(token), AMOUNT, 1, "");
    }

    // ------------------------------------------------------------------
    // Route validation
    // ------------------------------------------------------------------

    function test_rejectsUnknownLaunch() public {
        MockERC20 unknown = new MockERC20("Unknown", "UNK", 18);
        vm.expectRevert(
            abi.encodeWithSelector(
                SinjohPonsV2BuybackAdapter.UnknownLaunch.selector, address(unknown)
            )
        );
        adapter.swap(address(weth), address(unknown), AMOUNT, 1, "");
    }

    function test_rejectsCustomPairLaunch() public {
        MockERC20 usdg = new MockERC20("USDG", "USDG", 6);
        MockERC20 paired = new MockERC20("Paired", "PAIR", 18);
        factory.registerLaunch(
            address(paired), address(curve), address(usdg), 0, 200, PHASE_NOT_GRADUATED
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                SinjohPonsV2BuybackAdapter.UnsupportedPair.selector, address(usdg)
            )
        );
        adapter.swap(address(weth), address(paired), AMOUNT, 1, "");
    }

    function test_rejectsMalformedRoutes() public {
        vm.expectRevert(SinjohPonsV2BuybackAdapter.InvalidAmount.selector);
        adapter.swap(address(token), address(weth), AMOUNT, 1, "");
        vm.expectRevert(SinjohPonsV2BuybackAdapter.InvalidAmount.selector);
        adapter.swap(address(weth), address(weth), AMOUNT, 1, "");
        vm.expectRevert(SinjohPonsV2BuybackAdapter.InvalidAmount.selector);
        adapter.swap(address(weth), address(token), 0, 1, "");
        vm.expectRevert(SinjohPonsV2BuybackAdapter.InvalidAmount.selector);
        adapter.swap(address(weth), address(token), AMOUNT, 0, "");
        vm.expectRevert(SinjohPonsV2BuybackAdapter.InvalidRoute.selector);
        adapter.swap(address(weth), address(token), AMOUNT, 1, abi.encode(uint256(1)));
    }

    function test_dependencyChangeFailsClosed() public {
        vm.etch(address(hook), hex"60006000fd");
        vm.expectRevert(SinjohPonsV2BuybackAdapter.DependencyChanged.selector);
        adapter.swap(address(weth), address(token), AMOUNT, 1, "");
    }

    // ------------------------------------------------------------------
    // Price guard
    // ------------------------------------------------------------------

    function test_guardReturnsTheSignedFloor() public {
        bytes memory data = _guardData(address(token), AMOUNT, 975);
        (uint256 minimum, uint48 validUntil) = guard.minimumOutput(
            address(token), address(weth), address(token), AMOUNT, keccak256(""), data
        );
        assertEq(minimum, 975);
        assertEq(validUntil, block.timestamp + 60);
    }

    function test_guardSignatureBindsAmountAndRouter() public {
        bytes memory data = _guardData(address(token), AMOUNT + 1, 975);
        vm.expectRevert(SinjohSignedFloor.InvalidSignature.selector);
        guard.minimumOutput(
            address(token), address(weth), address(token), AMOUNT, keccak256(""), data
        );

        data = _guardData(address(token), AMOUNT, 975);
        vm.prank(address(0xBAD));
        vm.expectRevert(SinjohSignedFloor.InvalidSignature.selector);
        guard.minimumOutput(
            address(token), address(weth), address(token), AMOUNT, keccak256(""), data
        );
    }

    function test_guardRejectsZeroFloorAndForeignRoutes() public {
        bytes memory data = _guardData(address(token), AMOUNT, 0);
        vm.expectRevert(SinjohPonsV2BuybackPriceGuard.InvalidAmount.selector);
        guard.minimumOutput(
            address(token), address(weth), address(token), AMOUNT, keccak256(""), data
        );

        data = _guardData(address(token), AMOUNT, 975);
        vm.expectRevert(SinjohPonsV2BuybackPriceGuard.InvalidRoute.selector);
        guard.minimumOutput(
            address(token), address(weth), address(token), AMOUNT, keccak256("route"), data
        );
        // The buyback output is always the router's own subject.
        vm.expectRevert(SinjohPonsV2BuybackPriceGuard.InvalidAmount.selector);
        guard.minimumOutput(
            address(0x7777), address(weth), address(token), AMOUNT, keccak256(""), data
        );
    }

    function test_guardMirrorsTheAdaptersLaunchChecks() public {
        MockERC20 unknown = new MockERC20("Unknown", "UNK", 18);
        bytes memory data = _guardData(address(unknown), AMOUNT, 975);
        vm.expectRevert(
            abi.encodeWithSelector(
                SinjohPonsV2BuybackPriceGuard.UnknownLaunch.selector, address(unknown)
            )
        );
        guard.minimumOutput(
            address(unknown), address(weth), address(unknown), AMOUNT, keccak256(""), data
        );

        MockERC20 usdg = new MockERC20("USDG", "USDG", 6);
        MockERC20 paired = new MockERC20("Paired", "PAIR", 18);
        factory.registerLaunch(address(paired), address(curve), address(usdg), 0, 200, 0);
        data = _guardData(address(paired), AMOUNT, 975);
        vm.expectRevert(
            abi.encodeWithSelector(
                SinjohPonsV2BuybackPriceGuard.UnsupportedPair.selector, address(usdg)
            )
        );
        guard.minimumOutput(
            address(paired), address(weth), address(paired), AMOUNT, keccak256(""), data
        );
    }

    function test_guardValidityWindowIsEnforced() public {
        uint48 validAfter = uint48(block.timestamp + 30);
        uint48 validUntil = uint48(block.timestamp + 90);
        bytes memory data =
            _guardDataWithWindow(address(token), AMOUNT, 975, validAfter, validUntil);
        vm.expectRevert(SinjohSignedFloor.InvalidValidity.selector);
        guard.minimumOutput(
            address(token), address(weth), address(token), AMOUNT, keccak256(""), data
        );

        // A window wider than MAXIMUM_VALIDITY is refused outright.
        data = _guardDataWithWindow(
            address(token), AMOUNT, 975, uint48(block.timestamp), uint48(block.timestamp + 600)
        );
        vm.expectRevert(SinjohSignedFloor.InvalidValidity.selector);
        guard.minimumOutput(
            address(token), address(weth), address(token), AMOUNT, keccak256(""), data
        );
    }

    function test_guardDependencyChangeFailsClosed() public {
        bytes memory data = _guardData(address(token), AMOUNT, 975);
        vm.etch(address(factory), hex"60006000fd");
        vm.expectRevert(SinjohPonsV2BuybackPriceGuard.DependencyChanged.selector);
        guard.minimumOutput(
            address(token), address(weth), address(token), AMOUNT, keccak256(""), data
        );
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    function _guardData(address subject, uint256 amount, uint256 minimum)
        private
        returns (bytes memory)
    {
        return _guardDataWithWindow(
            subject, amount, minimum, uint48(block.timestamp), uint48(block.timestamp + 60)
        );
    }

    function _guardDataWithWindow(
        address subject,
        uint256 amount,
        uint256 minimum,
        uint48 validAfter,
        uint48 validUntil
    ) private returns (bytes memory) {
        bytes32 digest = guard.floorDigest(
            address(this),
            subject,
            address(weth),
            subject,
            amount,
            keccak256(""),
            minimum,
            validAfter,
            validUntil
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_KEY, _personalDigest(digest));
        return abi.encode(minimum, validAfter, validUntil, abi.encodePacked(r, s, v));
    }

    function _personalDigest(bytes32 digest) private pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", digest));
    }
}
