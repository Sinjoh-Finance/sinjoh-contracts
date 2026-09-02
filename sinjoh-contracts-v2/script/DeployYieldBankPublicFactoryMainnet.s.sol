// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
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

/// @notice Deploys and registers the reusable Yield Banks public factory without deploying a
/// collection.
/// @dev This release script is intentionally locked to the verified Robinhood Chain mainnet
/// dependency graph. The expected broadcaster nonce and resulting factory address must be reviewed
/// immediately before broadcast, preventing an unnoticed intervening transaction from changing the
/// deployment address.
contract DeployYieldBankPublicFactoryMainnet is Script {
    uint256 private constant EXPECTED_CHAIN_ID = 4663;

    address private constant GOVERNANCE = 0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49;
    address private constant REGISTRY = 0x09e4542f9fEA13A00aAF400E81bDC10434af5278;
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

    bytes32 public constant FACTORY_VERSION = keccak256("SINJOH_YIELD_BANK_PUBLIC_FACTORY_V1_0_0");

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

        if (block.chainid != EXPECTED_CHAIN_ID) {
            revert WrongChain(EXPECTED_CHAIN_ID, block.chainid);
        }
        if (broadcaster != GOVERNANCE) revert WrongBroadcaster(GOVERNANCE, broadcaster);

        YieldBankProtocolRegistry registry = YieldBankProtocolRegistry(REGISTRY);
        _requireRuntimeCodeHash(REGISTRY, REGISTRY_RUNTIME_CODE_HASH);
        _requireRuntimeCodeHash(WETH, WETH_RUNTIME_CODE_HASH);
        _requireRuntimeCodeHash(USDG, USDG_RUNTIME_CODE_HASH);
        _requireRuntimeCodeHash(SEA_DROP, SEA_DROP_RUNTIME_CODE_HASH);
        if (registry.governance() != broadcaster) {
            revert WrongBroadcaster(registry.governance(), broadcaster);
        }

        uint64 actualNonce = vm.getNonce(broadcaster);
        if (actualNonce != expectedNonce) revert WrongNonce(expectedNonce, actualNonce);
        address predictedFactory = vm.computeCreateAddress(broadcaster, expectedNonce);
        if (predictedFactory != expectedFactory) {
            revert WrongAddress(expectedFactory, predictedFactory);
        }
        if (expectedFactory.code.length != 0) {
            revert RuntimeCodeHashMismatch(expectedFactory, bytes32(0), expectedFactory.codehash);
        }

        YieldBankPublicFactory.CreationCodeHashes memory hashes = _creationCodeHashes();

        vm.startBroadcast();
        factory =
            new YieldBankPublicFactory(REGISTRY, FACTORY_VERSION, WETH, USDG, SEA_DROP, hashes);
        registry.registerFactory(address(factory), FACTORY_VERSION, address(factory).codehash);
        vm.stopBroadcast();

        if (address(factory) != expectedFactory) {
            revert WrongAddress(expectedFactory, address(factory));
        }
        _verifyFactory(factory, registry, hashes);

        console2.log("YieldBankPublicFactory", address(factory));
        console2.logBytes32(FACTORY_VERSION);
        console2.logBytes32(address(factory).codehash);
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
        YieldBankProtocolRegistry registry,
        YieldBankPublicFactory.CreationCodeHashes memory expectedHashes
    ) private view {
        if (
            address(factory.registry()) != REGISTRY || factory.factoryVersion() != FACTORY_VERSION
                || factory.weth() != WETH || factory.usdg() != USDG || factory.seaDrop() != SEA_DROP
                || factory.wethRuntimeCodeHash() != WETH_RUNTIME_CODE_HASH
                || factory.usdgRuntimeCodeHash() != USDG_RUNTIME_CODE_HASH
                || factory.seaDropRuntimeCodeHash() != SEA_DROP_RUNTIME_CODE_HASH
                || keccak256(abi.encode(factory.creationCodeHashes()))
                    != keccak256(abi.encode(expectedHashes))
        ) revert FactoryConfigurationMismatch();

        (
            bytes32 registeredVersion,
            bytes32 registeredRuntimeCodeHash,
            bool registered,
            bool deprecated
        ) = registry.factories(address(factory));
        if (
            !registered || deprecated || registeredVersion != FACTORY_VERSION
                || registeredRuntimeCodeHash != address(factory).codehash
                || !registry.isFactoryAvailableForNewCollections(address(factory))
        ) revert FactoryRegistrationMismatch();
    }

    function _requireRuntimeCodeHash(address instance, bytes32 expected) private view {
        bytes32 actual = instance.codehash;
        if (actual != expected) revert RuntimeCodeHashMismatch(instance, expected, actual);
    }
}
