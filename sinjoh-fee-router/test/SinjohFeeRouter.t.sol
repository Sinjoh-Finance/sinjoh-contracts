// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockSink } from "./mocks/MockSink.sol";
import { MockSwapAdapter } from "./mocks/MockSwapAdapter.sol";
import { MockPonsV1LaunchFactory, MockPonsV1Locker } from "./mocks/MockPonsV1.sol";
import {
    MockPonsV2Curve, MockPonsV2FeeEscrow, MockPonsV2LaunchFactory, MockWETH
} from "./mocks/MockPonsV2.sol";
import { RouterTypes } from "../src/RouterTypes.sol";
import { SinjohFeeRouter } from "../src/SinjohFeeRouter.sol";
import { SinjohFeeRouterFactory } from "../src/SinjohFeeRouterFactory.sol";
import { IPonsV1LaunchFactory } from "../src/interfaces/IPonsV1.sol";
import {
    IPonsV2BondingCurve, IPonsV2FeeEscrow, IPonsV2LaunchFactory
} from "../src/interfaces/IPonsV2.sol";

contract SinjohFeeRouterTest is TestBase {
    address internal constant PROTOCOL_RECIPIENT = address(0x1001);
    address internal constant WALLET = address(0x2002);
    address internal constant NEW_WALLET = address(0x3003);

    MockERC20 internal subjectToken;
    MockERC20 internal weth;
    MockERC20 internal payoutToken;
    MockSwapAdapter internal adapter;
    MockSink internal sink;
    SinjohFeeRouter internal implementation;
    SinjohFeeRouterFactory internal factory;
    SinjohFeeRouter internal router;

    function setUp() public {
        subjectToken = new MockERC20("Subject", "SUB");
        weth = new MockERC20("Wrapped Ether", "WETH");
        payoutToken = new MockERC20("Payout", "PAY");
        adapter = new MockSwapAdapter();
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

    function testPonsFactoryPredictionDoesNotDependOnSubjectConfiguration() public {
        RouterTypes.Config memory config = _config();
        bytes32 salt = bytes32("PONS");
        address predicted = factory.predictPonsAddress(address(this), salt);
        address deployed = factory.deployPons(address(this), salt, config);
        assertEq(deployed, predicted);
        assertEq(factory.deployPons(address(this), salt, config), deployed);

        config.protocolFeeRecipient = NEW_WALLET;
        vm.expectRevert(SinjohFeeRouterFactory.ConfigMismatch.selector);
        factory.deployPons(address(this), salt, config);
    }

    function testRouterOwnsPonsLaunchAndForwardsDeveloperBuyToCreator() public {
        RouterTypes.Config memory config = _config();
        bytes32 routerSalt = bytes32("ROUTER_OWNED");
        SinjohFeeRouter launchRouter =
            SinjohFeeRouter(payable(factory.deployPons(address(this), routerSalt, config)));
        MockPonsV1Locker locker = new MockPonsV1Locker(weth);
        MockPonsV1LaunchFactory pons = new MockPonsV1LaunchFactory(address(locker));
        pons.setLaunchBuyAmount(1_000);

        IPonsV1LaunchFactory.LaunchParams memory params = _ponsParams(address(launchRouter));
        address launched = launchRouter.launchPonsToken{ value: 1 ether }(
            address(pons), params, 0, 0, bytes32("TOKEN")
        );

        assertEq(pons.lastDeployer(), address(launchRouter));
        assertEq(pons.lastFeeWallet(), address(launchRouter));
        assertEq(launchRouter.creator(), address(this));
        assertEq(launchRouter.ponsLaunchFactory(), address(pons));
        assertEq(launchRouter.ponsLocker(), address(locker));
        assertEq(launchRouter.subject(), launched);
        assertTrue(launchRouter.bound());
        assertEq(MockERC20(launched).balanceOf(address(this)), 1_000);
        assertEq(MockERC20(launched).balanceOf(address(launchRouter)), 0);
    }

    function testPonsLaunchRejectsAnyFeeWalletOtherThanRouter() public {
        RouterTypes.Config memory config = _config();
        SinjohFeeRouter launchRouter = SinjohFeeRouter(
            payable(factory.deployPons(address(this), bytes32("WRONG_WALLET"), config))
        );
        MockPonsV1Locker locker = new MockPonsV1Locker(weth);
        MockPonsV1LaunchFactory pons = new MockPonsV1LaunchFactory(address(locker));
        IPonsV1LaunchFactory.LaunchParams memory params = _ponsParams(address(this));

        vm.expectRevert(SinjohFeeRouter.InvalidPonsFeeWallet.selector);
        launchRouter.launchPonsToken(address(pons), params, 0, 0, bytes32("TOKEN"));
    }

    function testAnyoneCanCollectPonsFeesThroughRouter() public {
        RouterTypes.Config memory config = _config();
        SinjohFeeRouter launchRouter = SinjohFeeRouter(
            payable(factory.deployPons(address(this), bytes32("COLLECT"), config))
        );
        MockPonsV1Locker locker = new MockPonsV1Locker(weth);
        MockPonsV1LaunchFactory pons = new MockPonsV1LaunchFactory(address(locker));
        address launched = launchRouter.launchPonsToken(
            address(pons), _ponsParams(address(launchRouter)), 0, 0, bytes32("TOKEN")
        );
        locker.setFees(launched, 2_000, 3_000);

        vm.prank(address(0xBEEF));
        (uint256 amount0, uint256 amount1) = launchRouter.collectPonsFees();

        assertEq(amount0, 2_000);
        assertEq(amount1, 3_000);
        assertEq(MockERC20(launched).balanceOf(address(launchRouter)), 2_000);
        assertEq(weth.balanceOf(address(launchRouter)), 3_000);
    }

    function testPonsV2LaunchAcceptsZeroTaxAndCreatorRecipient() public {
        (SinjohFeeRouter launchRouter, MockPonsV2LaunchFactory pons,) =
            _deployPonsV2Router(bytes32("V2_ZERO"), _config());

        (address launched, address curve) = launchRouter.launchPonsV2Token(
            address(pons), _ponsV2Params(address(this), 0, pons.economics()), 7, address(weth)
        , new address[](0));

        assertEq(launchRouter.subject(), launched);
        assertEq(launchRouter.ponsV2Curve(), curve);
        assertEq(launchRouter.ponsV2CreatorFeeRecipient(), address(this));
        assertEq(launchRouter.creatorTradeTaxBps(), 0);
        assertEq(pons.lastDeployer(), address(launchRouter));
        assertEq(pons.lastCreatorTaxBps(), 0);
    }

    function testPonsV2LaunchAcceptsOneBasisPointTax() public {
        (SinjohFeeRouter launchRouter, MockPonsV2LaunchFactory pons,) =
            _deployPonsV2Router(bytes32("V2_ONE_BPS"), _config());

        launchRouter.launchPonsV2Token(
            address(pons), _ponsV2Params(address(this), 1, pons.economics()), 7, address(weth)
        , new address[](0));

        assertEq(launchRouter.creatorTradeTaxBps(), 1);
    }

    function testPonsV2LaunchAcceptsSinjohMaximumWhenUpstreamAllowsIt() public {
        (SinjohFeeRouter launchRouter, MockPonsV2LaunchFactory pons,) =
            _deployPonsV2Router(bytes32("V2_MAX"), _config());
        pons.setMaxCreatorTaxBps(5_000);

        launchRouter.launchPonsV2Token(
            address(pons),
            _ponsV2Params(address(launchRouter), 5_000, pons.economics()),
            7,
            address(weth)
        , new address[](0));

        assertEq(launchRouter.creatorTradeTaxBps(), 5_000);
        assertEq(launchRouter.ponsV2CreatorFeeRecipient(), address(launchRouter));
    }

    function testPonsV2LaunchRejectsTaxAboveLiveFactoryCap() public {
        (SinjohFeeRouter launchRouter, MockPonsV2LaunchFactory pons,) =
            _deployPonsV2Router(bytes32("V2_CAP"), _config());
        pons.setMaxCreatorTaxBps(1_000);
        bytes32 economics = pons.economics();

        vm.expectRevert(
            abi.encodeWithSelector(SinjohFeeRouter.CreatorTaxTooHigh.selector, 1_001, 1_000)
        );
        launchRouter.launchPonsV2Token(
            address(pons), _ponsV2Params(address(this), 1_001, economics), 7, address(weth)
        , new address[](0));
    }

    function testPonsV2LaunchRejectsTaxAboveSinjohMaximum() public {
        (SinjohFeeRouter launchRouter, MockPonsV2LaunchFactory pons,) =
            _deployPonsV2Router(bytes32("V2_SINJOH_CAP"), _config());
        pons.setMaxCreatorTaxBps(6_000);
        bytes32 economics = pons.economics();

        vm.expectRevert(
            abi.encodeWithSelector(SinjohFeeRouter.CreatorTaxTooHigh.selector, 5_001, 5_000)
        );
        launchRouter.launchPonsV2Token(
            address(pons), _ponsV2Params(address(this), 5_001, economics), 7, address(weth)
        , new address[](0));
    }

    function testPonsV2LaunchRejectsUnapprovedFeeRecipient() public {
        (SinjohFeeRouter launchRouter, MockPonsV2LaunchFactory pons,) =
            _deployPonsV2Router(bytes32("V2_RECIPIENT"), _config());
        bytes32 economics = pons.economics();

        vm.expectRevert(
            abi.encodeWithSelector(SinjohFeeRouter.InvalidCreatorFeeRecipient.selector, NEW_WALLET)
        );
        launchRouter.launchPonsV2Token(
            address(pons), _ponsV2Params(NEW_WALLET, 100, economics), 7, address(weth)
        , new address[](0));
    }

    function testPonsV2LaunchRequiresEnabledOrWhitelistedRouter() public {
        (SinjohFeeRouter launchRouter, MockPonsV2LaunchFactory pons,) =
            _deployPonsV2Router(bytes32("V2_PAUSED"), _config());
        pons.setLaunchEnabled(false);
        bytes32 economics = pons.economics();

        vm.expectRevert(SinjohFeeRouter.InvalidPonsV2Configuration.selector);
        launchRouter.launchPonsV2Token(
            address(pons), _ponsV2Params(address(this), 100, economics), 7, address(weth)
        , new address[](0));

        pons.setWhitelistedLauncher(address(launchRouter), true);
        launchRouter.launchPonsV2Token(
            address(pons), _ponsV2Params(address(this), 100, economics), 7, address(weth)
        , new address[](0));
        assertEq(launchRouter.creatorTradeTaxBps(), 100);
    }

    function testPonsV2LaunchPinsFeeAndEconomicsAtExecution() public {
        (SinjohFeeRouter launchRouter, MockPonsV2LaunchFactory pons,) =
            _deployPonsV2Router(bytes32("V2_ECONOMICS"), _config());
        pons.setLaunchFee(0.25 ether);
        vm.deal(address(this), 1 ether);
        bytes32 economics = pons.economics();

        vm.expectRevert(SinjohFeeRouter.InvalidPonsV2Configuration.selector);
        launchRouter.launchPonsV2Token(
            address(pons), _ponsV2Params(address(this), 100, bytes32("STALE")), 7, address(weth)
        , new address[](0));

        vm.expectRevert(SinjohFeeRouter.InvalidPonsV2Configuration.selector);
        launchRouter.launchPonsV2Token{ value: 0.2 ether }(
            address(pons), _ponsV2Params(address(this), 100, economics), 7, address(weth)
        , new address[](0));

        launchRouter.launchPonsV2Token{ value: 0.25 ether }(
            address(pons), _ponsV2Params(address(this), 100, economics), 7, address(weth)
        , new address[](0));
        assertTrue(launchRouter.bound());
    }

    function testPonsV2LaunchRejectsCorruptFactoryReadback() public {
        (SinjohFeeRouter launchRouter, MockPonsV2LaunchFactory pons,) =
            _deployPonsV2Router(bytes32("V2_READBACK"), _config());
        pons.setCorruptReadback(true);
        bytes32 economics = pons.economics();

        vm.expectRevert(SinjohFeeRouter.InvalidPonsV2Configuration.selector);
        launchRouter.launchPonsV2Token(
            address(pons), _ponsV2Params(address(this), 100, economics), 7, address(weth)
        , new address[](0));
    }

    function testAnyoneCanClaimPonsV2WethFeesThenSyncThem() public {
        (SinjohFeeRouter launchRouter, MockPonsV2LaunchFactory pons, MockPonsV2FeeEscrow escrow) =
            _deployPonsV2Router(bytes32("V2_WETH_FEES"), _config());
        launchRouter.launchPonsV2Token(
            address(pons),
            _ponsV2Params(address(launchRouter), 100, pons.economics()),
            7,
            address(weth)
        , new address[](0));
        escrow.creditToken(address(launchRouter), address(weth), 10_000);

        vm.prank(address(0xBEEF));
        uint256 claimed = launchRouter.claimPonsV2Fees();
        assertEq(claimed, 10_000);
        assertEq(weth.balanceOf(address(launchRouter)), 10_000);

        launchRouter.sync(address(weth));
        assertEq(launchRouter.protocolOwed(address(weth)), 100);
        assertEq(launchRouter.totalLiability(address(weth)), 10_000);
    }

    function testAnyoneCanClaimPonsV2NativeFeesWhichAreWrapped() public {
        MockWETH wrappedNative = new MockWETH();
        RouterTypes.Config memory config = _config();
        config.weth = address(wrappedNative);
        config.buckets[0].output =
            RouterTypes.AssetRef(RouterTypes.AssetKind.FIXED_ERC20, address(wrappedNative));
        (SinjohFeeRouter launchRouter, MockPonsV2LaunchFactory pons, MockPonsV2FeeEscrow escrow) =
            _deployPonsV2Router(bytes32("V2_NATIVE_FEES"), config);
        launchRouter.launchPonsV2Token(
            address(pons),
            _ponsV2Params(address(launchRouter), 100, pons.economics()),
            7,
            address(0)
        , new address[](0));
        escrow.creditNative{ value: 1 ether }(address(launchRouter));

        vm.prank(address(0xBEEF));
        uint256 claimed = launchRouter.claimPonsV2Fees();

        assertEq(claimed, 1 ether);
        assertEq(wrappedNative.balanceOf(address(launchRouter)), 1 ether);
        assertEq(address(launchRouter).balance, 0);
    }

    function testPonsV2RouterRecipientRejectsUnsupportedPairToken() public {
        (SinjohFeeRouter launchRouter, MockPonsV2LaunchFactory pons,) =
            _deployPonsV2Router(bytes32("V2_PAIR"), _config());
        bytes32 economics = pons.economics();

        vm.expectRevert(
            abi.encodeWithSelector(SinjohFeeRouter.UnsupportedAsset.selector, address(payoutToken))
        );
        launchRouter.launchPonsV2Token(
            address(pons),
            _ponsV2Params(address(launchRouter), 100, economics),
            7,
            address(payoutToken)
        , new address[](0));
    }

    function testPonsV2CreatorRecipientCannotBeClaimedThroughRouter() public {
        (SinjohFeeRouter launchRouter, MockPonsV2LaunchFactory pons,) =
            _deployPonsV2Router(bytes32("V2_DIRECT"), _config());
        launchRouter.launchPonsV2Token(
            address(pons), _ponsV2Params(address(this), 100, pons.economics()), 7, address(weth)
        , new address[](0));

        vm.expectRevert(SinjohFeeRouter.PonsV2FeesNotRoutedHere.selector);
        launchRouter.claimPonsV2Fees();
    }

    function testBindCanReturnOnlyTheExactPonsLaunchBuyToCreator() public {
        RouterTypes.Config memory config = _config();
        SinjohFeeRouter launchRouter =
            SinjohFeeRouter(payable(factory.deploy(address(this), bytes32("LAUNCH_BUY"), config)));
        subjectToken.mint(address(launchRouter), 1_500);

        launchRouter.bindAndSendLaunchBuy(address(subjectToken), 1_000);

        assertTrue(launchRouter.bound());
        assertEq(launchRouter.subject(), address(subjectToken));
        assertEq(subjectToken.balanceOf(address(this)), 1_000);
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
            subjectToWeth: RouterTypes.Route(address(adapter), hex"01"),
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
            subjectToWeth: RouterTypes.Route(address(adapter), hex"01"),
            buckets: buckets
        });
    }

    function _ponsParams(address feeWallet)
        internal
        pure
        returns (IPonsV1LaunchFactory.LaunchParams memory params)
    {
        params = IPonsV1LaunchFactory.LaunchParams({
            name: "Router Owned",
            symbol: "ROUTE",
            logo: "",
            description: "",
            socials: IPonsV1LaunchFactory.Socials({
                twitter: "", telegram: "", discord: "", website: "", farcaster: ""
            }),
            feeWallet: feeWallet
        });
    }

    /// Pins every selector crossing the Pons v2 boundary against the literal
    /// signatures of the deployed, verified contracts. The copied TokenParams
    /// was missing its trailing `salt` field, which changed both launchToken
    /// selectors and made every launch revert against the real factory; this
    /// is the regression net for that class of failure.
    function testPonsV2SelectorsArePinnedToTheDeployedContracts() public pure {
        string memory tokenParams = "(string,string,string,string,(string,string,string,string,string),address,uint16,bool,bytes32,bytes32)";
        // Both overloads are pinned by literal signature because Solidity cannot
        // disambiguate `.selector` on an overloaded name. The constants are the
        // selectors read from the deployed factory's verified ABI. The previous
        // salt-less struct encoded to 0xa41d5f2b, which exists on no deployed
        // contract.
        assertEq(
            uint256(uint32(bytes4(
                keccak256(abi.encodePacked("launchToken(", tokenParams, ",uint256,address)"))
            ))),
            0xf35abbcf
        );
        assertEq(
            uint256(uint32(bytes4(
                keccak256(abi.encodePacked("launchToken(", tokenParams, ",uint256,address,address[])"))
            ))),
            0xa72101af
        );
        assertEq(
            uint256(uint32(IPonsV2BondingCurve.sweepFees.selector)),
            uint256(uint32(bytes4(keccak256("sweepFees(uint256)"))))
        );
        assertEq(
            uint256(uint32(IPonsV2FeeEscrow.claim.selector)),
            uint256(uint32(bytes4(keccak256("claim()"))))
        );
        assertEq(
            uint256(uint32(IPonsV2FeeEscrow.claimToken.selector)),
            uint256(uint32(bytes4(keccak256("claimToken(address)"))))
        );
        assertEq(
            uint256(uint32(IPonsV2LaunchFactory.getLaunchedToken.selector)),
            uint256(uint32(bytes4(keccak256("getLaunchedToken(address)"))))
        );
    }

    /// The full pre-graduation revenue pipeline with a creator trade tax:
    /// curve accrual -> permissionless router sweep -> escrow -> claim as WETH.
    function testPonsV2CurveFeesSweepThroughToClaimableWeth() public {
        MockWETH wrappedNative = new MockWETH();
        RouterTypes.Config memory config = _config();
        config.weth = address(wrappedNative);
        config.buckets[0].output =
            RouterTypes.AssetRef(RouterTypes.AssetKind.FIXED_ERC20, address(wrappedNative));
        (SinjohFeeRouter launchRouter, MockPonsV2LaunchFactory pons, MockPonsV2FeeEscrow escrow) =
            _deployPonsV2Router(bytes32("V2_SWEEP"), config);
        (, address curveAddress) = launchRouter.launchPonsV2Token(
            address(pons),
            _ponsV2Params(address(launchRouter), 500, pons.economics()),
            7,
            address(0),
            new address[](0)
        );
        MockPonsV2Curve curve = MockPonsV2Curve(payable(curveAddress));
        curve.configure(escrow, address(launchRouter));

        // A 5%-taxed trade accrued 1 unit of base fee and 5 of creator tax.
        curve.accrue{ value: 6 ether }(1 ether, 5 ether);

        vm.prank(address(0xCA11));
        assertEq(launchRouter.sweepPonsV2CurveFees(), 6 ether);
        assertEq(escrow.balanceOf(address(launchRouter)), 6 ether);
        assertEq(curve.quoteFeeBalance() + curve.creatorTaxBalance(), 0);

        assertEq(launchRouter.claimPonsV2Fees(), 6 ether);
        assertEq(wrappedNative.balanceOf(address(launchRouter)), 6 ether);

        vm.expectRevert(SinjohFeeRouter.NothingToSweep.selector);
        launchRouter.sweepPonsV2CurveFees();
    }

    /// An earmarked buyback sweep prices a swap and belongs to Pons's trusted
    /// operator; the permissionless router path must refuse it.
    function testPonsV2SweepRefusesAPendingBuybackEarmark() public {
        (SinjohFeeRouter launchRouter, MockPonsV2LaunchFactory pons, MockPonsV2FeeEscrow escrow) =
            _deployPonsV2Router(bytes32("V2_SWEEP_BB"), _config());
        (, address curveAddress) = launchRouter.launchPonsV2Token(
            address(pons),
            _ponsV2Params(address(launchRouter), 0, pons.economics()),
            7,
            address(0),
            new address[](0)
        );
        MockPonsV2Curve curve = MockPonsV2Curve(payable(curveAddress));
        curve.configure(escrow, address(launchRouter));
        curve.accrue{ value: 1 ether }(1 ether, 0);
        curve.setBuybackQuoteBalance(0.1 ether);

        vm.expectRevert(SinjohFeeRouter.PonsV2SweepRequiresOperator.selector);
        launchRouter.sweepPonsV2CurveFees();
    }

    function _deployPonsV2Router(bytes32 salt, RouterTypes.Config memory config)
        internal
        returns (
            SinjohFeeRouter launchRouter,
            MockPonsV2LaunchFactory pons,
            MockPonsV2FeeEscrow escrow
        )
    {
        launchRouter = SinjohFeeRouter(payable(factory.deployPons(address(this), salt, config)));
        escrow = new MockPonsV2FeeEscrow();
        pons = new MockPonsV2LaunchFactory(address(escrow));
    }

    function _ponsV2Params(address feeRecipient, uint16 taxBps, bytes32 economics)
        internal
        pure
        returns (IPonsV2LaunchFactory.TokenParams memory params)
    {
        params = IPonsV2LaunchFactory.TokenParams({
            name: "Router Owned v2",
            symbol: "ROUTE2",
            logo: "",
            description: "",
            socials: IPonsV2LaunchFactory.Socials({
                twitter: "", telegram: "", discord: "", website: "", farcaster: ""
            }),
            creatorFeeRecipient: feeRecipient,
            creatorTaxBps: taxBps,
            buybackEnabled: false,
            expectedEconomics: economics,
            salt: bytes32("V2_SALT")
        });
    }
}
