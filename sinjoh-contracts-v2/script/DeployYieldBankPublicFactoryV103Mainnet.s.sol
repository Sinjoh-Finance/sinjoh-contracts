// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { CreationCodeStoreV2 } from "../src/core/CreationCodeStoreV2.sol";
import { YieldBankProtocolRegistry } from "../src/yield-banks/YieldBankProtocolRegistry.sol";
import { YieldBankPublicFactory } from "../src/yield-banks/YieldBankPublicFactory.sol";

/// @notice Installs the staged public factory using the already-pinned v1.0.2 creation-code stores.
contract DeployYieldBankPublicFactoryV103Mainnet is Script {
    uint256 private constant EXPECTED_CHAIN_ID = 4_663;
    address private constant GOVERNANCE = 0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49;
    address private constant REGISTRY = 0x09e4542f9fEA13A00aAF400E81bDC10434af5278;
    address private constant V102_FACTORY = 0x3f7186138B591259113A3Fd4702E7ba52d7Ef4Bb;
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
    bytes32 public constant FACTORY_VERSION = keccak256("SINJOH_YIELD_BANK_PUBLIC_FACTORY_V1_0_3");

    error InvalidDeployment();
    error WrongAddress(address expected, address actual);

    function run() external returns (YieldBankPublicFactory factory) {
        address broadcaster = vm.envAddress("DEPLOYER_ADDRESS");
        uint64 expectedNonce = uint64(vm.envUint("EXPECTED_DEPLOYER_NONCE"));
        address expectedFactory = vm.envAddress("EXPECTED_PUBLIC_FACTORY");
        YieldBankPublicFactory.CreationCodeStores memory stores = _stores();
        YieldBankPublicFactory.CreationCodeHashes memory hashes = _hashes();
        _preflight(broadcaster, expectedNonce, expectedFactory, stores, hashes);

        vm.startBroadcast();
        factory = new YieldBankPublicFactory(
            REGISTRY, FACTORY_VERSION, WETH, USDG, SEA_DROP, stores, hashes
        );
        YieldBankProtocolRegistry(REGISTRY)
            .registerFactory(address(factory), FACTORY_VERSION, address(factory).codehash);
        YieldBankProtocolRegistry(REGISTRY).deprecateFactory(V102_FACTORY);
        vm.stopBroadcast();

        if (address(factory) != expectedFactory) {
            revert WrongAddress(expectedFactory, address(factory));
        }
        _verify(factory, stores, hashes);
        console2.log("YieldBankPublicFactoryV103", address(factory));
        console2.logBytes32(FACTORY_VERSION);
        console2.logBytes32(address(factory).codehash);
    }

    function _preflight(
        address broadcaster,
        uint64 expectedNonce,
        address expectedFactory,
        YieldBankPublicFactory.CreationCodeStores memory stores,
        YieldBankPublicFactory.CreationCodeHashes memory hashes
    ) private view {
        if (
            block.chainid != EXPECTED_CHAIN_ID || broadcaster != GOVERNANCE
                || vm.getNonce(broadcaster) != expectedNonce
                || vm.computeCreateAddress(broadcaster, expectedNonce) != expectedFactory
                || expectedFactory.code.length != 0
                || REGISTRY.codehash != REGISTRY_RUNTIME_CODE_HASH
                || WETH.codehash != WETH_RUNTIME_CODE_HASH
                || USDG.codehash != USDG_RUNTIME_CODE_HASH
                || SEA_DROP.codehash != SEA_DROP_RUNTIME_CODE_HASH
        ) revert InvalidDeployment();
        YieldBankProtocolRegistry registry = YieldBankProtocolRegistry(REGISTRY);
        (,, bool registered, bool deprecated) = registry.factories(V102_FACTORY);
        if (
            registry.governance() != broadcaster || !registered || deprecated
                || !registry.isFactoryAvailableForNewCollections(V102_FACTORY)
        ) revert InvalidDeployment();
        _verifyStores(stores, hashes);
    }

    function _verify(
        YieldBankPublicFactory factory,
        YieldBankPublicFactory.CreationCodeStores memory stores,
        YieldBankPublicFactory.CreationCodeHashes memory hashes
    ) private view {
        YieldBankProtocolRegistry registry = YieldBankProtocolRegistry(REGISTRY);
        (bytes32 version, bytes32 runtimeHash, bool registered, bool deprecated) =
            registry.factories(address(factory));
        if (
            address(factory.registry()) != REGISTRY || factory.factoryVersion() != FACTORY_VERSION
                || factory.weth() != WETH || factory.usdg() != USDG || factory.seaDrop() != SEA_DROP
                || keccak256(abi.encode(factory.creationCodeStores()))
                    != keccak256(abi.encode(stores))
                || keccak256(abi.encode(factory.creationCodeHashes()))
                    != keccak256(abi.encode(hashes)) || version != FACTORY_VERSION
                || runtimeHash != address(factory).codehash || !registered || deprecated
                || !registry.isFactoryAvailableForNewCollections(address(factory))
                || registry.isFactoryAvailableForNewCollections(V102_FACTORY)
        ) revert InvalidDeployment();
        _verifyStores(stores, hashes);
    }

    function _verifyStores(
        YieldBankPublicFactory.CreationCodeStores memory s,
        YieldBankPublicFactory.CreationCodeHashes memory h
    ) private view {
        if (
            !_validStore(s.supportBundle, h.supportBundle)
                || !_validStore(s.revenueRouter, h.revenueRouter)
                || !_validStore(s.portfolioAllocator, h.portfolioAllocator)
                || !_validStore(s.collectionTimelock, h.collectionTimelock)
                || !_validStore(s.coreSleeve, h.coreSleeve)
                || !_validStore(s.marketMakingSleeve, h.marketMakingSleeve)
                || !_validStore(s.usdgSleeve, h.usdgSleeve)
                || !_validStore(s.accountImplementation, h.accountImplementation)
                || !_validStore(s.deltaPoolController, h.deltaPoolController)
                || !_validStore(s.collection, h.collection)
        ) revert InvalidDeployment();
    }

    function _validStore(address store, bytes32 expected) private view returns (bool) {
        return store.code.length != 0 && CreationCodeStoreV2(store).creationCodeHash() == expected
            && keccak256(CreationCodeStoreV2(store).creationCode()) == expected;
    }

    function _stores() private pure returns (YieldBankPublicFactory.CreationCodeStores memory s) {
        s = YieldBankPublicFactory.CreationCodeStores({
            supportBundle: 0x39B2c823285a397F5E877e827a1D68547E8Ab13c,
            revenueRouter: 0x8B211c01E4dcc12ea31C8a2cD0E2C8B9737Ef359,
            portfolioAllocator: 0x409A9d297e9286F58404DAE9453F0ADE97C30834,
            collectionTimelock: 0x6CD871EB45413174E080A2EAbE0A2246561e924A,
            coreSleeve: 0x40def9B19B9059F8e7cA68Cb4c85aBAb81134FA5,
            marketMakingSleeve: 0x1CD61965E65f34caceF787D0c6eD58e42E2d6C02,
            usdgSleeve: 0xf87871300EC7680130d527AE3eCc15e8f9dc0054,
            accountImplementation: 0x06ffc59E5aFaa5A33246bd80aabdf8004F8ccBA4,
            deltaPoolController: 0xD40419E874315CaA3ECeaff6c334FE783D522Cb4,
            collection: 0xa309A3260191e1BbBAa085Bb892C6DA3D8BF54aB
        });
    }

    function _hashes() private pure returns (YieldBankPublicFactory.CreationCodeHashes memory h) {
        h = YieldBankPublicFactory.CreationCodeHashes({
            supportBundle: 0xc2c37bd172e81fabb7fe66186766bc8470f6e200bd275b90964283a99e4a373f,
            revenueRouter: 0xae36f59d924320e2aab8a30c8d0e0bf2a7bec70190289ee50ebf1cc9840b5feb,
            portfolioAllocator: 0x24f152b3ecfec362c8104627b094c3dbc9b9708c14c822d97e0b3e70f04235a4,
            collectionTimelock: 0xa702b5247962f215f2466228cbeed3b2ba1f705a8070d23c3bd89d15ec951874,
            coreSleeve: 0xb215f61ce447363b8c4d66a49802922f42d4c316a2c63af816ace0858a4d7933,
            marketMakingSleeve: 0xbe14391106b1a8e2925e85356642b57cfea1b41a345fa71b3c004bf3be2bb7a0,
            usdgSleeve: 0xe6bc3d2f723dab2621fcc7a6dc7789144317fa2c819ece4d26234553a2f6df4c,
            accountImplementation: 0x0217f95e69fdbb0ce3d3cc8c1d0fba4bb867d1a25160d7754651f4560945ad67,
            deltaPoolController: 0x7f1801e8e715eba37e8cbbef0d08170856f4e0f137df8c2d149243a7b9399319,
            collection: 0x24cb6ddbfff6bd3e4e7c2d6b66f58f37c50f79ace826a174a24c38e6674b66eb
        });
    }
}
