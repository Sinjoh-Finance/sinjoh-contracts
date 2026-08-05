// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import {
    SinjohPonsV2BuybackAdapter,
    SinjohPonsV2BuybackPriceGuard
} from "../src/SinjohPonsV2BuybackAdapter.sol";
import { IPonsV2BondingCurve, IPonsV2LaunchFactory } from "../src/interfaces/IPonsV2.sol";

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function deposit() external payable;
}

interface IPonsV2LaunchFactoryAdmin {
    function setLaunchEnabled(bool enabled) external;
}

interface IPonsV2FactoryGraduation {
    function createGraduatedPool(address token) external returns (uint256 positionId);
}

interface IPonsV2SnipeTaxViews {
    function snipeTaxSeconds() external view returns (uint256);
}

/// @notice Runs the buyback route against the real pons v2 deployment on
/// Robinhood Chain mainnet: a real launch, real curve buys, a real graduation
/// through `createGraduatedPool`, and a real hooked v4 swap.
///
/// The unit suite proves the adapter behaves as I modelled pons; this suite
/// proves the model — the launch record's shape, the two-step graduation, the
/// pool key the factory actually builds — is the real one.
///
/// Requires network access. Run with:
///   forge test --match-path 'test/PonsV2Buyback.mainnet.fork.t.sol'
contract PonsV2BuybackMainnetForkTest is TestBase {
    address constant LAUNCH_FACTORY = 0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e;
    address constant POOL_MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    address constant MEME_HOOK = 0xE5e702641Ea86F4ae6cC3cDaeD2B886f976Be044;
    address constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    address constant PONS_OWNER = 0xFdDE5a1E3cDF791Da71E49F817D70C7ceD72CC36;

    uint8 constant PHASE_SWEPT = 1;
    uint8 constant PHASE_POOL_CREATED = 2;

    uint256 constant SIGNER_KEY = uint256(keccak256("sinjoh-pons-v2-buyback-fork-signer"));
    bytes32 constant USER_SALT = keccak256("sinjoh-v2-buyback-fork");

    string constant DEFAULT_RPC = "https://rpc.mainnet.chain.robinhood.com";

    SinjohPonsV2BuybackAdapter adapter;
    SinjohPonsV2BuybackPriceGuard guard;
    address creator = address(0xC4EA704);

    function setUp() public {
        vm.createSelectFork(vm.envOr("ROBINHOOD_RPC_URL", DEFAULT_RPC));
        // Operational flag, normalised the same way the adapter fork suite
        // does: these tests exercise the buyback route, not pons's uptime.
        if (!IPonsV2LaunchFactory(LAUNCH_FACTORY).launchEnabled()) {
            vm.prank(PONS_OWNER);
            IPonsV2LaunchFactoryAdmin(LAUNCH_FACTORY).setLaunchEnabled(true);
        }
        adapter = new SinjohPonsV2BuybackAdapter(
            LAUNCH_FACTORY,
            POOL_MANAGER,
            WETH,
            LAUNCH_FACTORY.codehash,
            POOL_MANAGER.codehash,
            WETH.codehash
        );
        guard = new SinjohPonsV2BuybackPriceGuard(
            LAUNCH_FACTORY, WETH, LAUNCH_FACTORY.codehash, WETH.codehash, vm.addr(SIGNER_KEY)
        );

        vm.deal(creator, 100 ether);
        vm.deal(address(this), 100 ether);
        IERC20Like(WETH).deposit{ value: 50 ether }();
        IERC20Like(WETH).approve(address(adapter), type(uint256).max);
    }

    receive() external payable { }

    /// @dev The graduated-pool dependencies the adapter derives its keys from
    /// must be the ones pinned in PONS-V2-FINDINGS.md.
    function test_pinnedDependenciesAgreeOnChain() public view {
        assertEq(IPonsV2LaunchFactory(LAUNCH_FACTORY).poolManager(), POOL_MANAGER);
        assertEq(IPonsV2LaunchFactory(LAUNCH_FACTORY).memeHook(), MEME_HOOK);
        assertEq(adapter.memeHook(), MEME_HOOK);
    }

    /// @dev The launch record transcription: a fresh launch must come back
    /// with the fields the adapter routes on.
    function test_launchRecordMatchesTranscription() public {
        (address token, address curve) = _launch();
        IPonsV2LaunchFactory.LaunchedToken memory record =
            IPonsV2LaunchFactory(LAUNCH_FACTORY).getLaunchedToken(token);
        assertTrue(record.exists);
        assertEq(record.token, token);
        assertEq(record.curve, curve);
        assertEq(record.pairToken, address(0));
        assertEq(uint256(record.phase), 0);
        // Config 0's graduated-pool terms, snapshotted at launch.
        assertEq(uint256(record.poolFee), 0);
        assertEq(uint256(int256(record.tickSpacing)), 200);
    }

    function test_buysOnTheRealCurveBeforeGraduation() public {
        (address token,) = _launch();
        uint256 amountIn = 0.5 ether;

        uint256 wethBefore = IERC20Like(WETH).balanceOf(address(this));
        adapter.swap(WETH, token, amountIn, 1, "");
        uint256 received = IERC20Like(token).balanceOf(address(this));

        assertTrue(received > 0);
        assertEq(IERC20Like(WETH).balanceOf(address(this)), wethBefore - amountIn);
        assertEq(IERC20Like(WETH).balanceOf(address(adapter)), 0);
        assertEq(IERC20Like(token).balanceOf(address(adapter)), 0);
        assertEq(address(adapter).balance, 0);
    }

    /// @dev A buy sized past the graduation threshold gets clamped and
    /// refunded by the real curve; the adapter must refuse that fill
    /// atomically rather than deliver a partial buyback.
    function test_crossingBuyThroughTheAdapterFailsAtomically() public {
        (address token,) = _launch();
        // Config 0 graduates at 4.2 ether of real quote reserve.
        vm.expectRevert(SinjohPonsV2BuybackAdapter.UnexpectedBalance.selector);
        adapter.swap(WETH, token, 6 ether, 1, "");
    }

    /// @dev The full lifecycle: graduation closes the curve, the Swept window
    /// has no market, `createGraduatedPool` opens the v4 pool, and the same
    /// route then buys through it — under the real meme hook.
    function test_swapsThroughTheRealGraduatedPool() public {
        (address token, address curve) = _launch();

        address whale = address(0xDECAF);
        vm.deal(whale, 100 ether);
        vm.prank(whale);
        IPonsV2BondingCurve(curve).buy{ value: 10 ether }(10 ether, 1, whale);
        assertTrue(IPonsV2BondingCurve(curve).graduated());

        // Curve drained, pool not yet seeded: no market on either venue.
        IPonsV2LaunchFactory.LaunchedToken memory record =
            IPonsV2LaunchFactory(LAUNCH_FACTORY).getLaunchedToken(token);
        assertEq(uint256(record.phase), PHASE_SWEPT);
        vm.expectRevert(
            abi.encodeWithSelector(SinjohPonsV2BuybackAdapter.NoMarket.selector, PHASE_SWEPT)
        );
        adapter.swap(WETH, token, 0.5 ether, 1, "");

        // Permissionless seeding, exactly what a keeper would do.
        IPonsV2FactoryGraduation(LAUNCH_FACTORY).createGraduatedPool(token);
        record = IPonsV2LaunchFactory(LAUNCH_FACTORY).getLaunchedToken(token);
        assertEq(uint256(record.phase), PHASE_POOL_CREATED);

        uint256 amountIn = 0.5 ether;
        uint256 wethBefore = IERC20Like(WETH).balanceOf(address(this));
        adapter.swap(WETH, token, amountIn, 1, "");
        uint256 received = IERC20Like(token).balanceOf(address(this));

        assertTrue(received > 0);
        assertEq(IERC20Like(WETH).balanceOf(address(this)), wethBefore - amountIn);
        assertEq(IERC20Like(WETH).balanceOf(address(adapter)), 0);
        assertEq(IERC20Like(token).balanceOf(address(adapter)), 0);
        assertEq(address(adapter).balance, 0);
    }

    /// @dev The output floor holds on the real pool, after the hook's cut.
    function test_outputFloorIsEnforcedOnTheRealPool() public {
        (address token, address curve) = _launch();
        address whale = address(0xDECAF);
        vm.deal(whale, 100 ether);
        vm.prank(whale);
        IPonsV2BondingCurve(curve).buy{ value: 10 ether }(10 ether, 1, whale);
        IPonsV2FactoryGraduation(LAUNCH_FACTORY).createGraduatedPool(token);

        uint256 amountIn = 0.5 ether;
        adapter.swap(WETH, token, amountIn, 1, "");
        uint256 realistic = IERC20Like(token).balanceOf(address(this));

        vm.expectPartialRevert(SinjohPonsV2BuybackAdapter.InsufficientOutput.selector);
        adapter.swap(WETH, token, amountIn, realistic * 10, "");
    }

    /// @dev The guard's launch checks run against the real factory record.
    function test_guardAcceptsARealLaunchAndItsSignedFloor() public {
        (address token,) = _launch();
        uint48 validAfter = uint48(block.timestamp);
        uint48 validUntil = uint48(block.timestamp + 60);
        uint256 amountIn = 0.5 ether;
        bytes32 digest = guard.floorDigest(
            address(this), token, WETH, token, amountIn, keccak256(""), 975, validAfter, validUntil
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            SIGNER_KEY, keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", digest))
        );
        (uint256 minimum, uint48 until) = guard.minimumOutput(
            token,
            WETH,
            token,
            amountIn,
            keccak256(""),
            abi.encode(uint256(975), validAfter, validUntil, abi.encodePacked(r, s, v))
        );
        assertEq(minimum, 975);
        assertEq(until, validUntil);

        vm.expectRevert(
            abi.encodeWithSelector(
                SinjohPonsV2BuybackPriceGuard.UnknownLaunch.selector, address(0xDEAD)
            )
        );
        guard.minimumOutput(
            address(0xDEAD),
            WETH,
            address(0xDEAD),
            amountIn,
            keccak256(""),
            abi.encode(uint256(975), validAfter, validUntil, abi.encodePacked(r, s, v))
        );
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    /// @dev A real native-quote launch through the real factory, warped past
    /// the snipe window so buyback buys — whose curve-side recipient is the
    /// adapter, which is never exempt — price cleanly, exactly as they would
    /// in production where buybacks only run once fees have accrued.
    function _launch() internal returns (address token, address curve) {
        IPonsV2LaunchFactory factory = IPonsV2LaunchFactory(LAUNCH_FACTORY);
        IPonsV2LaunchFactory.TokenParams memory params;
        params.name = "Sinjoh Buyback Fork";
        params.symbol = "SJBB";
        params.creatorFeeRecipient = creator;
        params.creatorTaxBps = 0;
        params.buybackEnabled = false;
        params.expectedEconomics = factory.previewLaunchEconomics(0, address(0));
        params.salt = USER_SALT;

        vm.prank(creator);
        (token, curve) = factory.launchToken{ value: factory.launchFee() }(
            params, 0, address(0), new address[](0)
        );
        vm.warp(block.timestamp + IPonsV2SnipeTaxViews(LAUNCH_FACTORY).snipeTaxSeconds() + 1);
    }
}
