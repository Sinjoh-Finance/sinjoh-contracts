// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { YieldBankCollection } from "../src/yield-banks/YieldBankCollection.sol";
import { YieldBankProtocolRegistry } from "../src/yield-banks/YieldBankProtocolRegistry.sol";
import { YieldBankPublicFactory } from "../src/yield-banks/YieldBankPublicFactory.sol";
import { YieldBankSupportBundle } from "../src/yield-banks/YieldBankSupportBundle.sol";
import { YieldBankFeeWeightRange } from "../src/yield-banks/YieldBankTypes.sol";

/// @notice Deploys one explicitly configured mainnet collection through an approved public factory.
/// @dev Every collection-specific address and economic term is supplied at runtime.
contract DeployYieldBankCollectionMainnet is Script {
    uint256 private constant EXPECTED_CHAIN_ID = 4663;
    uint16 private constant BPS = 10_000;

    error InvalidConfiguration();
    error WrongChain(uint256 expected, uint256 actual);
    error RuntimeCodeHashMismatch(address instance, bytes32 expected, bytes32 actual);
    error DeploymentVerificationFailed();

    function run() external returns (YieldBankPublicFactory.SystemAddresses memory deployed) {
        if (block.chainid != EXPECTED_CHAIN_ID) {
            revert WrongChain(EXPECTED_CHAIN_ID, block.chainid);
        }
        address publicFactory = vm.envAddress("YIELD_BANK_PUBLIC_FACTORY");
        address registry = vm.envAddress("YIELD_BANK_PROTOCOL_REGISTRY");
        bytes32 publicFactoryRuntimeCodeHash =
            vm.envBytes32("YIELD_BANK_PUBLIC_FACTORY_RUNTIME_CODE_HASH");
        if (publicFactory.codehash != publicFactoryRuntimeCodeHash) {
            revert RuntimeCodeHashMismatch(
                publicFactory, publicFactoryRuntimeCodeHash, publicFactory.codehash
            );
        }

        address creator = vm.envAddress("YIELD_BANK_COLLECTION_CREATOR");
        address openSeaManager = vm.envAddress("YIELD_BANK_COLLECTION_OPENSEA_MANAGER");
        address sinjohFeeRecipient = vm.envAddress("YIELD_BANK_COLLECTION_SINJOH_FEE_RECIPIENT");
        address allocationOperator = vm.envAddress("YIELD_BANK_COLLECTION_ALLOCATION_OPERATOR");
        address timelockProposer = vm.envAddress("YIELD_BANK_COLLECTION_TIMELOCK_PROPOSER");
        address guardian = vm.envAddress("YIELD_BANK_COLLECTION_GUARDIAN");
        string memory name = vm.envString("YIELD_BANK_COLLECTION_NAME");
        string memory symbol = vm.envString("YIELD_BANK_COLLECTION_SYMBOL");
        uint256 maxSupply = vm.envUint("YIELD_BANK_COLLECTION_MAX_SUPPLY");
        uint256[] memory feeWeightEnds = vm.envUint("YIELD_BANK_FEE_WEIGHT_ENDS", ",");
        uint256[] memory feeWeights = vm.envUint("YIELD_BANK_FEE_WEIGHTS", ",");
        bytes32 userSalt = vm.envBytes32("YIELD_BANK_COLLECTION_SALT");
        uint96 secondaryRoyaltyBps = _toUint96(vm.envUint("YIELD_BANK_SECONDARY_ROYALTY_BPS"));
        uint16 primaryBackingBps = _toUint16(vm.envUint("YIELD_BANK_PRIMARY_BACKING_BPS"));
        uint16 primaryCreatorBps = _toUint16(vm.envUint("YIELD_BANK_PRIMARY_CREATOR_BPS"));
        uint16 primarySinjohBps = _toUint16(vm.envUint("YIELD_BANK_PRIMARY_SINJOH_BPS"));
        uint16 exitTaxBps = _toUint16(vm.envUint("YIELD_BANK_EXIT_TAX_BPS"));
        uint16 royaltyBackingBps = _toUint16(vm.envUint("YIELD_BANK_ROYALTY_BACKING_BPS"));
        uint16 royaltyCreatorBps = _toUint16(vm.envUint("YIELD_BANK_ROYALTY_CREATOR_BPS"));
        uint16 royaltySinjohBps = _toUint16(vm.envUint("YIELD_BANK_ROYALTY_SINJOH_BPS"));
        uint16 coreWeightBps = _toUint16(vm.envUint("YIELD_BANK_CORE_WEIGHT_BPS"));
        uint16 marketMakingWeightBps = _toUint16(vm.envUint("YIELD_BANK_MARKET_MAKING_WEIGHT_BPS"));
        uint16 usdgWeightBps = _toUint16(vm.envUint("YIELD_BANK_USDG_WEIGHT_BPS"));
        address redemptionToken = vm.envAddress("YIELD_BANK_REDEMPTION_TOKEN");
        uint256 redemptionTokenAmount = vm.envUint("YIELD_BANK_REDEMPTION_TOKEN_AMOUNT");
        bytes32 redemptionTokenCodeHash =
            vm.envBytes32("YIELD_BANK_REDEMPTION_TOKEN_RUNTIME_CODE_HASH");
        address eligibilityPolicy = vm.envAddress("YIELD_BANK_ELIGIBILITY_POLICY");
        bytes32 eligibilityPolicyCodeHash =
            vm.envBytes32("YIELD_BANK_ELIGIBILITY_POLICY_RUNTIME_CODE_HASH");
        bool redemptionDisabled = redemptionToken == address(0);

        if (
            creator == address(0) || openSeaManager == address(0)
                || sinjohFeeRecipient == address(0) || allocationOperator == address(0)
                || timelockProposer == address(0) || guardian == address(0)
                || registry.code.length == 0 || bytes(name).length == 0 || bytes(symbol).length == 0
                || maxSupply == 0 || feeWeightEnds.length == 0
                || feeWeightEnds.length != feeWeights.length || feeWeightEnds.length > 4
                || userSalt == bytes32(0) || secondaryRoyaltyBps > BPS
                || uint256(primaryBackingBps) + primaryCreatorBps + primarySinjohBps != BPS
                || primaryBackingBps == 0 || exitTaxBps > BPS
                || uint256(royaltyBackingBps) + royaltyCreatorBps + royaltySinjohBps != BPS
                || royaltyBackingBps == 0
                || uint256(coreWeightBps) + marketMakingWeightBps + usdgWeightBps != BPS
                || (redemptionDisabled
                        ? redemptionTokenAmount != 0 || redemptionTokenCodeHash != bytes32(0)
                        : redemptionTokenAmount == 0
                        || redemptionToken.codehash != redemptionTokenCodeHash)
                || (eligibilityPolicy == address(0)
                        ? eligibilityPolicyCodeHash != bytes32(0)
                        : eligibilityPolicy.codehash != eligibilityPolicyCodeHash)
        ) revert InvalidConfiguration();

        YieldBankPublicFactory factory = YieldBankPublicFactory(publicFactory);
        YieldBankPublicFactory.CollectionRequest memory request;
        request.name = name;
        request.symbol = symbol;
        request.maxSupply = maxSupply;
        request.feeWeightRanges = new YieldBankFeeWeightRange[](feeWeightEnds.length);
        uint64 previousEnd;
        uint256 maximumTotalFeeWeight;
        for (uint256 i; i < feeWeightEnds.length; ++i) {
            uint64 endTokenId = _toUint64(feeWeightEnds[i]);
            uint96 feeWeight = _toUint96(feeWeights[i]);
            if (endTokenId <= previousEnd || feeWeight == 0) revert InvalidConfiguration();
            request.feeWeightRanges[i] =
                YieldBankFeeWeightRange({ endTokenId: endTokenId, feeWeight: feeWeight });
            maximumTotalFeeWeight += uint256(endTokenId - previousEnd) * feeWeight;
            previousEnd = endTokenId;
        }
        if (previousEnd != maxSupply) revert InvalidConfiguration();
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
        request.creator = creator;
        request.openSeaManager = openSeaManager;
        request.sinjohFeeRecipient = sinjohFeeRecipient;
        request.allocationOperator = allocationOperator;
        request.timelockProposer = timelockProposer;
        request.timelockDelay = _toUint48(vm.envUint("YIELD_BANK_TIMELOCK_DELAY"));
        request.guardian = guardian;
        request.redemptionToken = redemptionToken;
        request.redemptionTokenAmount = redemptionTokenAmount;
        request.redemptionTokenCodeHash = redemptionTokenCodeHash;
        request.eligibilityPolicy = eligibilityPolicy;
        request.eligibilityPolicyCodeHash = eligibilityPolicyCodeHash;
        request.coreSleeve = YieldBankPublicFactory.SleeveConfig({
            maximumStrategies: _toUint8(vm.envUint("YIELD_BANK_CORE_MAXIMUM_STRATEGIES")),
            maximumAdapterCapBps: _toUint16(vm.envUint("YIELD_BANK_CORE_MAXIMUM_ADAPTER_CAP_BPS")),
            maximumOperatorLossBps: _toUint16(
                vm.envUint("YIELD_BANK_CORE_MAXIMUM_OPERATOR_LOSS_BPS")
            )
        });
        request.marketMakingSleeve = YieldBankPublicFactory.SleeveConfig({
            maximumStrategies: _toUint8(vm.envUint("YIELD_BANK_DELTA_MAXIMUM_STRATEGIES")),
            maximumAdapterCapBps: _toUint16(vm.envUint("YIELD_BANK_DELTA_MAXIMUM_ADAPTER_CAP_BPS")),
            maximumOperatorLossBps: _toUint16(
                vm.envUint("YIELD_BANK_DELTA_MAXIMUM_OPERATOR_LOSS_BPS")
            )
        });
        request.usdgSleeve = YieldBankPublicFactory.SleeveConfig({
            maximumStrategies: _toUint8(vm.envUint("YIELD_BANK_USDG_MAXIMUM_STRATEGIES")),
            maximumAdapterCapBps: _toUint16(vm.envUint("YIELD_BANK_USDG_MAXIMUM_ADAPTER_CAP_BPS")),
            maximumOperatorLossBps: _toUint16(
                vm.envUint("YIELD_BANK_USDG_MAXIMUM_OPERATOR_LOSS_BPS")
            )
        });
        request.deltaRisk = YieldBankPublicFactory.DeltaRiskConfig({
            maximumAdapterCapBps: _toUint16(
                vm.envUint("YIELD_BANK_DELTA_RISK_MAXIMUM_ADAPTER_CAP_BPS")
            ),
            maximumOperatorLossBps: _toUint16(
                vm.envUint("YIELD_BANK_DELTA_RISK_MAXIMUM_OPERATOR_LOSS_BPS")
            ),
            maximumPoolFeedHeartbeat: _toUint32(
                vm.envUint("YIELD_BANK_DELTA_RISK_MAXIMUM_FEED_HEARTBEAT")
            ),
            maximumPoolFeedGracePeriod: _toUint32(
                vm.envUint("YIELD_BANK_DELTA_RISK_MAXIMUM_FEED_GRACE_PERIOD")
            ),
            minimumPoolTwapWindow: _toUint32(
                vm.envUint("YIELD_BANK_DELTA_RISK_MINIMUM_TWAP_WINDOW")
            ),
            maximumPoolReferenceDeviationBps: _toUint16(
                vm.envUint("YIELD_BANK_DELTA_RISK_MAXIMUM_REFERENCE_DEVIATION_BPS")
            ),
            maximumPoolSpotDeviationBps: _toUint16(
                vm.envUint("YIELD_BANK_DELTA_RISK_MAXIMUM_SPOT_DEVIATION_BPS")
            )
        });

        vm.startBroadcast();
        factory.beginCollection(request, userSalt);
        factory.deployCollectionSleeves(request, userSalt);
        factory.deployCollectionRouting(request, userSalt);
        deployed = factory.finalizeCollection(request, userSalt);
        vm.stopBroadcast();

        YieldBankCollection collection = YieldBankCollection(deployed.collection);
        address expectedEligibilityPolicy = eligibilityPolicy == address(0)
            ? address(YieldBankSupportBundle(deployed.supportBundle).eligibilityPolicy())
            : eligibilityPolicy;
        if (
            deployed.collection.code.length == 0
                || !YieldBankProtocolRegistry(registry).isActiveCollection(deployed.collection)
                || collection.creator() != creator || collection.nft().owner() != openSeaManager
                || collection.sinjohFeeRecipient() != sinjohFeeRecipient
                || collection.proceedsVault().allocationOperator() != allocationOperator
                || collection.guardian() != guardian || collection.maxSupply() != maxSupply
                || address(collection.redemptionToken()) != redemptionToken
                || collection.redemptionTokenAmount() != redemptionTokenAmount
                || collection.redemptionTokenCodeHash() != redemptionTokenCodeHash
                || address(collection.eligibilityPolicy()) != expectedEligibilityPolicy
                || collection.maximumTotalFeeWeight() != maximumTotalFeeWeight
                || collection.feeWeightRangeCount() != feeWeightEnds.length
                || keccak256(bytes(collection.nft().name())) != keccak256(bytes(name))
                || keccak256(bytes(collection.nft().symbol())) != keccak256(bytes(symbol))
        ) revert DeploymentVerificationFailed();
        for (uint256 i; i < feeWeightEnds.length; ++i) {
            (uint64 endTokenId, uint96 feeWeight) = collection.feeWeightRange(i);
            if (endTokenId != feeWeightEnds[i] || feeWeight != feeWeights[i]) {
                revert DeploymentVerificationFailed();
            }
        }

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

    function _toUint16(uint256 value) private pure returns (uint16 result) {
        if (value > type(uint16).max) revert InvalidConfiguration();
        result = uint16(value);
    }

    function _toUint8(uint256 value) private pure returns (uint8 result) {
        if (value > type(uint8).max) revert InvalidConfiguration();
        result = uint8(value);
    }

    function _toUint32(uint256 value) private pure returns (uint32 result) {
        if (value > type(uint32).max) revert InvalidConfiguration();
        result = uint32(value);
    }

    function _toUint96(uint256 value) private pure returns (uint96 result) {
        if (value > type(uint96).max) revert InvalidConfiguration();
        result = uint96(value);
    }

    function _toUint64(uint256 value) private pure returns (uint64 result) {
        if (value > type(uint64).max) revert InvalidConfiguration();
        result = uint64(value);
    }

    function _toUint48(uint256 value) private pure returns (uint48 result) {
        if (value > type(uint48).max) revert InvalidConfiguration();
        result = uint48(value);
    }
}
