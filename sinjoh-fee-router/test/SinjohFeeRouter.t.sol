// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockPriceGuard } from "./mocks/MockPriceGuard.sol";
import { MockSink } from "./mocks/MockSink.sol";
import { MockSwapAdapter } from "./mocks/MockSwapAdapter.sol";
import { RouterTypes } from "../src/RouterTypes.sol";
import { SinjohFeeRouter } from "../src/SinjohFeeRouter.sol";
import { SinjohFeeRouterFactory } from "../src/SinjohFeeRouterFactory.sol";

contract SinjohFeeRouterTest is TestBase {
    address internal constant PROTOCOL_RECIPIENT = address(0x1001);
    address internal constant WALLET = address(0x2002);
    address internal constant NEW_WALLET = address(0x3003);

    MockERC20 internal subjectToken;
    MockERC20 internal quoteToken;
    MockPriceGuard internal guard;
    MockSwapAdapter internal adapter;
    MockSink internal sink;
    SinjohFeeRouter internal implementation;
    SinjohFeeRouterFactory internal factory;
    SinjohFeeRouter internal router;

    function setUp() public {
        subjectToken = new MockERC20("Subject", "SUB");
        quoteToken = new MockERC20("Wrapped Ether", "WETH");
        guard = new MockPriceGuard(1, type(uint48).max);
        adapter = new MockSwapAdapter();
        sink = new MockSink();
        implementation = new SinjohFeeRouter();
        factory = new SinjohFeeRouterFactory(address(implementation));

        RouterTypes.Config memory config = _config();
        address predicted = factory.predictAddress(address(this), bytes32("TEST"), config);
        router = SinjohFeeRouter(payable(factory.deploy(address(this), bytes32("TEST"), config)));
        assertEq(address(router), predicted);
        router.bind(address(subjectToken));
    }

    function testImplementationCannotBeInitialized() public {
        vm.expectRevert(SinjohFeeRouter.AlreadyInitialized.selector);
        implementation.initialize(_config());
    }

    function testCloneCannotBeReinitialized() public {
        vm.expectRevert(SinjohFeeRouter.AlreadyInitialized.selector);
        router.initialize(_config());
    }

    function testCreate2DeploymentIsIdempotent() public {
        RouterTypes.Config memory config = _config();
        address second = factory.deploy(address(this), bytes32("TEST"), config);
        assertEq(second, address(router));
    }

    function testCreate2FrontRunnerCannotSeizeInitializationAuthority() public {
        RouterTypes.Config memory config = _config();
        address predicted = factory.predictAddress(address(this), bytes32("FRONT_RUN"), config);

        vm.prank(address(0xBAD));
        address deployed = factory.deploy(address(this), bytes32("FRONT_RUN"), config);

        assertEq(deployed, predicted);
        assertEq(SinjohFeeRouter(payable(deployed)).creator(), address(this));
        vm.prank(address(0xBAD));
        vm.expectRevert(SinjohFeeRouter.Unauthorized.selector);
        SinjohFeeRouter(payable(deployed)).bind(address(subjectToken));
    }

    function testSyncChargesExactlyOnce() public {
        quoteToken.mint(address(router), 10_000);

        (uint256 gross, uint256 fee) = router.sync(address(quoteToken));
        assertEq(gross, 10_000);
        assertEq(fee, 100);
        assertEq(router.protocolOwed(address(quoteToken)), 100);
        assertEq(router.bucketInputOwed(0, address(quoteToken)), 9_900);
        assertEq(router.totalLiability(address(quoteToken)), 10_000);

        (gross, fee) = router.sync(address(quoteToken));
        assertEq(gross, 0);
        assertEq(fee, 0);
        assertEq(router.totalLiability(address(quoteToken)), 10_000);
    }

    function testFuzzSyncAccounting(uint128 rawAmount) public {
        uint256 amount = uint256(rawAmount) % type(uint96).max + 1;
        quoteToken.mint(address(router), amount);
        router.sync(address(quoteToken));

        uint256 fee = amount * 100 / 10_000;
        assertEq(router.protocolOwed(address(quoteToken)), fee);
        assertEq(router.bucketInputOwed(0, address(quoteToken)), amount - fee);
        assertEq(router.totalLiability(address(quoteToken)), amount);
        assertEq(quoteToken.balanceOf(address(router)), amount);
    }

    function testSplitSynchronizationCarriesProtocolFeeRemainder() public {
        quoteToken.mint(address(router), 50);
        router.sync(address(quoteToken));
        assertEq(router.protocolOwed(address(quoteToken)), 0);
        assertEq(router.protocolFeeRemainder(address(quoteToken)), 5_000);

        quoteToken.mint(address(router), 50);
        router.sync(address(quoteToken));

        assertEq(router.protocolOwed(address(quoteToken)), 1);
        assertEq(router.protocolFeeRemainder(address(quoteToken)), 0);
        assertEq(router.bucketInputOwed(0, address(quoteToken)), 99);
        assertEq(router.totalLiability(address(quoteToken)), 100);
    }

    function testSplitSynchronizationMatchesAggregateBucketAllocations() public {
        RouterTypes.Config memory config = _twoBucketConfig();
        SinjohFeeRouter splitRouter = SinjohFeeRouter(
            payable(factory.deploy(address(this), bytes32("SPLIT_BUCKET"), config))
        );
        splitRouter.bind(address(subjectToken));

        quoteToken.mint(address(splitRouter), 1);
        splitRouter.sync(address(quoteToken));
        assertEq(splitRouter.bucketInputOwed(0, address(quoteToken)), 1);
        assertEq(splitRouter.bucketInputOwed(1, address(quoteToken)), 0);

        quoteToken.mint(address(splitRouter), 1);
        splitRouter.sync(address(quoteToken));
        assertEq(splitRouter.bucketInputOwed(0, address(quoteToken)), 2);
        assertEq(splitRouter.bucketInputOwed(1, address(quoteToken)), 0);
    }

    function testSplitProcessingMatchesAggregateDestinationAllocations() public {
        subjectToken.mint(address(router), 1);
        router.sync(address(subjectToken));
        router.processBucket(0, address(subjectToken), 1, 0, "");
        assertEq(router.walletOwed(WALLET, address(subjectToken)), 1);
        assertEq(router.sinkOwed(router.allocationKey(0, 1), address(subjectToken)), 0);

        subjectToken.mint(address(router), 1);
        router.sync(address(subjectToken));
        router.processBucket(0, address(subjectToken), 1, 0, "");
        assertEq(router.walletOwed(WALLET, address(subjectToken)), 2);
        assertEq(router.sinkOwed(router.allocationKey(0, 1), address(subjectToken)), 0);
    }

    function testRealRoutingWeightsAreIndependentOfOneUnitTransactions() public {
        RouterTypes.Config memory config = _threeAllocationConfig();
        SinjohFeeRouter splitRouter = SinjohFeeRouter(
            payable(factory.deploy(address(this), bytes32("THREE_ALLOCATIONS"), config))
        );
        SinjohFeeRouter aggregateRouter = SinjohFeeRouter(
            payable(factory.deploy(address(this), bytes32("AGGREGATE_ALLOCATIONS"), config))
        );
        splitRouter.bind(address(subjectToken));
        aggregateRouter.bind(address(subjectToken));

        for (uint256 i; i < 10; ++i) {
            subjectToken.mint(address(splitRouter), 1);
            splitRouter.sync(address(subjectToken));
            uint256 pending = splitRouter.bucketInputOwed(0, address(subjectToken));
            if (pending != 0) splitRouter.processBucket(0, address(subjectToken), pending, 0, "");
        }

        subjectToken.mint(address(aggregateRouter), 10);
        aggregateRouter.sync(address(subjectToken));
        aggregateRouter.processBucket(0, address(subjectToken), 10, 0, "");

        assertEq(
            splitRouter.walletOwed(WALLET, address(subjectToken)),
            aggregateRouter.walletOwed(WALLET, address(subjectToken))
        );
        assertEq(
            splitRouter.sinkOwed(splitRouter.allocationKey(0, 1), address(subjectToken)),
            aggregateRouter.sinkOwed(aggregateRouter.allocationKey(0, 1), address(subjectToken))
        );
        assertEq(
            splitRouter.walletOwed(NEW_WALLET, address(subjectToken)),
            aggregateRouter.walletOwed(NEW_WALLET, address(subjectToken))
        );
    }

    function testRealRoutingWeightsAreExactOverAFullAllocationCycle() public {
        RouterTypes.Config memory config = _threeAllocationConfig();
        SinjohFeeRouter cycleRouter = SinjohFeeRouter(
            payable(factory.deploy(address(this), bytes32("ALLOCATION_CYCLE"), config))
        );
        cycleRouter.bind(address(subjectToken));

        subjectToken.mint(address(cycleRouter), 10_101);
        cycleRouter.sync(address(subjectToken));
        cycleRouter.processBucket(0, address(subjectToken), 10_000, 0, "");

        assertEq(cycleRouter.protocolOwed(address(subjectToken)), 101);
        assertEq(cycleRouter.walletOwed(WALLET, address(subjectToken)), 4_000);
        assertEq(
            cycleRouter.sinkOwed(cycleRouter.allocationKey(0, 1), address(subjectToken)), 3_000
        );
        assertEq(cycleRouter.walletOwed(NEW_WALLET, address(subjectToken)), 3_000);
    }

    function testProcessingRequiresTheFullPermittedTranche() public {
        subjectToken.mint(address(router), 10_000);
        router.sync(address(subjectToken));

        vm.expectRevert(SinjohFeeRouter.InvalidAmount.selector);
        router.processBucket(0, address(subjectToken), 1, 0, "");

        router.processBucket(0, address(subjectToken), 9_900, 0, "");
    }

    function testIdentityProcessingSnapshotsAllocations() public {
        subjectToken.mint(address(router), 10_000);
        router.sync(address(subjectToken));

        uint256 amountOut = router.processBucket(0, address(subjectToken), 9_900, 0, "");
        assertEq(amountOut, 9_900);
        assertEq(router.walletOwed(WALLET, address(subjectToken)), 5_000);
        assertEq(router.sinkOwed(router.allocationKey(0, 1), address(subjectToken)), 4_900);
        assertEq(router.totalLiability(address(subjectToken)), 10_000);
    }

    function testGuardedSwapUsesMeasuredDeltasAndStricterMinimum() public {
        quoteToken.mint(address(router), 10_000);
        subjectToken.mint(address(adapter), 20_000);
        router.sync(address(quoteToken));

        uint256 amountOut = router.processBucket(0, address(quoteToken), 9_900, 9_900, hex"01");
        assertEq(amountOut, 9_900);
        assertEq(router.totalLiability(address(quoteToken)), 100);
        assertEq(router.totalLiability(address(subjectToken)), 9_900);
        assertEq(quoteToken.allowance(address(router), address(adapter)), 0);
        assertEq(router.walletOwed(WALLET, address(subjectToken)), 5_000);
    }

    function testWeakCallerMinimumCannotLowerGuardAndStrictMinimumCanRevert() public {
        quoteToken.mint(address(router), 10_000);
        subjectToken.mint(address(adapter), 20_000);
        router.sync(address(quoteToken));
        guard.setQuote(9_900, type(uint48).max);

        vm.expectPartialRevert(SinjohFeeRouter.InsufficientOutput.selector);
        router.processBucket(0, address(quoteToken), 9_900, 9_901, "");

        assertEq(router.bucketInputOwed(0, address(quoteToken)), 9_900);
        assertEq(router.totalLiability(address(quoteToken)), 10_000);
        assertEq(quoteToken.allowance(address(router), address(adapter)), 0);
    }

    function testUnexpectedInputSpendRevertsWithoutChangingLiability() public {
        quoteToken.mint(address(router), 10_000);
        subjectToken.mint(address(adapter), 20_000);
        router.sync(address(quoteToken));
        adapter.setSpendLess(true);

        vm.expectPartialRevert(SinjohFeeRouter.UnexpectedBalanceDelta.selector);
        router.processBucket(0, address(quoteToken), 9_900, 0, "");

        assertEq(router.bucketInputOwed(0, address(quoteToken)), 9_900);
        assertEq(router.totalLiability(address(quoteToken)), 10_000);
    }

    function testWalletRepointOnlyAffectsFutureCredits() public {
        subjectToken.mint(address(router), 4_000);
        router.sync(address(subjectToken));
        router.processBucket(0, address(subjectToken), 3_960, 0, "");
        assertEq(router.walletOwed(WALLET, address(subjectToken)), 3_960);

        router.repointWallet(0, 0, NEW_WALLET);
        subjectToken.mint(address(router), 6_000);
        router.sync(address(subjectToken));
        router.processBucket(0, address(subjectToken), 5_940, 0, "");

        assertEq(router.walletOwed(WALLET, address(subjectToken)), 3_960);
        assertEq(router.walletOwed(NEW_WALLET, address(subjectToken)), 1_040);
    }

    function testWalletCannotBeRepointedToRouterItself() public {
        vm.expectPartialRevert(SinjohFeeRouter.InvalidAddress.selector);
        router.repointWallet(0, 0, address(router));
    }

    function testWalletAndProtocolDeliveryReduceExactLiability() public {
        subjectToken.mint(address(router), 10_000);
        router.sync(address(subjectToken));
        router.processBucket(0, address(subjectToken), 9_900, 0, "");

        router.sendProtocolFee(address(subjectToken), 100);
        router.sendWallet(WALLET, address(subjectToken), 5_000);

        assertEq(subjectToken.balanceOf(PROTOCOL_RECIPIENT), 100);
        assertEq(subjectToken.balanceOf(WALLET), 5_000);
        assertEq(router.totalLiability(address(subjectToken)), 4_900);
    }

    function testSinkPullsAtomicallyAndAllowanceReturnsToZero() public {
        subjectToken.mint(address(router), 10_000);
        router.sync(address(subjectToken));
        router.processBucket(0, address(subjectToken), 9_900, 0, "");

        router.fundSink(0, 1, 4_900);

        assertEq(subjectToken.balanceOf(address(sink)), 4_900);
        assertEq(subjectToken.allowance(address(router), address(sink)), 0);
        assertEq(router.totalLiability(address(subjectToken)), 5_100);
    }

    function testSinkFailureLeavesLiabilityAndAllowanceUnchanged() public {
        subjectToken.mint(address(router), 10_000);
        router.sync(address(subjectToken));
        router.processBucket(0, address(subjectToken), 9_900, 0, "");
        sink.setShouldRevert(true);

        vm.expectRevert();
        router.fundSink(0, 1, 4_900);

        assertEq(router.sinkOwed(router.allocationKey(0, 1), address(subjectToken)), 4_900);
        assertEq(subjectToken.allowance(address(router), address(sink)), 0);
        assertEq(router.totalLiability(address(subjectToken)), 10_000);
    }

    function testInsolvencyIsDetectedBeforeSynchronization() public {
        quoteToken.mint(address(router), 10_000);
        router.sync(address(quoteToken));
        quoteToken.burn(address(router), 1);

        vm.expectPartialRevert(SinjohFeeRouter.Insolvent.selector);
        router.sync(address(quoteToken));
    }

    function testUnsupportedAssetCannotAffectAccounting() public {
        MockERC20 unsupported = new MockERC20("Unsupported", "NOPE");
        unsupported.mint(address(router), 10_000);

        vm.expectPartialRevert(SinjohFeeRouter.UnsupportedAsset.selector);
        router.sync(address(unsupported));

        assertEq(router.totalLiability(address(unsupported)), 0);
        assertEq(router.totalLiability(address(subjectToken)), 0);
        assertEq(router.totalLiability(address(quoteToken)), 0);
    }

    function testFeeOnTransferDeliveryRevertsWithoutCorruptingLiability() public {
        quoteToken.mint(address(router), 10_000);
        router.sync(address(quoteToken));
        quoteToken.setFeeBps(100);

        vm.expectPartialRevert(SinjohFeeRouter.UnexpectedBalanceDelta.selector);
        router.sendProtocolFee(address(quoteToken), 100);

        assertEq(router.protocolOwed(address(quoteToken)), 100);
        assertEq(router.totalLiability(address(quoteToken)), 10_000);
        assertEq(quoteToken.balanceOf(PROTOCOL_RECIPIENT), 0);
        assertEq(quoteToken.balanceOf(address(router)), 10_000);
    }

    function testBucketFailureDoesNotBlockAnotherBucket() public {
        RouterTypes.Config memory config = _twoBucketConfig();
        SinjohFeeRouter twoBucketRouter =
            SinjohFeeRouter(payable(factory.deploy(address(this), bytes32("TWO_BUCKETS"), config)));
        twoBucketRouter.bind(address(subjectToken));
        quoteToken.mint(address(twoBucketRouter), 10_000);
        subjectToken.mint(address(adapter), 10_000);
        twoBucketRouter.sync(address(quoteToken));

        vm.expectPartialRevert(SinjohFeeRouter.InsufficientOutput.selector);
        twoBucketRouter.processBucket(0, address(quoteToken), 5_000, 5_001, "");

        assertEq(twoBucketRouter.bucketInputOwed(0, address(quoteToken)), 5_000);
        twoBucketRouter.processBucket(1, address(quoteToken), 4_900, 0, "");
        assertEq(twoBucketRouter.bucketInputOwed(1, address(quoteToken)), 0);
        assertEq(twoBucketRouter.walletOwed(NEW_WALLET, address(quoteToken)), 4_900);
    }

    function testBucketMayDeliberatelyConfigureNoConversions() public {
        RouterTypes.Config memory config = _config();
        config.buckets[0].conversions = new RouterTypes.Conversion[](0);
        SinjohFeeRouter disabledRouter =
            SinjohFeeRouter(payable(factory.deploy(address(this), bytes32("DISABLED"), config)));
        disabledRouter.bind(address(subjectToken));
        quoteToken.mint(address(disabledRouter), 10_000);
        disabledRouter.sync(address(quoteToken));

        vm.expectPartialRevert(SinjohFeeRouter.UnsupportedConversion.selector);
        disabledRouter.processBucket(0, address(quoteToken), 9_900, 0, "");

        assertEq(disabledRouter.bucketInputOwed(0, address(quoteToken)), 9_900);
        assertEq(disabledRouter.totalLiability(address(quoteToken)), 10_000);
    }

    function testCannotRepointBeforeBinding() public {
        RouterTypes.Config memory config = _config();
        SinjohFeeRouter unbound =
            SinjohFeeRouter(payable(factory.deploy(address(this), bytes32("UNBOUND"), config)));

        vm.expectRevert(SinjohFeeRouter.NotBound.selector);
        unbound.repointWallet(0, 0, NEW_WALLET);
    }

    function testOnlyCreatorCanBindOrRepoint() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert(SinjohFeeRouter.Unauthorized.selector);
        router.repointWallet(0, 0, address(0xCAFE));
    }

    function testMinimumIntervalIsImmutableAndEnforced() public {
        RouterTypes.Config memory config = _config();
        config.buckets[0].conversions[0].minInterval = 100;
        config.buckets[0].conversions[0].maxAmountInPerCall = 1_000;
        SinjohFeeRouter timedRouter =
            SinjohFeeRouter(payable(factory.deploy(address(this), bytes32("TIMED"), config)));
        timedRouter.bind(address(subjectToken));
        subjectToken.mint(address(timedRouter), 10_000);
        timedRouter.sync(address(subjectToken));

        timedRouter.processBucket(0, address(subjectToken), 1_000, 0, "");
        vm.expectRevert(SinjohFeeRouter.InvalidInterval.selector);
        timedRouter.processBucket(0, address(subjectToken), 1_000, 0, "");

        vm.warp(block.timestamp + 100);
        timedRouter.processBucket(0, address(subjectToken), 1_000, 0, "");
    }

    function testBindingRejectsResolvedDuplicateAssets() public {
        RouterTypes.Config memory config = _config();
        config.intakeAssets[1].token = address(subjectToken);
        config.buckets[0].conversions[1].input = config.intakeAssets[1];
        SinjohFeeRouter duplicateRouter =
            SinjohFeeRouter(payable(factory.deploy(address(this), bytes32("DUPLICATE"), config)));

        vm.expectPartialRevert(SinjohFeeRouter.DuplicateAsset.selector);
        duplicateRouter.bind(address(subjectToken));
    }

    function testNativeIntakeProcessingAndDelivery() public {
        RouterTypes.Config memory config = _nativeConfig();
        SinjohFeeRouter nativeRouter =
            SinjohFeeRouter(payable(factory.deploy(address(this), bytes32("NATIVE"), config)));
        nativeRouter.bind(address(subjectToken));
        vm.deal(address(nativeRouter), 1 ether);

        nativeRouter.sync(address(0));
        nativeRouter.processBucket(0, address(0), 0.99 ether, 0, "");
        uint256 walletBefore = WALLET.balance;
        nativeRouter.sendWallet(WALLET, address(0), 0.99 ether);
        nativeRouter.sendProtocolFee(address(0), 0.01 ether);

        assertEq(WALLET.balance - walletBefore, 0.99 ether);
        assertEq(PROTOCOL_RECIPIENT.balance, 0.01 ether);
        assertEq(nativeRouter.totalLiability(address(0)), 0);
        assertEq(address(nativeRouter).balance, 0);
    }

    function _config() internal view returns (RouterTypes.Config memory config) {
        RouterTypes.AssetRef[] memory intakeAssets = new RouterTypes.AssetRef[](2);
        intakeAssets[0] =
            RouterTypes.AssetRef({ kind: RouterTypes.AssetKind.SUBJECT, token: address(0) });
        intakeAssets[1] = RouterTypes.AssetRef({
            kind: RouterTypes.AssetKind.FIXED_ERC20, token: address(quoteToken)
        });

        RouterTypes.Conversion[] memory conversions = new RouterTypes.Conversion[](2);
        conversions[0] = RouterTypes.Conversion({
            input: intakeAssets[0],
            adapter: address(0),
            priceGuard: address(0),
            routeData: "",
            maxAmountInPerCall: type(uint128).max,
            minInterval: 0
        });
        conversions[1] = RouterTypes.Conversion({
            input: intakeAssets[1],
            adapter: address(adapter),
            priceGuard: address(guard),
            routeData: hex"1234",
            maxAmountInPerCall: type(uint128).max,
            minInterval: 0
        });

        RouterTypes.Allocation[] memory allocations = new RouterTypes.Allocation[](2);
        allocations[0] = RouterTypes.Allocation({
            destination: WALLET, bps: 5_000, isSink: false, creatorMayRepoint: true, sinkConfig: ""
        });
        allocations[1] = RouterTypes.Allocation({
            destination: address(sink),
            bps: 5_000,
            isSink: true,
            creatorMayRepoint: false,
            sinkConfig: abi.encode(bytes32("SINK_CONFIG"))
        });

        RouterTypes.Bucket[] memory buckets = new RouterTypes.Bucket[](1);
        buckets[0] = RouterTypes.Bucket({
            output: intakeAssets[0], bps: 10_000, conversions: conversions, allocations: allocations
        });

        config = RouterTypes.Config({
            creator: address(this),
            protocolFeeRecipient: PROTOCOL_RECIPIENT,
            weth: address(quoteToken),
            intakeAssets: intakeAssets,
            buckets: buckets
        });
    }

    function _nativeConfig() internal view returns (RouterTypes.Config memory config) {
        RouterTypes.AssetRef[] memory intakeAssets = new RouterTypes.AssetRef[](1);
        intakeAssets[0] =
            RouterTypes.AssetRef({ kind: RouterTypes.AssetKind.NATIVE, token: address(0) });

        RouterTypes.Conversion[] memory conversions = new RouterTypes.Conversion[](1);
        conversions[0] = RouterTypes.Conversion({
            input: intakeAssets[0],
            adapter: address(0),
            priceGuard: address(0),
            routeData: "",
            maxAmountInPerCall: type(uint128).max,
            minInterval: 0
        });

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
            output: intakeAssets[0], bps: 10_000, conversions: conversions, allocations: allocations
        });

        config = RouterTypes.Config({
            creator: address(this),
            protocolFeeRecipient: PROTOCOL_RECIPIENT,
            weth: address(quoteToken),
            intakeAssets: intakeAssets,
            buckets: buckets
        });
    }

    function _threeAllocationConfig() internal view returns (RouterTypes.Config memory config) {
        config = _config();
        RouterTypes.Allocation[] memory allocations = new RouterTypes.Allocation[](3);
        allocations[0] = RouterTypes.Allocation({
            destination: WALLET, bps: 4_000, isSink: false, creatorMayRepoint: false, sinkConfig: ""
        });
        allocations[1] = RouterTypes.Allocation({
            destination: address(sink),
            bps: 3_000,
            isSink: true,
            creatorMayRepoint: false,
            sinkConfig: abi.encode(bytes32("SINK_CONFIG"))
        });
        allocations[2] = RouterTypes.Allocation({
            destination: NEW_WALLET,
            bps: 3_000,
            isSink: false,
            creatorMayRepoint: false,
            sinkConfig: ""
        });
        config.buckets[0].allocations = allocations;
    }

    function _twoBucketConfig() internal view returns (RouterTypes.Config memory config) {
        config = _config();
        config.buckets[0].bps = 5_000;

        RouterTypes.Conversion[] memory conversions = new RouterTypes.Conversion[](1);
        conversions[0] = RouterTypes.Conversion({
            input: config.intakeAssets[1],
            adapter: address(0),
            priceGuard: address(0),
            routeData: "",
            maxAmountInPerCall: type(uint128).max,
            minInterval: 0
        });

        RouterTypes.Allocation[] memory allocations = new RouterTypes.Allocation[](1);
        allocations[0] = RouterTypes.Allocation({
            destination: NEW_WALLET,
            bps: 10_000,
            isSink: false,
            creatorMayRepoint: false,
            sinkConfig: ""
        });

        RouterTypes.Bucket[] memory buckets = new RouterTypes.Bucket[](2);
        buckets[0] = config.buckets[0];
        buckets[1] = RouterTypes.Bucket({
            output: config.intakeAssets[1],
            bps: 5_000,
            conversions: conversions,
            allocations: allocations
        });
        config.buckets = buckets;
    }
}
