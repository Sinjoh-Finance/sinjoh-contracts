// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Create3V2 } from "../libraries/Create3V2.sol";
import { YieldBankProtocolRegistry } from "./YieldBankProtocolRegistry.sol";
import { YieldBankSystemFactory } from "./YieldBankSystemFactory.sol";

/// @notice Governance-only deterministic deployer for version-pinned Yield Banks system factories.
/// @dev CREATE3 makes the factory address depend only on this contract and `factorySalt`, breaking
///      the address-planning cycle between a factory and its immutable collection components.
contract YieldBankSystemFactoryDeployer {
    YieldBankProtocolRegistry public immutable registry;

    error OnlyGovernance(address caller);
    error InvalidConfiguration();
    error FactoryAddressMismatch(address expected, address actual);

    event YieldBankSystemFactoryDeployed(
        address indexed factory,
        bytes32 indexed factorySalt,
        bytes32 indexed factoryVersion,
        bytes32 collectionCreationCodeHash,
        bytes32 systemPlanHash,
        bytes32 runtimeCodeHash
    );

    constructor(address registry_) {
        if (registry_.code.length == 0) revert InvalidConfiguration();
        registry = YieldBankProtocolRegistry(registry_);
    }

    function deploy(
        bytes32 factorySalt,
        bytes32 factoryVersion,
        bytes32 collectionCreationCodeHash,
        bytes32 systemPlanHash
    ) external returns (address factory) {
        if (msg.sender != registry.governance()) {
            revert OnlyGovernance(msg.sender);
        }
        if (
            factorySalt == bytes32(0) || factoryVersion == bytes32(0)
                || collectionCreationCodeHash == bytes32(0) || systemPlanHash == bytes32(0)
        ) revert InvalidConfiguration();
        address predicted = predict(factorySalt);
        factory = Create3V2.deploy(
            factorySalt,
            abi.encodePacked(
                type(YieldBankSystemFactory).creationCode,
                abi.encode(
                    address(registry), factoryVersion, collectionCreationCodeHash, systemPlanHash
                )
            )
        );
        if (factory != predicted) revert FactoryAddressMismatch(predicted, factory);
        emit YieldBankSystemFactoryDeployed(
            factory,
            factorySalt,
            factoryVersion,
            collectionCreationCodeHash,
            systemPlanHash,
            factory.codehash
        );
    }

    function predict(bytes32 factorySalt) public view returns (address) {
        return Create3V2.predict(address(this), factorySalt);
    }
}
