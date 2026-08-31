// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IPriceHub } from "./interfaces/IPriceHub.sol";
import {
    IYieldBankV3Factory,
    IYieldBankV3Pool,
    IYieldBankV3PositionManager
} from "./interfaces/IYieldBankV3.sol";
import { IDeltaPositionBuilder } from "./interfaces/IDeltaPositionBuilder.sol";
import { IntegrationBinding } from "./libraries/IntegrationBinding.sol";
import { YieldBankIds } from "./libraries/YieldBankIds.sol";
import { PriceHub } from "./PriceHub.sol";
import { StrategyRegistry } from "./StrategyRegistry.sol";
import { YieldBankAdapterState } from "./YieldBankTypes.sol";

interface IDeltaPoolAllocationOperatorSource {
    function allocationOperator() external view returns (address);
    function collection() external view returns (address);
}

interface IDeltaPoolCollectionRegistrar {
    function registerDynamicSleeve(address sleeve) external;
}

interface IDeltaPoolSleeve {
    function category() external view returns (bytes32);
    function accountingAsset() external view returns (address);
    function allocator() external view returns (address);
    function timelock() external view returns (address);
    function guardian() external view returns (address);
    function priceHub() external view returns (address);
    function strategyRegistry() external view returns (address);
    function eligibilityPolicy() external view returns (address);
    function maximumStrategies() external view returns (uint8);
    function maximumAdapterCapBps() external view returns (uint16);
    function adapterState(address adapter) external view returns (YieldBankAdapterState);
    function addAdapter(address adapter, uint16 capBps) external;
    function setAdapterCap(address adapter, uint16 capBps) external;
    function retireAdapter(address adapter) external;
    function setDepositsPaused(bool paused) external;
}

interface IDeltaPoolAdapterIdentity {
    function sleeve() external view returns (address);
    function accountingAsset() external view returns (address);
    function weth() external view returns (address);
    function pairedAsset() external view returns (address);
    function priceHub() external view returns (address);
    function pool() external view returns (address);
    function factory() external view returns (address);
    function positionManager() external view returns (address);
    function positionBuilder() external view returns (address);
}

interface IDeltaPoolDerivedFeed {
    function pairedAsset() external view returns (address);
    function weth() external view returns (address);
    function pool() external view returns (address);
    function factory() external view returns (address);
    function preparePoolOracle() external;
}

/// @notice Collection-scoped controller for source-verified Delta infrastructure and dynamic pools.
/// @dev Governance approves infrastructure generations. The current allocation operator may then
///      materialize any compatible canonical pool without a pool-specific manifest or governance
///      transaction. Investment execution remains separately operator-gated in the allocator.
contract DeltaPoolController is ReentrancyGuard {
    struct Infrastructure {
        address positionManager;
        address positionBuilder;
        bytes32 factoryRuntimeCodeHash;
        bytes32 positionManagerRuntimeCodeHash;
        bytes32 positionBuilderRuntimeCodeHash;
        bytes32 routeCreationCodeHash;
        bytes32 sleeveCreationCodeHash;
        bytes32 adapterCreationCodeHash;
        bytes32 feedCreationCodeHash;
        bool active;
    }

    struct InfrastructureConfig {
        address positionManager;
        address positionBuilder;
        bytes32 factoryRuntimeCodeHash;
        bytes32 positionManagerRuntimeCodeHash;
        bytes32 positionBuilderRuntimeCodeHash;
        bytes32 routeCreationCodeHash;
        bytes32 sleeveCreationCodeHash;
        bytes32 adapterCreationCodeHash;
        bytes32 feedCreationCodeHash;
    }

    struct MaterializationConfig {
        uint8 maximumPositions;
        uint16 adapterCapBps;
        uint16 maximumOperatorLossBps;
    }

    struct PoolFeedConfig {
        address referenceSource;
        uint32 heartbeat;
        uint32 gracePeriod;
        uint32 twapWindow;
        uint16 maxDeviationBps;
        uint16 maxSpotDeviationBps;
        uint128 comparisonAmount;
        uint128 minimumLiquidity;
        string description;
    }

    struct AdapterDeploymentConfig {
        address sleeve;
        address weth;
        address pairedAsset;
        address priceHub;
        address pool;
        address positionManager;
        address positionBuilder;
        address entryRoute;
        address exitRoute;
        bytes32 poolCodeHash;
        bytes32 factoryCodeHash;
        bytes32 positionManagerCodeHash;
        bytes32 positionBuilderCodeHash;
        bytes32 entryRouteCodeHash;
        bytes32 exitRouteCodeHash;
        uint8 maximumPositions;
    }

    struct PoolFoundation {
        address sleeve;
        address adapter;
        bytes32 poolRuntimeCodeHash;
        bytes32 sleeveRuntimeCodeHash;
        bytes32 adapterRuntimeCodeHash;
    }

    address public immutable allocator;
    address public immutable collection;
    address public immutable timelock;
    address public immutable guardian;
    address public immutable weth;
    address public immutable eligibilityPolicy;
    uint16 public immutable maximumAdapterCapBps;
    uint16 public immutable maximumOperatorLossBps;
    uint32 public immutable maximumPoolFeedHeartbeat;
    uint32 public immutable maximumPoolFeedGracePeriod;
    uint32 public immutable minimumPoolTwapWindow;
    uint16 public immutable maximumPoolReferenceDeviationBps;
    uint16 public immutable maximumPoolSpotDeviationBps;
    PriceHub public immutable priceHub;
    StrategyRegistry public immutable strategyRegistry;

    mapping(address factory => Infrastructure infrastructure) public infrastructureOfFactory;
    mapping(address pool => PoolFoundation foundation) public foundationOf;
    mapping(address sleeve => address pool) public poolOfSleeve;
    mapping(address pool => bytes32 commitment) public foundationInfrastructureCommitment;

    error OnlyTimelock(address caller);
    error OnlyAllocationOperator(address caller);
    error InvalidConfiguration();
    error InfrastructureUnavailable(address factory);
    error PoolUnavailable(address pool);
    error PoolAlreadyMaterialized(address pool);
    error FeedAlreadyConfigured(address asset);
    error DeploymentFailed(bytes32 creationCodeHash);

    event InfrastructureConfigured(
        address indexed factory,
        address indexed positionManager,
        address indexed positionBuilder,
        bytes32 factoryRuntimeCodeHash,
        bytes32 positionManagerRuntimeCodeHash,
        bytes32 positionBuilderRuntimeCodeHash,
        bytes32 routeCreationCodeHash,
        bytes32 sleeveCreationCodeHash,
        bytes32 adapterCreationCodeHash,
        bytes32 feedCreationCodeHash
    );
    event InfrastructureActiveSet(address indexed factory, bool active);
    event PoolFeedConfigured(address indexed pool, address indexed asset, address indexed feed);
    event PoolMaterialized(
        address indexed pool,
        address indexed sleeve,
        address indexed adapter,
        address factory,
        address pairedAsset,
        bytes32 poolRuntimeCodeHash,
        bytes32 sleeveRuntimeCodeHash,
        bytes32 adapterRuntimeCodeHash
    );

    constructor(
        address allocator_,
        address timelock_,
        address guardian_,
        address weth_,
        address priceHub_,
        address strategyRegistry_,
        address eligibilityPolicy_,
        uint16 maximumAdapterCapBps_,
        uint16 maximumOperatorLossBps_,
        uint32 maximumPoolFeedHeartbeat_,
        uint32 maximumPoolFeedGracePeriod_,
        uint32 minimumPoolTwapWindow_,
        uint16 maximumPoolReferenceDeviationBps_,
        uint16 maximumPoolSpotDeviationBps_
    ) {
        if (
            allocator_ == address(0) || timelock_ == address(0) || guardian_ == address(0)
                || weth_.code.length == 0 || priceHub_.code.length == 0
                || strategyRegistry_.code.length == 0 || eligibilityPolicy_.code.length == 0
                || maximumAdapterCapBps_ == 0 || maximumAdapterCapBps_ > 10_000
                || maximumOperatorLossBps_ > 10_000 || maximumPoolFeedHeartbeat_ == 0
                || minimumPoolTwapWindow_ == 0 || minimumPoolTwapWindow_ > 1 days
                || maximumPoolReferenceDeviationBps_ == 0
                || maximumPoolReferenceDeviationBps_ > 10_000 || maximumPoolSpotDeviationBps_ == 0
                || maximumPoolSpotDeviationBps_ > 2_000
        ) revert InvalidConfiguration();
        allocator = allocator_;
        collection = IDeltaPoolAllocationOperatorSource(allocator_).collection();
        if (collection == address(0)) revert InvalidConfiguration();
        timelock = timelock_;
        guardian = guardian_;
        weth = weth_;
        priceHub = PriceHub(priceHub_);
        strategyRegistry = StrategyRegistry(strategyRegistry_);
        eligibilityPolicy = eligibilityPolicy_;
        maximumAdapterCapBps = maximumAdapterCapBps_;
        maximumOperatorLossBps = maximumOperatorLossBps_;
        maximumPoolFeedHeartbeat = maximumPoolFeedHeartbeat_;
        maximumPoolFeedGracePeriod = maximumPoolFeedGracePeriod_;
        minimumPoolTwapWindow = minimumPoolTwapWindow_;
        maximumPoolReferenceDeviationBps = maximumPoolReferenceDeviationBps_;
        maximumPoolSpotDeviationBps = maximumPoolSpotDeviationBps_;
    }

    modifier onlyTimelock() {
        if (msg.sender != timelock) revert OnlyTimelock(msg.sender);
        _;
    }

    modifier onlyAllocationOperator() {
        address operator = allocationOperator();
        if (msg.sender != operator) revert OnlyAllocationOperator(msg.sender);
        _;
    }

    function allocationOperator() public view returns (address) {
        return IDeltaPoolAllocationOperatorSource(allocator).allocationOperator();
    }

    function configureInfrastructure(address factory, InfrastructureConfig calldata config)
        external
        onlyTimelock
        nonReentrant
    {
        if (
            factory.code.length == 0 || config.positionManager.code.length == 0
                || config.positionBuilder.code.length == 0
                || config.factoryRuntimeCodeHash == bytes32(0)
                || config.positionManagerRuntimeCodeHash == bytes32(0)
                || config.positionBuilderRuntimeCodeHash == bytes32(0)
                || config.routeCreationCodeHash == bytes32(0)
                || config.sleeveCreationCodeHash == bytes32(0)
                || config.adapterCreationCodeHash == bytes32(0)
                || config.feedCreationCodeHash == bytes32(0)
        ) revert InvalidConfiguration();
        IntegrationBinding.requireBound(factory, config.factoryRuntimeCodeHash);
        IntegrationBinding.requireBound(
            config.positionManager, config.positionManagerRuntimeCodeHash
        );
        IntegrationBinding.requireBound(
            config.positionBuilder, config.positionBuilderRuntimeCodeHash
        );
        if (
            IYieldBankV3PositionManager(config.positionManager).factory() != factory
                || IYieldBankV3PositionManager(config.positionManager).WETH9() != weth
                || IDeltaPositionBuilder(config.positionBuilder).uniFactory() != factory
                || IDeltaPositionBuilder(config.positionBuilder).positionManager()
                    != config.positionManager
                || IDeltaPositionBuilder(config.positionBuilder).weth() != weth
        ) revert InvalidConfiguration();

        infrastructureOfFactory[factory] = Infrastructure({
            positionManager: config.positionManager,
            positionBuilder: config.positionBuilder,
            factoryRuntimeCodeHash: config.factoryRuntimeCodeHash,
            positionManagerRuntimeCodeHash: config.positionManagerRuntimeCodeHash,
            positionBuilderRuntimeCodeHash: config.positionBuilderRuntimeCodeHash,
            routeCreationCodeHash: config.routeCreationCodeHash,
            sleeveCreationCodeHash: config.sleeveCreationCodeHash,
            adapterCreationCodeHash: config.adapterCreationCodeHash,
            feedCreationCodeHash: config.feedCreationCodeHash,
            active: true
        });
        emit InfrastructureConfigured(
            factory,
            config.positionManager,
            config.positionBuilder,
            config.factoryRuntimeCodeHash,
            config.positionManagerRuntimeCodeHash,
            config.positionBuilderRuntimeCodeHash,
            config.routeCreationCodeHash,
            config.sleeveCreationCodeHash,
            config.adapterCreationCodeHash,
            config.feedCreationCodeHash
        );
        emit InfrastructureActiveSet(factory, true);
    }

    function setInfrastructureActive(address factory, bool active) external onlyTimelock {
        Infrastructure storage infrastructure = infrastructureOfFactory[factory];
        if (infrastructure.positionManager == address(0)) {
            revert InfrastructureUnavailable(factory);
        }
        infrastructure.active = active;
        emit InfrastructureActiveSet(factory, active);
    }

    function isSelectablePool(address pool) public view returns (bool) {
        if (pool.code.length == 0) return false;
        (bool ok, uint256 rawFactory) =
            _readWord(pool, abi.encodeCall(IYieldBankV3Pool.factory, ()));
        if (!ok || rawFactory > type(uint160).max) return false;
        // The range check above proves this conversion is exact.
        // forge-lint: disable-next-line(unsafe-typecast)
        address factory = address(uint160(rawFactory));
        Infrastructure memory infrastructure = infrastructureOfFactory[factory];
        if (!infrastructure.active) return false;
        if (
            factory.codehash != infrastructure.factoryRuntimeCodeHash
                || infrastructure.positionManager.codehash
                    != infrastructure.positionManagerRuntimeCodeHash
                || infrastructure.positionBuilder.codehash
                    != infrastructure.positionBuilderRuntimeCodeHash
        ) return false;

        uint256 rawToken0;
        uint256 rawToken1;
        uint256 rawFee;
        (ok, rawToken0) = _readWord(pool, abi.encodeCall(IYieldBankV3Pool.token0, ()));
        if (!ok || rawToken0 > type(uint160).max) return false;
        (ok, rawToken1) = _readWord(pool, abi.encodeCall(IYieldBankV3Pool.token1, ()));
        if (!ok || rawToken1 > type(uint160).max) return false;
        (ok, rawFee) = _readWord(pool, abi.encodeCall(IYieldBankV3Pool.fee, ()));
        if (!ok || rawFee > type(uint24).max) return false;
        // The range checks above prove both conversions are exact.
        // forge-lint: disable-next-line(unsafe-typecast)
        address token0 = address(uint160(rawToken0));
        // forge-lint: disable-next-line(unsafe-typecast)
        address token1 = address(uint160(rawToken1));
        if (!((token0 == weth && token1.code.length != 0)
                    || (token1 == weth && token0.code.length != 0))) return false;

        uint256 rawCanonicalPool;
        // The range check above proves this conversion is exact.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint24 fee = uint24(rawFee);
        (ok, rawCanonicalPool) = _readWord(
            factory, abi.encodeCall(IYieldBankV3Factory.getPool, (token0, token1, fee))
        );
        if (!ok || rawCanonicalPool != uint256(uint160(pool))) return false;

        (bool slotOk, bytes memory slotData) =
            pool.staticcall(abi.encodeCall(IYieldBankV3Pool.slot0, ()));
        if (!slotOk || slotData.length < 224) return false;
        uint256 rawSqrtPriceX96;
        uint256 rawUnlocked;
        assembly ("memory-safe") {
            rawSqrtPriceX96 := mload(add(slotData, 0x20))
            rawUnlocked := mload(add(slotData, 0xe0))
        }
        if (rawSqrtPriceX96 == 0 || rawSqrtPriceX96 > type(uint160).max || rawUnlocked != 1) {
            return false;
        }
        uint256 rawLiquidity;
        (ok, rawLiquidity) = _readWord(pool, abi.encodeCall(IYieldBankV3Pool.liquidity, ()));
        return ok && rawLiquidity != 0 && rawLiquidity <= type(uint128).max;
    }

    function pairedAssetOf(address pool) public view returns (address pairedAsset) {
        if (!isSelectablePool(pool)) revert PoolUnavailable(pool);
        address token0 = IYieldBankV3Pool(pool).token0();
        pairedAsset = token0 == weth ? IYieldBankV3Pool(pool).token1() : token0;
    }

    /// @notice Whether a pool may be selected for a new allocation under current infrastructure.
    /// @dev A not-yet-materialized canonical pool is available. A materialized pool remains
    ///      available only while its exact infrastructure generation is still current and active.
    ///      Reconfiguration can therefore never route fresh deposits through stale dependencies.
    function isAllocationPool(address pool) public view returns (bool) {
        if (!isSelectablePool(pool)) return false;
        PoolFoundation memory foundation = foundationOf[pool];
        if (foundation.sleeve == address(0)) return true;
        address factory = IYieldBankV3Pool(pool).factory();
        return foundationInfrastructureCommitment[pool]
            == _infrastructureCommitment(factory, infrastructureOfFactory[factory]);
    }

    function configurePoolDerivedFeed(
        address pool,
        PoolFeedConfig calldata config,
        bytes calldata feedCreationCode
    ) external onlyAllocationOperator nonReentrant returns (address feed) {
        if (
            config.heartbeat == 0 || config.heartbeat > maximumPoolFeedHeartbeat
                || config.gracePeriod > maximumPoolFeedGracePeriod
                || config.twapWindow < minimumPoolTwapWindow || config.maxSpotDeviationBps == 0
                || config.maxSpotDeviationBps > maximumPoolSpotDeviationBps
                || (config.referenceSource == address(0) && config.maxDeviationBps != 0)
                || (config.referenceSource != address(0)
                    && (config.maxDeviationBps == 0
                        || config.maxDeviationBps > maximumPoolReferenceDeviationBps))
        ) revert InvalidConfiguration();
        address pairedAsset = pairedAssetOf(pool);
        (,, IPriceHub.FailureReason currentFailure) = priceHub.quoteUsd18(pairedAsset);
        if (currentFailure != IPriceHub.FailureReason.UNSUPPORTED_ASSET) {
            revert FeedAlreadyConfigured(pairedAsset);
        }
        address factory = IYieldBankV3Pool(pool).factory();
        Infrastructure memory infrastructure = infrastructureOfFactory[factory];
        if (keccak256(feedCreationCode) != infrastructure.feedCreationCodeHash) {
            revert InvalidConfiguration();
        }
        PriceHub.FeedConfig memory wethFeed = priceHub.feedDetails(weth);
        if (!wethFeed.supported || wethFeed.feed == address(0)) revert InvalidConfiguration();
        bytes32 poolRuntimeCodeHash = pool.codehash;
        feed = _deploy(
            abi.encodePacked(
                feedCreationCode,
                abi.encode(
                    pairedAsset,
                    weth,
                    pool,
                    factory,
                    wethFeed.feed,
                    poolRuntimeCodeHash,
                    infrastructure.factoryRuntimeCodeHash,
                    wethFeed.feedRuntimeCodeHash,
                    config.twapWindow,
                    config.maxSpotDeviationBps,
                    config.comparisonAmount,
                    config.minimumLiquidity,
                    config.description
                )
            ),
            infrastructure.feedCreationCodeHash
        );
        if (
            IDeltaPoolDerivedFeed(feed).pairedAsset() != pairedAsset
                || IDeltaPoolDerivedFeed(feed).weth() != weth
                || IDeltaPoolDerivedFeed(feed).pool() != pool
                || IDeltaPoolDerivedFeed(feed).factory() != factory
        ) revert InvalidConfiguration();
        IDeltaPoolDerivedFeed(feed).preparePoolOracle();
        priceHub.configureFeedFromRegistrar(
            pairedAsset,
            feed,
            config.referenceSource,
            config.heartbeat,
            config.gracePeriod,
            false,
            false,
            config.maxDeviationBps
        );
        emit PoolFeedConfigured(pool, pairedAsset, feed);
    }

    function materializePool(
        address pool,
        MaterializationConfig calldata config,
        bytes calldata routeCreationCode,
        bytes calldata sleeveCreationCode,
        bytes calldata adapterCreationCode
    ) external onlyAllocationOperator nonReentrant returns (address sleeve, address adapter) {
        if (foundationOf[pool].sleeve != address(0)) revert PoolAlreadyMaterialized(pool);
        if (!isAllocationPool(pool)) revert PoolUnavailable(pool);
        address pairedAsset = pairedAssetOf(pool);
        address factory = IYieldBankV3Pool(pool).factory();
        Infrastructure memory infrastructure = infrastructureOfFactory[factory];
        bytes32 poolRuntimeCodeHash = pool.codehash;
        if (
            config.maximumPositions == 0 || config.maximumPositions > 64
                || config.adapterCapBps == 0 || config.adapterCapBps > maximumAdapterCapBps
                || config.maximumOperatorLossBps > maximumOperatorLossBps
                || keccak256(routeCreationCode) != infrastructure.routeCreationCodeHash
                || keccak256(sleeveCreationCode) != infrastructure.sleeveCreationCodeHash
                || keccak256(adapterCreationCode) != infrastructure.adapterCreationCodeHash
        ) revert InvalidConfiguration();

        address entryRoute = _deploy(
            abi.encodePacked(
                routeCreationCode,
                abi.encode(
                    pool,
                    factory,
                    weth,
                    pairedAsset,
                    poolRuntimeCodeHash,
                    infrastructure.factoryRuntimeCodeHash
                )
            ),
            infrastructure.routeCreationCodeHash
        );
        address exitRoute = _deploy(
            abi.encodePacked(
                routeCreationCode,
                abi.encode(
                    pool,
                    factory,
                    pairedAsset,
                    weth,
                    poolRuntimeCodeHash,
                    infrastructure.factoryRuntimeCodeHash
                )
            ),
            infrastructure.routeCreationCodeHash
        );
        sleeve = _deploy(
            abi.encodePacked(
                sleeveCreationCode,
                abi.encode(
                    weth,
                    allocator,
                    address(this),
                    guardian,
                    address(priceHub),
                    address(strategyRegistry),
                    eligibilityPolicy,
                    uint8(1),
                    maximumAdapterCapBps,
                    config.maximumOperatorLossBps
                )
            ),
            infrastructure.sleeveCreationCodeHash
        );
        AdapterDeploymentConfig memory adapterConfig = AdapterDeploymentConfig({
            sleeve: sleeve,
            weth: weth,
            pairedAsset: pairedAsset,
            priceHub: address(priceHub),
            pool: pool,
            positionManager: infrastructure.positionManager,
            positionBuilder: infrastructure.positionBuilder,
            entryRoute: entryRoute,
            exitRoute: exitRoute,
            poolCodeHash: poolRuntimeCodeHash,
            factoryCodeHash: infrastructure.factoryRuntimeCodeHash,
            positionManagerCodeHash: infrastructure.positionManagerRuntimeCodeHash,
            positionBuilderCodeHash: infrastructure.positionBuilderRuntimeCodeHash,
            entryRouteCodeHash: entryRoute.codehash,
            exitRouteCodeHash: exitRoute.codehash,
            maximumPositions: config.maximumPositions
        });
        adapter = _deploy(
            abi.encodePacked(adapterCreationCode, abi.encode(adapterConfig)),
            infrastructure.adapterCreationCodeHash
        );

        IDeltaPoolSleeve poolSleeve = IDeltaPoolSleeve(sleeve);
        IDeltaPoolAdapterIdentity poolAdapter = IDeltaPoolAdapterIdentity(adapter);
        if (
            sleeve.code.length == 0 || adapter.code.length == 0
                || poolSleeve.category() != YieldBankIds.MARKET_MAKING
                || poolSleeve.accountingAsset() != weth || poolSleeve.allocator() != allocator
                || poolSleeve.timelock() != address(this) || poolSleeve.guardian() != guardian
                || poolSleeve.priceHub() != address(priceHub)
                || poolSleeve.strategyRegistry() != address(strategyRegistry)
                || poolSleeve.eligibilityPolicy() != eligibilityPolicy
                || poolSleeve.maximumStrategies() != 1
                || poolSleeve.maximumAdapterCapBps() != maximumAdapterCapBps
                || poolAdapter.sleeve() != sleeve || poolAdapter.accountingAsset() != weth
                || poolAdapter.weth() != weth || poolAdapter.pairedAsset() != pairedAsset
                || poolAdapter.priceHub() != address(priceHub) || poolAdapter.pool() != pool
                || poolAdapter.factory() != factory
                || poolAdapter.positionManager() != infrastructure.positionManager
                || poolAdapter.positionBuilder() != infrastructure.positionBuilder
        ) revert InvalidConfiguration();

        (,, IPriceHub.FailureReason wethFailure) = priceHub.quoteUsd18(weth);
        (,, IPriceHub.FailureReason pairedFailure) = priceHub.quoteUsd18(pairedAsset);
        if (
            wethFailure != IPriceHub.FailureReason.NONE
                || pairedFailure != IPriceHub.FailureReason.NONE
        ) revert InvalidConfiguration();

        strategyRegistry.register(adapter, YieldBankIds.MARKET_MAKING);
        poolSleeve.addAdapter(adapter, config.adapterCapBps);
        if (poolSleeve.adapterState(adapter) != YieldBankAdapterState.ACTIVE) {
            revert InvalidConfiguration();
        }

        PoolFoundation memory foundation = PoolFoundation({
            sleeve: sleeve,
            adapter: adapter,
            poolRuntimeCodeHash: pool.codehash,
            sleeveRuntimeCodeHash: sleeve.codehash,
            adapterRuntimeCodeHash: adapter.codehash
        });
        foundationOf[pool] = foundation;
        poolOfSleeve[sleeve] = pool;
        foundationInfrastructureCommitment[pool] =
            _infrastructureCommitment(factory, infrastructure);
        IDeltaPoolCollectionRegistrar(collection).registerDynamicSleeve(sleeve);
        emit PoolMaterialized(
            pool,
            sleeve,
            adapter,
            factory,
            pairedAsset,
            foundation.poolRuntimeCodeHash,
            foundation.sleeveRuntimeCodeHash,
            foundation.adapterRuntimeCodeHash
        );
    }

    function setPoolAdapterCap(address pool, uint16 capBps) external onlyTimelock {
        PoolFoundation memory foundation = _foundation(pool);
        IDeltaPoolSleeve(foundation.sleeve).setAdapterCap(foundation.adapter, capBps);
    }

    function setPoolDepositsPaused(address pool, bool paused) external onlyTimelock {
        IDeltaPoolSleeve(_foundation(pool).sleeve).setDepositsPaused(paused);
    }

    function retirePoolAdapter(address pool) external onlyTimelock {
        PoolFoundation memory foundation = _foundation(pool);
        IDeltaPoolSleeve(foundation.sleeve).retireAdapter(foundation.adapter);
    }

    function isFoundationSleeve(address sleeve) external view returns (bool) {
        return poolOfSleeve[sleeve] != address(0);
    }

    function _foundation(address pool) private view returns (PoolFoundation memory foundation) {
        foundation = foundationOf[pool];
        if (foundation.sleeve == address(0)) revert PoolUnavailable(pool);
    }

    function _deploy(bytes memory initCode, bytes32 creationCodeHash)
        private
        returns (address deployed)
    {
        assembly ("memory-safe") {
            deployed := create(0, add(initCode, 0x20), mload(initCode))
        }
        if (deployed == address(0)) revert DeploymentFailed(creationCodeHash);
    }

    function _readWord(address target, bytes memory callData)
        private
        view
        returns (bool ok, uint256 value)
    {
        bytes memory result;
        (ok, result) = target.staticcall(callData);
        if (!ok || result.length < 32) return (false, 0);
        assembly ("memory-safe") {
            value := mload(add(result, 0x20))
        }
    }

    function _infrastructureCommitment(address factory, Infrastructure memory infrastructure)
        private
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                factory,
                infrastructure.positionManager,
                infrastructure.positionBuilder,
                infrastructure.factoryRuntimeCodeHash,
                infrastructure.positionManagerRuntimeCodeHash,
                infrastructure.positionBuilderRuntimeCodeHash,
                infrastructure.routeCreationCodeHash,
                infrastructure.sleeveCreationCodeHash,
                infrastructure.adapterCreationCodeHash,
                infrastructure.feedCreationCodeHash
            )
        );
    }
}
