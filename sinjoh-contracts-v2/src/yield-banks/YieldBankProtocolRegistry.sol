// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

/// @notice Append-only provenance registry for Yield Banks factories, collections, and integrations.
/// @dev Deprecation affects discovery for new deployments only and never deletes history.
contract YieldBankProtocolRegistry {
    struct FactoryRecord {
        bytes32 version;
        bytes32 runtimeCodeHash;
        bool registered;
        bool deprecated;
    }

    struct CollectionRecord {
        address factory;
        bytes32 factoryVersion;
        bytes32 configurationHash;
        bytes32 runtimeCodeHash;
        uint48 registeredAt;
        bool registered;
    }

    struct IntegrationRecord {
        bytes32 kind;
        bytes32 version;
        bytes32 runtimeCodeHash;
        uint48 registeredAt;
        bool registered;
        bool deprecated;
    }

    address public immutable governance;
    mapping(address factory => FactoryRecord record) public factories;
    mapping(address collection => CollectionRecord record) public collections;
    mapping(address integration => IntegrationRecord record) public integrations;

    error OnlyGovernance(address caller);
    error InvalidAddress(address supplied);
    error AlreadyRegistered(address supplied);
    error FactoryUnavailable(address factory);
    error RuntimeCodeHashMismatch(address instance, bytes32 expected, bytes32 actual);

    event FactoryRegistered(
        address indexed factory, bytes32 indexed version, bytes32 runtimeCodeHash
    );
    event FactoryDeprecated(address indexed factory);
    event CollectionRegistered(
        address indexed collection,
        address indexed factory,
        bytes32 indexed factoryVersion,
        bytes32 configurationHash,
        bytes32 runtimeCodeHash
    );
    event IntegrationRegistered(
        address indexed integration,
        bytes32 indexed kind,
        bytes32 indexed version,
        bytes32 runtimeCodeHash
    );
    event IntegrationDeprecated(address indexed integration);

    modifier onlyGovernance() {
        if (msg.sender != governance) revert OnlyGovernance(msg.sender);
        _;
    }

    constructor(address governance_) {
        if (governance_ == address(0)) revert InvalidAddress(governance_);
        governance = governance_;
    }

    function registerFactory(address factory, bytes32 version, bytes32 expectedRuntimeCodeHash)
        external
        onlyGovernance
    {
        if (factory.code.length == 0 || version == bytes32(0)) revert InvalidAddress(factory);
        if (factories[factory].registered) revert AlreadyRegistered(factory);
        bytes32 actual = factory.codehash;
        if (actual != expectedRuntimeCodeHash) {
            revert RuntimeCodeHashMismatch(factory, expectedRuntimeCodeHash, actual);
        }
        factories[factory] = FactoryRecord(version, actual, true, false);
        emit FactoryRegistered(factory, version, actual);
    }

    function deprecateFactory(address factory) external onlyGovernance {
        FactoryRecord storage record = factories[factory];
        if (!record.registered) revert FactoryUnavailable(factory);
        record.deprecated = true;
        emit FactoryDeprecated(factory);
    }

    function registerCollection(address collection, bytes32 configurationHash) external {
        FactoryRecord memory factory = factories[msg.sender];
        if (!factory.registered || factory.deprecated) revert FactoryUnavailable(msg.sender);
        if (collection.code.length == 0) revert InvalidAddress(collection);
        if (collections[collection].registered) revert AlreadyRegistered(collection);
        bytes32 runtimeCodeHash = collection.codehash;
        collections[collection] = CollectionRecord({
            factory: msg.sender,
            factoryVersion: factory.version,
            configurationHash: configurationHash,
            runtimeCodeHash: runtimeCodeHash,
            registeredAt: uint48(block.timestamp),
            registered: true
        });
        emit CollectionRegistered(
            collection, msg.sender, factory.version, configurationHash, runtimeCodeHash
        );
    }

    function registerIntegration(address integration, bytes32 kind, bytes32 version)
        external
        onlyGovernance
    {
        if (integration.code.length == 0 || kind == bytes32(0) || version == bytes32(0)) {
            revert InvalidAddress(integration);
        }
        if (integrations[integration].registered) revert AlreadyRegistered(integration);
        bytes32 runtimeCodeHash = integration.codehash;
        integrations[integration] = IntegrationRecord({
            kind: kind,
            version: version,
            runtimeCodeHash: runtimeCodeHash,
            registeredAt: uint48(block.timestamp),
            registered: true,
            deprecated: false
        });
        emit IntegrationRegistered(integration, kind, version, runtimeCodeHash);
    }

    function deprecateIntegration(address integration) external onlyGovernance {
        IntegrationRecord storage record = integrations[integration];
        if (!record.registered) revert InvalidAddress(integration);
        record.deprecated = true;
        emit IntegrationDeprecated(integration);
    }

    function isActiveCollection(address collection) external view returns (bool) {
        return collections[collection].registered;
    }

    function isFactoryAvailableForNewCollections(address factory) external view returns (bool) {
        FactoryRecord memory record = factories[factory];
        return record.registered && !record.deprecated;
    }
}
