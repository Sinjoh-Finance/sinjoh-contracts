// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { SinjohPonsV2Adapter } from "../src/SinjohPonsV2Adapter.sol";
import { SinjohPonsV2AdapterFactory } from "../src/SinjohPonsV2AdapterFactory.sol";
import {
    IPonsV2BondingCurve,
    IPonsV2FeeEscrow,
    IPonsV2LaunchFactory
} from "../src/interfaces/IPonsV2.sol";
import { MockRouter } from "./mocks/PonsV2Mocks.sol";

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function decimals() external view returns (uint8);
}

interface IPonsV2LaunchFactoryAdmin {
    function setLaunchEnabled(bool enabled) external;
    function whitelistedLaunchers(address launcher) external view returns (bool);
}

interface IPonsV2SnipeTaxViews {
    function snipeTaxStartBps() external view returns (uint256);
    function snipeTaxSeconds() external view returns (uint256);
}

interface IPonsV2CurveSnipeViews {
    function snipeTaxExempt(address account) external view returns (bool);
    function currentSnipeTaxBps(address recipient) external view returns (uint256);
    function creatorTaxBalance() external view returns (uint256);
}

/// @notice Runs the adapter against the real pons v2 deployment on Robinhood
/// Chain mainnet.
///
/// The unit suite only proves the adapter behaves as I modelled pons. This
/// suite proves the model is right: every signature here was transcribed from
/// verified on-chain source because the published docs misstate several, and a
/// transcription error would pass the mocks and fail in production.
///
/// Requires network access. Run with:
///   forge test --match-path 'test/PonsV2Mainnet.fork.t.sol'
contract PonsV2MainnetForkTest is TestBase {
    // The 2026-08 redeployment. The original v2 factory at 0x7E1EAbd5… was
    // paused at block 24672804 and superseded; the first launch through this
    // factory that Sinjoh verified end-to-end is
    // 0xf985da537a04c35fc720fcd9539e2ba12ffb7d59d6cd86c68a1072181c07c13c.
    address constant LAUNCH_FACTORY = 0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e;
    address constant FEE_ESCROW = 0xd3AFEB2a57f70eF218Aa82451c51B2fb0416Ac9e;
    address constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    address constant USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;
    uint256 constant CHAIN_ID = 4663;
    bytes32 constant USER_SALT = keccak256("sinjoh-v2-fork");

    string constant DEFAULT_RPC = "https://rpc.mainnet.chain.robinhood.com";

    SinjohPonsV2AdapterFactory adapterFactory;
    MockRouter router;
    address creator = address(0xC4EA704);
    address keeper = address(0xBEEF);

    address constant PONS_OWNER = 0xFdDE5a1E3cDF791Da71E49F817D70C7ceD72CC36;

    function setUp() public {
        vm.createSelectFork(vm.envOr("ROBINHOOD_RPC_URL", DEFAULT_RPC));
        adapterFactory = new SinjohPonsV2AdapterFactory(LAUNCH_FACTORY, FEE_ESCROW, WETH, CHAIN_ID);
        router = new MockRouter();
        vm.deal(creator, 100 ether);

        // pons toggles `launchEnabled` operationally — the previous factory
        // went false at block 24672804 and stayed paused until this
        // redeployment. While it is false only whitelisted launchers may
        // launch. These tests exercise the adapter, not pons's uptime, so the
        // fork re-enables launches when the live flag happens to be off.
        if (!IPonsV2LaunchFactory(LAUNCH_FACTORY).launchEnabled()) {
            vm.prank(PONS_OWNER);
            IPonsV2LaunchFactoryAdmin(LAUNCH_FACTORY).setLaunchEnabled(true);
        }
    }

    function _deployAdapter() internal returns (SinjohPonsV2Adapter adapter) {
        address predicted = adapterFactory.predictAddress(creator, USER_SALT);
        router.setLaunchpadAdapter(predicted);
        vm.prank(creator);
        adapter = SinjohPonsV2Adapter(
            payable(adapterFactory.deploy(creator, address(router), USER_SALT))
        );
        assertEq(address(adapter), predicted);
    }

    /// @dev Takes the economics pin as an argument rather than reading it here.
    /// `vm.prank` and `vm.expectRevert` apply to the next call, so a helper that
    /// reached out to the factory would consume the cheatcode before the call
    /// under test ever ran.
    function _params(address adapter, bytes32 economics)
        internal
        pure
        returns (IPonsV2LaunchFactory.TokenParams memory params)
    {
        params.name = "Sinjoh Fork Test";
        params.symbol = "SJFORK";
        params.logo = "";
        params.description = "adapter fork test";
        params.creatorFeeRecipient = adapter;
        params.creatorTaxBps = 0;
        params.buybackEnabled = false;
        params.expectedEconomics = economics;
        // Namespaced per initiating account — the adapter — whose salt space
        // is empty on a fresh fork, so a fixed value cannot collide.
        params.salt = USER_SALT;
    }

    function _none() internal pure returns (address[] memory) {
        return new address[](0);
    }

    /// @dev Moves past the launch-window snipe tax (99% decaying across the
    /// factory's `snipeTaxSeconds`, currently 5) so a third-party trade prices
    /// cleanly. Tests about the tax itself stay inside the window instead.
    function _warpPastSnipeWindow() internal {
        vm.warp(block.timestamp + IPonsV2SnipeTaxViews(LAUNCH_FACTORY).snipeTaxSeconds() + 1);
    }

    function _economics(address pairToken) internal view returns (bytes32) {
        return IPonsV2LaunchFactory(LAUNCH_FACTORY).previewLaunchEconomics(0, pairToken);
    }

    function _dealToken(address token, address to, uint256 amount) internal {
        for (uint256 slot; slot < 16; ++slot) {
            bytes32 key = keccak256(abi.encode(to, slot));
            bytes32 previous = vm.load(token, key);
            vm.store(token, key, bytes32(amount));
            if (IERC20Like(token).balanceOf(to) == amount) return;
            vm.store(token, key, previous);
        }
        revert("balance slot not found");
    }

    /// @dev The pinned dependency graph must agree with itself on chain. If
    /// pons repointed its escrow, the adapter constructor is where we find out.
    /// `launchEnabled` is deliberately not asserted here — setUp normalises it,
    /// and it is an operational flag rather than part of the dependency graph.
    function test_pinnedDependenciesAgreeOnChain() public view {
        assertEq(IPonsV2LaunchFactory(LAUNCH_FACTORY).feeEscrow(), FEE_ESCROW);
        assertEq(adapterFactory.launchFactory(), LAUNCH_FACTORY);
        assertEq(adapterFactory.feeEscrow(), FEE_ESCROW);
        assertEq(adapterFactory.weth(), WETH);
    }

    /// @dev Documents the gate that decides whether Sinjoh can launch at all.
    /// While `launchEnabled` is false, `launchToken` reverts `NotWhitelisted`
    /// for every caller except a whitelisted launcher. Our per-launch adapter
    /// clone is a fresh address each time and can never be pre-whitelisted, so
    /// a persistent pause would require a singleton launcher instead. See
    /// PONS-V2-FINDINGS.md.
    function test_whitelistIsPerCallerNotPerCreator() public view {
        IPonsV2LaunchFactoryAdmin admin = IPonsV2LaunchFactoryAdmin(LAUNCH_FACTORY);
        assertTrue(admin.whitelistedLaunchers(PONS_OWNER));
        // A clone address that has never launched is not, and cannot be,
        // whitelisted ahead of time.
        assertTrue(!admin.whitelistedLaunchers(adapterFactory.predictAddress(creator, USER_SALT)));
    }

    /// @dev Native launches read economics from the launch config, so
    /// `approvedPairTokens(0)` is false and must not be treated as a blocker.
    function test_nativePairNeedsNoApproval() public view {
        assertTrue(!IPonsV2LaunchFactory(LAUNCH_FACTORY).approvedPairTokens(address(0)));
        assertTrue(
            IPonsV2LaunchFactory(LAUNCH_FACTORY).previewLaunchEconomics(0, address(0)) != bytes32(0)
        );
    }

    function test_usdgIsApprovedWithSixDecimals() public view {
        assertTrue(IPonsV2LaunchFactory(LAUNCH_FACTORY).approvedPairTokens(USDG));
        (,, uint8 decimals) = IPonsV2LaunchFactory(LAUNCH_FACTORY).pairTokenEconomics(USDG);
        assertEq(uint256(decimals), 6);
        assertEq(uint256(IERC20Like(USDG).decimals()), 6);
    }

    /// @dev The whole integration in one transaction, against real contracts.
    function test_nativeLaunchWithDeveloperBuy() public {
        SinjohPonsV2Adapter adapter = _deployAdapter();
        uint256 launchFee = IPonsV2LaunchFactory(LAUNCH_FACTORY).launchFee();
        uint256 devBuy = 0.05 ether;
        IPonsV2LaunchFactory.TokenParams memory params =
            _params(address(adapter), _economics(address(0)));

        vm.prank(creator);
        (address token, address curve) =
            adapter.launch{ value: launchFee + devBuy }(params, 0, address(0), devBuy, 1, _none());

        assertTrue(token != address(0));
        assertTrue(curve != address(0));
        assertEq(adapter.subject(), token);
        assertEq(IPonsV2BondingCurve(curve).token(), token);
        assertTrue(IPonsV2BondingCurve(curve).isNativeQuote());

        // The router was bound by the adapter, in the launch transaction.
        assertTrue(router.bound());
        assertEq(router.subject(), token);

        // The developer buy landed with the creator, not the adapter.
        assertTrue(IERC20Like(token).balanceOf(creator) > 0);
        assertEq(IERC20Like(token).balanceOf(address(adapter)), 0);
        assertEq(address(adapter).balance, 0);
    }

    /// @dev Fees accrue on the curve and only reach the escrow through
    /// `sweepFees`. This is the assertion that would have caught a `collect()`
    /// that claimed without sweeping.
    function test_feesAccrueOnCurveThenClaimAndForward() public {
        SinjohPonsV2Adapter adapter = _deployAdapter();
        uint256 launchFee = IPonsV2LaunchFactory(LAUNCH_FACTORY).launchFee();

        IPonsV2LaunchFactory.TokenParams memory params =
            _params(address(adapter), _economics(address(0)));
        vm.prank(creator);
        (, address curve) = adapter.launch{ value: launchFee }(params, 0, address(0), 0, 0, _none());

        // Independent trading generates the creator fee. Deliberately well
        // under the 4.2 ETH graduation threshold: a buy that crosses it
        // graduates the curve immediately, and `graduate()` sweeps
        // `quoteFeeBalance` to zero on its way out — which is the pre-swept
        // path, covered separately by test_buyThroughGraduationStillPaysFees.
        address trader = address(0xD00D);
        vm.deal(trader, 20 ether);
        _warpPastSnipeWindow();
        vm.prank(trader);
        IPonsV2BondingCurve(curve).buy{ value: 0.5 ether }(0.5 ether, 1, trader);

        assertTrue(IPonsV2BondingCurve(curve).quoteFeeBalance() > 0);
        assertEq(IPonsV2FeeEscrow(FEE_ESCROW).balanceOf(address(adapter)), 0);

        vm.prank(keeper);
        uint256[] memory _c_nativeAmount = adapter.collect();
        uint256 nativeAmount = _c_nativeAmount[0];

        assertTrue(nativeAmount > 0);
        assertEq(IPonsV2BondingCurve(curve).quoteFeeBalance(), 0);
        // Native arrived wrapped, so the router's 18-decimal WETH accounting is
        // untouched and no raw ETH is stranded.
        assertEq(IERC20Like(WETH).balanceOf(address(adapter)), nativeAmount);
        assertEq(address(adapter).balance, 0);

        vm.prank(keeper);
        uint256 forwarded = adapter.forward(WETH);
        assertEq(forwarded, nativeAmount);
        assertEq(IERC20Like(WETH).balanceOf(address(router)), nativeAmount);
        assertEq(IERC20Like(WETH).balanceOf(address(adapter)), 0);
    }

    /// @dev The 81% case. A USDG launch must accrue, claim and forward in USDG
    /// at 6 decimals without ever touching WETH.
    function test_usdgPairedLaunchAccruesAndForwardsInUsdg() public {
        SinjohPonsV2Adapter adapter = _deployAdapter();
        uint256 launchFee = IPonsV2LaunchFactory(LAUNCH_FACTORY).launchFee();

        IPonsV2LaunchFactory.TokenParams memory params = _params(address(adapter), _economics(USDG));
        vm.prank(creator);
        (, address curve) = adapter.launch{ value: launchFee }(params, 0, USDG, 0, 0, _none());

        assertEq(IPonsV2BondingCurve(curve).pairToken(), USDG);
        assertTrue(!IPonsV2BondingCurve(curve).isNativeQuote());

        address[] memory assets = adapter.intakeAssets();
        assertEq(assets.length, 1);
        assertEq(assets[0], USDG);

        address trader = address(0xD00D);
        uint256 quoteIn = 100e6;
        _dealToken(USDG, trader, quoteIn);
        _warpPastSnipeWindow();
        vm.prank(trader);
        IERC20Like(USDG).approve(curve, quoteIn);
        vm.prank(trader);
        IPonsV2BondingCurve(curve).buy(quoteIn, 1, trader);

        assertTrue(IPonsV2BondingCurve(curve).quoteFeeBalance() > 0);
        assertEq(IPonsV2FeeEscrow(FEE_ESCROW).balanceOfToken(address(adapter), USDG), 0);

        vm.prank(keeper);
        uint256[] memory amounts = adapter.collect();
        assertTrue(amounts[0] > 0);
        assertEq(IPonsV2BondingCurve(curve).quoteFeeBalance(), 0);
        assertEq(IERC20Like(USDG).balanceOf(address(adapter)), amounts[0]);

        vm.prank(keeper);
        assertEq(adapter.forward(USDG), amounts[0]);
        assertEq(IERC20Like(USDG).balanceOf(address(router)), amounts[0]);
        assertEq(IERC20Like(USDG).balanceOf(address(adapter)), 0);

        // A USDG launch must never be able to forward WETH.
        vm.expectRevert(abi.encodeWithSelector(SinjohPonsV2Adapter.UnsupportedAsset.selector, WETH));
        adapter.forward(WETH);
    }

    /// @dev The end state of every successful launch. A buy that crosses the
    /// graduation threshold graduates the curve in the same call, and
    /// `graduate()` sweeps pending fees to the escrow on its way out. The
    /// adapter's own curve sweep then reverts `AlreadyGraduated`, which is
    /// exactly why `collect()` tolerates a failed sweep instead of requiring one.
    function test_buyThroughGraduationStillPaysFees() public {
        SinjohPonsV2Adapter adapter = _deployAdapter();
        uint256 launchFee = IPonsV2LaunchFactory(LAUNCH_FACTORY).launchFee();

        IPonsV2LaunchFactory.TokenParams memory params =
            _params(address(adapter), _economics(address(0)));
        vm.prank(creator);
        (, address curve) = adapter.launch{ value: launchFee }(params, 0, address(0), 0, 0, _none());

        address whale = address(0xDECAF);
        vm.deal(whale, 100 ether);
        // Inside the launch window a 99% snipe tax would eat most of the buy's
        // quote leg and the net reserve movement would miss the threshold.
        _warpPastSnipeWindow();
        vm.prank(whale);
        IPonsV2BondingCurve(curve).buy{ value: 10 ether }(10 ether, 1, whale);

        assertTrue(IPonsV2BondingCurve(curve).graduated());
        // Fees were swept by graduation, so they are already sitting in escrow.
        assertTrue(IPonsV2FeeEscrow(FEE_ESCROW).balanceOf(address(adapter)) > 0);

        vm.prank(keeper);
        uint256[] memory _c_nativeAmount = adapter.collect();
        uint256 nativeAmount = _c_nativeAmount[0];
        assertTrue(nativeAmount > 0);
        assertEq(IERC20Like(WETH).balanceOf(address(adapter)), nativeAmount);
        assertEq(address(adapter).balance, 0);

        vm.prank(keeper);
        assertEq(adapter.forward(WETH), nativeAmount);
        assertEq(IERC20Like(WETH).balanceOf(address(router)), nativeAmount);
    }

    function test_collectOnIdleLaunchIsNoOpOnChain() public {
        SinjohPonsV2Adapter adapter = _deployAdapter();
        uint256 launchFee = IPonsV2LaunchFactory(LAUNCH_FACTORY).launchFee();

        IPonsV2LaunchFactory.TokenParams memory params =
            _params(address(adapter), _economics(address(0)));
        vm.prank(creator);
        adapter.launch{ value: launchFee }(params, 0, address(0), 0, 0, _none());

        // No trading yet: the curve sweep is a no-op and the escrow reverts
        // NoBalance(). Neither may surface as a failure to a keeper.
        vm.prank(keeper);
        uint256[] memory _c_nativeAmount = adapter.collect();
        uint256 nativeAmount = _c_nativeAmount[0];
        uint256 tokenAmount = 0;
        assertEq(nativeAmount, 0);
        assertEq(tokenAmount, 0);
    }

    /// @dev The redeployment's launch window: the adapter (launch caller and
    /// creator-fee recipient) is auto-exempt, so the atomic developer buy —
    /// whose curve-side recipient is the adapter — clears untaxed in the launch
    /// second; a declared bundle wallet clears untaxed too; an undeclared
    /// sniper in the same second is quoted the full starting tax.
    function test_snipeTaxExemptionsProtectDevBuyAndDeclaredWallets() public {
        SinjohPonsV2Adapter adapter = _deployAdapter();
        uint256 launchFee = IPonsV2LaunchFactory(LAUNCH_FACTORY).launchFee();
        address bundleWallet = address(0xB0B);
        address sniper = address(0x5A1);
        address[] memory exemptions = new address[](1);
        exemptions[0] = bundleWallet;

        IPonsV2LaunchFactory.TokenParams memory params =
            _params(address(adapter), _economics(address(0)));
        vm.prank(creator);
        (address token, address curve) = adapter.launch{ value: launchFee + 0.05 ether }(
            params, 0, address(0), 0.05 ether, 1, exemptions
        );

        // The developer buy landed in the launch second and was not consumed
        // by the 99% starting tax: at the config-0 phantom reserve of 1.68
        // ETH, an untaxed 0.05 ETH clears well over 1% of supply, while a
        // taxed one could not.
        assertTrue(IERC20Like(token).balanceOf(creator) > 1e27 / 100);

        IPonsV2CurveSnipeViews views = IPonsV2CurveSnipeViews(curve);
        assertTrue(views.snipeTaxExempt(address(adapter)));
        assertTrue(views.snipeTaxExempt(bundleWallet));
        assertEq(views.currentSnipeTaxBps(bundleWallet), 0);
        // Same second, undeclared wallet: quoted the full starting tax.
        assertEq(
            views.currentSnipeTaxBps(sniper),
            IPonsV2SnipeTaxViews(LAUNCH_FACTORY).snipeTaxStartBps()
        );
    }

    /// @dev The creator tax is charged on top of the base fee, bypasses the
    /// protocol split entirely, and is credited to the curve's `deployer` —
    /// which is the creator-fee recipient, i.e. this adapter. It must arrive
    /// through the same collect-and-forward path as the base-fee share.
    function test_creatorTaxAccruesAndFlowsThroughCollect() public {
        SinjohPonsV2Adapter adapter = _deployAdapter();
        uint256 launchFee = IPonsV2LaunchFactory(LAUNCH_FACTORY).launchFee();

        IPonsV2LaunchFactory.TokenParams memory params =
            _params(address(adapter), _economics(address(0)));
        params.creatorTaxBps = 500;
        vm.prank(creator);
        (, address curve) = adapter.launch{ value: launchFee }(params, 0, address(0), 0, 0, _none());

        address trader = address(0xD00D);
        vm.deal(trader, 20 ether);
        _warpPastSnipeWindow();
        vm.prank(trader);
        IPonsV2BondingCurve(curve).buy{ value: 1 ether }(1 ether, 1, trader);

        // 5% creator tax against a 1% base fee: the tax bucket dominates.
        uint256 tax = IPonsV2CurveSnipeViews(curve).creatorTaxBalance();
        uint256 baseFee = IPonsV2BondingCurve(curve).quoteFeeBalance();
        assertTrue(tax > 0);
        assertTrue(baseFee > 0);
        assertTrue(tax > baseFee);

        vm.prank(keeper);
        uint256[] memory amounts = adapter.collect();
        // The adapter's claim spans its base-fee share plus the entire tax:
        // strictly more than the tax alone, and both buckets emptied.
        assertTrue(amounts[0] > tax);
        assertEq(IPonsV2CurveSnipeViews(curve).creatorTaxBalance(), 0);
        assertEq(IPonsV2BondingCurve(curve).quoteFeeBalance(), 0);
        assertEq(IERC20Like(WETH).balanceOf(address(adapter)), amounts[0]);

        vm.prank(keeper);
        assertEq(adapter.forward(WETH), amounts[0]);
    }

    /// @dev A stale quote must stop the launch rather than execute on terms the
    /// creator never saw. Every economic term on v2 is owner-updatable.
    function test_staleEconomicsPinIsRejectedOnChain() public {
        SinjohPonsV2Adapter adapter = _deployAdapter();
        uint256 launchFee = IPonsV2LaunchFactory(LAUNCH_FACTORY).launchFee();
        IPonsV2LaunchFactory.TokenParams memory params =
            _params(address(adapter), keccak256("stale"));

        vm.prank(creator);
        vm.expectRevert();
        adapter.launch{ value: launchFee }(params, 0, address(0), 0, 0, _none());
    }
}
