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

contract FakeInitializedImplementation {
    function initialized() external pure returns (bool) {
        return true;
    }
}

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
    MockPriceGuard internal priceGuard;
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
        priceGuard = new MockPriceGuard(1, type(uint48).max);
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

    function testFactoryRejectsMissingOrNonRouterImplementation() public {
        vm.expectRevert(SinjohFeeRouterFactory.InvalidImplementation.selector);
        new SinjohFeeRouterFactory(address(0));

        vm.expectRevert(SinjohFeeRouterFactory.InvalidImplementation.selector);
        new SinjohFeeRouterFactory(address(subjectToken));

        FakeInitializedImplementation fake = new FakeInitializedImplementation();
        vm.expectRevert(SinjohFeeRouterFactory.InvalidImplementation.selector);
        new SinjohFeeRouterFactory(address(fake));
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

    function testNobodyMayPreemptAnotherCreatorsLaunchpadRouter() public {
        RouterTypes.Config memory config = _config();
        vm.prank(address(0xBAD));
        vm.expectRevert(SinjohFeeRouterFactory.Unauthorized.selector);
        factory.deployForLaunchpad(address(this), bytes32("PREEMPT"), config);
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

    function testBindRejectsNonContractSubject() public {
        RouterTypes.Config memory config = _config();
        SinjohFeeRouter unbound =
            SinjohFeeRouter(payable(factory.deploy(address(this), bytes32("BAD_SUBJECT"), config)));
        vm.expectPartialRevert(SinjohFeeRouter.NonContract.selector);
        unbound.bind(address(0xBEEF));
    }

    function testBindRejectsNormalizationRefsThatResolveToSameAsset() public {
        RouterTypes.Config memory config = _config();
        RouterTypes.Normalization[] memory normalizations = new RouterTypes.Normalization[](2);
        normalizations[0] = config.normalizations[0];
        normalizations[1] = RouterTypes.Normalization({
            asset: RouterTypes.AssetRef(RouterTypes.AssetKind.FIXED_ERC20, address(subjectToken)),
            route: RouterTypes.Route(address(adapter), hex"03"),
            priceGuard: address(priceGuard),
            maxAmountInPerCall: type(uint128).max
        });
        config.normalizations = normalizations;
        SinjohFeeRouter unbound = SinjohFeeRouter(
            payable(factory.deploy(address(this), bytes32("RESOLVED_NORMALIZATION_DUP"), config))
        );

        vm.expectPartialRevert(SinjohFeeRouter.DuplicateAsset.selector);
        unbound.bind(address(subjectToken));
    }

    function testBindRejectsBucketRefsThatResolveToSameAsset() public {
        RouterTypes.Config memory config = _config();
        config.buckets[0].output =
            RouterTypes.AssetRef(RouterTypes.AssetKind.FIXED_ERC20, address(subjectToken));
        config.buckets[0].route = RouterTypes.Route(address(adapter), hex"03");
        config.buckets[0].priceGuard = address(priceGuard);
        SinjohFeeRouter unbound = SinjohFeeRouter(
            payable(factory.deploy(address(this), bytes32("RESOLVED_BUCKET_DUP"), config))
        );

        vm.expectPartialRevert(SinjohFeeRouter.DuplicateAsset.selector);
        unbound.bind(address(subjectToken));
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
        launchRouter.sync(address(subjectToken), 1);
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

        (uint256 gross,) = quoteRouter.sync(address(quoteToken), 1);

        assertEq(gross, 1_000);
        assertEq(quoteToken.balanceOf(address(quoteRouter)), 0);
        assertEq(quoteRouter.totalLiability(address(weth)), 1_000 * 1e12);
    }

    /// @dev Audit finding: `isIntakeAsset` used to mark the subject
    /// unconditionally at bind, while `sync` only accepts assets with a
    /// normalization route. A launch whose fees arrive purely in a quote asset
    /// has no subject route, so the mapping advertised an asset that reverts —
    /// and a keeper reading it would have called `sync(subject)` and failed.
    function testIntakeAssetMapAgreesWithWhatSyncAccepts() public {
        RouterTypes.Config memory config = _config();
        // Fees arrive only as the quote asset; the subject is never a fee asset.
        RouterTypes.Normalization[] memory normalizations = new RouterTypes.Normalization[](1);
        normalizations[0] = RouterTypes.Normalization({
            asset: RouterTypes.AssetRef(RouterTypes.AssetKind.FIXED_ERC20, address(quoteToken)),
            route: RouterTypes.Route(address(quoteAdapter), hex"09"),
            priceGuard: address(priceGuard),
            maxAmountInPerCall: type(uint128).max
        });
        config.normalizations = normalizations;

        SinjohFeeRouter quoteOnly =
            SinjohFeeRouter(payable(factory.deploy(address(this), bytes32("QUOTE_ONLY"), config)));
        quoteOnly.bind(address(subjectToken));

        assertTrue(quoteOnly.isIntakeAsset(address(quoteToken)));
        assertTrue(quoteOnly.isIntakeAsset(address(weth)));
        // The subject is not an intake asset here, and must not claim to be.
        assertTrue(!quoteOnly.isIntakeAsset(address(subjectToken)));

        vm.expectRevert(
            abi.encodeWithSelector(SinjohFeeRouter.UnsupportedAsset.selector, address(subjectToken))
        );
        quoteOnly.sync(address(subjectToken), 0);
    }

    /// @dev Audit finding: normalization was the one swap leg with no caller
    /// floor. `processBucket` already took one; `sync` hardcoded zero.
    function testSyncFloorRejectsAnUnderpricedNormalization() public {
        subjectToken.mint(address(router), 10_000);
        weth.mint(address(adapter), 10_000);

        vm.expectRevert(
            abi.encodeWithSelector(SinjohFeeRouter.InsufficientOutput.selector, 10_001, 10_000)
        );
        router.sync(address(subjectToken), 10_001);
    }

    function testSyncFloorAcceptsAnAdequateNormalization() public {
        subjectToken.mint(address(router), 10_000);
        weth.mint(address(adapter), 10_000);

        (uint256 gross,) = router.sync(address(subjectToken), 10_000);
        assertEq(gross, 10_000);
        assertEq(router.totalLiability(address(weth)), 10_000);
    }

    function testRevertingNormalizationPreservesBalanceLiabilityAndAllowance() public {
        subjectToken.mint(address(router), 100);
        weth.mint(address(adapter), 100);
        adapter.setSpendLess(true);

        vm.expectPartialRevert(SinjohFeeRouter.UnexpectedBalanceDelta.selector);
        router.sync(address(subjectToken), 1);

        assertEq(subjectToken.balanceOf(address(router)), 100);
        assertEq(router.totalLiability(address(subjectToken)), 0);
        assertEq(subjectToken.allowance(address(router), address(adapter)), 0);
    }

    function testImmutableGuardCannotBeWeakenedByPermissionlessCaller() public {
        subjectToken.mint(address(router), 10_000);
        weth.mint(address(adapter), 10_000);
        priceGuard.setQuote(10_001, type(uint48).max);

        vm.expectRevert(
            abi.encodeWithSelector(SinjohFeeRouter.InsufficientOutput.selector, 10_001, 10_000)
        );
        router.sync(address(subjectToken), 1);
    }

    function testNormalizationRejectsExpiredGuardQuote() public {
        subjectToken.mint(address(router), 10_000);
        priceGuard.setQuote(10_000, uint48(block.timestamp - 1));

        vm.expectRevert(SinjohFeeRouter.InvalidExpiry.selector);
        router.sync(address(subjectToken), 1);
    }

    function testNormalizationRejectsZeroGuardQuote() public {
        subjectToken.mint(address(router), 10_000);
        priceGuard.setQuote(0, type(uint48).max);

        vm.expectRevert(SinjohFeeRouter.InvalidMinimumOutput.selector);
        router.sync(address(subjectToken), 1);
    }

    function testNormalizationGuardReceivesExactSwapArguments() public {
        subjectToken.mint(address(router), 123);
        weth.mint(address(adapter), 123);
        priceGuard.setExpectedArguments(
            address(subjectToken), address(subjectToken), address(weth), 123, keccak256(hex"01"), ""
        );

        router.sync(address(subjectToken), 1);
        assertEq(router.totalLiability(address(weth)), 123);
    }

    function testNormalizationProcessesBoundedTranchesAfterOversizedDonation() public {
        RouterTypes.Config memory config = _config();
        config.normalizations[0].maxAmountInPerCall = 100;
        SinjohFeeRouter bounded =
            SinjohFeeRouter(payable(factory.deploy(address(this), bytes32("BOUNDED"), config)));
        bounded.bind(address(subjectToken));
        subjectToken.mint(address(bounded), 250);
        weth.mint(address(adapter), 250);

        (uint256 firstGross,) = bounded.sync(address(subjectToken), 1);
        assertEq(firstGross, 100);
        assertEq(subjectToken.balanceOf(address(bounded)), 150);
        assertEq(bounded.unaccountedBalance(address(subjectToken)), 150);
        assertEq(bounded.totalLiability(address(weth)), 100);

        (uint256 secondGross,) = bounded.sync(address(subjectToken), 1);
        assertEq(secondGross, 100);
        assertEq(bounded.unaccountedBalance(address(subjectToken)), 50);
        assertEq(bounded.totalLiability(address(weth)), 200);
    }

    /// @dev The floor is meaningless when no swap happens, and must not block.
    function testWethSyncIgnoresTheFloor() public {
        weth.mint(address(router), 10_000);
        (uint256 gross,) = router.sync(address(weth), type(uint256).max);
        assertEq(gross, 10_000);
    }

    /// @dev A swappable asset cannot be synchronized without stating a floor.
    /// The one-argument form exists only for WETH, which performs no swap.
    function testSwappableAssetsMustStateAFloor() public {
        subjectToken.mint(address(router), 10_000);
        weth.mint(address(adapter), 10_000);

        vm.expectRevert(
            abi.encodeWithSelector(
                SinjohFeeRouter.NormalizationFloorRequired.selector, address(subjectToken)
            )
        );
        router.sync(address(subjectToken));

        vm.expectRevert(
            abi.encodeWithSelector(
                SinjohFeeRouter.NormalizationFloorRequired.selector, address(subjectToken)
            )
        );
        router.sync(address(subjectToken), 0);
    }

    function testWethOnlyRouterNeedsNoDummyNormalization() public {
        RouterTypes.Config memory config = _config();
        config.normalizations = new RouterTypes.Normalization[](0);
        SinjohFeeRouter wethOnly =
            SinjohFeeRouter(payable(factory.deploy(address(this), bytes32("WETH_ONLY"), config)));
        wethOnly.bind(address(subjectToken));

        assertEq(wethOnly.normalizationCount(), 0);
        assertEq(wethOnly.intakeAssetCount(), 1);
        assertTrue(wethOnly.isIntakeAsset(address(weth)));
        assertTrue(!wethOnly.isIntakeAsset(address(subjectToken)));

        weth.mint(address(wethOnly), 10_000);
        wethOnly.sync(address(weth));
        assertEq(wethOnly.totalLiability(address(weth)), 10_000);
    }

    /// @dev And the refusal says why. Telling a caller to supply a floor for an
    /// asset that has no route at all would send them to fix the wrong thing.
    function testRefusalDistinguishesNoRouteFromNoFloor() public {
        vm.expectRevert(
            abi.encodeWithSelector(SinjohFeeRouter.UnsupportedAsset.selector, address(payoutToken))
        );
        router.sync(address(payoutToken));

        vm.expectRevert(SinjohFeeRouter.NativeIntakeUnsupported.selector);
        router.sync(address(0));
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

        (uint256 gross, uint256 fee) = router.sync(address(subjectToken), 1);

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

    function testPermissionlessBucketSwapCannotWeakenImmutableGuard() public {
        weth.mint(address(router), 10_000);
        subjectToken.mint(address(adapter), 4_950);
        router.sync(address(weth));
        priceGuard.setQuote(4_951, type(uint48).max);

        vm.prank(address(0xBAD));
        vm.expectRevert(
            abi.encodeWithSelector(SinjohFeeRouter.InsufficientOutput.selector, 4_951, 4_950)
        );
        router.processBucket(1, address(weth), 4_950, 0, "");

        assertEq(router.bucketInputOwed(1, address(weth)), 4_950);
        assertEq(router.totalLiability(address(weth)), 10_000);
    }

    function testBucketGuardReceivesExactSwapArgumentsAndGuardData() public {
        weth.mint(address(router), 10_000);
        subjectToken.mint(address(adapter), 4_950);
        router.sync(address(weth));
        bytes memory guardData = hex"cafe";
        priceGuard.setExpectedArguments(
            address(subjectToken),
            address(weth),
            address(subjectToken),
            4_950,
            keccak256(hex"02"),
            guardData
        );

        vm.prank(address(0xBAD));
        router.processBucket(1, address(weth), 4_950, 0, guardData);
        assertEq(router.walletOwed(router.BURN_ADDRESS(), address(subjectToken)), 4_950);
    }

    function testBucketRejectsExpiredGuardQuote() public {
        weth.mint(address(router), 10_000);
        router.sync(address(weth));
        priceGuard.setQuote(1, uint48(block.timestamp - 1));

        vm.expectRevert(SinjohFeeRouter.InvalidExpiry.selector);
        router.processBucket(1, address(weth), 4_950, 0, "");
    }

    function testBucketRejectsZeroGuardQuote() public {
        weth.mint(address(router), 10_000);
        router.sync(address(weth));
        priceGuard.setQuote(0, type(uint48).max);

        vm.expectRevert(SinjohFeeRouter.InvalidMinimumOutput.selector);
        router.processBucket(1, address(weth), 4_950, 0, "");
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

    function testNativeBucketRequiresExactOneToOneUnwrap() public {
        RouterTypes.Config memory config = _nativeConfig();
        SinjohFeeRouter nativeRouter = SinjohFeeRouter(
            payable(factory.deploy(address(this), bytes32("NATIVE_EXACT"), config))
        );
        nativeRouter.bind(address(subjectToken));
        weth.mint(address(nativeRouter), 10_000);
        vm.deal(address(adapter), 10_000);
        adapter.setRate(1, 2);
        nativeRouter.sync(address(weth));

        vm.expectRevert(
            abi.encodeWithSelector(SinjohFeeRouter.InsufficientOutput.selector, 9_900, 4_950)
        );
        nativeRouter.processBucket(0, address(weth), 9_900, 0, "");
        assertEq(nativeRouter.bucketInputOwed(0, address(weth)), 9_900);
    }

    function testPartialProcessingIsAllowedAndRemainderStaysCredited() public {
        weth.mint(address(router), 10_000);
        router.sync(address(weth));
        router.processBucket(0, address(weth), 1_000, 0, "");
        assertEq(router.bucketInputOwed(0, address(weth)), 3_950);
        router.processBucket(0, address(weth), 3_950, 0, "");
        assertEq(router.bucketInputOwed(0, address(weth)), 0);
    }

    function testBucketCapRejectsOversizedTrancheAndLeavesLiability() public {
        RouterTypes.Config memory config = _config();
        config.buckets[0].maxAmountInPerCall = 100;
        SinjohFeeRouter capped =
            SinjohFeeRouter(payable(factory.deploy(address(this), bytes32("BUCKET_CAP"), config)));
        capped.bind(address(subjectToken));
        weth.mint(address(capped), 1_000);
        capped.sync(address(weth));

        vm.expectRevert(SinjohFeeRouter.InvalidAmount.selector);
        capped.processBucket(0, address(weth), 101, 0, "");
        assertEq(capped.bucketInputOwed(0, address(weth)), 495);
        assertEq(capped.totalLiability(address(weth)), 1_000);

        capped.processBucket(0, address(weth), 99, 0, "");
        assertEq(capped.bucketInputOwed(0, address(weth)), 396);
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

    function testOnlyCreatorMayRepointAndSinkCannotBeRepointed() public {
        vm.prank(address(0xBAD));
        vm.expectRevert(SinjohFeeRouter.Unauthorized.selector);
        router.repointWallet(0, 0, NEW_WALLET);

        vm.expectRevert(SinjohFeeRouter.ImmutableAllocation.selector);
        router.repointWallet(0, 1, NEW_WALLET);
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

    function testRevertingSinkPreservesLiabilityAndAllowance() public {
        weth.mint(address(router), 10_000);
        router.sync(address(weth));
        router.processBucket(0, address(weth), 4_950, 0, "");
        sink.setShouldRevert(true);

        vm.expectRevert();
        router.fundSink(0, 1, 2_475);

        assertEq(router.sinkOwed(router.allocationKey(0, 1), address(weth)), 2_475);
        assertEq(router.totalLiability(address(weth)), 10_000);
        assertEq(weth.allowance(address(router), address(sink)), 0);

        // A failed sink is isolated from an independent wallet delivery.
        router.sendWallet(WALLET, address(weth), 2_475);
        assertEq(weth.balanceOf(WALLET), 2_475);
    }

    function testSinkReceiptMismatchPreservesLiabilityAndAllowance() public {
        weth.mint(address(router), 10_000);
        router.sync(address(weth));
        router.processBucket(0, address(weth), 4_950, 0, "");
        sink.setLieAboutReceipt(true);

        vm.expectRevert(
            abi.encodeWithSelector(SinjohFeeRouter.SinkReceiptMismatch.selector, 2_475, 2_474)
        );
        router.fundSink(0, 1, 2_475);

        assertEq(router.sinkOwed(router.allocationKey(0, 1), address(weth)), 2_475);
        assertEq(router.totalLiability(address(weth)), 10_000);
        assertEq(weth.allowance(address(router), address(sink)), 0);
    }

    function testRevertingWalletTransferPreservesLiability() public {
        weth.mint(address(router), 10_000);
        router.sync(address(weth));
        router.processBucket(0, address(weth), 4_950, 0, "");
        weth.setFailTransfers(true);

        vm.expectRevert();
        router.sendWallet(WALLET, address(weth), 2_475);

        assertEq(router.walletOwed(WALLET, address(weth)), 2_475);
        assertEq(router.totalLiability(address(weth)), 10_000);
    }

    function testExistingSubjectLiabilityIsExcludedFromNewSubjectIntake() public {
        weth.mint(address(router), 10_000);
        subjectToken.mint(address(adapter), 5_050);
        router.sync(address(weth));
        router.processBucket(1, address(weth), 4_950, 0, "");
        assertEq(router.totalLiability(address(subjectToken)), 4_950);

        subjectToken.mint(address(router), 100);
        weth.mint(address(adapter), 100);
        (uint256 gross,) = router.sync(address(subjectToken), 1);

        assertEq(gross, 100);
        assertEq(router.totalLiability(address(subjectToken)), 4_950);
        assertEq(subjectToken.balanceOf(address(router)), 4_950);
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

    function testBucketSharesAreIndependentOfSyncCallSplitting() public {
        RouterTypes.Config memory config = _config();
        SinjohFeeRouter oneShot =
            SinjohFeeRouter(payable(factory.deploy(address(this), bytes32("ONE_SHOT"), config)));
        SinjohFeeRouter split =
            SinjohFeeRouter(payable(factory.deploy(address(this), bytes32("SPLIT"), config)));
        oneShot.bind(address(subjectToken));
        split.bind(address(subjectToken));

        weth.mint(address(oneShot), 100);
        oneShot.sync(address(weth));
        for (uint256 i; i < 100; ++i) {
            weth.mint(address(split), 1);
            split.sync(address(weth));
        }

        assertEq(split.bucketInputOwed(0, address(weth)), oneShot.bucketInputOwed(0, address(weth)));
        assertEq(split.bucketInputOwed(1, address(weth)), oneShot.bucketInputOwed(1, address(weth)));
        assertEq(split.bucketInputOwed(0, address(weth)), 50);
        assertEq(split.bucketInputOwed(1, address(weth)), 49);
    }

    function testThreeBucketApportionmentNeverDecreasesAnEntitlement() public {
        RouterTypes.Config memory config = _threeBucketConfig();
        SinjohFeeRouter three = SinjohFeeRouter(
            payable(factory.deploy(address(this), bytes32("THREE_ROUNDING"), config))
        );
        three.bind(address(subjectToken));

        weth.mint(address(three), 9);
        three.sync(address(weth));
        weth.mint(address(three), 1);
        three.sync(address(weth));

        assertEq(three.bucketInputOwed(0, address(weth)), 4);
        assertEq(three.bucketInputOwed(1, address(weth)), 3);
        assertEq(three.bucketInputOwed(2, address(weth)), 3);
    }

    function testFuzzThreeBucketApportionmentIsSplitIndependent(uint96 rawFirst, uint96 rawSecond)
        public
    {
        uint256 first = uint256(rawFirst) % 1e24 + 1;
        uint256 second = uint256(rawSecond) % 1e24 + 1;
        RouterTypes.Config memory config = _threeBucketConfig();
        SinjohFeeRouter oneShot = SinjohFeeRouter(
            payable(factory.deploy(address(this), bytes32("THREE_FUZZ_ONE"), config))
        );
        SinjohFeeRouter split = SinjohFeeRouter(
            payable(factory.deploy(address(this), bytes32("THREE_FUZZ_SPLIT"), config))
        );
        oneShot.bind(address(subjectToken));
        split.bind(address(subjectToken));

        weth.mint(address(oneShot), first + second);
        oneShot.sync(address(weth));
        weth.mint(address(split), first);
        split.sync(address(weth));
        weth.mint(address(split), second);
        split.sync(address(weth));

        for (uint8 i; i < 3; ++i) {
            assertEq(
                split.bucketInputOwed(i, address(weth)), oneShot.bucketInputOwed(i, address(weth))
            );
        }
    }

    function testApportionmentHandlesMaximumUintWithoutOverflow() public {
        weth.mint(address(router), type(uint256).max);
        router.sync(address(weth));

        assertEq(router.totalLiability(address(weth)), type(uint256).max);
        assertEq(
            router.protocolOwed(address(weth)) + router.bucketInputOwed(0, address(weth))
                + router.bucketInputOwed(1, address(weth)),
            type(uint256).max
        );
    }

    function testAllocationSharesAreIndependentOfProcessingCallSplitting() public {
        RouterTypes.Config memory config = _config();
        SinjohFeeRouter oneShot = SinjohFeeRouter(
            payable(factory.deploy(address(this), bytes32("ALLOC_ONE_SHOT"), config))
        );
        SinjohFeeRouter split =
            SinjohFeeRouter(payable(factory.deploy(address(this), bytes32("ALLOC_SPLIT"), config)));
        oneShot.bind(address(subjectToken));
        split.bind(address(subjectToken));
        weth.mint(address(oneShot), 1_000);
        weth.mint(address(split), 1_000);
        oneShot.sync(address(weth));
        split.sync(address(weth));

        oneShot.processBucket(0, address(weth), 100, 0, "");
        for (uint256 i; i < 100; ++i) {
            split.processBucket(0, address(weth), 1, 0, "");
        }

        assertEq(split.walletOwed(WALLET, address(weth)), oneShot.walletOwed(WALLET, address(weth)));
        assertEq(
            split.sinkOwed(split.allocationKey(0, 1), address(weth)),
            oneShot.sinkOwed(oneShot.allocationKey(0, 1), address(weth))
        );
        assertEq(split.walletOwed(WALLET, address(weth)), 50);
    }

    function testThreeAllocationApportionmentNeverDecreasesAnEntitlement() public {
        RouterTypes.Config memory config = _threeAllocationConfig();
        SinjohFeeRouter three = SinjohFeeRouter(
            payable(factory.deploy(address(this), bytes32("THREE_ALLOC_ROUNDING"), config))
        );
        three.bind(address(subjectToken));
        weth.mint(address(three), 100);
        three.sync(address(weth));

        three.processBucket(0, address(weth), 9, 0, "");
        three.processBucket(0, address(weth), 1, 0, "");

        assertEq(three.walletOwed(WALLET, address(weth)), 4);
        assertEq(three.walletOwed(NEW_WALLET, address(weth)), 3);
        assertEq(three.walletOwed(three.BURN_ADDRESS(), address(weth)), 3);
    }

    function testInitializationRejectsNonContractSink() public {
        RouterTypes.Config memory config = _config();
        config.buckets[0].allocations[1].destination = address(0xBEEF);
        vm.expectPartialRevert(SinjohFeeRouterFactory.InitializationFailed.selector);
        factory.deploy(address(this), bytes32("EOA_SINK"), config);
    }

    function testInitializationRejectsZeroNormalizationCap() public {
        RouterTypes.Config memory config = _config();
        config.normalizations[0].maxAmountInPerCall = 0;
        vm.expectPartialRevert(SinjohFeeRouterFactory.InitializationFailed.selector);
        factory.deploy(address(this), bytes32("ZERO_CAP"), config);
    }

    function testInitializationRejectsZeroBucketCap() public {
        RouterTypes.Config memory config = _config();
        config.buckets[0].maxAmountInPerCall = 0;
        vm.expectPartialRevert(SinjohFeeRouterFactory.InitializationFailed.selector);
        factory.deploy(address(this), bytes32("ZERO_BUCKET_CAP"), config);
    }

    function testInitializationRejectsMissingBucketGuard() public {
        RouterTypes.Config memory config = _config();
        config.buckets[1].priceGuard = address(0);
        vm.expectPartialRevert(SinjohFeeRouterFactory.InitializationFailed.selector);
        factory.deploy(address(this), bytes32("NO_BUCKET_GUARD"), config);
    }

    function testInitializationRejectsGuardOnIdentityBucket() public {
        RouterTypes.Config memory config = _config();
        config.buckets[0].priceGuard = address(priceGuard);
        vm.expectPartialRevert(SinjohFeeRouterFactory.InitializationFailed.selector);
        factory.deploy(address(this), bytes32("IDENTITY_GUARD"), config);
    }

    function testInitializationRejectsDuplicateNormalizationRefs() public {
        RouterTypes.Config memory config = _config();
        RouterTypes.Normalization[] memory duplicates = new RouterTypes.Normalization[](2);
        duplicates[0] = config.normalizations[0];
        duplicates[1] = config.normalizations[0];
        config.normalizations = duplicates;
        vm.expectPartialRevert(SinjohFeeRouterFactory.InitializationFailed.selector);
        factory.deploy(address(this), bytes32("DUP_NORMALIZATION"), config);
    }

    function testInitializationRejectsDuplicateBucketRefs() public {
        RouterTypes.Config memory config = _config();
        config.buckets[1].output = config.buckets[0].output;
        vm.expectPartialRevert(SinjohFeeRouterFactory.InitializationFailed.selector);
        factory.deploy(address(this), bytes32("DUP_BUCKET"), config);
    }

    function testInvalidInitializationDoesNotOccupyPredictedAddress() public {
        RouterTypes.Config memory config = _config();
        config.normalizations[0].maxAmountInPerCall = 0;
        address predicted = factory.predictAddress(address(this), bytes32("FAILED_INIT"), config);

        vm.expectPartialRevert(SinjohFeeRouterFactory.InitializationFailed.selector);
        factory.deploy(address(this), bytes32("FAILED_INIT"), config);
        assertEq(predicted.code.length, 0);
    }

    function testRouteViewsReturnImmutableGuardsAndCaps() public view {
        (
            address normalizationAdapter,
            address normalizationPriceGuard,
            bytes memory routeData,
            uint128 cap
        ) = router.normalizationInfo(address(subjectToken));
        assertEq(normalizationAdapter, address(adapter));
        assertEq(normalizationPriceGuard, address(priceGuard));
        assertTrue(keccak256(routeData) == keccak256(hex"01"));
        assertEq(uint256(cap), type(uint128).max);

        (,,, address bucketPriceGuard, bytes memory bucketRouteData, uint128 bucketCap,) =
            router.conversionInfo(1, 0);
        assertEq(bucketPriceGuard, address(priceGuard));
        assertTrue(keccak256(bucketRouteData) == keccak256(hex"02"));
        assertEq(uint256(bucketCap), type(uint128).max);
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
            route: RouterTypes.Route(address(adapter), hex"01"),
            priceGuard: address(priceGuard),
            maxAmountInPerCall: type(uint128).max
        });
    }

    /// @dev A launchpad paying fees in its quote asset. Both the subject and the
    /// quote asset need routes, each through its own adapter.
    function _quotePairConfig() internal view returns (RouterTypes.Config memory config) {
        config = _config();
        RouterTypes.Normalization[] memory normalizations = new RouterTypes.Normalization[](2);
        normalizations[0] = RouterTypes.Normalization({
            asset: RouterTypes.AssetRef(RouterTypes.AssetKind.SUBJECT, address(0)),
            route: RouterTypes.Route(address(adapter), hex"01"),
            priceGuard: address(priceGuard),
            maxAmountInPerCall: type(uint128).max
        });
        normalizations[1] = RouterTypes.Normalization({
            asset: RouterTypes.AssetRef(RouterTypes.AssetKind.FIXED_ERC20, address(quoteToken)),
            route: RouterTypes.Route(address(quoteAdapter), hex"09"),
            priceGuard: address(priceGuard),
            maxAmountInPerCall: type(uint128).max
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
            priceGuard: address(0),
            maxAmountInPerCall: type(uint128).max,
            allocations: wethAllocations
        });
        buckets[1] = RouterTypes.Bucket({
            output: RouterTypes.AssetRef(RouterTypes.AssetKind.SUBJECT, address(0)),
            bps: 5_000,
            route: RouterTypes.Route(address(adapter), hex"02"),
            priceGuard: address(priceGuard),
            maxAmountInPerCall: type(uint128).max,
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
            priceGuard: address(priceGuard),
            maxAmountInPerCall: type(uint128).max,
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
            priceGuard: address(0),
            maxAmountInPerCall: type(uint128).max,
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

    function _threeAllocationConfig() internal view returns (RouterTypes.Config memory config) {
        RouterTypes.Allocation[] memory allocations = new RouterTypes.Allocation[](3);
        allocations[0] = RouterTypes.Allocation({
            destination: WALLET, bps: 4_000, isSink: false, creatorMayRepoint: false, sinkConfig: ""
        });
        allocations[1] = RouterTypes.Allocation({
            destination: NEW_WALLET,
            bps: 3_000,
            isSink: false,
            creatorMayRepoint: false,
            sinkConfig: ""
        });
        allocations[2] = RouterTypes.Allocation({
            destination: 0x000000000000000000000000000000000000dEaD,
            bps: 3_000,
            isSink: false,
            creatorMayRepoint: false,
            sinkConfig: ""
        });
        RouterTypes.Bucket[] memory buckets = new RouterTypes.Bucket[](1);
        buckets[0] = RouterTypes.Bucket({
            output: RouterTypes.AssetRef(RouterTypes.AssetKind.FIXED_ERC20, address(weth)),
            bps: 10_000,
            route: RouterTypes.Route(address(0), ""),
            priceGuard: address(0),
            maxAmountInPerCall: type(uint128).max,
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
