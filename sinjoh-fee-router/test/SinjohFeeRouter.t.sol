// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockSink } from "./mocks/MockSink.sol";
import { MockSwapAdapter } from "./mocks/MockSwapAdapter.sol";
import { RouterTypes } from "../src/RouterTypes.sol";
import { SinjohFeeRouter } from "../src/SinjohFeeRouter.sol";
import { SinjohFeeRouterFactory } from "../src/SinjohFeeRouterFactory.sol";

contract SinjohFeeRouterTest is TestBase {
    address internal constant PROTOCOL_RECIPIENT = address(0x1001);
    address internal constant WALLET = address(0x2002);
    address internal constant NEW_WALLET = address(0x3003);
    address internal constant LAUNCHPAD_ADAPTER = address(0x4004);

    MockERC20 internal subjectToken;
    MockERC20 internal weth;
    MockERC20 internal payoutToken;
    /// @dev Stands in for a launchpad's quote asset (USDG, an equity token).
    MockERC20 internal quoteToken;
    MockSwapAdapter internal adapter;
    MockSwapAdapter internal quoteAdapter;
    MockSink internal sink;
    SinjohFeeRouter internal implementation;
    SinjohFeeRouterFactory internal factory;
    SinjohFeeRouter internal router;

    function setUp() public {
        subjectToken = new MockERC20("Subject", "SUB");
        weth = new MockERC20("Wrapped Ether", "WETH");
        payoutToken = new MockERC20("Payout", "PAY");
        quoteToken = new MockERC20("Global Dollar", "USDG");
        adapter = new MockSwapAdapter();
        quoteAdapter = new MockSwapAdapter();
        sink = new MockSink();
        implementation = new SinjohFeeRouter();
        factory = new SinjohFeeRouterFactory(address(implementation));
        RouterTypes.Config memory config = _config();
        router = SinjohFeeRouter(payable(factory.deploy(address(this), bytes32("TEST"), config)));
        router.bind(address(subjectToken));
    }

    function testImplementationAndCloneCannotBeReinitialized() public {
        vm.expectRevert(SinjohFeeRouter.AlreadyInitialized.selector);
        implementation.initialize(_config());
        vm.expectRevert(SinjohFeeRouter.AlreadyInitialized.selector);
        router.initialize(_config());
    }

    function testFactoryPredictionAndDeploymentAreIdempotent() public {
        RouterTypes.Config memory config = _config();
        address predicted = factory.predictAddress(address(this), bytes32("SECOND"), config);
        address deployed = factory.deploy(address(this), bytes32("SECOND"), config);
        assertEq(deployed, predicted);
        assertEq(factory.deploy(address(this), bytes32("SECOND"), config), deployed);
    }

    function testLaunchpadPredictionDoesNotDependOnConfiguration() public {
        RouterTypes.Config memory config = _config();
        bytes32 salt = bytes32("LAUNCHPAD");
        address predicted = factory.predictLaunchpadAddress(address(this), salt);
        address deployed = factory.deployForLaunchpad(address(this), salt, config);
        assertEq(deployed, predicted);
        assertEq(factory.deployForLaunchpad(address(this), salt, config), deployed);

        // Address stability is what lets an adapter be named in a config that
        // has not been deployed yet; a changed config must still be refused.
        config.protocolFeeRecipient = NEW_WALLET;
        vm.expectRevert(SinjohFeeRouterFactory.ConfigMismatch.selector);
        factory.deployForLaunchpad(address(this), salt, config);
    }

    /// @dev The router's entire launchpad surface. It never calls the adapter
    /// and does not know what it integrates with; the adapter may bind, once.
    function testConfiguredLaunchpadAdapterMayBindTheSubject() public {
        RouterTypes.Config memory config = _config();
        config.launchpadAdapter = LAUNCHPAD_ADAPTER;
        SinjohFeeRouter adapterRouter =
            SinjohFeeRouter(payable(factory.deploy(address(this), bytes32("ADAPTER"), config)));

        vm.prank(LAUNCHPAD_ADAPTER);
        adapterRouter.bind(address(subjectToken));

        assertTrue(adapterRouter.bound());
        assertEq(adapterRouter.subject(), address(subjectToken));
        assertEq(adapterRouter.launchpadAdapter(), LAUNCHPAD_ADAPTER);
    }

    function testCreatorMayStillBindAlongsideTheAdapter() public {
        RouterTypes.Config memory config = _config();
        config.launchpadAdapter = LAUNCHPAD_ADAPTER;
        SinjohFeeRouter adapterRouter =
            SinjohFeeRouter(payable(factory.deploy(address(this), bytes32("BOTH"), config)));

        adapterRouter.bind(address(subjectToken));
        assertTrue(adapterRouter.bound());
    }

    function testNobodyElseMayBind() public {
        RouterTypes.Config memory config = _config();
        config.launchpadAdapter = LAUNCHPAD_ADAPTER;
        SinjohFeeRouter adapterRouter =
            SinjohFeeRouter(payable(factory.deploy(address(this), bytes32("STRANGER"), config)));

        vm.prank(address(0xBAD));
        vm.expectRevert(SinjohFeeRouter.Unauthorized.selector);
        adapterRouter.bind(address(subjectToken));
    }

    function testBindHappensOnlyOnce() public {
        vm.expectRevert(SinjohFeeRouter.AlreadyBound.selector);
        router.bind(address(subjectToken));
    }

    /// @dev The creator-direct path: a launchpad delivers first-buy tokens to
    /// the router itself. Without this the tokens would be indistinguishable
    /// from fee revenue and `sync` would route them away from the creator.
    function testBindCanReturnTheExactLaunchBuyToCreator() public {
        RouterTypes.Config memory config = _config();
        SinjohFeeRouter launchRouter =
            SinjohFeeRouter(payable(factory.deploy(address(this), bytes32("LAUNCH_BUY"), config)));
        subjectToken.mint(address(launchRouter), 1_500);

        launchRouter.bindAndSendLaunchBuy(address(subjectToken), 1_000);

        assertTrue(launchRouter.bound());
        assertEq(launchRouter.subject(), address(subjectToken));
        assertEq(subjectToken.balanceOf(address(this)), 1_000);
        // The remainder stays available as ordinary fee revenue.
        assertEq(subjectToken.balanceOf(address(launchRouter)), 500);

        weth.mint(address(adapter), 500);
        launchRouter.sync(address(subjectToken));
        assertEq(subjectToken.balanceOf(address(launchRouter)), 0);
    }

    function testBindAndSendLaunchBuyRejectsZeroAmount() public {
        RouterTypes.Config memory config = _config();
        SinjohFeeRouter launchRouter =
            SinjohFeeRouter(payable(factory.deploy(address(this), bytes32("ZERO_BUY"), config)));
        vm.expectRevert(SinjohFeeRouter.InvalidAmount.selector);
        launchRouter.bindAndSendLaunchBuy(address(subjectToken), 0);
    }

    function testBindAndSendLaunchBuyIsCreatorOnly() public {
        RouterTypes.Config memory config = _config();
        config.launchpadAdapter = LAUNCHPAD_ADAPTER;
        SinjohFeeRouter launchRouter =
            SinjohFeeRouter(payable(factory.deploy(address(this), bytes32("BUY_AUTH"), config)));
        subjectToken.mint(address(launchRouter), 1_000);

        // Binding is delegable to the adapter; moving value to the creator is not.
        vm.prank(LAUNCHPAD_ADAPTER);
        vm.expectRevert(SinjohFeeRouter.Unauthorized.selector);
        launchRouter.bindAndSendLaunchBuy(address(subjectToken), 1_000);
    }

    /// @dev The case that motivated per-asset normalization. A launchpad that
    /// pairs against a quote asset pays fees in that asset, which is neither the
    /// subject nor WETH. The rate stands in for a 6-decimal asset normalizing
    /// into 18-decimal WETH.
    function testQuoteAssetIntakeNormalizesThroughItsOwnRoute() public {
        RouterTypes.Config memory config = _quotePairConfig();
        SinjohFeeRouter quoteRouter =
            SinjohFeeRouter(payable(factory.deploy(address(this), bytes32("QUOTE"), config)));
        quoteRouter.bind(address(subjectToken));

        quoteAdapter.setRate(1e12, 1);
        quoteToken.mint(address(quoteRouter), 1_000);
        weth.mint(address(quoteAdapter), 1_000 * 1e12);

        (uint256 gross,) = quoteRouter.sync(address(quoteToken));

        assertEq(gross, 1_000);
        assertEq(quoteToken.balanceOf(address(quoteRouter)), 0);
        assertEq(quoteRouter.totalLiability(address(weth)), 1_000 * 1e12);
    }

    function testAssetWithoutANormalizationRouteIsRejected() public {
        payoutToken.mint(address(router), 1_000);
        vm.expectRevert(
            abi.encodeWithSelector(SinjohFeeRouter.UnsupportedAsset.selector, address(payoutToken))
        );
        router.sync(address(payoutToken));
    }

    /// @dev Adapters wrap before forwarding, so intake stays uniformly ERC-20.
    function testNativeIntakeIsRejected() public {
        vm.expectRevert(SinjohFeeRouter.NativeIntakeUnsupported.selector);
        router.sync(address(0));
    }

    function testSubjectIsNormalizedBeforeWethIsSplit() public {
        subjectToken.mint(address(router), 10_000);
        weth.mint(address(adapter), 10_000);

        (uint256 gross, uint256 fee) = router.sync(address(subjectToken));

        assertEq(gross, 10_000);
        assertEq(fee, 100);
        assertEq(subjectToken.balanceOf(address(router)), 0);
        assertEq(weth.balanceOf(address(router)), 10_000);
        assertEq(router.protocolOwed(address(weth)), 100);
        assertEq(router.protocolOwed(address(subjectToken)), 0);
        assertEq(router.bucketInputOwed(0, address(weth)), 4_950);
        assertEq(router.bucketInputOwed(1, address(weth)), 4_950);
        assertEq(router.totalLiability(address(weth)), 10_000);
        assertEq(router.totalLiability(address(subjectToken)), 0);
    }

    function testWethIntakeUsesTheSameDistributionPath() public {
        weth.mint(address(router), 10_000);
        router.sync(address(weth));

        assertEq(router.protocolOwed(address(weth)), 100);
        assertEq(router.bucketInputOwed(0, address(weth)), 4_950);
        assertEq(router.bucketInputOwed(1, address(weth)), 4_950);
    }

    function testWethBucketCreditsWalletAndSinkWithoutASwap() public {
        weth.mint(address(router), 10_000);
        router.sync(address(weth));
        router.processBucket(0, address(weth), 4_950, 0, "");

        assertEq(router.walletOwed(WALLET, address(weth)), 2_475);
        assertEq(router.sinkOwed(router.allocationKey(0, 1), address(weth)), 2_475);

        router.sendWallet(WALLET, address(weth), 2_475);
        router.fundSink(0, 1, 2_475);
        assertEq(weth.balanceOf(WALLET), 2_475);
        assertEq(weth.balanceOf(address(sink)), 2_475);
    }

    function testBucketSwapsOnlyWethIntoItsPayoutAsset() public {
        weth.mint(address(router), 10_000);
        subjectToken.mint(address(adapter), 10_000);
        router.sync(address(weth));

        uint256 amountOut = router.processBucket(1, address(weth), 4_950, 0, "");

        assertEq(amountOut, 4_950);
        assertEq(router.bucketInputOwed(1, address(weth)), 0);
        assertEq(router.walletOwed(router.BURN_ADDRESS(), address(subjectToken)), 4_950);
        assertEq(router.totalLiability(address(weth)), 5_050);
        assertEq(router.totalLiability(address(subjectToken)), 4_950);
    }

    function testASecondTokenBucketUsesOneDirectWethSwap() public {
        RouterTypes.Config memory config = _threeBucketConfig();
        SinjohFeeRouter three =
            SinjohFeeRouter(payable(factory.deploy(address(this), bytes32("THREE"), config)));
        three.bind(address(subjectToken));
        weth.mint(address(three), 10_000);
        payoutToken.mint(address(adapter), 10_000);
        three.sync(address(weth));

        uint256 amount = three.bucketInputOwed(2, address(weth));
        three.processBucket(2, address(weth), amount, 0, "");

        assertEq(three.walletOwed(NEW_WALLET, address(payoutToken)), amount);
    }

    function testNativeBucketUnwrapsWethAndSendsEth() public {
        RouterTypes.Config memory config = _nativeConfig();
        SinjohFeeRouter nativeRouter =
            SinjohFeeRouter(payable(factory.deploy(address(this), bytes32("NATIVE"), config)));
        nativeRouter.bind(address(subjectToken));
        weth.mint(address(nativeRouter), 10_000);
        vm.deal(address(adapter), 10_000);
        nativeRouter.sync(address(weth));
        nativeRouter.processBucket(0, address(weth), 9_900, 0, "");

        uint256 beforeBalance = WALLET.balance;
        nativeRouter.sendWallet(WALLET, address(0), 9_900);
        assertEq(WALLET.balance - beforeBalance, 9_900);
    }

    function testPartialProcessingIsAllowedAndRemainderStaysCredited() public {
        weth.mint(address(router), 10_000);
        router.sync(address(weth));
        router.processBucket(0, address(weth), 1_000, 0, "");
        assertEq(router.bucketInputOwed(0, address(weth)), 3_950);
        router.processBucket(0, address(weth), 3_950, 0, "");
        assertEq(router.bucketInputOwed(0, address(weth)), 0);
    }

    function testCreatorCanRepointOnlyFutureWalletCredits() public {
        weth.mint(address(router), 10_000);
        router.sync(address(weth));
        router.processBucket(0, address(weth), 2_000, 0, "");
        router.repointWallet(0, 0, NEW_WALLET);
        router.processBucket(0, address(weth), 2_950, 0, "");

        assertEq(router.walletOwed(WALLET, address(weth)), 1_000);
        assertEq(router.walletOwed(NEW_WALLET, address(weth)), 1_475);
    }

    function testSwapFailureLeavesTheBucketCredited() public {
        weth.mint(address(router), 10_000);
        subjectToken.mint(address(adapter), 10_000);
        router.sync(address(weth));
        adapter.setSpendLess(true);

        vm.expectPartialRevert(SinjohFeeRouter.UnexpectedBalanceDelta.selector);
        router.processBucket(1, address(weth), 4_950, 0, "");

        assertEq(router.bucketInputOwed(1, address(weth)), 4_950);
        assertEq(router.totalLiability(address(weth)), 10_000);
    }

    function testUnsupportedAssetsCannotEnterTheAccounting() public {
        payoutToken.mint(address(router), 10_000);
        vm.expectPartialRevert(SinjohFeeRouter.UnsupportedAsset.selector);
        router.sync(address(payoutToken));
        assertEq(router.totalLiability(address(payoutToken)), 0);
    }

    function testProtocolFeeRemainderCannotBeAvoidedBySplitting() public {
        weth.mint(address(router), 50);
        router.sync(address(weth));
        weth.mint(address(router), 50);
        router.sync(address(weth));
        assertEq(router.protocolOwed(address(weth)), 1);
        assertEq(router.totalLiability(address(weth)), 100);
    }

    function testAllNormalizedValueCanLeaveTheRouter() public {
        weth.mint(address(router), 10_000);
        subjectToken.mint(address(adapter), 10_000);
        router.sync(address(weth));
        router.processBucket(0, address(weth), 4_950, 0, "");
        router.processBucket(1, address(weth), 4_950, 0, "");
        router.sendProtocolFee(address(weth), 100);
        router.sendWallet(WALLET, address(weth), 2_475);
        router.fundSink(0, 1, 2_475);
        router.sendWallet(router.BURN_ADDRESS(), address(subjectToken), 4_950);

        assertEq(router.totalLiability(address(weth)), 0);
        assertEq(router.totalLiability(address(subjectToken)), 0);
        assertEq(weth.balanceOf(address(router)), 0);
        assertEq(subjectToken.balanceOf(address(router)), 0);
    }

    /// @dev The default: fees arrive as the subject token and normalize to WETH.
    function _subjectNormalization()
        internal
        view
        returns (RouterTypes.Normalization[] memory normalizations)
    {
        normalizations = new RouterTypes.Normalization[](1);
        normalizations[0] = RouterTypes.Normalization({
            asset: RouterTypes.AssetRef(RouterTypes.AssetKind.SUBJECT, address(0)),
            route: RouterTypes.Route(address(adapter), hex"01")
        });
    }

    /// @dev A launchpad paying fees in its quote asset. Both the subject and the
    /// quote asset need routes, each through its own adapter.
    function _quotePairConfig() internal view returns (RouterTypes.Config memory config) {
        config = _config();
        RouterTypes.Normalization[] memory normalizations = new RouterTypes.Normalization[](2);
        normalizations[0] = RouterTypes.Normalization({
            asset: RouterTypes.AssetRef(RouterTypes.AssetKind.SUBJECT, address(0)),
            route: RouterTypes.Route(address(adapter), hex"01")
        });
        normalizations[1] = RouterTypes.Normalization({
            asset: RouterTypes.AssetRef(RouterTypes.AssetKind.FIXED_ERC20, address(quoteToken)),
            route: RouterTypes.Route(address(quoteAdapter), hex"09")
        });
        config.normalizations = normalizations;
    }

    function _config() internal view returns (RouterTypes.Config memory config) {
        RouterTypes.Allocation[] memory wethAllocations = new RouterTypes.Allocation[](2);
        wethAllocations[0] = RouterTypes.Allocation({
            destination: WALLET, bps: 5_000, isSink: false, creatorMayRepoint: true, sinkConfig: ""
        });
        wethAllocations[1] = RouterTypes.Allocation({
            destination: address(sink),
            bps: 5_000,
            isSink: true,
            creatorMayRepoint: false,
            sinkConfig: hex"01"
        });

        RouterTypes.Allocation[] memory burnAllocation = new RouterTypes.Allocation[](1);
        burnAllocation[0] = RouterTypes.Allocation({
            destination: 0x000000000000000000000000000000000000dEaD,
            bps: 10_000,
            isSink: false,
            creatorMayRepoint: false,
            sinkConfig: ""
        });

        RouterTypes.Bucket[] memory buckets = new RouterTypes.Bucket[](2);
        buckets[0] = RouterTypes.Bucket({
            output: RouterTypes.AssetRef(RouterTypes.AssetKind.FIXED_ERC20, address(weth)),
            bps: 5_000,
            route: RouterTypes.Route(address(0), ""),
            allocations: wethAllocations
        });
        buckets[1] = RouterTypes.Bucket({
            output: RouterTypes.AssetRef(RouterTypes.AssetKind.SUBJECT, address(0)),
            bps: 5_000,
            route: RouterTypes.Route(address(adapter), hex"02"),
            allocations: burnAllocation
        });

        config = RouterTypes.Config({
            creator: address(this),
            protocolFeeRecipient: PROTOCOL_RECIPIENT,
            weth: address(weth),
            launchpadAdapter: address(0),
            normalizations: _subjectNormalization(),
            buckets: buckets
        });
    }

    function _threeBucketConfig() internal view returns (RouterTypes.Config memory config) {
        config = _config();
        config.buckets[0].bps = 4_000;
        config.buckets[1].bps = 3_000;
        RouterTypes.Allocation[] memory allocation = new RouterTypes.Allocation[](1);
        allocation[0] = RouterTypes.Allocation({
            destination: NEW_WALLET,
            bps: 10_000,
            isSink: false,
            creatorMayRepoint: false,
            sinkConfig: ""
        });
        RouterTypes.Bucket[] memory buckets = new RouterTypes.Bucket[](3);
        buckets[0] = config.buckets[0];
        buckets[1] = config.buckets[1];
        buckets[2] = RouterTypes.Bucket({
            output: RouterTypes.AssetRef(RouterTypes.AssetKind.FIXED_ERC20, address(payoutToken)),
            bps: 3_000,
            route: RouterTypes.Route(address(adapter), hex"03"),
            allocations: allocation
        });
        config.buckets = buckets;
    }

    function _nativeConfig() internal view returns (RouterTypes.Config memory config) {
        RouterTypes.Allocation[] memory allocations = new RouterTypes.Allocation[](1);
        allocations[0] = RouterTypes.Allocation({
            destination: WALLET,
            bps: 10_000,
            isSink: false,
            creatorMayRepoint: false,
            sinkConfig: ""
        });
        RouterTypes.Bucket[] memory buckets = new RouterTypes.Bucket[](1);
        buckets[0] = RouterTypes.Bucket({
            output: RouterTypes.AssetRef(RouterTypes.AssetKind.NATIVE, address(0)),
            bps: 10_000,
            route: RouterTypes.Route(address(adapter), ""),
            allocations: allocations
        });
        config = RouterTypes.Config({
            creator: address(this),
            protocolFeeRecipient: PROTOCOL_RECIPIENT,
            weth: address(weth),
            launchpadAdapter: address(0),
            normalizations: _subjectNormalization(),
            buckets: buckets
        });
    }
}
