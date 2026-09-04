// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { YieldBankConfig, YieldBankFeeWeightRange } from "./YieldBankTypes.sol";

interface IYieldBankConfiguredRevenueEconomics {
    function primaryBackingBps() external view returns (uint16);
    function primaryCreatorBps() external view returns (uint16);
    function primarySinjohBps() external view returns (uint16);
    function royaltyBackingBps() external view returns (uint16);
    function royaltyCreatorBps() external view returns (uint16);
    function royaltySinjohBps() external view returns (uint16);
}

interface IYieldBankConfiguredPortfolioEconomics {
    function coreWeightBps() external view returns (uint16);
    function marketMakingWeightBps() external view returns (uint16);
    function usdgWeightBps() external view returns (uint16);
}

interface IYieldBankConfiguredCollectionMetadata {
    function collectionName() external view returns (string memory);
    function collectionSymbol() external view returns (string memory);
}

interface IYieldBankConfiguredAllocatorBindings {
    function collection() external view returns (address);
    function revenueRouter() external view returns (address);
    function timelock() external view returns (address);
    function guardian() external view returns (address);
    function deltaPoolController() external view returns (address);
    function sleeves(uint256 index) external view returns (address);
}

interface IYieldBankConfiguredRevenueBindings {
    function collection() external view returns (address);
    function allocator() external view returns (address);
    function timelock() external view returns (address);
    function creatorRecipient() external view returns (address);
    function sinjohRecipient() external view returns (address);
}

interface IYieldBankConfiguredControllerBindings {
    function allocator() external view returns (address);
    function collection() external view returns (address);
    function timelock() external view returns (address);
    function guardian() external view returns (address);
    function eligibilityPolicy() external view returns (address);
}

interface IYieldBankConfiguredSleeveBindings {
    function allocator() external view returns (address);
    function timelock() external view returns (address);
    function guardian() external view returns (address);
    function eligibilityPolicy() external view returns (address);
}

/// @dev Factory-side validation keeps the collection's complete CREATE2 initialization code below
///      EIP-3860 while preserving the same checks at the registered protocol entry point.
library YieldBankConfigValidator {
    uint256 private constant BPS = 10_000;
    uint256 private constant MAX_FEE_WEIGHT_RANGES = 4;
    uint256 private constant MAX_TOTAL_FEE_WEIGHT = 1e27;

    error InvalidConfiguration();

    function validate(YieldBankConfig calldata c) internal view {
        bool redemptionDisabled = c.redemptionToken == address(0) && c.redemptionTokenAmount == 0
            && c.redemptionTokenCodeHash == bytes32(0);
        bool redemptionEnabled = c.redemptionToken.code.length != 0 && c.redemptionTokenAmount != 0
            && c.redemptionToken.codehash == c.redemptionTokenCodeHash;
        if (
            c.collectionId == bytes32(0) || c.maxSupply == 0 || c.maxSupply > type(uint64).max
                || c.secondaryRoyaltyBps > BPS || c.creator == address(0)
                || c.openSeaManager == address(0) || c.sinjohFeeRecipient == address(0)
                || c.revenueRouter.code.length == 0 || c.eligibilityPolicy.code.length == 0
                || c.portfolioAllocator.code.length == 0 || c.allocationOperator == address(0)
                || c.collectionTimelock.code.length == 0 || c.guardian == address(0)
                || c.metadata.code.length == 0 || c.weth.code.length == 0
                || c.seaDrop.code.length == 0 || c.coreSleeve.code.length == 0
                || c.marketMakingSleeve.code.length == 0 || c.usdgSleeve.code.length == 0
                || c.accountImplementation.code.length == 0 || c.coreSleeve == c.marketMakingSleeve
                || c.coreSleeve == c.usdgSleeve || c.marketMakingSleeve == c.usdgSleeve
                || c.primaryBackingBps == 0
                || uint256(c.primaryBackingBps) + c.primaryCreatorBps + c.primarySinjohBps != BPS
                || c.royaltyBackingBps == 0
                || uint256(c.royaltyBackingBps) + c.royaltyCreatorBps + c.royaltySinjohBps != BPS
                || c.exitTaxBps > BPS
                || uint256(c.coreWeightBps) + c.marketMakingWeightBps + c.usdgWeightBps != BPS
                || (!redemptionDisabled && !redemptionEnabled)
        ) revert InvalidConfiguration();

        _validateCollectionMetadata(c.metadata);
        _validateFeeWeightSchedule(c);
        bytes32[10] calldata h = c.integrationCodeHashes;
        if (
            c.revenueRouter.codehash != h[0] || c.eligibilityPolicy.codehash != h[1]
                || c.portfolioAllocator.codehash != h[2] || c.collectionTimelock.codehash != h[3]
                || c.metadata.codehash != h[4] || c.weth.codehash != h[5]
                || c.seaDrop.codehash != h[6] || c.coreSleeve.codehash != h[7]
                || c.marketMakingSleeve.codehash != h[8] || c.usdgSleeve.codehash != h[9]
        ) revert InvalidConfiguration();

        IYieldBankConfiguredRevenueEconomics revenue =
            IYieldBankConfiguredRevenueEconomics(c.revenueRouter);
        IYieldBankConfiguredPortfolioEconomics portfolio =
            IYieldBankConfiguredPortfolioEconomics(c.portfolioAllocator);
        if (
            revenue.primaryBackingBps() != c.primaryBackingBps
                || revenue.primaryCreatorBps() != c.primaryCreatorBps
                || revenue.primarySinjohBps() != c.primarySinjohBps
                || revenue.royaltyBackingBps() != c.royaltyBackingBps
                || revenue.royaltyCreatorBps() != c.royaltyCreatorBps
                || revenue.royaltySinjohBps() != c.royaltySinjohBps
                || portfolio.coreWeightBps() != c.coreWeightBps
                || portfolio.marketMakingWeightBps() != c.marketMakingWeightBps
                || portfolio.usdgWeightBps() != c.usdgWeightBps
        ) revert InvalidConfiguration();
    }

    /// @dev Validation mode for a factory that pins every internal component's creation code and
    ///      constructs those components itself. Internally deployed components use zero runtime
    ///      commitments because immutable constructor bindings make their runtime hashes depend on
    ///      the collection address, while the collection CREATE2 address depends on this config.
    ///      External dependencies remain runtime-hash pinned.
    function validatePinnedCreation(YieldBankConfig memory c) internal view {
        bool redemptionDisabled = c.redemptionToken == address(0) && c.redemptionTokenAmount == 0
            && c.redemptionTokenCodeHash == bytes32(0);
        bool redemptionEnabled = c.redemptionToken.code.length != 0 && c.redemptionTokenAmount != 0
            && c.redemptionToken.codehash == c.redemptionTokenCodeHash;
        if (
            c.collectionId == bytes32(0) || c.maxSupply == 0 || c.maxSupply > type(uint64).max
                || c.secondaryRoyaltyBps > BPS || c.creator == address(0)
                || c.openSeaManager == address(0) || c.sinjohFeeRecipient == address(0)
                || c.revenueRouter.code.length == 0 || c.eligibilityPolicy.code.length == 0
                || c.portfolioAllocator.code.length == 0 || c.allocationOperator == address(0)
                || c.collectionTimelock.code.length == 0 || c.guardian == address(0)
                || c.metadata.code.length == 0 || c.weth.code.length == 0
                || c.seaDrop.code.length == 0 || c.coreSleeve.code.length == 0
                || c.marketMakingSleeve.code.length == 0 || c.usdgSleeve.code.length == 0
                || c.accountImplementation.code.length == 0 || c.coreSleeve == c.marketMakingSleeve
                || c.coreSleeve == c.usdgSleeve || c.marketMakingSleeve == c.usdgSleeve
                || c.primaryBackingBps == 0
                || uint256(c.primaryBackingBps) + c.primaryCreatorBps + c.primarySinjohBps != BPS
                || c.royaltyBackingBps == 0
                || uint256(c.royaltyBackingBps) + c.royaltyCreatorBps + c.royaltySinjohBps != BPS
                || c.exitTaxBps > BPS
                || uint256(c.coreWeightBps) + c.marketMakingWeightBps + c.usdgWeightBps != BPS
                || (!redemptionDisabled && !redemptionEnabled)
        ) revert InvalidConfiguration();

        _validateCollectionMetadata(c.metadata);
        _validateFeeWeightScheduleMemory(c);
        bytes32[10] memory h = c.integrationCodeHashes;
        if (
            h[0] != bytes32(0) || c.eligibilityPolicy.codehash != h[1] || h[2] != bytes32(0)
                || h[3] != bytes32(0) || c.metadata.codehash != h[4] || c.weth.codehash != h[5]
                || c.seaDrop.codehash != h[6] || h[7] != bytes32(0) || h[8] != bytes32(0)
                || h[9] != bytes32(0)
        ) revert InvalidConfiguration();

        IYieldBankConfiguredRevenueEconomics revenue =
            IYieldBankConfiguredRevenueEconomics(c.revenueRouter);
        IYieldBankConfiguredPortfolioEconomics portfolio =
            IYieldBankConfiguredPortfolioEconomics(c.portfolioAllocator);
        if (
            revenue.primaryBackingBps() != c.primaryBackingBps
                || revenue.primaryCreatorBps() != c.primaryCreatorBps
                || revenue.primarySinjohBps() != c.primarySinjohBps
                || revenue.royaltyBackingBps() != c.royaltyBackingBps
                || revenue.royaltyCreatorBps() != c.royaltyCreatorBps
                || revenue.royaltySinjohBps() != c.royaltySinjohBps
                || portfolio.coreWeightBps() != c.coreWeightBps
                || portfolio.marketMakingWeightBps() != c.marketMakingWeightBps
                || portfolio.usdgWeightBps() != c.usdgWeightBps
        ) revert InvalidConfiguration();
    }

    /// @dev Proves that every mutable-flow component was constructed for this exact collection
    ///      system. Runtime hashes alone are insufficient because immutable constructor bindings
    ///      produce valid code with the wrong collection, allocator, timelock, or policy.
    function validateBindings(
        YieldBankConfig memory c,
        address expectedCollection,
        address expectedDeltaPoolController
    ) internal view {
        if (expectedCollection == address(0) || expectedDeltaPoolController.code.length == 0) {
            revert InvalidConfiguration();
        }
        IYieldBankConfiguredAllocatorBindings allocator =
            IYieldBankConfiguredAllocatorBindings(c.portfolioAllocator);
        IYieldBankConfiguredRevenueBindings revenue =
            IYieldBankConfiguredRevenueBindings(c.revenueRouter);
        IYieldBankConfiguredControllerBindings controller =
            IYieldBankConfiguredControllerBindings(expectedDeltaPoolController);
        if (
            allocator.collection() != expectedCollection
                || allocator.revenueRouter() != c.revenueRouter
                || allocator.timelock() != c.collectionTimelock
                || allocator.guardian() != c.guardian
                || allocator.deltaPoolController() != expectedDeltaPoolController
                || allocator.sleeves(0) != c.coreSleeve
                || allocator.sleeves(1) != c.marketMakingSleeve
                || allocator.sleeves(2) != c.usdgSleeve
                || revenue.collection() != expectedCollection
                || revenue.allocator() != c.portfolioAllocator
                || revenue.timelock() != c.collectionTimelock
                || revenue.creatorRecipient() != c.creator
                || revenue.sinjohRecipient() != c.sinjohFeeRecipient
                || controller.allocator() != c.portfolioAllocator
                || controller.collection() != expectedCollection
                || controller.timelock() != c.collectionTimelock
                || controller.guardian() != c.guardian
                || controller.eligibilityPolicy() != c.eligibilityPolicy
                || !_validSleeveBindings(c.coreSleeve, c)
                || !_validSleeveBindings(c.marketMakingSleeve, c)
                || !_validSleeveBindings(c.usdgSleeve, c)
        ) revert InvalidConfiguration();
    }

    function _validateFeeWeightSchedule(YieldBankConfig calldata c) private pure {
        uint256 length = c.feeWeightRanges.length;
        if (length == 0) return;
        if (length > MAX_FEE_WEIGHT_RANGES) revert InvalidConfiguration();
        uint64 previousEnd;
        uint256 totalFeeWeight;
        for (uint256 i; i < length; ++i) {
            YieldBankFeeWeightRange calldata range = c.feeWeightRanges[i];
            if (range.endTokenId <= previousEnd || range.feeWeight == 0) {
                revert InvalidConfiguration();
            }
            totalFeeWeight += uint256(range.endTokenId - previousEnd) * range.feeWeight;
            previousEnd = range.endTokenId;
        }
        if (previousEnd != c.maxSupply || totalFeeWeight > MAX_TOTAL_FEE_WEIGHT) {
            revert InvalidConfiguration();
        }
    }

    function _validateFeeWeightScheduleMemory(YieldBankConfig memory c) private pure {
        uint256 length = c.feeWeightRanges.length;
        if (length == 0) return;
        if (length > MAX_FEE_WEIGHT_RANGES) revert InvalidConfiguration();
        uint64 previousEnd;
        uint256 totalFeeWeight;
        for (uint256 i; i < length; ++i) {
            YieldBankFeeWeightRange memory range = c.feeWeightRanges[i];
            if (range.endTokenId <= previousEnd || range.feeWeight == 0) {
                revert InvalidConfiguration();
            }
            totalFeeWeight += uint256(range.endTokenId - previousEnd) * range.feeWeight;
            previousEnd = range.endTokenId;
        }
        if (previousEnd != c.maxSupply || totalFeeWeight > MAX_TOTAL_FEE_WEIGHT) {
            revert InvalidConfiguration();
        }
    }

    function _validateCollectionMetadata(address metadataAddress) private view {
        IYieldBankConfiguredCollectionMetadata metadata =
            IYieldBankConfiguredCollectionMetadata(metadataAddress);
        bytes memory name = bytes(metadata.collectionName());
        bytes memory symbol = bytes(metadata.collectionSymbol());
        if (name.length == 0 || name.length > 128 || symbol.length == 0 || symbol.length > 32) {
            revert InvalidConfiguration();
        }
    }

    function _validSleeveBindings(address sleeve, YieldBankConfig memory c)
        private
        view
        returns (bool)
    {
        IYieldBankConfiguredSleeveBindings bindings = IYieldBankConfiguredSleeveBindings(sleeve);
        return bindings.allocator() == c.portfolioAllocator
            && bindings.timelock() == c.collectionTimelock && bindings.guardian() == c.guardian
            && bindings.eligibilityPolicy() == c.eligibilityPolicy;
    }
}
