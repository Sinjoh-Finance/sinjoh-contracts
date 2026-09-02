// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { CreationCodeStoreV2 } from "../src/core/CreationCodeStoreV2.sol";
import { CollectionPortfolioAllocator } from "../src/yield-banks/CollectionPortfolioAllocator.sol";
import { CollectionRevenueRouter } from "../src/yield-banks/CollectionRevenueRouter.sol";
import { CollectionTimelock } from "../src/yield-banks/CollectionTimelock.sol";
import { DeltaPoolController } from "../src/yield-banks/DeltaPoolController.sol";
import { YieldBankAccount } from "../src/yield-banks/YieldBankAccount.sol";
import { YieldBankCollection } from "../src/yield-banks/YieldBankCollection.sol";
import { YieldBankProtocolRegistry } from "../src/yield-banks/YieldBankProtocolRegistry.sol";
import { YieldBankPublicFactory } from "../src/yield-banks/YieldBankPublicFactory.sol";
import { YieldBankSupportBundle } from "../src/yield-banks/YieldBankSupportBundle.sol";
import { CoreStockTokenSleeve } from "../src/yield-banks/sleeves/CoreStockTokenSleeve.sol";
import { MarketMakingSleeve } from "../src/yield-banks/sleeves/MarketMakingSleeve.sol";
import { USDGSleeve } from "../src/yield-banks/sleeves/USDGSleeve.sol";

/// @notice Installs the compact public factory and deprecates the unusable oversized-calldata
/// release. Component creation code is stored in ownerless contracts and pinned by both store
/// runtime hash and stored creation-code hash.
contract DeployYieldBankPublicFactoryV102Mainnet is Script {
    uint256 private constant EXPECTED_CHAIN_ID = 4_663;
    uint64 private constant STORE_COUNT = 10;

    address private constant GOVERNANCE = 0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49;
    address private constant REGISTRY = 0x09e4542f9fEA13A00aAF400E81bDC10434af5278;
    address private constant V101_FACTORY = 0x909541dbf65f9250EDAc3FaF61931E59881eb2b4;
    address private constant V100_FACTORY = 0xDEf30346f545f7D27393C0d6878898D13330d6a4;
    address private constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    address private constant USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;
    address private constant SEA_DROP = 0x00005EA00Ac477B1030CE78506496e8C2dE24bf5;

    bytes32 private constant REGISTRY_RUNTIME_CODE_HASH =
        0x946ec7768669b7520fa5744c788a77b2f865c6482b094f759ef323d6a5ecfef0;
    bytes32 private constant WETH_RUNTIME_CODE_HASH =
        0x5706be52f64875fee65a2cec0d80e47a23d8793cbe85d214b48445e2d05f5353;
    bytes32 private constant USDG_RUNTIME_CODE_HASH =
        0x864cc9ad53b338b82da1f7cab85ab0b3d5c8861acb422b6fec63cf36234f36a6;
    bytes32 private constant SEA_DROP_RUNTIME_CODE_HASH =
        0x53e4b9339cf624803c9a7d0195576cca5b917920813508d86b3eb93dcbabeb5c;

    bytes32 public constant FACTORY_VERSION = keccak256("SINJOH_YIELD_BANK_PUBLIC_FACTORY_V1_0_2");

    error WrongChain(uint256 expected, uint256 actual);
    error WrongBroadcaster(address expected, address actual);
    error WrongNonce(uint64 expected, uint64 actual);
    error WrongAddress(address expected, address actual);
    error RuntimeCodeHashMismatch(address instance, bytes32 expected, bytes32 actual);
    error FactoryRegistrationMismatch();
    error FactoryConfigurationMismatch();

    function run() external returns (YieldBankPublicFactory factory) {
        address broadcaster = vm.envAddress("DEPLOYER_ADDRESS");
        uint64 expectedNonce = uint64(vm.envUint("EXPECTED_DEPLOYER_NONCE"));
        address expectedFactory = vm.envAddress("EXPECTED_PUBLIC_FACTORY");
        _preflight(broadcaster, expectedNonce, expectedFactory);

        YieldBankPublicFactory.CreationCodeHashes memory hashes = _creationCodeHashes();
        vm.startBroadcast();
        YieldBankPublicFactory.CreationCodeStores memory stores = _deployStores();
        factory = new YieldBankPublicFactory(
            REGISTRY, FACTORY_VERSION, WETH, USDG, SEA_DROP, stores, hashes
        );
        YieldBankProtocolRegistry(REGISTRY)
            .registerFactory(address(factory), FACTORY_VERSION, address(factory).codehash);
        YieldBankProtocolRegistry(REGISTRY).deprecateFactory(V101_FACTORY);
        vm.stopBroadcast();

        if (address(factory) != expectedFactory) {
            revert WrongAddress(expectedFactory, address(factory));
        }
        _verifyFactory(factory, stores, hashes);
        _logDeployment(factory, stores);
    }

    function _preflight(address broadcaster, uint64 expectedNonce, address expectedFactory)
        private
        view
    {
        if (block.chainid != EXPECTED_CHAIN_ID) {
            revert WrongChain(EXPECTED_CHAIN_ID, block.chainid);
        }
        if (broadcaster != GOVERNANCE) revert WrongBroadcaster(GOVERNANCE, broadcaster);
        _requireRuntimeCodeHash(REGISTRY, REGISTRY_RUNTIME_CODE_HASH);
        _requireRuntimeCodeHash(WETH, WETH_RUNTIME_CODE_HASH);
        _requireRuntimeCodeHash(USDG, USDG_RUNTIME_CODE_HASH);
        _requireRuntimeCodeHash(SEA_DROP, SEA_DROP_RUNTIME_CODE_HASH);

        YieldBankProtocolRegistry registry = YieldBankProtocolRegistry(REGISTRY);
        if (registry.governance() != broadcaster) {
            revert WrongBroadcaster(registry.governance(), broadcaster);
        }
        (,, bool v101Registered, bool v101Deprecated) = registry.factories(V101_FACTORY);
        (,, bool v100Registered, bool v100Deprecated) = registry.factories(V100_FACTORY);
        if (!v101Registered || v101Deprecated || !v100Registered || !v100Deprecated) {
            revert FactoryRegistrationMismatch();
        }

        uint64 actualNonce = vm.getNonce(broadcaster);
        if (actualNonce != expectedNonce) revert WrongNonce(expectedNonce, actualNonce);
        address predictedFactory = vm.computeCreateAddress(broadcaster, expectedNonce + STORE_COUNT);
        if (predictedFactory != expectedFactory) {
            revert WrongAddress(expectedFactory, predictedFactory);
        }
        if (expectedFactory.code.length != 0) {
            revert RuntimeCodeHashMismatch(expectedFactory, bytes32(0), expectedFactory.codehash);
        }
    }

    function _deployStores()
        private
        returns (YieldBankPublicFactory.CreationCodeStores memory stores)
    {
        stores.supportBundle = _deployStore(type(YieldBankSupportBundle).creationCode);
        stores.revenueRouter = _deployStore(type(CollectionRevenueRouter).creationCode);
        stores.portfolioAllocator = _deployStore(type(CollectionPortfolioAllocator).creationCode);
        stores.collectionTimelock = _deployStore(type(CollectionTimelock).creationCode);
        stores.coreSleeve = _deployStore(type(CoreStockTokenSleeve).creationCode);
        stores.marketMakingSleeve = _deployStore(type(MarketMakingSleeve).creationCode);
        stores.usdgSleeve = _deployStore(type(USDGSleeve).creationCode);
        stores.accountImplementation = _deployStore(type(YieldBankAccount).creationCode);
        stores.deltaPoolController = _deployStore(type(DeltaPoolController).creationCode);
        stores.collection = _deployStore(type(YieldBankCollection).creationCode);
    }

    function _deployStore(bytes memory creationCode) private returns (address) {
        return address(new CreationCodeStoreV2(creationCode));
    }

    function _creationCodeHashes()
        private
        pure
        returns (YieldBankPublicFactory.CreationCodeHashes memory hashes)
    {
        hashes = YieldBankPublicFactory.CreationCodeHashes({
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

    function _verifyFactory(
        YieldBankPublicFactory factory,
        YieldBankPublicFactory.CreationCodeStores memory stores,
        YieldBankPublicFactory.CreationCodeHashes memory hashes
    ) private view {
        YieldBankPublicFactory.CreationCodeHashes memory storeRuntimeHashes =
            factory.creationCodeStoreRuntimeCodeHashes();
        if (
            address(factory.registry()) != REGISTRY || factory.factoryVersion() != FACTORY_VERSION
                || factory.weth() != WETH || factory.usdg() != USDG || factory.seaDrop() != SEA_DROP
                || factory.wethRuntimeCodeHash() != WETH_RUNTIME_CODE_HASH
                || factory.usdgRuntimeCodeHash() != USDG_RUNTIME_CODE_HASH
                || factory.seaDropRuntimeCodeHash() != SEA_DROP_RUNTIME_CODE_HASH
                || keccak256(abi.encode(factory.creationCodeHashes()))
                    != keccak256(abi.encode(hashes))
                || keccak256(abi.encode(factory.creationCodeStores()))
                    != keccak256(abi.encode(stores))
                || storeRuntimeHashes.supportBundle != stores.supportBundle.codehash
                || storeRuntimeHashes.revenueRouter != stores.revenueRouter.codehash
                || storeRuntimeHashes.portfolioAllocator != stores.portfolioAllocator.codehash
                || storeRuntimeHashes.collectionTimelock != stores.collectionTimelock.codehash
                || storeRuntimeHashes.coreSleeve != stores.coreSleeve.codehash
                || storeRuntimeHashes.marketMakingSleeve != stores.marketMakingSleeve.codehash
                || storeRuntimeHashes.usdgSleeve != stores.usdgSleeve.codehash
                || storeRuntimeHashes.accountImplementation != stores.accountImplementation.codehash
                || storeRuntimeHashes.deltaPoolController != stores.deltaPoolController.codehash
                || storeRuntimeHashes.collection != stores.collection.codehash
        ) revert FactoryConfigurationMismatch();

        _verifyStore(stores.supportBundle, hashes.supportBundle);
        _verifyStore(stores.revenueRouter, hashes.revenueRouter);
        _verifyStore(stores.portfolioAllocator, hashes.portfolioAllocator);
        _verifyStore(stores.collectionTimelock, hashes.collectionTimelock);
        _verifyStore(stores.coreSleeve, hashes.coreSleeve);
        _verifyStore(stores.marketMakingSleeve, hashes.marketMakingSleeve);
        _verifyStore(stores.usdgSleeve, hashes.usdgSleeve);
        _verifyStore(stores.accountImplementation, hashes.accountImplementation);
        _verifyStore(stores.deltaPoolController, hashes.deltaPoolController);
        _verifyStore(stores.collection, hashes.collection);

        YieldBankProtocolRegistry registry = YieldBankProtocolRegistry(REGISTRY);
        (bytes32 version, bytes32 runtimeHash, bool registered, bool deprecated) =
            registry.factories(address(factory));
        (,, bool v101Registered, bool v101Deprecated) = registry.factories(V101_FACTORY);
        (,, bool v100Registered, bool v100Deprecated) = registry.factories(V100_FACTORY);
        if (
            !registered || deprecated || version != FACTORY_VERSION
                || runtimeHash != address(factory).codehash || !v101Registered || !v101Deprecated
                || !v100Registered || !v100Deprecated
                || !registry.isFactoryAvailableForNewCollections(address(factory))
                || registry.isFactoryAvailableForNewCollections(V101_FACTORY)
                || registry.isFactoryAvailableForNewCollections(V100_FACTORY)
        ) revert FactoryRegistrationMismatch();
    }

    function _verifyStore(address store, bytes32 expectedCreationCodeHash) private view {
        CreationCodeStoreV2 codeStore = CreationCodeStoreV2(store);
        if (
            store.code.length == 0 || codeStore.creationCodeHash() != expectedCreationCodeHash
                || keccak256(codeStore.creationCode()) != expectedCreationCodeHash
        ) revert FactoryConfigurationMismatch();
    }

    function _logDeployment(
        YieldBankPublicFactory factory,
        YieldBankPublicFactory.CreationCodeStores memory stores
    ) private view {
        console2.log("YieldBankPublicFactoryV102", address(factory));
        console2.log("SupportBundleCreationCodeStore", stores.supportBundle);
        console2.log("RevenueRouterCreationCodeStore", stores.revenueRouter);
        console2.log("PortfolioAllocatorCreationCodeStore", stores.portfolioAllocator);
        console2.log("CollectionTimelockCreationCodeStore", stores.collectionTimelock);
        console2.log("CoreSleeveCreationCodeStore", stores.coreSleeve);
        console2.log("MarketMakingSleeveCreationCodeStore", stores.marketMakingSleeve);
        console2.log("USDGSleeveCreationCodeStore", stores.usdgSleeve);
        console2.log("AccountImplementationCreationCodeStore", stores.accountImplementation);
        console2.log("DeltaPoolControllerCreationCodeStore", stores.deltaPoolController);
        console2.log("CollectionCreationCodeStore", stores.collection);
        console2.logBytes32(FACTORY_VERSION);
        console2.logBytes32(address(factory).codehash);
    }

    function _requireRuntimeCodeHash(address instance, bytes32 expected) private view {
        bytes32 actual = instance.codehash;
        if (actual != expected) revert RuntimeCodeHashMismatch(instance, expected, actual);
    }
}
