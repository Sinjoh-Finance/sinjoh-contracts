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
import { YieldBankFeeWeightRange } from "../src/yield-banks/YieldBankTypes.sol";
import { CoreStockTokenSleeve } from "../src/yield-banks/sleeves/CoreStockTokenSleeve.sol";
import { MarketMakingSleeve } from "../src/yield-banks/sleeves/MarketMakingSleeve.sol";
import { USDGSleeve } from "../src/yield-banks/sleeves/USDGSleeve.sol";

/// @notice Deploys one explicitly configured disposable mainnet collection through the public
/// factory. This script is not the Piggy Banks collection release script.
contract DeployYieldBankTestCollectionMainnet is Script {
    uint256 private constant EXPECTED_CHAIN_ID = 4663;
    uint16 private constant BPS = 10_000;

    address private constant REGISTRY = 0x09e4542f9fEA13A00aAF400E81bDC10434af5278;

    error InvalidConfiguration();
    error WrongChain(uint256 expected, uint256 actual);
    error RuntimeCodeHashMismatch(address instance, bytes32 expected, bytes32 actual);
    error DeploymentVerificationFailed();

    function run() external returns (YieldBankPublicFactory.SystemAddresses memory deployed) {
        if (block.chainid != EXPECTED_CHAIN_ID) {
            revert WrongChain(EXPECTED_CHAIN_ID, block.chainid);
        }
        address publicFactory = vm.envAddress("TEST_PUBLIC_FACTORY");
        bytes32 publicFactoryRuntimeCodeHash =
            vm.envBytes32("TEST_PUBLIC_FACTORY_RUNTIME_CODE_HASH");
        if (publicFactory.codehash != publicFactoryRuntimeCodeHash) {
            revert RuntimeCodeHashMismatch(
                publicFactory, publicFactoryRuntimeCodeHash, publicFactory.codehash
            );
        }

        address owner = vm.envAddress("TEST_COLLECTION_OWNER");
        string memory name = vm.envString("TEST_COLLECTION_NAME");
        string memory symbol = vm.envString("TEST_COLLECTION_SYMBOL");
        uint256 maxSupply = vm.envUint("TEST_COLLECTION_MAX_SUPPLY");
        bytes32 userSalt = vm.envBytes32("TEST_COLLECTION_SALT");
        uint96 secondaryRoyaltyBps = _toUint96(vm.envUint("TEST_SECONDARY_ROYALTY_BPS"));
        uint16 primaryBackingBps = _toUint16(vm.envUint("TEST_PRIMARY_BACKING_BPS"));
        uint16 primaryCreatorBps = _toUint16(vm.envUint("TEST_PRIMARY_CREATOR_BPS"));
        uint16 primarySinjohBps = _toUint16(vm.envUint("TEST_PRIMARY_SINJOH_BPS"));
        uint16 exitTaxBps = _toUint16(vm.envUint("TEST_EXIT_TAX_BPS"));
        uint16 royaltyBackingBps = _toUint16(vm.envUint("TEST_ROYALTY_BACKING_BPS"));
        uint16 royaltyCreatorBps = _toUint16(vm.envUint("TEST_ROYALTY_CREATOR_BPS"));
        uint16 royaltySinjohBps = _toUint16(vm.envUint("TEST_ROYALTY_SINJOH_BPS"));
        uint16 coreWeightBps = _toUint16(vm.envUint("TEST_CORE_WEIGHT_BPS"));
        uint16 marketMakingWeightBps = _toUint16(vm.envUint("TEST_MARKET_MAKING_WEIGHT_BPS"));
        uint16 usdgWeightBps = _toUint16(vm.envUint("TEST_USDG_WEIGHT_BPS"));

        if (
            owner == address(0) || bytes(name).length == 0 || bytes(symbol).length == 0
                || maxSupply == 0 || userSalt == bytes32(0) || secondaryRoyaltyBps > BPS
                || uint256(primaryBackingBps) + primaryCreatorBps + primarySinjohBps != BPS
                || primaryBackingBps == 0 || exitTaxBps > BPS
                || uint256(royaltyBackingBps) + royaltyCreatorBps + royaltySinjohBps != BPS
                || royaltyBackingBps == 0
                || uint256(coreWeightBps) + marketMakingWeightBps + usdgWeightBps != BPS
        ) revert InvalidConfiguration();

        YieldBankPublicFactory factory = YieldBankPublicFactory(publicFactory);
        YieldBankPublicFactory.CollectionRequest memory request;
        request.name = name;
        request.symbol = symbol;
        request.maxSupply = maxSupply;
        request.feeWeightRanges = new YieldBankFeeWeightRange[](0);
        request.secondaryRoyaltyBps = secondaryRoyaltyBps;
        request.primaryBackingBps = primaryBackingBps;
        request.primaryCreatorBps = primaryCreatorBps;
        request.primarySinjohBps = primarySinjohBps;
        request.exitTaxBps = exitTaxBps;
        request.royaltyBackingBps = royaltyBackingBps;
        request.royaltyCreatorBps = royaltyCreatorBps;
        request.royaltySinjohBps = royaltySinjohBps;
        request.coreWeightBps = coreWeightBps;
        request.marketMakingWeightBps = marketMakingWeightBps;
        request.usdgWeightBps = usdgWeightBps;
        request.creator = owner;
        request.openSeaManager = owner;
        request.sinjohFeeRecipient = owner;
        request.allocationOperator = owner;
        request.timelockProposer = owner;
        request.timelockDelay = _toUint48(vm.envUint("TEST_TIMELOCK_DELAY"));
        request.guardian = owner;
        request.coreSleeve = YieldBankPublicFactory.SleeveConfig({
            maximumStrategies: 8, maximumAdapterCapBps: BPS, maximumOperatorLossBps: 0
        });
        request.marketMakingSleeve = YieldBankPublicFactory.SleeveConfig({
            maximumStrategies: 8, maximumAdapterCapBps: BPS, maximumOperatorLossBps: 0
        });
        request.usdgSleeve = YieldBankPublicFactory.SleeveConfig({
            maximumStrategies: 0, maximumAdapterCapBps: 0, maximumOperatorLossBps: 0
        });
        request.deltaRisk = YieldBankPublicFactory.DeltaRiskConfig({
            maximumAdapterCapBps: BPS,
            maximumOperatorLossBps: 0,
            maximumPoolFeedHeartbeat: 1 days,
            maximumPoolFeedGracePeriod: 1 days,
            minimumPoolTwapWindow: 5 minutes,
            maximumPoolReferenceDeviationBps: 1_000,
            maximumPoolSpotDeviationBps: 1_000
        });

        vm.startBroadcast();
        deployed = factory.createCollection(_creationCode(), request, userSalt);
        vm.stopBroadcast();

        YieldBankCollection collection = YieldBankCollection(deployed.collection);
        if (
            deployed.collection.code.length == 0
                || !YieldBankProtocolRegistry(REGISTRY).isActiveCollection(deployed.collection)
                || collection.creator() != owner || collection.nft().owner() != owner
                || collection.proceedsVault().allocationOperator() != owner
                || collection.maxSupply() != maxSupply
                || keccak256(bytes(collection.nft().name())) != keccak256(bytes(name))
                || keccak256(bytes(collection.nft().symbol())) != keccak256(bytes(symbol))
        ) revert DeploymentVerificationFailed();

        console2.log("Collection", deployed.collection);
        console2.log("NFT", address(collection.nft()));
        console2.log("ProceedsVault", address(collection.proceedsVault()));
        console2.log("Distributor", address(collection.distributor()));
        console2.log("RevenueRouter", deployed.revenueRouter);
        console2.log("PortfolioAllocator", deployed.portfolioAllocator);
        console2.log("CollectionTimelock", deployed.collectionTimelock);
        console2.log("DeltaPoolController", deployed.deltaPoolController);
        console2.log("CoreSleeve", deployed.coreSleeve);
        console2.log("MarketMakingSleeve", deployed.marketMakingSleeve);
        console2.log("USDGSleeve", deployed.usdgSleeve);
    }

    function _creationCode()
        private
        pure
        returns (YieldBankPublicFactory.CreationCode memory code)
    {
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

    function _toUint16(uint256 value) private pure returns (uint16 result) {
        if (value > type(uint16).max) revert InvalidConfiguration();
        result = uint16(value);
    }

    function _toUint96(uint256 value) private pure returns (uint96 result) {
        if (value > type(uint96).max) revert InvalidConfiguration();
        result = uint96(value);
    }

    function _toUint48(uint256 value) private pure returns (uint48 result) {
        if (value > type(uint48).max) revert InvalidConfiguration();
        result = uint48(value);
    }
}
