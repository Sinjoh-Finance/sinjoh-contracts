// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { SinjohPonsV1LaunchAdapter } from "../src/SinjohPonsV1LaunchAdapter.sol";
import { SinjohPonsV1LaunchAdapterFactory } from "../src/SinjohPonsV1LaunchAdapterFactory.sol";
import { IPonsV1LaunchFactory, IPonsV1Locker } from "../src/interfaces/IPonsV1.sol";
import { RouterTypes } from "sinjoh-fee-router/src/RouterTypes.sol";
import { SinjohFeeRouter } from "sinjoh-fee-router/src/SinjohFeeRouter.sol";
import { SinjohFeeRouterFactory } from "sinjoh-fee-router/src/SinjohFeeRouterFactory.sol";

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IWETHLike is IERC20Like {
    function deposit() external payable;
}

/// @notice The integration the unit suites cannot cover: the **real**
/// `SinjohFeeRouter` driven by a **real** launchpad adapter against the **real**
/// pons deployment on Robinhood Chain mainnet.
///
/// Every other adapter test binds `MockRouter`, so until this file existed the
/// router and the adapters had never executed together. This exercises the full
/// chain — predict router, deploy naming the adapter, deploy adapter, launch,
/// bind, accrue, collect, forward, sync, process, pay out.
///
/// pons v1 is used because it is the live launchpad: `launchEnabled` is true and
/// it is taking thousands of launches, while v2 is paused by pons for a fault in
/// their own code. The v2 path has its own fork suite.
///
///   node script/rpc-proxy.mjs &
///   forge test --match-path 'test/RouterIntegration.fork.t.sol' \
///     --fork-url http://127.0.0.1:8545
contract RouterIntegrationForkTest is TestBase {
    address constant V1_FACTORY = 0xA5aAb3F0c6EeadF30Ef1D3Eb997108E976351feB;
    address constant V1_LOCKER = 0x736D76699C26D0d966744cAe304C000d471f7F35;
    address constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    /// @dev The live SwapRouter02-interface adapter from mainnet-deployments.json.
    address constant SWAP_ADAPTER = 0xc9F600ebaf9EE1F4a24568D2e4Af9E8df1e07D7B;
    uint256 constant CHAIN_ID = 4663;
    bytes32 constant USER_SALT = keccak256("sinjoh-router-integration");

    string constant DEFAULT_RPC = "https://rpc.mainnet.chain.robinhood.com";

    address constant PROTOCOL_RECIPIENT = address(0x1001);
    address constant WALLET = address(0x2002);

    SinjohFeeRouter implementation;
    SinjohFeeRouterFactory routerFactory;
    SinjohPonsV1LaunchAdapterFactory adapterFactory;

    address creator = address(0xC4EA704);
    address keeper = address(0xBEEF);

    function setUp() public {
        vm.createSelectFork(vm.envOr("ROBINHOOD_RPC_URL", DEFAULT_RPC));
        implementation = new SinjohFeeRouter();
        routerFactory = new SinjohFeeRouterFactory(address(implementation));
        adapterFactory = new SinjohPonsV1LaunchAdapterFactory(V1_FACTORY, V1_LOCKER, WETH, CHAIN_ID);
        vm.deal(creator, 100 ether);
    }

    /// @dev The ordering the whole design turns on: both addresses derive from
    /// (creator, userSalt) alone, so neither salt can reference the other.
    function _deployPair()
        internal
        returns (SinjohFeeRouter router, SinjohPonsV1LaunchAdapter adapter)
    {
        address predictedAdapter = adapterFactory.predictAddress(creator, USER_SALT);
        address predictedRouter = routerFactory.predictLaunchpadAddress(creator, USER_SALT);

        RouterTypes.Config memory config = _config(predictedAdapter);
        vm.prank(creator);
        address deployedRouter = routerFactory.deployForLaunchpad(creator, USER_SALT, config);
        assertEq(deployedRouter, predictedRouter);

        vm.prank(creator);
        address deployedAdapter = adapterFactory.deploy(creator, deployedRouter, USER_SALT);
        assertEq(deployedAdapter, predictedAdapter);

        router = SinjohFeeRouter(payable(deployedRouter));
        adapter = SinjohPonsV1LaunchAdapter(payable(deployedAdapter));
        assertEq(router.launchpadAdapter(), address(adapter));
    }

    /// @dev One bucket, WETH out, one wallet. Deliberately swap-free on the
    /// payout side so a failure implicates the router or the adapter rather than
    /// pool depth on a brand-new token.
    function _config(address launchpadAdapter)
        internal
        pure
        returns (RouterTypes.Config memory config)
    {
        RouterTypes.Allocation[] memory allocations = new RouterTypes.Allocation[](1);
        allocations[0] = RouterTypes.Allocation({
            destination: WALLET, bps: 10_000, isSink: false, creatorMayRepoint: true, sinkConfig: ""
        });

        RouterTypes.Bucket[] memory buckets = new RouterTypes.Bucket[](1);
        buckets[0] = RouterTypes.Bucket({
            output: RouterTypes.AssetRef(RouterTypes.AssetKind.FIXED_ERC20, WETH),
            bps: 10_000,
            route: RouterTypes.Route(address(0), ""),
            allocations: allocations
        });

        // v1 pays fees in both pool assets, so the subject needs a route even
        // when the payout side needs none.
        RouterTypes.Normalization[] memory normalizations = new RouterTypes.Normalization[](1);
        normalizations[0] = RouterTypes.Normalization({
            asset: RouterTypes.AssetRef(RouterTypes.AssetKind.SUBJECT, address(0)),
            route: RouterTypes.Route(SWAP_ADAPTER, abi.encode(uint24(10_000)))
        });

        config = RouterTypes.Config({
            creator: creatorAddress(),
            protocolFeeRecipient: PROTOCOL_RECIPIENT,
            weth: WETH,
            launchpadAdapter: launchpadAdapter,
            normalizations: normalizations,
            buckets: buckets
        });
    }

    function creatorAddress() internal pure returns (address) {
        return address(0xC4EA704);
    }

    function _params(address feeWallet)
        internal
        pure
        returns (IPonsV1LaunchFactory.LaunchParams memory params)
    {
        params.name = "Sinjoh Integration";
        params.symbol = "SJINT";
        params.logo = "";
        params.description = "router integration fork test";
        params.feeWallet = feeWallet;
    }

    // ------------------------------------------------------------------

    function test_v1IsTheLiveLaunchpad() public view {
        assertTrue(IPonsV1LaunchFactory(V1_FACTORY).launchEnabled());
        assertEq(IPonsV1LaunchFactory(V1_FACTORY).locker(), V1_LOCKER);
    }

    /// @dev The real router, bound by the real adapter, in a real launch.
    function test_realRouterIsBoundByRealAdapterOnALiveLaunch() public {
        (SinjohFeeRouter router, SinjohPonsV1LaunchAdapter adapter) = _deployPair();
        uint256 launchFee = IPonsV1LaunchFactory(V1_FACTORY).launchFee();

        vm.prank(creator);
        address token = adapter.launch{ value: launchFee }(
            _params(address(adapter)), 0, 0, keccak256("integration-1")
        );

        assertTrue(token != address(0));
        assertEq(adapter.subject(), token);
        // The router was bound by the adapter, not the creator.
        assertTrue(router.bound());
        assertEq(router.subject(), token);
        // And the locker still resolves this launch's payout to the adapter.
        assertTrue(adapter.feeRedirectIntact());
    }

    function test_developerBuyReachesTheCreatorNotTheRouter() public {
        (SinjohFeeRouter router, SinjohPonsV1LaunchAdapter adapter) = _deployPair();
        uint256 launchFee = IPonsV1LaunchFactory(V1_FACTORY).launchFee();
        uint256 devBuy = 0.05 ether;

        vm.prank(creator);
        address token = adapter.launch{ value: launchFee + devBuy }(
            _params(address(adapter)), 0, 0, keccak256("integration-2")
        );

        // v1 delivers the first buy to the fee wallet; it must not be mistaken
        // for fee revenue by either the adapter or the router.
        assertTrue(IERC20Like(token).balanceOf(creator) > 0);
        assertEq(IERC20Like(token).balanceOf(address(adapter)), 0);
        assertEq(IERC20Like(token).balanceOf(address(router)), 0);
    }

    function test_collectOnAnIdleLaunchIsANoOp() public {
        (, SinjohPonsV1LaunchAdapter adapter) = _deployPair();
        uint256 launchFee = IPonsV1LaunchFactory(V1_FACTORY).launchFee();

        vm.prank(creator);
        adapter.launch{ value: launchFee }(
            _params(address(adapter)), 0, 0, keccak256("integration-3")
        );

        // No trades yet: the locker reverts NoFeesToCollect, which a keeper poll
        // must not see as a failure.
        vm.prank(keeper);
        uint256[] memory amounts = adapter.collect();
        assertEq(amounts.length, 2);
        assertEq(amounts[0], 0);
        assertEq(amounts[1], 0);
    }

    /// @dev The whole router path against real contracts: adapter forwards, the
    /// real router accounts, splits, converts and pays out, and ends solvent.
    function test_fullRouterPathFromAdapterForwardToWalletPayout() public {
        (SinjohFeeRouter router, SinjohPonsV1LaunchAdapter adapter) = _deployPair();
        uint256 launchFee = IPonsV1LaunchFactory(V1_FACTORY).launchFee();

        vm.prank(creator);
        adapter.launch{ value: launchFee }(
            _params(address(adapter)), 0, 0, keccak256("integration-4")
        );

        // Stand in for accrued WETH fees arriving at the adapter. The upstream
        // accrual path is covered by test_collectOnAnIdleLaunchIsANoOp and the
        // v2 suite; this isolates the router.
        uint256 fees = 1 ether;
        vm.deal(address(this), fees);
        IWETHLike(WETH).deposit{ value: fees }();
        IWETHLike(WETH).transfer(address(adapter), fees);

        vm.prank(keeper);
        assertEq(adapter.forward(WETH), fees);
        assertEq(IERC20Like(WETH).balanceOf(address(router)), fees);

        vm.prank(keeper);
        (uint256 gross, uint256 fee) = router.sync(WETH);
        assertEq(gross, fees);
        // 1% protocol fee, charged exactly once.
        assertEq(fee, fees / 100);
        assertEq(router.protocolOwed(WETH), fees / 100);
        assertEq(router.totalLiability(WETH), fees);

        uint256 bucketShare = router.bucketInputOwed(0, WETH);
        assertEq(bucketShare, fees - fee);

        vm.prank(keeper);
        router.processBucket(0, WETH, bucketShare, 0, "");
        assertEq(router.walletOwed(WALLET, WETH), bucketShare);

        vm.prank(keeper);
        router.sendWallet(WALLET, WETH, bucketShare);
        vm.prank(keeper);
        router.sendProtocolFee(WETH, fee);

        assertEq(IERC20Like(WETH).balanceOf(WALLET), bucketShare);
        assertEq(IERC20Like(WETH).balanceOf(PROTOCOL_RECIPIENT), fee);
        // Everything left, and the router is empty and solvent.
        assertEq(IERC20Like(WETH).balanceOf(address(router)), 0);
        assertEq(router.totalLiability(WETH), 0);
    }

    function test_adapterCannotLaunchIntoARouterThatDidNotNameIt() public {
        address predictedAdapter = adapterFactory.predictAddress(creator, USER_SALT);
        // A router naming somebody else entirely.
        RouterTypes.Config memory config = _config(address(0xDEAD));
        vm.prank(creator);
        address strangerRouter = routerFactory.deployForLaunchpad(creator, USER_SALT, config);

        vm.prank(creator);
        SinjohPonsV1LaunchAdapter adapter = SinjohPonsV1LaunchAdapter(
            payable(adapterFactory.deploy(creator, strangerRouter, USER_SALT))
        );
        assertEq(address(adapter), predictedAdapter);

        uint256 launchFee = IPonsV1LaunchFactory(V1_FACTORY).launchFee();
        vm.prank(creator);
        vm.expectRevert(
            abi.encodeWithSelector(
                SinjohPonsV1LaunchAdapter.RouterDidNotNameAdapter.selector, address(0xDEAD)
            )
        );
        adapter.launch{ value: launchFee }(
            _params(address(adapter)), 0, 0, keccak256("integration-5")
        );
    }

    function test_launchRejectsAFeeWalletOtherThanTheAdapter() public {
        (, SinjohPonsV1LaunchAdapter adapter) = _deployPair();
        uint256 launchFee = IPonsV1LaunchFactory(V1_FACTORY).launchFee();

        vm.prank(creator);
        vm.expectRevert(SinjohPonsV1LaunchAdapter.FeeWalletNotAdapter.selector);
        adapter.launch{ value: launchFee }(_params(creator), 0, 0, keccak256("integration-6"));
    }

    function test_routerRejectsAnAssetWithNoNormalizationRoute() public {
        (SinjohFeeRouter router, SinjohPonsV1LaunchAdapter adapter) = _deployPair();
        uint256 launchFee = IPonsV1LaunchFactory(V1_FACTORY).launchFee();
        vm.prank(creator);
        adapter.launch{ value: launchFee }(
            _params(address(adapter)), 0, 0, keccak256("integration-7")
        );

        vm.expectRevert(
            abi.encodeWithSelector(SinjohFeeRouter.UnsupportedAsset.selector, V1_LOCKER)
        );
        router.sync(V1_LOCKER);
    }

    function test_intakeAssetsCoverBothPoolAssets() public {
        (, SinjohPonsV1LaunchAdapter adapter) = _deployPair();
        uint256 launchFee = IPonsV1LaunchFactory(V1_FACTORY).launchFee();
        vm.prank(creator);
        address token = adapter.launch{ value: launchFee }(
            _params(address(adapter)), 0, 0, keccak256("integration-8")
        );

        address[] memory assets = adapter.intakeAssets();
        assertEq(assets.length, 2);
        assertEq(assets[0], token);
        assertEq(assets[1], WETH);
    }
}
