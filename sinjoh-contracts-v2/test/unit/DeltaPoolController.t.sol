// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { DeltaPoolController } from "../../src/yield-banks/DeltaPoolController.sol";
import { PriceHub } from "../../src/yield-banks/PriceHub.sol";
import { StrategyRegistry } from "../../src/yield-banks/StrategyRegistry.sol";
import { DeltaV3LPAdapter } from "../../src/yield-banks/adapters/DeltaV3LPAdapter.sol";
import { DeltaV3SinglePoolRoute } from "../../src/yield-banks/adapters/DeltaV3SinglePoolRoute.sol";
import { DeltaV3TwapUsdFeed } from "../../src/yield-banks/adapters/DeltaV3TwapUsdFeed.sol";
import { MarketMakingSleeve } from "../../src/yield-banks/sleeves/MarketMakingSleeve.sol";
import { YieldBankAdapterState } from "../../src/yield-banks/YieldBankTypes.sol";
import {
    MockDeltaPositionBuilder,
    MockDeltaV3Factory,
    MockDeltaV3Pool,
    MockDeltaV3PositionManager
} from "../mocks/MockDeltaIntegrations.sol";
import {
    MockYieldBankAggregator,
    MockYieldBankAsset,
    MockYieldBankEligibilityPolicy
} from "../mocks/MockYieldBankIntegrations.sol";

contract MockDeltaPoolAllocatorSource {
    address public allocationOperator;
    address public collection;

    constructor(address operator_, address collection_) {
        allocationOperator = operator_;
        collection = collection_;
    }

    function setAllocationOperator(address operator_) external {
        allocationOperator = operator_;
    }
}

contract MockDynamicSleeveRegistrar {
    mapping(address sleeve => bool registered) public isRegistered;

    function registerDynamicSleeve(address sleeve) external {
        isRegistered[sleeve] = true;
    }
}

contract MalformedDeltaPool {
    address public immutable factory;

    constructor(address factory_) {
        factory = factory_;
    }
}

contract DeltaPoolControllerTest is Test {
    address private constant GUARDIAN = address(0x6A4D1A);

    MockYieldBankAsset private weth;
    MockYieldBankAsset private pairedAsset;
    MockDeltaV3Factory private factory;
    MockDeltaV3Pool private pool;
    MockDeltaV3PositionManager private manager;
    MockDeltaPositionBuilder private builder;
    MockDeltaPoolAllocatorSource private allocator;
    MockDynamicSleeveRegistrar private collectionRegistrar;
    MockYieldBankEligibilityPolicy private eligibilityPolicy;
    PriceHub private priceHub;
    StrategyRegistry private strategyRegistry;
    DeltaPoolController private controller;

    function setUp() external {
        weth = new MockYieldBankAsset("Wrapped Ether", "WETH");
        pairedAsset = new MockYieldBankAsset("Project Token", "PROJECT");
        factory = new MockDeltaV3Factory();
        pool = new MockDeltaV3Pool(
            address(factory), address(weth), address(pairedAsset), 10_000, 200
        );
        factory.setPool(address(weth), address(pairedAsset), 10_000, address(pool));
        manager = new MockDeltaV3PositionManager(address(factory), address(weth), address(pool));
        builder = new MockDeltaPositionBuilder(address(factory), address(manager), address(weth));
        collectionRegistrar = new MockDynamicSleeveRegistrar();
        allocator = new MockDeltaPoolAllocatorSource(address(this), address(collectionRegistrar));
        eligibilityPolicy = new MockYieldBankEligibilityPolicy();
        priceHub = new PriceHub(address(this), GUARDIAN);
        strategyRegistry = new StrategyRegistry(address(this));
        controller = new DeltaPoolController(
            address(allocator),
            address(this),
            GUARDIAN,
            address(weth),
            address(priceHub),
            address(strategyRegistry),
            address(eligibilityPolicy),
            10_000,
            1_000,
            1 days,
            1 days,
            5 minutes,
            1_000,
            1_000
        );
        priceHub.setRegistrar(address(controller), true);
        strategyRegistry.setRegistrar(address(controller), true);

        MockYieldBankAggregator wethFeed = new MockYieldBankAggregator(8, 3_000e8);
        MockYieldBankAggregator pairedFeed = new MockYieldBankAggregator(8, 1e8);
        priceHub.configureFeed(address(weth), address(wethFeed), address(0), 1 days, 0, false, 0);
        priceHub.configureFeed(
            address(pairedAsset), address(pairedFeed), address(0), 1 days, 0, false, 0
        );
        _configureInfrastructure(address(factory), address(manager), address(builder));
    }

    function testOwnerSelectablePoolRequiresNoPoolSpecificGovernanceOrManifestState() external {
        assertTrue(controller.isSelectablePool(address(pool)));
        assertTrue(controller.isAllocationPool(address(pool)));
        assertEq(controller.pairedAssetOf(address(pool)), address(pairedAsset));

        (address sleeve, address adapter) = _materialize();

        (
            address configuredSleeve,
            address configuredAdapter,
            bytes32 poolHash,
            bytes32 sleeveHash,
            bytes32 adapterHash
        ) = controller.foundationOf(address(pool));
        assertEq(configuredSleeve, sleeve);
        assertEq(configuredAdapter, adapter);
        assertEq(poolHash, address(pool).codehash);
        assertEq(sleeveHash, sleeve.codehash);
        assertEq(adapterHash, adapter.codehash);
        assertEq(controller.poolOfSleeve(sleeve), address(pool));
        assertNotEq(controller.foundationInfrastructureCommitment(address(pool)), bytes32(0));
        assertTrue(controller.isAllocationPool(address(pool)));
        assertEq(
            uint8(MarketMakingSleeve(sleeve).adapterState(adapter)),
            uint8(YieldBankAdapterState.ACTIVE)
        );
        assertTrue(strategyRegistry.isRuntimeValid(adapter));
        assertTrue(collectionRegistrar.isRegistered(sleeve));
    }

    function testOnlyCurrentAllocationOperatorCanMaterialize() external {
        address caller = address(0xBAD);
        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(DeltaPoolController.OnlyAllocationOperator.selector, caller)
        );
        controller.materializePool(
            address(pool),
            _materializationConfig(),
            type(DeltaV3SinglePoolRoute).creationCode,
            type(MarketMakingSleeve).creationCode,
            type(DeltaV3LPAdapter).creationCode
        );
    }

    function testMaterializationRejectsUnapprovedContractBytecode() external {
        vm.expectRevert(DeltaPoolController.InvalidConfiguration.selector);
        controller.materializePool(
            address(pool),
            _materializationConfig(),
            type(MockYieldBankAsset).creationCode,
            type(MarketMakingSleeve).creationCode,
            type(DeltaV3LPAdapter).creationCode
        );
    }

    function testPoolFeedIsDeployedFromTheApprovedBinary() external {
        priceHub.configureFeed(
            address(pairedAsset),
            address(new MockYieldBankAggregator(8, 1e8)),
            address(0),
            1 days,
            0,
            false,
            0
        );
        MockYieldBankAsset secondAsset = new MockYieldBankAsset("Unpriced Token", "UNPRICED");
        MockDeltaV3Pool secondPool =
            new MockDeltaV3Pool(address(factory), address(weth), address(secondAsset), 3_000, 60);
        factory.setPool(address(weth), address(secondAsset), 3_000, address(secondPool));

        // Pool immutables make runtime hashes differ; canonical factory discovery must still work.
        assertNotEq(address(secondPool).codehash, address(pool).codehash);
        address feed = controller.configurePoolDerivedFeed(
            address(secondPool),
            DeltaPoolController.PoolFeedConfig({
                referenceSource: address(0),
                heartbeat: 1 days,
                gracePeriod: 1 hours,
                twapWindow: 30 minutes,
                maxDeviationBps: 0,
                maxSpotDeviationBps: 500,
                comparisonAmount: 1e18,
                minimumLiquidity: 1,
                description: "UNPRICED / USD (Delta V3 TWAP)"
            }),
            type(DeltaV3TwapUsdFeed).creationCode
        );
        assertEq(address(DeltaV3TwapUsdFeed(feed).pool()), address(secondPool));
        assertEq(DeltaV3TwapUsdFeed(feed).pairedAsset(), address(secondAsset));
        assertEq(priceHub.feedDetails(address(secondAsset)).feed, feed);
    }

    function testPoolFeedConfigurationCannotExceedCollectionRiskPolicy() external {
        (address secondPool,) = _unpricedPool();
        DeltaPoolController.PoolFeedConfig memory config = _poolFeedConfig();

        config.heartbeat = 1 days + 1;
        _expectInvalidFeed(secondPool, config);
        config = _poolFeedConfig();
        config.gracePeriod = 1 days + 1;
        _expectInvalidFeed(secondPool, config);
        config = _poolFeedConfig();
        config.twapWindow = 5 minutes - 1;
        _expectInvalidFeed(secondPool, config);
        config = _poolFeedConfig();
        config.maxSpotDeviationBps = 1_001;
        _expectInvalidFeed(secondPool, config);
        config = _poolFeedConfig();
        config.referenceSource = address(new MockYieldBankAggregator(8, 1e8));
        config.maxDeviationBps = 1_001;
        _expectInvalidFeed(secondPool, config);
    }

    function testPoolFeedReferenceAndDeviationMustBeConfiguredTogether() external {
        (address secondPool,) = _unpricedPool();
        DeltaPoolController.PoolFeedConfig memory config = _poolFeedConfig();
        config.maxDeviationBps = 1;
        _expectInvalidFeed(secondPool, config);

        config = _poolFeedConfig();
        config.referenceSource = address(new MockYieldBankAggregator(8, 1e8));
        config.maxDeviationBps = 0;
        _expectInvalidFeed(secondPool, config);
    }

    function testDisablingInfrastructureStopsNewSelectionWithoutInvalidatingFoundationCustody()
        external
    {
        (address sleeve, address adapter) = _materialize();
        controller.setInfrastructureActive(address(factory), false);

        assertFalse(controller.isSelectablePool(address(pool)));
        assertFalse(controller.isAllocationPool(address(pool)));
        (address configuredSleeve, address configuredAdapter,,,) =
            controller.foundationOf(address(pool));
        assertEq(configuredSleeve, sleeve);
        assertEq(configuredAdapter, adapter);
    }

    function testReplacingSameFactoryInfrastructureCannotReactivateStaleFoundationDeposits()
        external
    {
        (address sleeve, address adapter) = _materialize();
        MockDeltaV3PositionManager replacementManager =
            new MockDeltaV3PositionManager(address(factory), address(weth), address(pool));
        MockDeltaPositionBuilder replacementBuilder = new MockDeltaPositionBuilder(
            address(factory), address(replacementManager), address(weth)
        );

        _configureInfrastructure(
            address(factory), address(replacementManager), address(replacementBuilder)
        );

        assertTrue(controller.isSelectablePool(address(pool)));
        assertFalse(controller.isAllocationPool(address(pool)));
        (address retainedSleeve, address retainedAdapter,,,) =
            controller.foundationOf(address(pool));
        assertEq(retainedSleeve, sleeve);
        assertEq(retainedAdapter, adapter);
    }

    function testRejectsPoolOutsideApprovedFactory() external {
        MockDeltaV3Factory otherFactory = new MockDeltaV3Factory();
        MockDeltaV3Pool otherPool = new MockDeltaV3Pool(
            address(otherFactory), address(weth), address(pairedAsset), 10_000, 200
        );
        otherFactory.setPool(address(weth), address(pairedAsset), 10_000, address(otherPool));
        assertFalse(controller.isSelectablePool(address(otherPool)));
    }

    function testPoolSelectionDoesNotConsumeGlobalDistributionAssetCapacity() external {
        assertTrue(controller.isSelectablePool(address(pool)));
        assertTrue(controller.isAllocationPool(address(pool)));
        _materialize();
        (address sleeve,,,,) = controller.foundationOf(address(pool));
        assertTrue(collectionRegistrar.isRegistered(sleeve));
    }

    function testArbitraryMalformedPoolAddressReturnsFalseInsteadOfReverting() external {
        MalformedDeltaPool malformed = new MalformedDeltaPool(address(factory));
        assertFalse(controller.isSelectablePool(address(malformed)));
    }

    function testGovernanceCanApproveANewSourceVerifiedInfrastructureGeneration() external {
        MockYieldBankAsset secondAsset = new MockYieldBankAsset("Second Token", "SECOND");
        MockDeltaV3Factory secondFactory = new MockDeltaV3Factory();
        MockDeltaV3Pool secondPool = new MockDeltaV3Pool(
            address(secondFactory), address(weth), address(secondAsset), 3_000, 60
        );
        secondFactory.setPool(address(weth), address(secondAsset), 3_000, address(secondPool));
        MockDeltaV3PositionManager secondManager = new MockDeltaV3PositionManager(
            address(secondFactory), address(weth), address(secondPool)
        );
        MockDeltaPositionBuilder secondBuilder = new MockDeltaPositionBuilder(
            address(secondFactory), address(secondManager), address(weth)
        );

        assertFalse(controller.isSelectablePool(address(secondPool)));
        _configureInfrastructure(
            address(secondFactory), address(secondManager), address(secondBuilder)
        );
        assertTrue(controller.isSelectablePool(address(secondPool)));
    }

    function _configureInfrastructure(address factory_, address manager_, address builder_)
        private
    {
        controller.configureInfrastructure(
            factory_,
            DeltaPoolController.InfrastructureConfig({
                positionManager: manager_,
                positionBuilder: builder_,
                factoryRuntimeCodeHash: factory_.codehash,
                positionManagerRuntimeCodeHash: manager_.codehash,
                positionBuilderRuntimeCodeHash: builder_.codehash,
                routeCreationCodeHash: keccak256(type(DeltaV3SinglePoolRoute).creationCode),
                sleeveCreationCodeHash: keccak256(type(MarketMakingSleeve).creationCode),
                adapterCreationCodeHash: keccak256(type(DeltaV3LPAdapter).creationCode),
                feedCreationCodeHash: keccak256(type(DeltaV3TwapUsdFeed).creationCode)
            })
        );
    }

    function _materialize() private returns (address sleeve, address adapter) {
        return controller.materializePool(
            address(pool),
            _materializationConfig(),
            type(DeltaV3SinglePoolRoute).creationCode,
            type(MarketMakingSleeve).creationCode,
            type(DeltaV3LPAdapter).creationCode
        );
    }

    function _unpricedPool() private returns (address secondPool, address secondAsset) {
        secondAsset = address(new MockYieldBankAsset("Unpriced Token", "UNPRICED"));
        secondPool =
            address(new MockDeltaV3Pool(address(factory), address(weth), secondAsset, 3_000, 60));
        factory.setPool(address(weth), secondAsset, 3_000, secondPool);
    }

    function _poolFeedConfig() private pure returns (DeltaPoolController.PoolFeedConfig memory) {
        return DeltaPoolController.PoolFeedConfig({
            referenceSource: address(0),
            heartbeat: 1 days,
            gracePeriod: 1 hours,
            twapWindow: 30 minutes,
            maxDeviationBps: 0,
            maxSpotDeviationBps: 500,
            comparisonAmount: 1e18,
            minimumLiquidity: 1,
            description: "UNPRICED / USD (Delta V3 TWAP)"
        });
    }

    function _expectInvalidFeed(
        address secondPool,
        DeltaPoolController.PoolFeedConfig memory config
    ) private {
        vm.expectRevert(DeltaPoolController.InvalidConfiguration.selector);
        controller.configurePoolDerivedFeed(
            secondPool, config, type(DeltaV3TwapUsdFeed).creationCode
        );
    }

    function _materializationConfig()
        private
        pure
        returns (DeltaPoolController.MaterializationConfig memory)
    {
        return DeltaPoolController.MaterializationConfig({
            maximumPositions: 8, adapterCapBps: 10_000, maximumOperatorLossBps: 1_000
        });
    }
}
