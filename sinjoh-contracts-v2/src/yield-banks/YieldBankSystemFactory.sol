// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { YieldBankConfig } from "./YieldBankTypes.sol";
import { YieldBankProtocolRegistry } from "./YieldBankProtocolRegistry.sol";
import { Create3V2 } from "../libraries/Create3V2.sol";

interface IYieldBankSystemComponents {
    function nft() external view returns (address);
    function distributor() external view returns (address);
    function proceedsVault() external view returns (address);
    function accountImplementation() external view returns (address);
}

/// @notice Version-pinned atomic deterministic deployer for one complete Yield Banks collection system.
/// @dev Collection components use CREATE3 so mutually bound immutable constructor arguments can be
///      planned from addresses that do not depend on their init code. The collection uses CREATE2
///      after all component addresses are fixed. Every init-code and runtime-code hash remains pinned.
contract YieldBankSystemFactory is ReentrancyGuard {
    struct ComponentDeployment {
        bytes32 kind;
        bytes32 salt;
        bytes initCode;
        bytes32 expectedRuntimeCodeHash;
    }

    bytes32 public constant KIND_OPERATIONS_RESERVE = keccak256("OPERATIONS_RESERVE");
    bytes32 public constant KIND_REVENUE_ROUTER = keccak256("REVENUE_ROUTER");
    bytes32 public constant KIND_PORTFOLIO_ALLOCATOR = keccak256("PORTFOLIO_ALLOCATOR");
    bytes32 public constant KIND_COLLECTION_TIMELOCK = keccak256("COLLECTION_TIMELOCK");
    bytes32 public constant KIND_CORE_SLEEVE = keccak256("CORE_SLEEVE");
    bytes32 public constant KIND_MARKET_MAKING_SLEEVE = keccak256("MARKET_MAKING_SLEEVE");
    bytes32 public constant KIND_USDG_SLEEVE = keccak256("USDG_SLEEVE");
    uint256 public constant COMPONENT_COUNT = 7;

    YieldBankProtocolRegistry public immutable registry;
    bytes32 public immutable factoryVersion;
    bytes32 public immutable collectionCreationCodeHash;
    bytes32 public immutable systemPlanHash;

    error InvalidConfiguration();
    error SystemPlanHashMismatch(bytes32 expected, bytes32 actual);
    error CreationCodeHashMismatch(bytes32 expected, bytes32 actual);
    error ComponentDeploymentFailed(bytes32 kind, bytes32 salt);
    error RuntimeCodeHashMismatch(bytes32 kind, bytes32 expected, bytes32 actual);
    error DuplicateComponentKind(bytes32 kind);

    event SystemComponentDeployed(
        bytes32 indexed kind,
        address indexed component,
        bytes32 indexed salt,
        bytes32 runtimeCodeHash
    );
    event YieldBankSystemDeployed(
        address indexed collection,
        bytes32 indexed collectionId,
        bytes32 indexed collectionSalt,
        bytes32 configurationHash,
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
        address operationsReserve,
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
        uint16 primaryBackingBps,
        uint16 primaryCreatorBps,
        uint16 primarySinjohBps,
        uint16 primaryOperationsBps,
        uint16 coreWeightBps,
        uint16 marketMakingWeightBps,
        uint16 usdgWeightBps
    );

    constructor(
        address registry_,
        bytes32 factoryVersion_,
        bytes32 collectionCreationCodeHash_,
        bytes32 systemPlanHash_
    ) {
        if (
            registry_.code.length == 0 || factoryVersion_ == bytes32(0)
                || collectionCreationCodeHash_ == bytes32(0) || systemPlanHash_ == bytes32(0)
        ) revert InvalidConfiguration();
        registry = YieldBankProtocolRegistry(registry_);
        factoryVersion = factoryVersion_;
        collectionCreationCodeHash = collectionCreationCodeHash_;
        systemPlanHash = systemPlanHash_;
    }

    function deploySystem(
        ComponentDeployment[] calldata components,
        bytes calldata collectionCreationCode,
        YieldBankConfig calldata config,
        bytes32 collectionSalt
    ) external nonReentrant returns (address collection) {
        if (components.length != COMPONENT_COUNT) {
            revert InvalidConfiguration();
        }
        bytes32 actualPlanHash = planHash(
            components,
            keccak256(collectionCreationCode),
            keccak256(abi.encode(config)),
            collectionSalt
        );
        if (actualPlanHash != systemPlanHash) {
            revert SystemPlanHashMismatch(systemPlanHash, actualPlanHash);
        }
        address[7] memory deployed;
        uint256 seen;
        for (uint256 i; i < COMPONENT_COUNT; ++i) {
            ComponentDeployment calldata component = components[i];
            uint256 bit = _kindBit(component.kind);
            if (seen & bit != 0) revert DuplicateComponentKind(component.kind);
            seen |= bit;
            bytes memory initCode = component.initCode;
            address instance = Create3V2.deploy(component.salt, initCode);
            bytes32 runtimeCodeHash = instance.codehash;
            if (runtimeCodeHash != component.expectedRuntimeCodeHash) {
                revert RuntimeCodeHashMismatch(
                    component.kind, component.expectedRuntimeCodeHash, runtimeCodeHash
                );
            }
            deployed[_kindIndex(component.kind)] = instance;
            emit SystemComponentDeployed(component.kind, instance, component.salt, runtimeCodeHash);
        }
        _validateDeployedConfig(config, deployed);
        bytes32 actualCollectionCodeHash = keccak256(collectionCreationCode);
        if (actualCollectionCodeHash != collectionCreationCodeHash) {
            revert CreationCodeHashMismatch(collectionCreationCodeHash, actualCollectionCodeHash);
        }
        bytes memory collectionInitCode =
            abi.encodePacked(collectionCreationCode, abi.encode(config));
        assembly ("memory-safe") {
            collection := create2(
                0,
                add(collectionInitCode, 0x20),
                mload(collectionInitCode),
                collectionSalt
            )
        }
        if (collection == address(0)) {
            revert ComponentDeploymentFailed(keccak256("COLLECTION"), collectionSalt);
        }
        bytes32 configurationHash = keccak256(abi.encode(config));
        registry.registerCollection(collection, configurationHash);
        emit YieldBankSystemDeployed(
            collection, config.collectionId, collectionSalt, configurationHash, factoryVersion
        );
        IYieldBankSystemComponents internals = IYieldBankSystemComponents(collection);
        emit CollectionComponentsRegistered(
            collection,
            config.collectionId,
            internals.nft(),
            internals.distributor(),
            internals.proceedsVault(),
            internals.accountImplementation(),
            config.revenueRouter,
            config.operationsReserve,
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
            config.primaryBackingBps,
            config.primaryCreatorBps,
            config.primarySinjohBps,
            config.primaryOperationsBps,
            config.coreWeightBps,
            config.marketMakingWeightBps,
            config.usdgWeightBps
        );
    }

    function planHash(
        ComponentDeployment[] calldata components,
        bytes32 collectionCodeHash,
        bytes32 configurationHash,
        bytes32 collectionSalt
    ) public pure returns (bytes32) {
        bytes32[] memory records = new bytes32[](components.length);
        for (uint256 i; i < components.length; ++i) {
            ComponentDeployment calldata component = components[i];
            records[i] = keccak256(
                abi.encode(
                    component.kind,
                    component.salt,
                    keccak256(component.initCode),
                    component.expectedRuntimeCodeHash
                )
            );
        }
        return keccak256(abi.encode(records, collectionCodeHash, configurationHash, collectionSalt));
    }

    function predictComponent(bytes32 salt) external view returns (address) {
        return Create3V2.predict(address(this), salt);
    }

    function predictCollection(
        bytes calldata collectionCreationCode,
        YieldBankConfig calldata config,
        bytes32 salt
    ) external view returns (address) {
        bytes32 actual = keccak256(collectionCreationCode);
        if (actual != collectionCreationCodeHash) {
            revert CreationCodeHashMismatch(collectionCreationCodeHash, actual);
        }
        return
            _predict(salt, keccak256(abi.encodePacked(collectionCreationCode, abi.encode(config))));
    }

    function _validateDeployedConfig(YieldBankConfig calldata config, address[7] memory deployed)
        private
        pure
    {
        if (
            config.operationsReserve != deployed[0] || config.revenueRouter != deployed[1]
                || config.portfolioAllocator != deployed[2]
                || config.collectionTimelock != deployed[3] || config.coreSleeve != deployed[4]
                || config.marketMakingSleeve != deployed[5] || config.usdgSleeve != deployed[6]
        ) revert InvalidConfiguration();
    }

    function _kindIndex(bytes32 kind) private pure returns (uint256) {
        if (kind == KIND_OPERATIONS_RESERVE) return 0;
        if (kind == KIND_REVENUE_ROUTER) return 1;
        if (kind == KIND_PORTFOLIO_ALLOCATOR) return 2;
        if (kind == KIND_COLLECTION_TIMELOCK) return 3;
        if (kind == KIND_CORE_SLEEVE) return 4;
        if (kind == KIND_MARKET_MAKING_SLEEVE) return 5;
        if (kind == KIND_USDG_SLEEVE) return 6;
        revert InvalidConfiguration();
    }

    function _kindBit(bytes32 kind) private pure returns (uint256) {
        return 2 ** _kindIndex(kind);
    }

    function _predict(bytes32 salt, bytes32 initCodeHash) private view returns (address) {
        return address(
            uint160(
                uint256(
                    keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, initCodeHash))
                )
            )
        );
    }
}
