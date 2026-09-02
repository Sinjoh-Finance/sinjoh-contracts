// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { CreationCodeStoreV2 } from "../core/CreationCodeStoreV2.sol";
import { Create3V2 } from "../libraries/Create3V2.sol";
import { YieldBankCollection } from "./YieldBankCollection.sol";
import { YieldBankConfigValidator } from "./YieldBankConfigValidator.sol";
import { YieldBankProtocolRegistry } from "./YieldBankProtocolRegistry.sol";
import { YieldBankSupportBundle } from "./YieldBankSupportBundle.sol";
import { YieldBankConfig, YieldBankFeeWeightRange } from "./YieldBankTypes.sol";

interface IYieldBankPublicCollectionInternals {
    function nft() external view returns (address);
    function distributor() external view returns (address);
    function proceedsVault() external view returns (address);
}

/// @notice One governance-approved factory release that any wallet can use to create a Yield Bank.
/// @dev Approved creation code is held in immutable, chunked bytecode stores. Collection creators
/// submit only structured configuration, avoiding oversized transactions without permitting callers
/// to substitute component behavior.
contract YieldBankPublicFactory is ReentrancyGuard {
    uint16 private constant BPS = 10_000;
    uint8 private constant MAX_STRATEGIES = 8;
    uint256 private constant MAX_FEE_WEIGHT_RANGES = 16;
    uint256 private constant MAX_TOTAL_FEE_WEIGHT = 1e27;

    bytes32 public constant KIND_SUPPORT_BUNDLE = keccak256("SUPPORT_BUNDLE");
    bytes32 public constant KIND_REVENUE_ROUTER = keccak256("REVENUE_ROUTER");
    bytes32 public constant KIND_PORTFOLIO_ALLOCATOR = keccak256("PORTFOLIO_ALLOCATOR");
    bytes32 public constant KIND_COLLECTION_TIMELOCK = keccak256("COLLECTION_TIMELOCK");
    bytes32 public constant KIND_CORE_SLEEVE = keccak256("CORE_SLEEVE");
    bytes32 public constant KIND_MARKET_MAKING_SLEEVE = keccak256("MARKET_MAKING_SLEEVE");
    bytes32 public constant KIND_USDG_SLEEVE = keccak256("USDG_SLEEVE");
    bytes32 public constant KIND_ACCOUNT_IMPLEMENTATION = keccak256("ACCOUNT_IMPLEMENTATION");
    bytes32 public constant KIND_DELTA_POOL_CONTROLLER = keccak256("DELTA_POOL_CONTROLLER");

    struct CreationCodeHashes {
        bytes32 supportBundle;
        bytes32 revenueRouter;
        bytes32 portfolioAllocator;
        bytes32 collectionTimelock;
        bytes32 coreSleeve;
        bytes32 marketMakingSleeve;
        bytes32 usdgSleeve;
        bytes32 accountImplementation;
        bytes32 deltaPoolController;
        bytes32 collection;
    }

    struct CreationCodeStores {
        address supportBundle;
        address revenueRouter;
        address portfolioAllocator;
        address collectionTimelock;
        address coreSleeve;
        address marketMakingSleeve;
        address usdgSleeve;
        address accountImplementation;
        address deltaPoolController;
        address collection;
    }

    struct SleeveConfig {
        uint8 maximumStrategies;
        uint16 maximumAdapterCapBps;
        uint16 maximumOperatorLossBps;
    }

    struct DeltaRiskConfig {
        uint16 maximumAdapterCapBps;
        uint16 maximumOperatorLossBps;
        uint32 maximumPoolFeedHeartbeat;
        uint32 maximumPoolFeedGracePeriod;
        uint32 minimumPoolTwapWindow;
        uint16 maximumPoolReferenceDeviationBps;
        uint16 maximumPoolSpotDeviationBps;
    }

    struct CollectionRequest {
        string name;
        string symbol;
        uint256 maxSupply;
        YieldBankFeeWeightRange[] feeWeightRanges;
        uint96 secondaryRoyaltyBps;
        uint16 primaryBackingBps;
        uint16 primaryCreatorBps;
        uint16 primarySinjohBps;
        uint16 exitTaxBps;
        uint16 royaltyBackingBps;
        uint16 royaltyCreatorBps;
        uint16 royaltySinjohBps;
        uint16 coreWeightBps;
        uint16 marketMakingWeightBps;
        uint16 usdgWeightBps;
        address creator;
        address openSeaManager;
        address sinjohFeeRecipient;
        address allocationOperator;
        address timelockProposer;
        uint48 timelockDelay;
        address guardian;
        address redemptionToken;
        uint256 redemptionTokenAmount;
        bytes32 redemptionTokenCodeHash;
        address eligibilityPolicy;
        bytes32 eligibilityPolicyCodeHash;
        SleeveConfig coreSleeve;
        SleeveConfig marketMakingSleeve;
        SleeveConfig usdgSleeve;
        DeltaRiskConfig deltaRisk;
    }

    struct SystemAddresses {
        address supportBundle;
        address revenueRouter;
        address portfolioAllocator;
        address collectionTimelock;
        address coreSleeve;
        address marketMakingSleeve;
        address usdgSleeve;
        address accountImplementation;
        address deltaPoolController;
        address collection;
    }

    YieldBankProtocolRegistry public immutable registry;
    bytes32 public immutable factoryVersion;
    address public immutable weth;
    address public immutable usdg;
    address public immutable seaDrop;
    bytes32 public immutable wethRuntimeCodeHash;
    bytes32 public immutable usdgRuntimeCodeHash;
    bytes32 public immutable seaDropRuntimeCodeHash;
    CreationCodeHashes private _creationCodeHashes;
    CreationCodeStores private _creationCodeStores;
    CreationCodeHashes private _creationCodeStoreRuntimeCodeHashes;
    mapping(bytes32 deploymentId => bool used) public deploymentUsed;

    error InvalidConfiguration();
    error CreationCodeStoreMismatch(address store, bytes32 expected, bytes32 actual);
    error DeploymentAlreadyUsed(bytes32 deploymentId);
    error AddressMismatch(address expected, address actual);

    event PublicSystemComponentDeployed(
        bytes32 indexed deploymentId,
        bytes32 indexed kind,
        address indexed component,
        bytes32 runtimeCodeHash
    );
    event PublicYieldBankCollectionDeployed(
        bytes32 indexed deploymentId,
        address indexed caller,
        address indexed collection,
        bytes32 collectionId,
        bytes32 configurationHash,
        bytes32 factoryVersion,
        address nft,
        address proceedsVault,
        address distributor
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
        address portfolioAllocator,
        address collectionTimelock,
        address seaDrop,
        uint256 maxSupply,
        address allocationOperator,
        address deltaPoolController,
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
        uint16 royaltyBackingBps,
        uint16 royaltyCreatorBps,
        uint16 royaltySinjohBps,
        uint16 exitTaxBps,
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
    event CollectionFeeWeightScheduleRegistered(
        address indexed collection,
        bytes32 indexed scheduleHash,
        uint256 maximumTotalFeeWeight,
        uint256 rangeCount
    );

    constructor(
        address registry_,
        bytes32 factoryVersion_,
        address weth_,
        address usdg_,
        address seaDrop_,
        CreationCodeStores memory creationCodeStores_,
        CreationCodeHashes memory creationCodeHashes_
    ) {
        if (
            registry_.code.length == 0 || factoryVersion_ == bytes32(0) || weth_.code.length == 0
                || usdg_.code.length == 0 || seaDrop_.code.length == 0
                || !_allStoresSet(creationCodeStores_) || !_allHashesSet(creationCodeHashes_)
        ) revert InvalidConfiguration();
        registry = YieldBankProtocolRegistry(registry_);
        factoryVersion = factoryVersion_;
        weth = weth_;
        usdg = usdg_;
        seaDrop = seaDrop_;
        wethRuntimeCodeHash = weth_.codehash;
        usdgRuntimeCodeHash = usdg_.codehash;
        seaDropRuntimeCodeHash = seaDrop_.codehash;
        _creationCodeStores = creationCodeStores_;
        _creationCodeHashes = creationCodeHashes_;
        _creationCodeStoreRuntimeCodeHashes = _pinStores(creationCodeStores_, creationCodeHashes_);
    }

    function creationCodeHashes() external view returns (CreationCodeHashes memory) {
        return _creationCodeHashes;
    }

    function creationCodeStores() external view returns (CreationCodeStores memory) {
        return _creationCodeStores;
    }

    function creationCodeStoreRuntimeCodeHashes()
        external
        view
        returns (CreationCodeHashes memory)
    {
        return _creationCodeStoreRuntimeCodeHashes;
    }

    function deploymentId(address caller, bytes32 userSalt) public view returns (bytes32) {
        return keccak256(abi.encode(address(this), caller, userSalt));
    }

    /// @notice Predicts the nine fixed component addresses for a caller salt.
    /// @dev The collection address also depends on the complete request and creation code, so it is
    ///      returned only by `createCollection` and remains zero in this component-only prediction.
    function predictComponentAddresses(address caller, bytes32 userSalt)
        public
        view
        returns (SystemAddresses memory a)
    {
        bytes32 id = deploymentId(caller, userSalt);
        a.supportBundle = _predictComponent(id, KIND_SUPPORT_BUNDLE);
        a.revenueRouter = _predictComponent(id, KIND_REVENUE_ROUTER);
        a.portfolioAllocator = _predictComponent(id, KIND_PORTFOLIO_ALLOCATOR);
        a.collectionTimelock = _predictComponent(id, KIND_COLLECTION_TIMELOCK);
        a.coreSleeve = _predictComponent(id, KIND_CORE_SLEEVE);
        a.marketMakingSleeve = _predictComponent(id, KIND_MARKET_MAKING_SLEEVE);
        a.usdgSleeve = _predictComponent(id, KIND_USDG_SLEEVE);
        a.accountImplementation = _predictComponent(id, KIND_ACCOUNT_IMPLEMENTATION);
        a.deltaPoolController = _predictComponent(id, KIND_DELTA_POOL_CONTROLLER);
    }

    function createCollection(CollectionRequest calldata request, bytes32 userSalt)
        external
        nonReentrant
        returns (SystemAddresses memory a)
    {
        _validateDependencies();
        _validateRequest(request);
        bytes32 id = deploymentId(msg.sender, userSalt);
        if (userSalt == bytes32(0)) revert InvalidConfiguration();
        if (deploymentUsed[id]) revert DeploymentAlreadyUsed(id);
        deploymentUsed[id] = true;
        a = predictComponentAddresses(msg.sender, userSalt);

        a.supportBundle = _deploy(
            id,
            KIND_SUPPORT_BUNDLE,
            abi.encodePacked(
                _loadCreationCode(
                    _creationCodeStores.supportBundle, _creationCodeHashes.supportBundle
                ),
                abi.encode(request.name, request.symbol, a.collectionTimelock, request.guardian)
            )
        );
        YieldBankSupportBundle support = YieldBankSupportBundle(a.supportBundle);
        address eligibilityPolicy = request.eligibilityPolicy == address(0)
            ? address(support.eligibilityPolicy())
            : request.eligibilityPolicy;
        bytes32 eligibilityPolicyCodeHash = request.eligibilityPolicy == address(0)
            ? eligibilityPolicy.codehash
            : request.eligibilityPolicyCodeHash;

        YieldBankConfig memory config =
            _buildConfig(id, a, support, eligibilityPolicy, eligibilityPolicyCodeHash, request);
        bytes memory collectionCreationCode =
            _loadCreationCode(_creationCodeStores.collection, _creationCodeHashes.collection);
        bytes32 collectionInitCodeHash =
            keccak256(abi.encodePacked(collectionCreationCode, abi.encode(config)));
        a.collection = _predictCollection(id, collectionInitCodeHash);
        config = _buildConfig(id, a, support, eligibilityPolicy, eligibilityPolicyCodeHash, request);

        a.collectionTimelock = _deploy(
            id,
            KIND_COLLECTION_TIMELOCK,
            abi.encodePacked(
                _loadCreationCode(
                    _creationCodeStores.collectionTimelock, _creationCodeHashes.collectionTimelock
                ),
                abi.encode(request.timelockProposer, request.timelockDelay)
            )
        );
        a.coreSleeve = _deploy(
            id,
            KIND_CORE_SLEEVE,
            abi.encodePacked(
                _loadCreationCode(_creationCodeStores.coreSleeve, _creationCodeHashes.coreSleeve),
                abi.encode(
                    string.concat(request.name, " Stock Token Sleeve"),
                    string.concat(request.symbol, "-STOCK"),
                    weth,
                    a.portfolioAllocator,
                    a.collectionTimelock,
                    request.guardian,
                    address(support.priceHub()),
                    address(support.strategyRegistry()),
                    eligibilityPolicy,
                    request.coreSleeve.maximumStrategies,
                    request.coreSleeve.maximumAdapterCapBps,
                    request.coreSleeve.maximumOperatorLossBps
                )
            )
        );
        a.marketMakingSleeve = _deploy(
            id,
            KIND_MARKET_MAKING_SLEEVE,
            abi.encodePacked(
                _loadCreationCode(
                    _creationCodeStores.marketMakingSleeve, _creationCodeHashes.marketMakingSleeve
                ),
                abi.encode(
                    string.concat(request.name, " Delta Liquidity Sleeve"),
                    string.concat(request.symbol, "-DELTA"),
                    weth,
                    a.portfolioAllocator,
                    a.collectionTimelock,
                    request.guardian,
                    address(support.priceHub()),
                    address(support.strategyRegistry()),
                    eligibilityPolicy,
                    request.marketMakingSleeve.maximumStrategies,
                    request.marketMakingSleeve.maximumAdapterCapBps,
                    request.marketMakingSleeve.maximumOperatorLossBps
                )
            )
        );
        a.usdgSleeve = _deploy(
            id,
            KIND_USDG_SLEEVE,
            abi.encodePacked(
                _loadCreationCode(_creationCodeStores.usdgSleeve, _creationCodeHashes.usdgSleeve),
                abi.encode(
                    string.concat(request.name, " USDG Sleeve"),
                    string.concat(request.symbol, "-USDG"),
                    usdg,
                    a.portfolioAllocator,
                    a.collectionTimelock,
                    request.guardian,
                    address(support.priceHub()),
                    address(support.strategyRegistry()),
                    eligibilityPolicy,
                    request.usdgSleeve.maximumStrategies,
                    request.usdgSleeve.maximumAdapterCapBps,
                    request.usdgSleeve.maximumOperatorLossBps
                )
            )
        );
        a.portfolioAllocator = _deploy(
            id,
            KIND_PORTFOLIO_ALLOCATOR,
            abi.encodePacked(
                _loadCreationCode(
                    _creationCodeStores.portfolioAllocator, _creationCodeHashes.portfolioAllocator
                ),
                abi.encode(
                    a.collection,
                    a.revenueRouter,
                    a.collectionTimelock,
                    request.guardian,
                    a.deltaPoolController,
                    a.coreSleeve,
                    a.marketMakingSleeve,
                    a.usdgSleeve,
                    request.coreWeightBps,
                    request.marketMakingWeightBps,
                    request.usdgWeightBps
                )
            )
        );
        a.deltaPoolController = _deploy(
            id,
            KIND_DELTA_POOL_CONTROLLER,
            abi.encodePacked(
                _loadCreationCode(
                    _creationCodeStores.deltaPoolController, _creationCodeHashes.deltaPoolController
                ),
                abi.encode(
                    a.portfolioAllocator,
                    a.collectionTimelock,
                    request.guardian,
                    weth,
                    address(support.priceHub()),
                    address(support.strategyRegistry()),
                    eligibilityPolicy,
                    request.deltaRisk.maximumAdapterCapBps,
                    request.deltaRisk.maximumOperatorLossBps,
                    request.deltaRisk.maximumPoolFeedHeartbeat,
                    request.deltaRisk.maximumPoolFeedGracePeriod,
                    request.deltaRisk.minimumPoolTwapWindow,
                    request.deltaRisk.maximumPoolReferenceDeviationBps,
                    request.deltaRisk.maximumPoolSpotDeviationBps,
                    string.concat(request.name, " Delta Liquidity Sleeve"),
                    string.concat(request.symbol, "-DELTA")
                )
            )
        );
        a.revenueRouter = _deploy(
            id,
            KIND_REVENUE_ROUTER,
            abi.encodePacked(
                _loadCreationCode(
                    _creationCodeStores.revenueRouter, _creationCodeHashes.revenueRouter
                ),
                abi.encode(
                    a.collection,
                    a.portfolioAllocator,
                    a.collectionTimelock,
                    request.creator,
                    request.sinjohFeeRecipient,
                    request.primaryBackingBps,
                    request.primaryCreatorBps,
                    request.primarySinjohBps,
                    request.royaltyBackingBps,
                    request.royaltyCreatorBps,
                    request.royaltySinjohBps
                )
            )
        );
        a.accountImplementation = _deploy(
            id,
            KIND_ACCOUNT_IMPLEMENTATION,
            _loadCreationCode(
                _creationCodeStores.accountImplementation, _creationCodeHashes.accountImplementation
            )
        );

        YieldBankConfigValidator.validatePinnedCreation(config);
        YieldBankConfigValidator.validateBindings(config, a.collection, a.deltaPoolController);
        a.collection = _deployCollection(id, collectionCreationCode, config, a.collection);
        bytes32 configurationHash = keccak256(abi.encode(config));
        registry.registerCollection(a.collection, configurationHash);
        IYieldBankPublicCollectionInternals internals =
            IYieldBankPublicCollectionInternals(a.collection);
        emit PublicYieldBankCollectionDeployed(
            id,
            msg.sender,
            a.collection,
            config.collectionId,
            configurationHash,
            factoryVersion,
            internals.nft(),
            internals.proceedsVault(),
            internals.distributor()
        );
        emit YieldBankSystemDeployed(
            a.collection, config.collectionId, id, configurationHash, factoryVersion
        );
        emit CollectionComponentsRegistered(
            a.collection,
            config.collectionId,
            internals.nft(),
            internals.distributor(),
            internals.proceedsVault(),
            a.accountImplementation,
            a.revenueRouter,
            a.portfolioAllocator,
            a.collectionTimelock,
            seaDrop,
            request.maxSupply,
            request.allocationOperator,
            a.deltaPoolController,
            a.coreSleeve,
            a.marketMakingSleeve,
            a.usdgSleeve
        );
        emit CollectionEconomicsRegistered(
            a.collection,
            request.secondaryRoyaltyBps,
            request.primaryBackingBps,
            request.primaryCreatorBps,
            request.primarySinjohBps,
            request.royaltyBackingBps,
            request.royaltyCreatorBps,
            request.royaltySinjohBps,
            request.exitTaxBps,
            request.coreWeightBps,
            request.marketMakingWeightBps,
            request.usdgWeightBps
        );
        emit CollectionRedemptionRequirementRegistered(
            a.collection,
            request.redemptionToken,
            request.redemptionTokenAmount,
            request.redemptionTokenCodeHash
        );
        emit CollectionFeeWeightScheduleRegistered(
            a.collection,
            keccak256(abi.encode(request.feeWeightRanges)),
            YieldBankCollection(a.collection).maximumTotalFeeWeight(),
            request.feeWeightRanges.length
        );
    }

    function _buildConfig(
        bytes32 id,
        SystemAddresses memory a,
        YieldBankSupportBundle support,
        address eligibilityPolicy,
        bytes32 eligibilityPolicyCodeHash,
        CollectionRequest calldata r
    ) private view returns (YieldBankConfig memory config) {
        config = YieldBankConfig({
            collectionId: id,
            maxSupply: r.maxSupply,
            feeWeightRanges: r.feeWeightRanges,
            secondaryRoyaltyBps: r.secondaryRoyaltyBps,
            primaryBackingBps: r.primaryBackingBps,
            primaryCreatorBps: r.primaryCreatorBps,
            primarySinjohBps: r.primarySinjohBps,
            royaltyBackingBps: r.royaltyBackingBps,
            royaltyCreatorBps: r.royaltyCreatorBps,
            royaltySinjohBps: r.royaltySinjohBps,
            exitTaxBps: r.exitTaxBps,
            coreWeightBps: r.coreWeightBps,
            marketMakingWeightBps: r.marketMakingWeightBps,
            usdgWeightBps: r.usdgWeightBps,
            creator: r.creator,
            openSeaManager: r.openSeaManager,
            sinjohFeeRecipient: r.sinjohFeeRecipient,
            redemptionToken: r.redemptionToken,
            redemptionTokenAmount: r.redemptionTokenAmount,
            redemptionTokenCodeHash: r.redemptionTokenCodeHash,
            revenueRouter: a.revenueRouter,
            eligibilityPolicy: eligibilityPolicy,
            portfolioAllocator: a.portfolioAllocator,
            allocationOperator: r.allocationOperator,
            collectionTimelock: a.collectionTimelock,
            guardian: r.guardian,
            metadata: address(support.metadata()),
            weth: weth,
            seaDrop: seaDrop,
            coreSleeve: a.coreSleeve,
            marketMakingSleeve: a.marketMakingSleeve,
            usdgSleeve: a.usdgSleeve,
            accountImplementation: a.accountImplementation,
            integrationCodeHashes: [
                bytes32(0),
                eligibilityPolicyCodeHash,
                bytes32(0),
                bytes32(0),
                address(support.metadata()).codehash,
                wethRuntimeCodeHash,
                seaDropRuntimeCodeHash,
                bytes32(0),
                bytes32(0),
                bytes32(0)
            ]
        });
    }

    function _deploy(bytes32 id, bytes32 kind, bytes memory initCode)
        private
        returns (address deployed)
    {
        deployed = Create3V2.deploy(_componentSalt(id, kind), initCode);
        emit PublicSystemComponentDeployed(id, kind, deployed, deployed.codehash);
    }

    function _deployCollection(
        bytes32 id,
        bytes memory creationCode,
        YieldBankConfig memory config,
        address expected
    ) private returns (address collection) {
        bytes memory initCode = abi.encodePacked(creationCode, abi.encode(config));
        bytes32 salt = id;
        assembly ("memory-safe") {
            collection := create2(0, add(initCode, 0x20), mload(initCode), salt)
        }
        if (collection == address(0) || collection != expected) {
            revert AddressMismatch(expected, collection);
        }
    }

    function _validateRequest(CollectionRequest calldata r) private view {
        if (
            bytes(r.name).length == 0 || bytes(r.name).length > 128 || bytes(r.symbol).length == 0
                || bytes(r.symbol).length > 32 || r.maxSupply == 0 || r.maxSupply > type(uint64).max
                || r.secondaryRoyaltyBps > BPS || r.creator == address(0)
                || r.openSeaManager == address(0) || r.sinjohFeeRecipient == address(0)
                || r.allocationOperator == address(0) || r.timelockProposer == address(0)
                || r.guardian == address(0) || r.primaryBackingBps == 0
                || uint256(r.primaryBackingBps) + r.primaryCreatorBps + r.primarySinjohBps != BPS
                || r.exitTaxBps > BPS || r.royaltyBackingBps == 0
                || uint256(r.royaltyBackingBps) + r.royaltyCreatorBps + r.royaltySinjohBps != BPS
                || uint256(r.coreWeightBps) + r.marketMakingWeightBps + r.usdgWeightBps != BPS
        ) revert InvalidConfiguration();
        _validateFeeWeightSchedule(r);
        bool noExternalPolicy =
            r.eligibilityPolicy == address(0) && r.eligibilityPolicyCodeHash == bytes32(0);
        bool validExternalPolicy = r.eligibilityPolicy.code.length != 0
            && r.eligibilityPolicy.codehash == r.eligibilityPolicyCodeHash;
        bool redemptionDisabled = r.redemptionToken == address(0) && r.redemptionTokenAmount == 0
            && r.redemptionTokenCodeHash == bytes32(0);
        bool redemptionEnabled = r.redemptionToken.code.length != 0 && r.redemptionTokenAmount != 0
            && r.redemptionToken.codehash == r.redemptionTokenCodeHash;
        if (
            (!noExternalPolicy && !validExternalPolicy)
                || (!redemptionDisabled && !redemptionEnabled) || !_validSleeveConfig(r.coreSleeve)
                || !_validSleeveConfig(r.marketMakingSleeve) || !_validSleeveConfig(r.usdgSleeve)
                || !_validDeltaRisk(r.deltaRisk)
        ) revert InvalidConfiguration();
    }

    function _validateFeeWeightSchedule(CollectionRequest calldata r) private pure {
        uint256 length = r.feeWeightRanges.length;
        if (length == 0) return;
        if (length > MAX_FEE_WEIGHT_RANGES) revert InvalidConfiguration();
        uint64 previousEnd;
        uint256 totalFeeWeight;
        for (uint256 i; i < length; ++i) {
            YieldBankFeeWeightRange calldata range = r.feeWeightRanges[i];
            if (range.endTokenId <= previousEnd || range.feeWeight == 0) {
                revert InvalidConfiguration();
            }
            totalFeeWeight += uint256(range.endTokenId - previousEnd) * range.feeWeight;
            previousEnd = range.endTokenId;
        }
        if (previousEnd != r.maxSupply || totalFeeWeight > MAX_TOTAL_FEE_WEIGHT) {
            revert InvalidConfiguration();
        }
    }

    function _validateDependencies() private view {
        if (
            weth.codehash != wethRuntimeCodeHash || usdg.codehash != usdgRuntimeCodeHash
                || seaDrop.codehash != seaDropRuntimeCodeHash
        ) revert InvalidConfiguration();
        _validateStores();
    }

    function _loadCreationCode(address store, bytes32 expected)
        private
        view
        returns (bytes memory creationCode)
    {
        creationCode = CreationCodeStoreV2(store).creationCode();
        bytes32 actual = keccak256(creationCode);
        if (actual != expected) revert CreationCodeStoreMismatch(store, expected, actual);
    }

    function _predictComponent(bytes32 id, bytes32 kind) private view returns (address) {
        return Create3V2.predict(address(this), _componentSalt(id, kind));
    }

    function _componentSalt(bytes32 id, bytes32 kind) private pure returns (bytes32) {
        return keccak256(abi.encode(id, kind));
    }

    function _predictCollection(bytes32 id, bytes32 initCodeHash) private view returns (address) {
        return address(
            uint160(
                uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), id, initCodeHash)))
            )
        );
    }

    function _pinStores(CreationCodeStores memory s, CreationCodeHashes memory h)
        private
        view
        returns (CreationCodeHashes memory runtimeHashes)
    {
        runtimeHashes.supportBundle = _pinStore(s.supportBundle, h.supportBundle);
        runtimeHashes.revenueRouter = _pinStore(s.revenueRouter, h.revenueRouter);
        runtimeHashes.portfolioAllocator = _pinStore(s.portfolioAllocator, h.portfolioAllocator);
        runtimeHashes.collectionTimelock = _pinStore(s.collectionTimelock, h.collectionTimelock);
        runtimeHashes.coreSleeve = _pinStore(s.coreSleeve, h.coreSleeve);
        runtimeHashes.marketMakingSleeve = _pinStore(s.marketMakingSleeve, h.marketMakingSleeve);
        runtimeHashes.usdgSleeve = _pinStore(s.usdgSleeve, h.usdgSleeve);
        runtimeHashes.accountImplementation =
            _pinStore(s.accountImplementation, h.accountImplementation);
        runtimeHashes.deltaPoolController = _pinStore(s.deltaPoolController, h.deltaPoolController);
        runtimeHashes.collection = _pinStore(s.collection, h.collection);
    }

    function _pinStore(address store, bytes32 expectedCreationCodeHash)
        private
        view
        returns (bytes32 runtimeCodeHash)
    {
        if (
            store.code.length == 0
                || CreationCodeStoreV2(store).creationCodeHash() != expectedCreationCodeHash
        ) revert InvalidConfiguration();
        runtimeCodeHash = store.codehash;
    }

    function _validateStores() private view {
        CreationCodeStores memory s = _creationCodeStores;
        CreationCodeHashes memory h = _creationCodeStoreRuntimeCodeHashes;
        if (
            s.supportBundle.codehash != h.supportBundle
                || s.revenueRouter.codehash != h.revenueRouter
                || s.portfolioAllocator.codehash != h.portfolioAllocator
                || s.collectionTimelock.codehash != h.collectionTimelock
                || s.coreSleeve.codehash != h.coreSleeve
                || s.marketMakingSleeve.codehash != h.marketMakingSleeve
                || s.usdgSleeve.codehash != h.usdgSleeve
                || s.accountImplementation.codehash != h.accountImplementation
                || s.deltaPoolController.codehash != h.deltaPoolController
                || s.collection.codehash != h.collection
        ) revert InvalidConfiguration();
    }

    function _allStoresSet(CreationCodeStores memory s) private pure returns (bool) {
        return s.supportBundle != address(0) && s.revenueRouter != address(0)
            && s.portfolioAllocator != address(0) && s.collectionTimelock != address(0)
            && s.coreSleeve != address(0) && s.marketMakingSleeve != address(0)
            && s.usdgSleeve != address(0) && s.accountImplementation != address(0)
            && s.deltaPoolController != address(0) && s.collection != address(0);
    }

    function _allHashesSet(CreationCodeHashes memory h) private pure returns (bool) {
        return h.supportBundle != bytes32(0) && h.revenueRouter != bytes32(0)
            && h.portfolioAllocator != bytes32(0) && h.collectionTimelock != bytes32(0)
            && h.coreSleeve != bytes32(0) && h.marketMakingSleeve != bytes32(0)
            && h.usdgSleeve != bytes32(0) && h.accountImplementation != bytes32(0)
            && h.deltaPoolController != bytes32(0) && h.collection != bytes32(0);
    }

    function _validSleeveConfig(SleeveConfig calldata config) private pure returns (bool) {
        return config.maximumStrategies <= MAX_STRATEGIES && config.maximumAdapterCapBps <= BPS
            && (config.maximumStrategies == 0 || config.maximumAdapterCapBps != 0)
            && config.maximumOperatorLossBps <= BPS;
    }

    function _validDeltaRisk(DeltaRiskConfig calldata config) private pure returns (bool) {
        return config.maximumAdapterCapBps != 0 && config.maximumAdapterCapBps <= BPS
            && config.maximumOperatorLossBps <= BPS && config.maximumPoolFeedHeartbeat != 0
            && config.minimumPoolTwapWindow != 0 && config.minimumPoolTwapWindow <= 1 days
            && config.maximumPoolReferenceDeviationBps != 0
            && config.maximumPoolReferenceDeviationBps <= BPS
            && config.maximumPoolSpotDeviationBps != 0
            && config.maximumPoolSpotDeviationBps <= 2_000;
    }
}
