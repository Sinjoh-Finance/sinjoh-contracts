// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { SinjohPonsV2Adapter } from "../src/SinjohPonsV2Adapter.sol";
import { SinjohPonsV2AdapterFactory } from "../src/SinjohPonsV2AdapterFactory.sol";
import { IPonsV2LaunchFactory } from "../src/interfaces/IPonsV2.sol";
import {
    MockBondingCurve,
    MockERC20,
    MockFeeEscrow,
    MockLaunchFactory,
    MockRouter,
    MockWETH
} from "./mocks/PonsV2Mocks.sol";

contract SinjohPonsV2AdapterTest is TestBase {
    uint256 constant CHAIN_ID = 4663;
    uint256 constant LAUNCH_FEE = 0.0005 ether;
    bytes32 constant USER_SALT = keccak256("salt");

    MockFeeEscrow escrow;
    MockLaunchFactory launchFactory;
    MockWETH weth;
    MockERC20 usdg;
    SinjohPonsV2AdapterFactory adapterFactory;
    MockRouter router;

    address creator = address(0xC4EA704);
    address keeper = address(0xBEEF);
    address attacker = address(0xA77ACC);

    function setUp() public {
        vm.chainId(CHAIN_ID);
        escrow = new MockFeeEscrow();
        launchFactory = new MockLaunchFactory(address(escrow));
        weth = new MockWETH();
        usdg = new MockERC20("Global Dollar", "USDG", 6);
        launchFactory.approvePair(address(usdg), 6);

        adapterFactory = new SinjohPonsV2AdapterFactory(
            address(launchFactory), address(escrow), address(weth), CHAIN_ID
        );
        router = new MockRouter();
        vm.deal(creator, 100 ether);
    }

    function _deployAdapter() internal returns (SinjohPonsV2Adapter adapter) {
        address predicted = adapterFactory.predictAddress(creator, USER_SALT);
        router.setLaunchpadAdapter(predicted);
        vm.prank(creator);
        address deployed = adapterFactory.deploy(creator, address(router), USER_SALT);
        assertEq(deployed, predicted);
        adapter = SinjohPonsV2Adapter(payable(deployed));
    }

    /// @dev Pure on purpose. `vm.prank` and `vm.expectRevert` apply to the next
    /// call, so a helper that reached out to the factory would consume the
    /// cheatcode before the call under test ever ran. `test_paramsHelperMatchesFactory`
    /// pins this local digest to the factory's so the two cannot drift.
    function _params(address feeRecipient, uint256 launchConfigId, address pairToken)
        internal
        pure
        returns (IPonsV2LaunchFactory.TokenParams memory params)
    {
        params.name = "Sinjoh Test";
        params.symbol = "SJT";
        params.creatorFeeRecipient = feeRecipient;
        params.creatorTaxBps = 100;
        params.expectedEconomics = keccak256(abi.encode("economics", launchConfigId, pairToken));
    }

    function test_paramsHelperMatchesFactory() public view {
        assertTrue(
            _params(address(0), 0, address(0)).expectedEconomics
                == launchFactory.previewLaunchEconomics(0, address(0))
        );
        assertTrue(
            _params(address(0), 0, address(usdg)).expectedEconomics
                == launchFactory.previewLaunchEconomics(0, address(usdg))
        );
    }

    // ------------------------------------------------------------------
    // Deployment and initialization
    // ------------------------------------------------------------------

    function test_predictionMatchesDeployment() public {
        SinjohPonsV2Adapter adapter = _deployAdapter();
        assertEq(adapter.router(), address(router));
        assertEq(adapter.creator(), creator);
    }

    function test_reinitializationReverts() public {
        SinjohPonsV2Adapter adapter = _deployAdapter();
        vm.expectRevert(SinjohPonsV2Adapter.AlreadyInitialized.selector);
        adapter.initialize(address(router), creator);
    }

    function test_implementationCannotBeSeized() public {
        SinjohPonsV2Adapter implementation =
            SinjohPonsV2Adapter(payable(adapterFactory.implementation()));
        vm.expectRevert(SinjohPonsV2Adapter.AlreadyInitialized.selector);
        implementation.initialize(address(router), attacker);
    }

    function test_onlyCreatorMayDeployTheirAdapter() public {
        vm.prank(attacker);
        vm.expectRevert(SinjohPonsV2AdapterFactory.Unauthorized.selector);
        adapterFactory.deploy(creator, address(router), USER_SALT);
    }

    function test_deployIsIdempotent() public {
        SinjohPonsV2Adapter adapter = _deployAdapter();
        vm.prank(creator);
        address again = adapterFactory.deploy(creator, address(router), USER_SALT);
        assertEq(again, address(adapter));
    }

    function test_deployRetryRejectsADifferentRouter() public {
        _deployAdapter();
        MockRouter otherRouter = new MockRouter();

        vm.prank(creator);
        vm.expectRevert(SinjohPonsV2AdapterFactory.ConfigMismatch.selector);
        adapterFactory.deploy(creator, address(otherRouter), USER_SALT);
    }

    // ------------------------------------------------------------------
    // Launch guards
    // ------------------------------------------------------------------

    function test_launchRevertsWhenRouterDidNotNameAdapter() public {
        address predicted = adapterFactory.predictAddress(creator, USER_SALT);
        router.setLaunchpadAdapter(attacker);
        vm.prank(creator);
        SinjohPonsV2Adapter adapter = SinjohPonsV2Adapter(
            payable(adapterFactory.deploy(creator, address(router), USER_SALT))
        );
        assertEq(address(adapter), predicted);

        vm.prank(creator);
        vm.expectRevert(
            abi.encodeWithSelector(SinjohPonsV2Adapter.RouterDidNotNameAdapter.selector, attacker)
        );
        adapter.launch{ value: LAUNCH_FEE }(
            _params(address(adapter), 0, address(0)), 0, address(0), 0, 0
        );
    }

    function test_launchRevertsWhenFeeRecipientIsNotAdapter() public {
        SinjohPonsV2Adapter adapter = _deployAdapter();
        vm.prank(creator);
        vm.expectRevert(SinjohPonsV2Adapter.FeeRecipientNotAdapter.selector);
        adapter.launch{ value: LAUNCH_FEE }(_params(creator, 0, address(0)), 0, address(0), 0, 0);
    }

    function test_launchRevertsOnEconomicsMismatch() public {
        SinjohPonsV2Adapter adapter = _deployAdapter();
        IPonsV2LaunchFactory.TokenParams memory params = _params(address(adapter), 0, address(0));
        params.expectedEconomics = keccak256("stale quote");

        vm.prank(creator);
        vm.expectRevert();
        adapter.launch{ value: LAUNCH_FEE }(params, 0, address(0), 0, 0);
    }

    function test_launchRevertsOnUnapprovedPairToken() public {
        SinjohPonsV2Adapter adapter = _deployAdapter();
        MockERC20 unapproved = new MockERC20("Coinbase", "COIN", 18);

        vm.prank(creator);
        vm.expectRevert(
            abi.encodeWithSelector(
                SinjohPonsV2Adapter.PairTokenNotApproved.selector, address(unapproved)
            )
        );
        adapter.launch{ value: LAUNCH_FEE }(
            _params(address(adapter), 0, address(unapproved)), 0, address(unapproved), 0, 0
        );
    }

    /// @dev An approved quote asset can be upgradeable. A curve prices against
    /// its recorded scale for life, so a changed scale must stop the launch.
    function test_launchRevertsWhenPairDecimalsChanged() public {
        SinjohPonsV2Adapter adapter = _deployAdapter();
        usdg.setDecimals(18);

        vm.prank(creator);
        vm.expectRevert(
            abi.encodeWithSelector(
                SinjohPonsV2Adapter.PairTokenDecimalsChanged.selector, address(usdg), 6, 18
            )
        );
        adapter.launch{ value: LAUNCH_FEE }(
            _params(address(adapter), 0, address(usdg)), 0, address(usdg), 0, 0
        );
    }

    function test_launchRevertsOnWrongNativeValue() public {
        SinjohPonsV2Adapter adapter = _deployAdapter();
        vm.prank(creator);
        vm.expectRevert(
            abi.encodeWithSelector(
                SinjohPonsV2Adapter.NativeValueMismatch.selector, LAUNCH_FEE, LAUNCH_FEE + 1
            )
        );
        adapter.launch{ value: LAUNCH_FEE + 1 }(
            _params(address(adapter), 0, address(0)), 0, address(0), 0, 0
        );
    }

    function test_launchIsCreatorOnlyAndOneShot() public {
        SinjohPonsV2Adapter adapter = _deployAdapter();

        vm.prank(attacker);
        vm.expectRevert(SinjohPonsV2Adapter.Unauthorized.selector);
        adapter.launch{ value: 0 }(_params(address(adapter), 0, address(0)), 0, address(0), 0, 0);

        vm.prank(creator);
        adapter.launch{ value: LAUNCH_FEE }(
            _params(address(adapter), 0, address(0)), 0, address(0), 0, 0
        );

        vm.prank(creator);
        vm.expectRevert(SinjohPonsV2Adapter.AlreadyLaunched.selector);
        adapter.launch{ value: LAUNCH_FEE }(
            _params(address(adapter), 0, address(0)), 0, address(0), 0, 0
        );
    }

    function test_launchBindsRouter() public {
        SinjohPonsV2Adapter adapter = _deployAdapter();
        vm.prank(creator);
        (address token,) = adapter.launch{ value: LAUNCH_FEE }(
            _params(address(adapter), 0, address(0)), 0, address(0), 0, 0
        );
        assertTrue(router.bound());
        assertEq(router.subject(), token);
        assertEq(adapter.subject(), token);
    }

    // ------------------------------------------------------------------
    // Developer buy
    // ------------------------------------------------------------------

    function test_nativeDeveloperBuyDeliversTokensToCreator() public {
        SinjohPonsV2Adapter adapter = _deployAdapter();
        uint256 devBuy = 1 ether;

        vm.prank(creator);
        (address token,) = adapter.launch{ value: LAUNCH_FEE + devBuy }(
            _params(address(adapter), 0, address(0)), 0, address(0), devBuy, 1
        );

        assertEq(MockERC20(token).balanceOf(creator), devBuy * 1000);
        assertEq(MockERC20(token).balanceOf(address(adapter)), 0);
    }

    /// @dev v2 clamps an oversized buy and refunds the difference, so the tokens
    /// received can be fewer than a quote taken a moment earlier suggested. The
    /// adapter must measure rather than trust, and must not retain the refund.
    function test_clampedNativeDeveloperBuyRefundsCreator() public {
        uint256 devBuy = 1 ether;
        uint256 clamp = 0.4 ether;
        launchFactory.setNextClamp(clamp);

        SinjohPonsV2Adapter adapter = _deployAdapter();
        uint256 balanceBefore = creator.balance;

        vm.prank(creator);
        (address token,) = adapter.launch{ value: LAUNCH_FEE + devBuy }(
            _params(address(adapter), 0, address(0)), 0, address(0), devBuy, 1
        );

        assertEq(MockERC20(token).balanceOf(creator), clamp * 1000);
        assertEq(address(adapter).balance, 0);
        // Creator paid the fee and the consumed portion; the clamped remainder
        // came back in the same transaction.
        assertEq(balanceBefore - creator.balance, LAUNCH_FEE + clamp);
    }

    function test_clampedCustomPairDeveloperBuyRefundsCreator() public {
        uint256 devBuy = 500e6;
        uint256 clamp = 200e6;
        launchFactory.setNextClamp(clamp);

        SinjohPonsV2Adapter adapter = _deployAdapter();
        usdg.mint(creator, devBuy);
        vm.prank(creator);
        usdg.approve(address(adapter), devBuy);

        vm.prank(creator);
        (address token, address curve) = adapter.launch{ value: LAUNCH_FEE }(
            _params(address(adapter), 0, address(usdg)), 0, address(usdg), devBuy, 1
        );

        assertEq(MockERC20(token).balanceOf(creator), clamp * 1000);
        assertEq(usdg.balanceOf(creator), devBuy - clamp);
        assertEq(usdg.balanceOf(address(adapter)), 0);
        assertEq(usdg.allowance(address(adapter), curve), 0);
    }

    function test_developerBuyRequiresSlippageFloor() public {
        SinjohPonsV2Adapter adapter = _deployAdapter();
        vm.prank(creator);
        vm.expectRevert(SinjohPonsV2Adapter.InvalidDeveloperBuy.selector);
        adapter.launch{ value: LAUNCH_FEE + 1 ether }(
            _params(address(adapter), 0, address(0)), 0, address(0), 1 ether, 0
        );
    }

    function test_customPairDeveloperBuyPullsExactAmountAndLeavesNoAllowance() public {
        SinjohPonsV2Adapter adapter = _deployAdapter();
        uint256 devBuy = 500e6;
        usdg.mint(creator, devBuy);

        vm.prank(creator);
        usdg.approve(address(adapter), devBuy);

        vm.prank(creator);
        (address token, address curve) = adapter.launch{ value: LAUNCH_FEE }(
            _params(address(adapter), 0, address(usdg)), 0, address(usdg), devBuy, 1
        );

        assertEq(usdg.balanceOf(creator), 0);
        assertEq(usdg.balanceOf(address(adapter)), 0);
        assertEq(usdg.allowance(address(adapter), curve), 0);
        assertEq(MockERC20(token).balanceOf(creator), devBuy * 1000);
    }

    function test_adapterHoldsNoAllowanceOutsideLaunch() public {
        SinjohPonsV2Adapter adapter = _deployAdapter();
        usdg.mint(creator, 1000e6);
        vm.prank(creator);
        usdg.approve(address(adapter), type(uint256).max);

        vm.prank(creator);
        adapter.launch{ value: LAUNCH_FEE }(
            _params(address(adapter), 0, address(usdg)), 0, address(usdg), 0, 0
        );

        // With no developer buy the adapter never touches the creator's balance,
        // even though a standing allowance exists.
        assertEq(usdg.balanceOf(creator), 1000e6);
    }

    // ------------------------------------------------------------------
    // Collect and forward
    // ------------------------------------------------------------------

    function _launchNative() internal returns (SinjohPonsV2Adapter adapter, address token) {
        adapter = _deployAdapter();
        vm.prank(creator);
        (token,) = adapter.launch{ value: LAUNCH_FEE }(
            _params(address(adapter), 0, address(0)), 0, address(0), 0, 0
        );
    }

    /// @dev The path that actually matters: trading fees accrue on the curve,
    /// not in the escrow. A collect that only claimed would drain an empty
    /// escrow and leave the real fees stranded on the curve indefinitely.
    function test_collectSweepsCurveFeesBeforeClaiming() public {
        (SinjohPonsV2Adapter adapter,) = _launchNative();
        MockBondingCurve curve = MockBondingCurve(payable(adapter.curve()));

        vm.deal(address(this), 10 ether);
        curve.buy{ value: 10 ether }(10 ether, 1, address(this));

        uint256 expectedFee = 10 ether / 100;
        assertEq(curve.quoteFeeBalance(), expectedFee);
        assertEq(escrow.balanceOf(address(adapter)), 0);

        vm.prank(keeper);
        uint256[] memory _c_nativeAmount = adapter.collect();
        uint256 nativeAmount = _c_nativeAmount[0];

        assertEq(nativeAmount, expectedFee);
        assertEq(curve.quoteFeeBalance(), 0);
        assertEq(weth.balanceOf(address(adapter)), expectedFee);
    }

    function test_collectSurvivesAGraduatedCurve() public {
        (SinjohPonsV2Adapter adapter,) = _launchNative();
        MockBondingCurve curve = MockBondingCurve(payable(adapter.curve()));

        // Post-graduation the curve rejects sweeps and fees arrive from the v4
        // hook instead. A failed sweep must not block the claim.
        curve.setGraduated(true);
        escrow.credit{ value: 1 ether }(address(adapter));

        vm.prank(keeper);
        uint256[] memory _c_nativeAmount = adapter.collect();
        uint256 nativeAmount = _c_nativeAmount[0];
        assertEq(nativeAmount, 1 ether);
    }

    function test_collectSurfacesAnUnexpectedSweepFailure() public {
        (SinjohPonsV2Adapter adapter,) = _launchNative();
        MockBondingCurve curve = MockBondingCurve(payable(adapter.curve()));

        curve.setBuybackQuoteBalance(1);
        escrow.credit{ value: 1 ether }(address(adapter));

        vm.prank(keeper);
        vm.expectRevert(MockBondingCurve.NotFeeSweepOperator.selector);
        adapter.collect();
        assertEq(escrow.balanceOf(address(adapter)), 1 ether);
    }

    /// @dev Enabling buyback makes `buybackQuoteBalance` non-zero, which hands
    /// the sweep to pons's operator and ends permissionless fee arrival.
    function test_launchRefusesBuybackEnabled() public {
        SinjohPonsV2Adapter adapter = _deployAdapter();
        IPonsV2LaunchFactory.TokenParams memory params = _params(address(adapter), 0, address(0));
        params.buybackEnabled = true;

        vm.prank(creator);
        vm.expectRevert(SinjohPonsV2Adapter.BuybackMustBeDisabled.selector);
        adapter.launch{ value: LAUNCH_FEE }(params, 0, address(0), 0, 0);
    }

    /// @dev An idle launch is the normal case for a keeper poll. The escrow
    /// reverts `NoBalance()` when empty and that must not read as a failure.
    function test_collectOnIdleLaunchIsNoOp() public {
        (SinjohPonsV2Adapter adapter,) = _launchNative();
        vm.prank(keeper);
        uint256[] memory _c_nativeAmount = adapter.collect();
        uint256 nativeAmount = _c_nativeAmount[0];
        uint256 tokenAmount = 0;
        assertEq(nativeAmount, 0);
        assertEq(tokenAmount, 0);
    }

    function test_nativeFeesAreClaimedAndWrapped() public {
        (SinjohPonsV2Adapter adapter,) = _launchNative();
        escrow.credit{ value: 3 ether }(address(adapter));

        vm.prank(keeper);
        uint256[] memory _c_nativeAmount = adapter.collect();
        uint256 nativeAmount = _c_nativeAmount[0];

        assertEq(nativeAmount, 3 ether);
        assertEq(weth.balanceOf(address(adapter)), 3 ether);
        assertEq(address(adapter).balance, 0);
    }

    function test_customPairFeesAreClaimedAsThePairAsset() public {
        SinjohPonsV2Adapter adapter = _deployAdapter();
        vm.prank(creator);
        adapter.launch{ value: LAUNCH_FEE }(
            _params(address(adapter), 0, address(usdg)), 0, address(usdg), 0, 0
        );

        usdg.mint(address(this), 250e6);
        usdg.approve(address(escrow), 250e6);
        escrow.creditToken(address(adapter), address(usdg), 250e6);

        vm.prank(keeper);
        uint256[] memory _c_tokenAmount = adapter.collect();
        uint256 tokenAmount = _c_tokenAmount[0];
        assertEq(tokenAmount, 250e6);
        assertEq(usdg.balanceOf(address(adapter)), 250e6);
    }

    function test_forwardMovesFullBalanceToRouter() public {
        (SinjohPonsV2Adapter adapter,) = _launchNative();
        escrow.credit{ value: 2 ether }(address(adapter));
        vm.prank(keeper);
        adapter.collect();

        vm.prank(keeper);
        uint256 amount = adapter.forward(address(weth));

        assertEq(amount, 2 ether);
        assertEq(weth.balanceOf(address(router)), 2 ether);
        assertEq(weth.balanceOf(address(adapter)), 0);
    }

    function test_forwardOnZeroBalanceReturnsZero() public {
        (SinjohPonsV2Adapter adapter,) = _launchNative();
        vm.prank(keeper);
        assertEq(adapter.forward(address(weth)), 0);
    }

    function test_forwardRejectsUnsupportedAsset() public {
        (SinjohPonsV2Adapter adapter, address token) = _launchNative();
        // The launch token is never a fee asset on v2, so it must not be
        // forwardable even though the adapter can hold it transiently.
        vm.expectRevert(
            abi.encodeWithSelector(SinjohPonsV2Adapter.UnsupportedAsset.selector, token)
        );
        adapter.forward(token);

        vm.expectRevert(
            abi.encodeWithSelector(SinjohPonsV2Adapter.UnsupportedAsset.selector, address(usdg))
        );
        adapter.forward(address(usdg));
    }

    function test_intakeAssetsReflectPairChoice() public {
        (SinjohPonsV2Adapter native,) = _launchNative();
        address[] memory nativeAssets = native.intakeAssets();
        assertEq(nativeAssets.length, 1);
        assertEq(nativeAssets[0], address(weth));
    }

    function test_directTransfersAreForwardable() public {
        (SinjohPonsV2Adapter adapter,) = _launchNative();
        vm.deal(address(this), 1 ether);
        weth.deposit{ value: 1 ether }();
        weth.transfer(address(adapter), 1 ether);

        vm.prank(keeper);
        assertEq(adapter.forward(address(weth)), 1 ether);
        assertEq(weth.balanceOf(address(router)), 1 ether);
    }

    function test_collectAndForwardArePermissionless() public {
        (SinjohPonsV2Adapter adapter,) = _launchNative();
        escrow.credit{ value: 1 ether }(address(adapter));

        vm.prank(attacker);
        adapter.collect();
        vm.prank(attacker);
        adapter.forward(address(weth));

        // Anyone may push value along; nobody may redirect it.
        assertEq(weth.balanceOf(address(router)), 1 ether);
    }

    function test_wrongChainReverts() public {
        (SinjohPonsV2Adapter adapter,) = _launchNative();
        vm.chainId(1);
        vm.expectRevert(abi.encodeWithSelector(SinjohPonsV2Adapter.WrongChain.selector, 1));
        adapter.collect();
    }
}
