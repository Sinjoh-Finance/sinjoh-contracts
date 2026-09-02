// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import {
    CollectionPortfolioAllocator
} from "../../src/yield-banks/CollectionPortfolioAllocator.sol";
import { CollectionRevenueRouter } from "../../src/yield-banks/CollectionRevenueRouter.sol";
import { CollectionTimelock } from "../../src/yield-banks/CollectionTimelock.sol";
import { DeltaPoolController } from "../../src/yield-banks/DeltaPoolController.sol";
import { YieldBankAccount } from "../../src/yield-banks/YieldBankAccount.sol";
import { YieldBankCollection } from "../../src/yield-banks/YieldBankCollection.sol";
import { YieldBankNFT } from "../../src/yield-banks/YieldBankNFT.sol";
import { YieldBankProtocolRegistry } from "../../src/yield-banks/YieldBankProtocolRegistry.sol";
import { YieldBankPublicFactory } from "../../src/yield-banks/YieldBankPublicFactory.sol";
import { YieldBankSupportBundle } from "../../src/yield-banks/YieldBankSupportBundle.sol";
import { YieldBankFeeWeightRange } from "../../src/yield-banks/YieldBankTypes.sol";
import { CoreStockTokenSleeve } from "../../src/yield-banks/sleeves/CoreStockTokenSleeve.sol";
import { MarketMakingSleeve } from "../../src/yield-banks/sleeves/MarketMakingSleeve.sol";
import { USDGSleeve } from "../../src/yield-banks/sleeves/USDGSleeve.sol";
import { MockYieldBankAsset, MockYieldBankSeaDrop } from "../mocks/MockYieldBankIntegrations.sol";

contract YieldBankPublicFactoryTest is Test {
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    bytes32 private constant VERSION = keccak256("PUBLIC-1");

    MockYieldBankAsset private weth;
    MockYieldBankAsset private usdg;
    MockYieldBankSeaDrop private seaDrop;
    YieldBankProtocolRegistry private registry;
    YieldBankPublicFactory private factory;

    function setUp() public {
        weth = new MockYieldBankAsset("W", "W");
        usdg = new MockYieldBankAsset("U", "U");
        seaDrop = new MockYieldBankSeaDrop();
        registry = new YieldBankProtocolRegistry(address(this));
        factory = new YieldBankPublicFactory(
            address(registry), VERSION, address(weth), address(usdg), address(seaDrop), _hashes()
        );
        registry.registerFactory(address(factory), VERSION, address(factory).codehash);
    }

    function testAnyWalletCanCreateAndRegisterAnIndependentCollection() public {
        YieldBankPublicFactory.CreationCode memory code = _code();
        YieldBankPublicFactory.CollectionRequest memory aliceRequest = _request(ALICE, "A", "A");
        YieldBankPublicFactory.CollectionRequest memory bobRequest = _request(BOB, "B", "B");
        bytes32 sharedUserSalt = keccak256("1");

        YieldBankPublicFactory.SystemAddresses memory alicePredicted =
            factory.predictComponentAddresses(ALICE, sharedUserSalt);
        YieldBankPublicFactory.SystemAddresses memory bobPredicted =
            factory.predictComponentAddresses(BOB, sharedUserSalt);
        assertNotEq(alicePredicted.supportBundle, bobPredicted.supportBundle);
        assertNotEq(alicePredicted.collectionTimelock, bobPredicted.collectionTimelock);

        vm.prank(ALICE);
        YieldBankPublicFactory.SystemAddresses memory aliceSystem =
            factory.createCollection(code, aliceRequest, sharedUserSalt);
        vm.prank(BOB);
        YieldBankPublicFactory.SystemAddresses memory bobSystem =
            factory.createCollection(code, bobRequest, sharedUserSalt);

        assertEq(aliceSystem.supportBundle, alicePredicted.supportBundle);
        assertEq(bobSystem.supportBundle, bobPredicted.supportBundle);
        assertNotEq(aliceSystem.collection, bobSystem.collection);
        assertTrue(registry.isActiveCollection(aliceSystem.collection));
        assertTrue(registry.isActiveCollection(bobSystem.collection));
        assertEq(YieldBankCollection(aliceSystem.collection).creator(), ALICE);
        assertEq(YieldBankCollection(aliceSystem.collection).nft().owner(), ALICE);
        assertEq(YieldBankCollection(bobSystem.collection).creator(), BOB);
        assertEq(YieldBankCollection(bobSystem.collection).nft().name(), "B");
        assertEq(CoreStockTokenSleeve(aliceSystem.coreSleeve).name(), "A Stock Token Sleeve");
        assertEq(CoreStockTokenSleeve(aliceSystem.coreSleeve).symbol(), "A-STOCK");
        assertEq(
            MarketMakingSleeve(aliceSystem.marketMakingSleeve).name(), "A Delta Liquidity Sleeve"
        );
        assertEq(MarketMakingSleeve(aliceSystem.marketMakingSleeve).symbol(), "A-DELTA");
        assertEq(USDGSleeve(aliceSystem.usdgSleeve).name(), "A USDG Sleeve");
        assertEq(USDGSleeve(aliceSystem.usdgSleeve).symbol(), "A-USDG");

        YieldBankNFT nft = YieldBankCollection(aliceSystem.collection).nft();
        vm.deal(address(this), 1 ether);
        seaDrop.mint{ value: 0.01 ether }(nft, ALICE, 1);
        assertEq(nft.ownerOf(1), ALICE);
        assertEq(
            YieldBankCollection(aliceSystem.collection).proceedsVault().pendingBackingOf(1),
            0.01 ether
        );
    }

    function testPublicCollectionUsesCallerConfiguredSupplyNameAndFeeWeights() public {
        YieldBankPublicFactory.CollectionRequest memory request =
            _request(ALICE, "Piggy Banks", "PIGGY");
        request.maxSupply = 3_333;
        request.feeWeightRanges = new YieldBankFeeWeightRange[](4);
        request.feeWeightRanges[0] = YieldBankFeeWeightRange({ endTokenId: 3_000, feeWeight: 2 });
        request.feeWeightRanges[1] = YieldBankFeeWeightRange({ endTokenId: 3_300, feeWeight: 5 });
        request.feeWeightRanges[2] = YieldBankFeeWeightRange({ endTokenId: 3_330, feeWeight: 15 });
        request.feeWeightRanges[3] = YieldBankFeeWeightRange({ endTokenId: 3_333, feeWeight: 60 });

        vm.prank(ALICE);
        YieldBankPublicFactory.SystemAddresses memory system =
            factory.createCollection(_code(), request, keccak256("PIGGY"));
        YieldBankCollection collection = YieldBankCollection(system.collection);

        assertEq(collection.maxSupply(), 3_333);
        assertEq(collection.maximumTotalFeeWeight(), 8_130);
        assertEq(collection.feeWeightOf(1), 2);
        assertEq(collection.feeWeightOf(3_001), 5);
        assertEq(collection.feeWeightOf(3_301), 15);
        assertEq(collection.feeWeightOf(3_331), 60);
        assertEq(collection.nft().name(), "Piggy Banks");
        assertEq(collection.nft().symbol(), "PIGGY");
    }

    function testCollectionEconomicsTimelockAndUnusedSleevesAreConfigurable() public {
        YieldBankPublicFactory.CollectionRequest memory request = _request(ALICE, "A", "A");
        request.coreWeightBps = 0;
        request.marketMakingWeightBps = 10_000;
        request.usdgWeightBps = 0;
        request.exitTaxBps = 137;
        request.royaltyBackingBps = 6_000;
        request.royaltyCreatorBps = 2_500;
        request.royaltySinjohBps = 1_500;
        request.timelockDelay = 0;

        vm.prank(ALICE);
        YieldBankPublicFactory.SystemAddresses memory system =
            factory.createCollection(_code(), request, keccak256("CONFIGURABLE"));
        YieldBankCollection collection = YieldBankCollection(system.collection);

        assertEq(collection.coreWeightBps(), 0);
        assertEq(collection.marketMakingWeightBps(), 10_000);
        assertEq(collection.usdgWeightBps(), 0);
        assertEq(collection.exitTaxBps(), 137);
        CollectionRevenueRouter router = CollectionRevenueRouter(payable(system.revenueRouter));
        assertEq(router.royaltyBackingBps(), 6_000);
        assertEq(router.royaltyCreatorBps(), 2_500);
        assertEq(router.royaltySinjohBps(), 1_500);
        assertEq(CollectionTimelock(payable(system.collectionTimelock)).getMinDelay(), 0);
    }

    function testCallerCannotSubstituteUnapprovedCreationCode() public {
        YieldBankPublicFactory.CreationCode memory code = _code();
        code.accountImplementation = hex"00";
        bytes32 actual = keccak256(code.accountImplementation);
        vm.prank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(
                YieldBankPublicFactory.CreationCodeHashMismatch.selector,
                factory.KIND_ACCOUNT_IMPLEMENTATION(),
                keccak256(type(YieldBankAccount).creationCode),
                actual
            )
        );
        factory.createCollection(code, _request(ALICE, "A", "A"), keccak256("2"));
    }

    function testSameCallerCannotReuseSalt() public {
        YieldBankPublicFactory.CreationCode memory code = _code();
        YieldBankPublicFactory.CollectionRequest memory request = _request(ALICE, "A", "A");
        bytes32 salt = keccak256("3");
        vm.prank(ALICE);
        factory.createCollection(code, request, salt);
        bytes32 id = factory.deploymentId(ALICE, salt);
        vm.prank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(YieldBankPublicFactory.DeploymentAlreadyUsed.selector, id)
        );
        factory.createCollection(code, request, salt);
    }

    function testZeroSaltIsRejectedBeforeDeployment() public {
        vm.prank(ALICE);
        vm.expectRevert(YieldBankPublicFactory.InvalidConfiguration.selector);
        factory.createCollection(_code(), _request(ALICE, "A", "A"), bytes32(0));
    }

    function testInvalidSleeveAndDeltaLimitsAreRejectedBeforeDeployment() public {
        YieldBankPublicFactory.CollectionRequest memory request = _request(ALICE, "A", "A");
        request.coreSleeve.maximumStrategies = 9;
        vm.prank(ALICE);
        vm.expectRevert(YieldBankPublicFactory.InvalidConfiguration.selector);
        factory.createCollection(_code(), request, keccak256("4"));

        request = _request(ALICE, "A", "A");
        request.deltaRisk.maximumPoolSpotDeviationBps = 2_001;
        vm.prank(ALICE);
        vm.expectRevert(YieldBankPublicFactory.InvalidConfiguration.selector);
        factory.createCollection(_code(), request, keccak256("5"));
    }

    function testInvalidFeeWeightScheduleIsRejectedBeforeDeployment() public {
        YieldBankPublicFactory.CollectionRequest memory request = _request(ALICE, "A", "A");
        request.feeWeightRanges = new YieldBankFeeWeightRange[](1);
        request.feeWeightRanges[0] = YieldBankFeeWeightRange({ endTokenId: 2, feeWeight: 1 });
        vm.prank(ALICE);
        vm.expectRevert(YieldBankPublicFactory.InvalidConfiguration.selector);
        factory.createCollection(_code(), request, keccak256("BAD-WEIGHTS"));

        request = _request(ALICE, "A", "A");
        request.maxSupply = 1;
        request.feeWeightRanges = new YieldBankFeeWeightRange[](1);
        request.feeWeightRanges[0] =
            YieldBankFeeWeightRange({ endTokenId: 1, feeWeight: uint96(1e27 + 1) });
        vm.prank(ALICE);
        vm.expectRevert(YieldBankPublicFactory.InvalidConfiguration.selector);
        factory.createCollection(_code(), request, keccak256("EXCESS-WEIGHT"));
    }

    function testDeprecatedFactoryCannotRegisterNewCollections() public {
        registry.deprecateFactory(address(factory));
        vm.prank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(
                YieldBankProtocolRegistry.FactoryUnavailable.selector, address(factory)
            )
        );
        factory.createCollection(_code(), _request(ALICE, "A", "A"), keccak256("6"));
    }

    function testDependencyRuntimeDriftFailsClosed() public {
        vm.etch(address(weth), hex"00");
        vm.prank(ALICE);
        vm.expectRevert(YieldBankPublicFactory.InvalidConfiguration.selector);
        factory.createCollection(_code(), _request(ALICE, "A", "A"), keccak256("7"));
    }

    function _hashes() private pure returns (YieldBankPublicFactory.CreationCodeHashes memory h) {
        h = YieldBankPublicFactory.CreationCodeHashes({
            supportBundle: keccak256(type(YieldBankSupportBundle).creationCode),
            revenueRouter: keccak256(type(CollectionRevenueRouter).creationCode),
            portfolioAllocator: keccak256(type(CollectionPortfolioAllocator).creationCode),
            collectionTimelock: keccak256(type(CollectionTimelock).creationCode),
            coreSleeve: keccak256(type(CoreStockTokenSleeve).creationCode),
            marketMakingSleeve: keccak256(type(MarketMakingSleeve).creationCode),
            usdgSleeve: keccak256(type(USDGSleeve).creationCode),
            accountImplementation: keccak256(type(YieldBankAccount).creationCode),
            deltaPoolController: keccak256(type(DeltaPoolController).creationCode),
            collection: keccak256(type(YieldBankCollection).creationCode)
        });
    }

    function _code() private pure returns (YieldBankPublicFactory.CreationCode memory code) {
        code = YieldBankPublicFactory.CreationCode({
            supportBundle: type(YieldBankSupportBundle).creationCode,
            revenueRouter: type(CollectionRevenueRouter).creationCode,
            portfolioAllocator: type(CollectionPortfolioAllocator).creationCode,
            collectionTimelock: type(CollectionTimelock).creationCode,
            coreSleeve: type(CoreStockTokenSleeve).creationCode,
            marketMakingSleeve: type(MarketMakingSleeve).creationCode,
            usdgSleeve: type(USDGSleeve).creationCode,
            accountImplementation: type(YieldBankAccount).creationCode,
            deltaPoolController: type(DeltaPoolController).creationCode,
            collection: type(YieldBankCollection).creationCode
        });
    }

    function _request(address owner, string memory name, string memory symbol)
        private
        pure
        returns (YieldBankPublicFactory.CollectionRequest memory r)
    {
        r.name = name;
        r.symbol = symbol;
        r.maxSupply = 3;
        r.primaryBackingBps = 10_000;
        r.exitTaxBps = 500;
        r.royaltyBackingBps = 10_000;
        r.coreWeightBps = 3_334;
        r.marketMakingWeightBps = 3_333;
        r.usdgWeightBps = 3_333;
        r.creator = owner;
        r.openSeaManager = owner;
        r.sinjohFeeRecipient = owner;
        r.allocationOperator = owner;
        r.timelockProposer = owner;
        r.timelockDelay = 7 days;
        r.guardian = owner;
        r.coreSleeve = YieldBankPublicFactory.SleeveConfig({
            maximumStrategies: 8, maximumAdapterCapBps: 10_000, maximumOperatorLossBps: 0
        });
        r.marketMakingSleeve = YieldBankPublicFactory.SleeveConfig({
            maximumStrategies: 8, maximumAdapterCapBps: 10_000, maximumOperatorLossBps: 0
        });
        r.usdgSleeve = YieldBankPublicFactory.SleeveConfig({
            maximumStrategies: 0, maximumAdapterCapBps: 0, maximumOperatorLossBps: 0
        });
        r.deltaRisk = YieldBankPublicFactory.DeltaRiskConfig({
            maximumAdapterCapBps: 10_000,
            maximumOperatorLossBps: 0,
            maximumPoolFeedHeartbeat: 1 days,
            maximumPoolFeedGracePeriod: 1 days,
            minimumPoolTwapWindow: 5 minutes,
            maximumPoolReferenceDeviationBps: 1_000,
            maximumPoolSpotDeviationBps: 1_000
        });
    }
}
