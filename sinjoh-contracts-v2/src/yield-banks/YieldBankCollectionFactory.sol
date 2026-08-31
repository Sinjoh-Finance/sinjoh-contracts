// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { YieldBankConfig } from "./YieldBankTypes.sol";
import { YieldBankProtocolRegistry } from "./YieldBankProtocolRegistry.sol";

interface IYieldBankDeployedComponents {
    function nft() external view returns (address);
    function distributor() external view returns (address);
    function proceedsVault() external view returns (address);
    function accountImplementation() external view returns (address);
}

/// @notice Version-pinned CREATE2 deployer for immutable Yield Banks collection systems.
/// @dev Creation code is supplied as calldata to keep this factory below the EIP-170 runtime limit.
contract YieldBankCollectionFactory is ReentrancyGuard {
    YieldBankProtocolRegistry public immutable registry;
    bytes32 public immutable factoryVersion;
    bytes32 public immutable collectionCreationCodeHash;

    error InvalidConfiguration();
    error CreationCodeHashMismatch(bytes32 expected, bytes32 actual);
    error DeploymentFailed(bytes32 salt);

    event CollectionDeployed(
        address indexed collection,
        bytes32 indexed salt,
        bytes32 indexed configurationHash,
        bytes32 factoryVersion
    );
    event CollectionComponentsRegistered(
        address indexed collection,
        bytes32 indexed collectionId,
        address indexed nft,
        address distributor,
        address proceedsVault,
        address accountImplementation,
        address revenueRouter,
        address portfolioAllocator,
        address collectionTimelock,
        address seaDrop,
        uint256 maxSupply,
        address allocationOperator,
        address coreSleeve,
        address marketMakingSleeve,
        address usdgSleeve
    );
    event CollectionEconomicsRegistered(
        address indexed collection,
        uint96 secondaryRoyaltyBps,
        uint16 primaryBackingBps,
        uint16 primaryCreatorBps,
        uint16 primarySinjohBps,
        uint16 coreWeightBps,
        uint16 marketMakingWeightBps,
        uint16 usdgWeightBps
    );
    event CollectionRedemptionRequirementRegistered(
        address indexed collection,
        address indexed redemptionToken,
        uint256 redemptionTokenAmount,
        bytes32 redemptionTokenCodeHash
    );

    constructor(address registry_, bytes32 factoryVersion_, bytes32 collectionCreationCodeHash_) {
        if (
            registry_.code.length == 0 || factoryVersion_ == bytes32(0)
                || collectionCreationCodeHash_ == bytes32(0)
        ) revert InvalidConfiguration();
        registry = YieldBankProtocolRegistry(registry_);
        factoryVersion = factoryVersion_;
        collectionCreationCodeHash = collectionCreationCodeHash_;
    }

    function deploy(
        bytes calldata collectionCreationCode,
        YieldBankConfig calldata config,
        bytes32 salt
    ) external nonReentrant returns (address collection) {
        bytes32 actualCreationCodeHash = keccak256(collectionCreationCode);
        if (actualCreationCodeHash != collectionCreationCodeHash) {
            revert CreationCodeHashMismatch(collectionCreationCodeHash, actualCreationCodeHash);
        }
        bytes memory initializationCode =
            abi.encodePacked(collectionCreationCode, abi.encode(config));
        assembly ("memory-safe") {
            collection := create2(0, add(initializationCode, 0x20), mload(initializationCode), salt)
        }
        if (collection == address(0)) revert DeploymentFailed(salt);
        bytes32 configurationHash = keccak256(abi.encode(config));
        registry.registerCollection(collection, configurationHash);
        emit CollectionDeployed(collection, salt, configurationHash, factoryVersion);
        IYieldBankDeployedComponents components = IYieldBankDeployedComponents(collection);
        emit CollectionComponentsRegistered(
            collection,
            config.collectionId,
            components.nft(),
            components.distributor(),
            components.proceedsVault(),
            components.accountImplementation(),
            config.revenueRouter,
            config.portfolioAllocator,
            config.collectionTimelock,
            config.seaDrop,
            config.maxSupply,
            config.allocationOperator,
            config.coreSleeve,
            config.marketMakingSleeve,
            config.usdgSleeve
        );
        emit CollectionEconomicsRegistered(
            collection,
            config.secondaryRoyaltyBps,
            config.primaryBackingBps,
            config.primaryCreatorBps,
            config.primarySinjohBps,
            config.coreWeightBps,
            config.marketMakingWeightBps,
            config.usdgWeightBps
        );
        emit CollectionRedemptionRequirementRegistered(
            collection,
            config.redemptionToken,
            config.redemptionTokenAmount,
            config.redemptionTokenCodeHash
        );
    }

    function predictAddress(
        bytes calldata collectionCreationCode,
        YieldBankConfig calldata config,
        bytes32 salt
    ) external view returns (address predicted) {
        bytes32 actualCreationCodeHash = keccak256(collectionCreationCode);
        if (actualCreationCodeHash != collectionCreationCodeHash) {
            revert CreationCodeHashMismatch(collectionCreationCodeHash, actualCreationCodeHash);
        }
        bytes32 initializationCodeHash =
            keccak256(abi.encodePacked(collectionCreationCode, abi.encode(config)));
        predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), address(this), salt, initializationCodeHash)
                    )
                )
            )
        );
    }
}
