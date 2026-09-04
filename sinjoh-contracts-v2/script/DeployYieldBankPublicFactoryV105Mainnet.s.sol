// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { CreationCodeStoreV2 } from "../src/core/CreationCodeStoreV2.sol";
import { YieldBankCollection } from "../src/yield-banks/YieldBankCollection.sol";
import { YieldBankProtocolRegistry } from "../src/yield-banks/YieldBankProtocolRegistry.sol";
import { YieldBankPublicFactory } from "../src/yield-banks/YieldBankPublicFactory.sol";

/// @notice Installs the public factory release with policy-backed paid Merkle mint stages.
/// @dev Reuses every unchanged V1.0.4 creation-code store and replaces only the collection store.
contract DeployYieldBankPublicFactoryV105Mainnet is Script {
    uint256 private constant EXPECTED_CHAIN_ID = 4_663;
    address private constant V104_FACTORY = 0x2cCF137B1B41F325b23fBD467FbD1C2d65e695f7;
    bytes32 public constant FACTORY_VERSION = keccak256("SINJOH_YIELD_BANK_PUBLIC_FACTORY_V1_0_5");

    error InvalidDeployment();
    error WrongAddress(address expected, address actual);

    function run() external returns (YieldBankPublicFactory factory) {
        address broadcaster = vm.envAddress("DEPLOYER_ADDRESS");
        uint64 expectedNonce = uint64(vm.envUint("EXPECTED_DEPLOYER_NONCE"));
        address expectedCollectionStore = vm.envAddress("EXPECTED_COLLECTION_STORE");
        address expectedFactory = vm.envAddress("EXPECTED_PUBLIC_FACTORY");
        YieldBankPublicFactory previous = YieldBankPublicFactory(V104_FACTORY);
        YieldBankPublicFactory.CreationCodeStores memory stores = previous.creationCodeStores();
        YieldBankPublicFactory.CreationCodeHashes memory hashes = previous.creationCodeHashes();
        hashes.collection = keccak256(type(YieldBankCollection).creationCode);
        _preflight(
            previous,
            broadcaster,
            expectedNonce,
            expectedCollectionStore,
            expectedFactory,
            stores,
            hashes
        );

        vm.startBroadcast();
        stores.collection = address(new CreationCodeStoreV2(type(YieldBankCollection).creationCode));
        factory = new YieldBankPublicFactory(
            address(previous.registry()),
            FACTORY_VERSION,
            previous.weth(),
            previous.usdg(),
            previous.seaDrop(),
            stores,
            hashes
        );
        YieldBankProtocolRegistry registry = previous.registry();
        registry.registerFactory(address(factory), FACTORY_VERSION, address(factory).codehash);
        registry.deprecateFactory(V104_FACTORY);
        vm.stopBroadcast();

        if (stores.collection != expectedCollectionStore) {
            revert WrongAddress(expectedCollectionStore, stores.collection);
        }
        if (address(factory) != expectedFactory) {
            revert WrongAddress(expectedFactory, address(factory));
        }
        _verify(previous.registry(), factory, stores, hashes);
        console2.log("YieldBankCollectionCreationCodeStoreV105", stores.collection);
        console2.log("YieldBankPublicFactoryV105", address(factory));
        console2.logBytes32(FACTORY_VERSION);
        console2.logBytes32(address(factory).codehash);
    }

    function _preflight(
        YieldBankPublicFactory previous,
        address broadcaster,
        uint64 expectedNonce,
        address expectedCollectionStore,
        address expectedFactory,
        YieldBankPublicFactory.CreationCodeStores memory stores,
        YieldBankPublicFactory.CreationCodeHashes memory hashes
    ) private view {
        YieldBankProtocolRegistry registry = previous.registry();
        (,, bool registered, bool deprecated) = registry.factories(V104_FACTORY);
        if (
            block.chainid != EXPECTED_CHAIN_ID || broadcaster != registry.governance()
                || vm.getNonce(broadcaster) != expectedNonce
                || vm.computeCreateAddress(broadcaster, expectedNonce) != expectedCollectionStore
                || vm.computeCreateAddress(broadcaster, expectedNonce + 1) != expectedFactory
                || expectedCollectionStore.code.length != 0 || expectedFactory.code.length != 0
                || !registered || deprecated
                || !registry.isFactoryAvailableForNewCollections(V104_FACTORY)
                || !_validStore(stores.supportBundle, hashes.supportBundle)
                || !_validStore(stores.revenueRouter, hashes.revenueRouter)
                || !_validStore(stores.portfolioAllocator, hashes.portfolioAllocator)
                || !_validStore(stores.collectionTimelock, hashes.collectionTimelock)
                || !_validStore(stores.coreSleeve, hashes.coreSleeve)
                || !_validStore(stores.marketMakingSleeve, hashes.marketMakingSleeve)
                || !_validStore(stores.usdgSleeve, hashes.usdgSleeve)
                || !_validStore(stores.accountImplementation, hashes.accountImplementation)
                || !_validStore(stores.deltaPoolController, hashes.deltaPoolController)
                || address(registry).code.length == 0 || previous.weth().code.length == 0
                || previous.usdg().code.length == 0 || previous.seaDrop().code.length == 0
        ) revert InvalidDeployment();
    }

    function _verify(
        YieldBankProtocolRegistry registry,
        YieldBankPublicFactory factory,
        YieldBankPublicFactory.CreationCodeStores memory stores,
        YieldBankPublicFactory.CreationCodeHashes memory hashes
    ) private view {
        (bytes32 version, bytes32 runtimeHash, bool registered, bool deprecated) =
            registry.factories(address(factory));
        if (
            factory.factoryVersion() != FACTORY_VERSION
                || keccak256(abi.encode(factory.creationCodeStores()))
                    != keccak256(abi.encode(stores))
                || keccak256(abi.encode(factory.creationCodeHashes()))
                    != keccak256(abi.encode(hashes)) || version != FACTORY_VERSION
                || runtimeHash != address(factory).codehash || !registered || deprecated
                || !registry.isFactoryAvailableForNewCollections(address(factory))
                || registry.isFactoryAvailableForNewCollections(V104_FACTORY)
                || !_validStore(stores.collection, hashes.collection)
        ) revert InvalidDeployment();
    }

    function _validStore(address store, bytes32 expected) private view returns (bool) {
        return store.code.length != 0 && CreationCodeStoreV2(store).creationCodeHash() == expected
            && keccak256(CreationCodeStoreV2(store).creationCode()) == expected;
    }
}
