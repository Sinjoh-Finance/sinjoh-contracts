// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockPriceGuard } from "./mocks/MockPriceGuard.sol";
import { MockSwapAdapter } from "./mocks/MockSwapAdapter.sol";
import { RouterTypes } from "../src/RouterTypes.sol";
import { SinjohFeeRouter } from "../src/SinjohFeeRouter.sol";
import { SinjohFeeRouterFactory } from "../src/SinjohFeeRouterFactory.sol";

/// @notice Covers normalising an intake asset into WETH before any split.
///
/// Without it, `sync` divides the project token across every bucket the moment
/// fees are logged, and each bucket has to sell its own share — one launch with
/// five conversions paid the pool fee and price impact five times.
contract SinjohFeeRouterNormalizeTest is TestBase {
    address internal constant PROTOCOL_RECIPIENT = address(0x1001);
    address internal constant WALLET = address(0x2002);

    MockERC20 internal subjectToken;
    MockERC20 internal quoteToken;
    MockERC20 internal payoutToken;
    MockPriceGuard internal guard;
    MockSwapAdapter internal adapter;
    SinjohFeeRouter internal implementation;
    SinjohFeeRouterFactory internal factory;
    SinjohFeeRouter internal router;

    function setUp() public {
        subjectToken = new MockERC20("Subject", "SUB");
        quoteToken = new MockERC20("Wrapped Ether", "WETH");
        payoutToken = new MockERC20("Payout", "PAY");
        guard = new MockPriceGuard(1, type(uint48).max);
        adapter = new MockSwapAdapter();
        implementation = new SinjohFeeRouter();
        factory = new SinjohFeeRouterFactory(address(implementation));

        router = SinjohFeeRouter(
            payable(factory.deploy(address(this), keccak256("normalize"), _config()))
        );
        router.bind(address(subjectToken));
    }

    function testSyncQueuesANormalizedAssetInsteadOfSplittingIt() public {
        subjectToken.mint(address(router), 1_000);
        router.sync(address(subjectToken));

        // 1% protocol fee, and the rest waits whole rather than being divided.
        assertEq(router.normalizeOwed(address(subjectToken)), 990);
        assertEq(router.bucketInputOwed(0, address(subjectToken)), 0);
        assertEq(router.bucketInputOwed(1, address(subjectToken)), 0);
    }

    function testNormalizeSellsOnceThenSplitsTheProceeds() public {
        // A whole number of 10,000-unit allocation cycles, so the split is
        // exact rather than phase-dependent.
        subjectToken.mint(address(router), 1_000_000);
        router.sync(address(subjectToken));
        quoteToken.mint(address(adapter), 1_000_000);

        uint256 out = router.normalize(address(subjectToken), 990_000, 0, "");

        assertEq(out, 990_000);
        assertEq(router.normalizeOwed(address(subjectToken)), 0);
        // Split across the two buckets by their bps, and charged no second fee.
        assertEq(router.bucketInputOwed(0, address(quoteToken)), 594_000);
        assertEq(router.bucketInputOwed(1, address(quoteToken)), 396_000);
        assertEq(router.totalLiability(address(subjectToken)), 10_000);
        assertEq(router.totalLiability(address(quoteToken)), 990_000);
    }

    /// @dev The protocol fee is taken once, when value is logged. Normalising
    /// moves already-charged value between assets and must not charge again.
    function testNormalizeChargesNoSecondProtocolFee() public {
        subjectToken.mint(address(router), 1_000_000);
        router.sync(address(subjectToken));
        quoteToken.mint(address(adapter), 1_000_000);
        router.normalize(address(subjectToken), 990_000, 0, "");

        assertEq(router.protocolOwed(address(subjectToken)), 10_000);
        assertEq(router.protocolOwed(address(quoteToken)), 0);
    }

    function testNormalizeTakesAnExactTranche() public {
        subjectToken.mint(address(router), 1_000);
        router.sync(address(subjectToken));
        quoteToken.mint(address(adapter), 10_000);

        vm.expectPartialRevert(SinjohFeeRouter.InvalidAmount.selector);
        router.normalize(address(subjectToken), 989, 0, "");
    }

    function testNormalizeRejectsAnAssetWithNoNormalizationRoute() public {
        quoteToken.mint(address(router), 1_000);
        router.sync(address(quoteToken));

        vm.expectPartialRevert(SinjohFeeRouter.NotNormalized.selector);
        router.normalize(address(quoteToken), 990, 0, "");
    }

    /// @dev A bucket conversion for a normalized asset could never run, because
    /// that asset never reaches a bucket. Freezing one would be dead config.
    function testConfigurationRejectsABucketConversionForANormalizedAsset() public {
        RouterTypes.Config memory config = _config();
        RouterTypes.Conversion[] memory conversions = new RouterTypes.Conversion[](2);
        conversions[0] = config.buckets[0].conversions[0];
        conversions[1] = RouterTypes.Conversion({
            input: RouterTypes.AssetRef({
                kind: RouterTypes.AssetKind.SUBJECT,
                token: address(0)
            }),
            adapter: address(adapter),
            priceGuard: address(guard),
            routeData: hex"01",
            maxAmountInPerCall: type(uint128).max,
            minInterval: 0
        });
        config.buckets[0].conversions = conversions;

        vm.expectPartialRevert(SinjohFeeRouterFactory.InitializationFailed.selector);
        factory.deploy(address(this), keccak256("dead-conversion"), config);
    }

    function testConfigurationRejectsNormalizingTheQuoteAssetIntoItself() public {
        RouterTypes.Config memory config = _config();
        config.normalizations[0].input = RouterTypes.AssetRef({
            kind: RouterTypes.AssetKind.FIXED_ERC20,
            token: address(quoteToken)
        });

        vm.expectPartialRevert(SinjohFeeRouterFactory.InitializationFailed.selector);
        factory.deploy(address(this), keccak256("weth-into-weth"), config);
    }

    function _config() internal view returns (RouterTypes.Config memory config) {
        RouterTypes.AssetRef memory subjectRef =
            RouterTypes.AssetRef({ kind: RouterTypes.AssetKind.SUBJECT, token: address(0) });
        RouterTypes.AssetRef memory quoteRef = RouterTypes.AssetRef({
            kind: RouterTypes.AssetKind.FIXED_ERC20,
            token: address(quoteToken)
        });
        RouterTypes.AssetRef memory payoutRef = RouterTypes.AssetRef({
            kind: RouterTypes.AssetKind.FIXED_ERC20,
            token: address(payoutToken)
        });

        RouterTypes.AssetRef[] memory intakeAssets = new RouterTypes.AssetRef[](2);
        intakeAssets[0] = subjectRef;
        intakeAssets[1] = quoteRef;

        // The project token becomes WETH once, before anything is divided.
        RouterTypes.Conversion[] memory normalizations = new RouterTypes.Conversion[](1);
        normalizations[0] = RouterTypes.Conversion({
            input: subjectRef,
            adapter: address(adapter),
            priceGuard: address(guard),
            routeData: hex"1234",
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

        // Every bucket now only ever handles WETH.
        RouterTypes.Conversion[] memory keepWeth = new RouterTypes.Conversion[](1);
        keepWeth[0] = RouterTypes.Conversion({
            input: quoteRef,
            adapter: address(0),
            priceGuard: address(0),
            routeData: "",
            maxAmountInPerCall: type(uint128).max,
            minInterval: 0
        });
        RouterTypes.Conversion[] memory intoPayout = new RouterTypes.Conversion[](1);
        intoPayout[0] = RouterTypes.Conversion({
            input: quoteRef,
            adapter: address(adapter),
            priceGuard: address(guard),
            routeData: hex"5678",
            maxAmountInPerCall: type(uint128).max,
            minInterval: 0
        });

        RouterTypes.Bucket[] memory buckets = new RouterTypes.Bucket[](2);
        buckets[0] = RouterTypes.Bucket({
            output: quoteRef, bps: 6_000, conversions: keepWeth, allocations: allocations
        });
        buckets[1] = RouterTypes.Bucket({
            output: payoutRef, bps: 4_000, conversions: intoPayout, allocations: allocations
        });

        config = RouterTypes.Config({
            creator: address(this),
            protocolFeeRecipient: PROTOCOL_RECIPIENT,
            weth: address(quoteToken),
            intakeAssets: intakeAssets,
            normalizations: normalizations,
            buckets: buckets
        });
    }
}
