// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IYieldBankCollection } from "./interfaces/IYieldBankCollection.sol";
import { IYieldBankAllocationReceiver } from "./interfaces/IYieldBankAllocationReceiver.sol";
import { IYieldBankAllocationRoute } from "./interfaces/IYieldBankAllocationRoute.sol";
import { IYieldBankSleeve } from "./interfaces/IYieldBankSleeve.sol";
import { RebalanceValueGuard } from "./RebalanceValueGuard.sol";
import {
    IYieldBankManagedSleeve,
    YieldBankAdapterRedemptionCall
} from "./interfaces/IYieldBankManagedSleeve.sol";
import { IntegrationBinding } from "./libraries/IntegrationBinding.sol";
import { YieldBankAdapterState, YieldBankCollectionState } from "./YieldBankTypes.sol";
import { YieldBankIds } from "./libraries/YieldBankIds.sol";

interface IYieldBankAllocationOperatorSource {
    function allocationOperator() external view returns (address);
    function PRIMARY_PENDING() external view returns (uint8);
    function PRIMARY_ALLOCATED() external view returns (uint8);
    function primaryStateOf(uint256 tokenId) external view returns (uint8);
}

interface IYieldBankOwnerNFT {
    function ownerOf(uint256 tokenId) external view returns (address);
}

interface IYieldBankRebalanceAccount {
    function trackAsset(address asset) external;
    function untrackEmptyAsset(address asset) external;
    function approveRebalance(address asset, uint256 amount) external;
    function clearRebalanceApproval(address asset) external;
}

interface IYieldBankPoolSleeve is IYieldBankManagedSleeve {
    function category() external view returns (bytes32);
    function accountingAsset() external view returns (address);
    function allocator() external view returns (address);
    function totalAssetsUsd18() external view returns (uint256 value, uint48 pricedAt);
    function adapterState(address adapter) external view returns (YieldBankAdapterState);
    function maximumStrategies() external view returns (uint8);
    function adapters() external view returns (address[] memory);
}

interface IYieldBankDeltaPoolAdapter {
    function sleeve() external view returns (address);
    function pool() external view returns (address);
}

interface IYieldBankDeltaPoolController {
    function isAllocationPool(address pool) external view returns (bool);
    function poolOfSleeve(address sleeve) external view returns (address);
    function foundationOf(address pool)
        external
        view
        returns (
            address sleeve,
            address adapter,
            bytes32 poolRuntimeCodeHash,
            bytes32 sleeveRuntimeCodeHash,
            bytes32 adapterRuntimeCodeHash
        );
}

/// @notice Allocates collection flows at their defaults and executes owner-requested NFT rebalances.
contract CollectionPortfolioAllocator is IYieldBankAllocationReceiver, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    struct RouteBinding {
        address route;
        bytes32 runtimeCodeHash;
    }

    struct AllocationCall {
        uint256 minimumOutput;
        uint256 minimumShares;
        bytes routeData;
        bytes sleeveData;
    }

    struct AllocationTarget {
        address requester;
        address deltaPool;
        uint16 coreWeightBps;
        uint16 marketMakingWeightBps;
        uint16 usdgWeightBps;
        uint16 maximumAdapterLossBps;
        uint64 revision;
        uint64 executedRevision;
        uint48 requestedAt;
        uint48 validUntil;
        uint48 executedAt;
    }

    struct SleeveRedemptionCall {
        uint256[] minimumOutputs;
        YieldBankAdapterRedemptionCall[] adapterCalls;
    }

    struct ConversionCall {
        address asset;
        uint256 minimumWethOut;
        bytes routeData;
    }

    struct RebalanceExecution {
        SleeveRedemptionCall[3] redemptions;
        SleeveRedemptionCall deltaPoolRedemption;
        ConversionCall[] conversions;
        AllocationCall[3] allocations;
        uint256 minimumWethRecovered;
        uint256 deadline;
    }

    struct DeltaPoolBinding {
        address sleeve;
        address adapter;
        bytes32 poolRuntimeCodeHash;
        bytes32 sleeveRuntimeCodeHash;
        bytes32 adapterRuntimeCodeHash;
    }

    uint16 private constant BPS = 10_000;
    uint256 public constant MAX_REBALANCE_ASSETS = 24;

    IYieldBankCollection public immutable collection;
    address public immutable revenueRouter;
    address public immutable timelock;
    address public immutable guardian;
    IYieldBankDeltaPoolController public immutable deltaPoolController;
    RebalanceValueGuard public immutable rebalanceValueGuard;
    uint16 public immutable coreWeightBps;
    uint16 public immutable marketMakingWeightBps;
    uint16 public immutable usdgWeightBps;
    address[3] public sleeves;
    mapping(address inputAsset => mapping(address sleeve => RouteBinding binding)) public
        routeBinding;
    mapping(address inputAsset => RouteBinding binding) public rebalanceRoute;
    mapping(uint256 tokenId => address pool) public activeDeltaPoolOf;
    mapping(uint256 tokenId => AllocationTarget target) private _allocationTargets;

    error OnlyRevenueRouter(address caller);
    error OnlyProceedsVault(address caller);
    error OnlyTimelock(address caller);
    error OnlyAllocationOperator(address caller);
    error OnlyOperatorOrGuardian(address caller);
    error InvalidConfiguration();
    error InexactReceipt(uint256 expected, uint256 received);
    error RouteUnavailable(address inputAsset, address sleeve);
    error InvestmentUnavailable(YieldBankCollectionState state);
    error OnlyTokenOwner(uint256 tokenId, address caller);
    error TargetOwnerChanged(uint256 tokenId, address requester, address currentOwner);
    error InvalidTargetRevision(uint256 tokenId, uint64 expected, uint64 actual);
    error TargetAlreadyExecuted(uint256 tokenId, uint64 revision);
    error InvalidTargetExpiry(uint256 validUntil);
    error OwnerAdapterLossLimitExceeded(uint16 maximum, uint16 supplied);
    error OwnerTotalLossLimitExceeded(uint256 minimumValueUsd18, uint256 actualValueUsd18);
    error RebalanceExpired(uint256 deadline);
    error PrimaryAllocationPending(uint256 tokenId);
    error MissingConversionRoute(address asset);
    error TooManyRebalanceAssets(uint256 supplied);
    error DeltaPoolUnavailable(address pool);

    event RouteBound(
        address indexed inputAsset,
        address indexed sleeve,
        address indexed route,
        bytes32 runtimeCodeHash
    );
    event PortfolioAllocated(
        address indexed inputAsset,
        uint256 amount,
        address indexed receiver,
        uint256 coreShares,
        uint256 marketMakingShares,
        uint256 usdgShares
    );
    event RebalanceRouteBound(
        address indexed inputAsset, address indexed route, bytes32 runtimeCodeHash
    );
    event AllocationTargetUpdated(
        uint256 indexed tokenId,
        address indexed owner,
        uint64 indexed revision,
        address deltaPool,
        uint16 coreWeightBps,
        uint16 marketMakingWeightBps,
        uint16 usdgWeightBps,
        uint16 maximumAdapterLossBps,
        uint48 validUntil
    );
    event AllocationRebalanced(
        uint256 indexed tokenId,
        address indexed account,
        uint64 indexed revision,
        address deltaPool,
        uint256 wethRecovered,
        uint256 coreShares,
        uint256 marketMakingShares,
        uint256 usdgShares
    );

    constructor(
        address collection_,
        address revenueRouter_,
        address timelock_,
        address guardian_,
        address deltaPoolController_,
        address coreSleeve_,
        address marketMakingSleeve_,
        address usdgSleeve_,
        uint16 coreWeightBps_,
        uint16 marketMakingWeightBps_,
        uint16 usdgWeightBps_
    ) {
        if (
            collection_ == address(0) || revenueRouter_ == address(0) || timelock_ == address(0)
                || guardian_ == address(0) || deltaPoolController_ == address(0)
                || coreSleeve_.code.length == 0 || marketMakingSleeve_.code.length == 0
                || usdgSleeve_.code.length == 0
                || uint256(coreWeightBps_) + marketMakingWeightBps_ + usdgWeightBps_ != BPS
        ) revert InvalidConfiguration();
        collection = IYieldBankCollection(collection_);
        revenueRouter = revenueRouter_;
        timelock = timelock_;
        guardian = guardian_;
        deltaPoolController = IYieldBankDeltaPoolController(deltaPoolController_);
        rebalanceValueGuard = new RebalanceValueGuard();
        coreWeightBps = coreWeightBps_;
        marketMakingWeightBps = marketMakingWeightBps_;
        usdgWeightBps = usdgWeightBps_;
        sleeves = [coreSleeve_, marketMakingSleeve_, usdgSleeve_];
    }

    modifier onlyTimelock() {
        if (msg.sender != timelock) revert OnlyTimelock(msg.sender);
        _;
    }

    modifier onlyRevenueRouter() {
        if (msg.sender != revenueRouter) revert OnlyRevenueRouter(msg.sender);
        _;
    }

    modifier onlyAllocationOperator() {
        if (msg.sender != allocationOperator()) revert OnlyAllocationOperator(msg.sender);
        _;
    }

    modifier onlyOperatorOrGuardian() {
        if (msg.sender != guardian && msg.sender != allocationOperator()) {
            revert OnlyOperatorOrGuardian(msg.sender);
        }
        _;
    }

    modifier whenInvestmentActive() {
        YieldBankCollectionState current = collection.state();
        if (current != YieldBankCollectionState.ACTIVE) revert InvestmentUnavailable(current);
        _;
    }

    function allocationOperator() public view returns (address) {
        return IYieldBankAllocationOperatorSource(collection.proceedsVault()).allocationOperator();
    }

    function bindRoute(address inputAsset, address sleeve, address route, bytes32 runtimeCodeHash)
        external
        onlyTimelock
    {
        if (!_isSleeve(sleeve) || inputAsset.code.length == 0) revert InvalidConfiguration();
        if (inputAsset == IYieldBankSleeve(sleeve).accountingAsset()) {
            if (route != address(0) || runtimeCodeHash != bytes32(0)) {
                revert InvalidConfiguration();
            }
        } else {
            IntegrationBinding.requireBound(route, runtimeCodeHash);
            if (
                IYieldBankAllocationRoute(route).inputAsset() != inputAsset
                    || IYieldBankAllocationRoute(route).outputAsset()
                        != IYieldBankSleeve(sleeve).accountingAsset()
            ) revert InvalidConfiguration();
        }
        routeBinding[inputAsset][sleeve] =
            RouteBinding({ route: route, runtimeCodeHash: runtimeCodeHash });
        emit RouteBound(inputAsset, sleeve, route, runtimeCodeHash);
    }

    function bindRebalanceRoute(address inputAsset, address route, bytes32 runtimeCodeHash)
        external
        onlyTimelock
    {
        address weth_ = collection.weth();
        if (inputAsset.code.length == 0 || inputAsset == weth_) revert InvalidConfiguration();
        IntegrationBinding.requireBound(route, runtimeCodeHash);
        if (
            IYieldBankAllocationRoute(route).inputAsset() != inputAsset
                || IYieldBankAllocationRoute(route).outputAsset() != weth_
        ) revert InvalidConfiguration();
        rebalanceRoute[inputAsset] =
            RouteBinding({ route: route, runtimeCodeHash: runtimeCodeHash });
        emit RebalanceRouteBound(inputAsset, route, runtimeCodeHash);
    }

    function deltaPoolBinding(address pool) public view returns (DeltaPoolBinding memory binding) {
        (
            binding.sleeve,
            binding.adapter,
            binding.poolRuntimeCodeHash,
            binding.sleeveRuntimeCodeHash,
            binding.adapterRuntimeCodeHash
        ) = deltaPoolController.foundationOf(pool);
    }

    function deltaPoolOfSleeve(address sleeve) public view returns (address) {
        return deltaPoolController.poolOfSleeve(sleeve);
    }

    function isDeltaPoolSleeve(address sleeve) external view returns (bool) {
        return deltaPoolController.poolOfSleeve(sleeve) != address(0);
    }

    function allocationTargetOf(uint256 tokenId)
        public
        view
        returns (AllocationTarget memory target)
    {
        target = _allocationTargets[tokenId];
        if (target.revision == 0) {
            target.coreWeightBps = coreWeightBps;
            target.marketMakingWeightBps = marketMakingWeightBps;
            target.usdgWeightBps = usdgWeightBps;
        }
    }

    function setTargetAllocation(
        uint256 tokenId,
        uint16[3] calldata weights,
        address deltaPool,
        uint16 maximumAdapterLossBps,
        uint48 validUntil
    ) external returns (uint64 revision) {
        YieldBankCollectionState current = collection.state();
        if (
            current != YieldBankCollectionState.ACTIVE
                && current != YieldBankCollectionState.INVESTMENT_PAUSED
        ) revert InvestmentUnavailable(current);
        address owner = IYieldBankOwnerNFT(collection.nft()).ownerOf(tokenId);
        if (owner != msg.sender) revert OnlyTokenOwner(tokenId, msg.sender);
        _validateWeights(weights);
        if (deltaPool != address(0) && !deltaPoolController.isAllocationPool(deltaPool)) {
            revert DeltaPoolUnavailable(deltaPool);
        }
        if (weights[1] == 0 && deltaPool != address(0)) revert InvalidConfiguration();
        if (maximumAdapterLossBps > BPS) {
            revert OwnerAdapterLossLimitExceeded(BPS, maximumAdapterLossBps);
        }
        if (validUntil <= block.timestamp) revert InvalidTargetExpiry(validUntil);
        AllocationTarget storage target = _allocationTargets[tokenId];
        revision = target.revision + 1;
        target.deltaPool = deltaPool;
        target.coreWeightBps = weights[0];
        target.marketMakingWeightBps = weights[1];
        target.usdgWeightBps = weights[2];
        target.maximumAdapterLossBps = maximumAdapterLossBps;
        target.revision = revision;
        target.requester = owner;
        target.requestedAt = block.timestamp.toUint48();
        target.validUntil = validUntil;
        emit AllocationTargetUpdated(
            tokenId,
            owner,
            revision,
            deltaPool,
            weights[0],
            weights[1],
            weights[2],
            maximumAdapterLossBps,
            validUntil
        );
    }

    function executeTargetAllocation(
        uint256 tokenId,
        uint64 expectedRevision,
        RebalanceExecution calldata execution
    )
        external
        onlyAllocationOperator
        whenInvestmentActive
        nonReentrant
        returns (uint256 wethRecovered, uint256[3] memory shares)
    {
        if (block.timestamp > execution.deadline) {
            revert RebalanceExpired(execution.deadline);
        }
        AllocationTarget storage target = _allocationTargets[tokenId];
        if (target.revision == 0 || target.revision != expectedRevision) {
            revert InvalidTargetRevision(tokenId, expectedRevision, target.revision);
        }
        if (target.executedRevision >= expectedRevision) {
            revert TargetAlreadyExecuted(tokenId, expectedRevision);
        }
        if (block.timestamp > target.validUntil || execution.deadline > target.validUntil) {
            revert RebalanceExpired(target.validUntil);
        }
        address currentOwner = IYieldBankOwnerNFT(collection.nft()).ownerOf(tokenId);
        if (target.requester != currentOwner) {
            revert TargetOwnerChanged(tokenId, target.requester, currentOwner);
        }
        address account = collection.accountOf(tokenId);
        if (account == address(0)) revert InvalidConfiguration();
        IYieldBankAllocationOperatorSource vault =
            IYieldBankAllocationOperatorSource(collection.proceedsVault());
        uint8 primaryState = vault.primaryStateOf(tokenId);
        if (primaryState == vault.PRIMARY_PENDING()) revert PrimaryAllocationPending(tokenId);
        collection.deliverRevenue(tokenId);

        uint16[3] memory weights =
            [target.coreWeightBps, target.marketMakingWeightBps, target.usdgWeightBps];
        _validateOwnerLossLimits(execution, target.maximumAdapterLossBps);
        address targetMarketMakingSleeve = sleeves[1];
        if (target.deltaPool != address(0)) {
            targetMarketMakingSleeve = _requireActiveDeltaPool(target.deltaPool).sleeve;
        }
        address previousDeltaPool = activeDeltaPoolOf[tokenId];
        address previousPoolSleeve = previousDeltaPool == address(0)
            ? address(0)
            : _requireDeltaPool(previousDeltaPool).sleeve;
        uint256 valueBeforeUsd18 = rebalanceValueGuard.accountValueUsd18(
            account, collection.weth(), sleeves, previousPoolSleeve
        );
        (wethRecovered, shares) = _rebalanceAccount(
            account, weights, previousPoolSleeve, targetMarketMakingSleeve, execution
        );
        uint256 valueAfterUsd18 = rebalanceValueGuard.mintedValueUsd18(
            shares, [sleeves[0], targetMarketMakingSleeve, sleeves[2]]
        );
        uint256 minimumValueUsd18 =
            Math.mulDiv(valueBeforeUsd18, BPS - target.maximumAdapterLossBps, BPS);
        if (valueAfterUsd18 < minimumValueUsd18) {
            revert OwnerTotalLossLimitExceeded(minimumValueUsd18, valueAfterUsd18);
        }
        activeDeltaPoolOf[tokenId] = weights[1] == 0 ? address(0) : target.deltaPool;
        target.executedRevision = expectedRevision;
        target.executedAt = block.timestamp.toUint48();
        emit AllocationRebalanced(
            tokenId,
            account,
            expectedRevision,
            activeDeltaPoolOf[tokenId],
            wethRecovered,
            shares[0],
            shares[1],
            shares[2]
        );
    }

    function _validateOwnerLossLimits(
        RebalanceExecution calldata execution,
        uint16 maximumAdapterLossBps
    ) private pure {
        for (uint256 i; i < 3; ++i) {
            YieldBankAdapterRedemptionCall[] calldata calls = execution.redemptions[i].adapterCalls;
            for (uint256 j; j < calls.length; ++j) {
                if (calls[j].maxLossBps > maximumAdapterLossBps) {
                    revert OwnerAdapterLossLimitExceeded(maximumAdapterLossBps, calls[j].maxLossBps);
                }
            }
        }
        YieldBankAdapterRedemptionCall[] calldata poolCalls =
        execution.deltaPoolRedemption.adapterCalls;
        for (uint256 i; i < poolCalls.length; ++i) {
            if (poolCalls[i].maxLossBps > maximumAdapterLossBps) {
                revert OwnerAdapterLossLimitExceeded(maximumAdapterLossBps, poolCalls[i].maxLossBps);
            }
        }
    }

    function allocate(address asset, uint256 amount, bytes calldata data)
        external
        onlyRevenueRouter
        whenInvestmentActive
        nonReentrant
        returns (address[] memory distributionAssets, uint256[] memory distributionAmounts)
    {
        _collect(asset, msg.sender, amount);
        AllocationCall[3] memory calls = abi.decode(data, (AllocationCall[3]));
        (distributionAssets, distributionAmounts) = _allocate(asset, amount, msg.sender, calls);
    }

    function allocatePrimary(
        address asset,
        uint256 amount,
        address receiver,
        AllocationCall[3] calldata calls
    )
        external
        whenInvestmentActive
        nonReentrant
        returns (address[] memory distributionAssets, uint256[] memory distributionAmounts)
    {
        if (msg.sender != collection.proceedsVault()) {
            revert OnlyProceedsVault(msg.sender);
        }
        if (receiver != msg.sender) revert InvalidConfiguration();
        _collect(asset, msg.sender, amount);
        AllocationCall[3] memory execution = calls;
        return _allocate(asset, amount, receiver, execution);
    }

    function depositToAdapter(
        address sleeve,
        address adapter,
        uint256 assets,
        uint256 minPositionUnits,
        bytes calldata data
    )
        external
        onlyAllocationOperator
        whenInvestmentActive
        nonReentrant
        returns (uint256 positionUnits)
    {
        if (!_isSleeve(sleeve)) revert InvalidConfiguration();
        _requireSleeveAdapterBinding(sleeve, adapter);
        if (!_isBaseSleeve(sleeve)) {
            address pool = deltaPoolController.poolOfSleeve(sleeve);
            if (!deltaPoolController.isAllocationPool(pool)) revert DeltaPoolUnavailable(pool);
        }
        return
            IYieldBankManagedSleeve(sleeve)
                .depositToAdapter(adapter, assets, minPositionUnits, data);
    }

    function withdrawFromAdapter(
        address sleeve,
        address adapter,
        uint256 assets,
        uint16 maxLossBps,
        bytes calldata data
    ) external onlyOperatorOrGuardian nonReentrant returns (uint256 assetsReturned) {
        if (!_isSleeve(sleeve)) revert InvalidConfiguration();
        _requireSleeveAdapterBinding(sleeve, adapter);
        return
            IYieldBankManagedSleeve(sleeve).withdrawFromAdapter(adapter, assets, maxLossBps, data);
    }

    function collectAdapter(address sleeve, address adapter, bytes calldata data)
        external
        onlyAllocationOperator
        whenInvestmentActive
        nonReentrant
        returns (address[] memory assets, uint256[] memory amounts)
    {
        if (!_isSleeve(sleeve)) revert InvalidConfiguration();
        _requireSleeveAdapterBinding(sleeve, adapter);
        return IYieldBankManagedSleeve(sleeve).collectAdapter(adapter, data);
    }

    function exitAdapter(address sleeve, address adapter, uint16 maxLossBps, bytes calldata data)
        external
        onlyOperatorOrGuardian
        nonReentrant
        returns (address[] memory assets, uint256[] memory amounts)
    {
        if (!_isSleeve(sleeve)) revert InvalidConfiguration();
        _requireSleeveAdapterBinding(sleeve, adapter);
        return IYieldBankManagedSleeve(sleeve).exitAdapter(adapter, maxLossBps, data);
    }

    function emergencyExitAdapterInKind(address sleeve, address adapter, bytes calldata data)
        external
        nonReentrant
        returns (address[] memory assets, uint256[] memory amounts)
    {
        if (msg.sender != guardian) revert OnlyOperatorOrGuardian(msg.sender);
        if (!_isSleeve(sleeve)) revert InvalidConfiguration();
        _requireSleeveAdapterBinding(sleeve, adapter);
        return IYieldBankManagedSleeve(sleeve).emergencyExitAdapterInKind(adapter, data);
    }

    function _rebalanceAccount(
        address account,
        uint16[3] memory weights,
        address previousPoolSleeve,
        address targetMarketMakingSleeve,
        RebalanceExecution calldata execution
    ) private returns (uint256 wethRecovered, uint256[3] memory shares) {
        if (execution.conversions.length > MAX_REBALANCE_ASSETS) {
            revert TooManyRebalanceAssets(execution.conversions.length);
        }
        (address[] memory universe, uint256 universeLength, uint256[] memory balancesBefore) =
            _snapshotRebalanceAssets(previousPoolSleeve);
        address weth_ = collection.weth();
        uint256 wethBefore = IERC20(weth_).balanceOf(address(this));

        for (uint256 i; i < 3; ++i) {
            address sleeve = sleeves[i];
            uint256 sleeveShares = IERC20(sleeve).balanceOf(account);
            SleeveRedemptionCall calldata redemption = execution.redemptions[i];
            if (sleeveShares == 0) {
                if (redemption.minimumOutputs.length != 0 || redemption.adapterCalls.length != 0) {
                    revert InvalidConfiguration();
                }
                continue;
            }
            IYieldBankRebalanceAccount(account).approveRebalance(sleeve, sleeveShares);
            IYieldBankManagedSleeve(sleeve)
                .redeemManaged(
                    sleeveShares,
                    address(this),
                    account,
                    redemption.minimumOutputs,
                    redemption.adapterCalls
                );
            IYieldBankRebalanceAccount(account).clearRebalanceApproval(sleeve);
            IYieldBankRebalanceAccount(account).untrackEmptyAsset(sleeve);
        }

        if (previousPoolSleeve != address(0) && previousPoolSleeve != sleeves[1]) {
            uint256 poolShares = IERC20(previousPoolSleeve).balanceOf(account);
            SleeveRedemptionCall calldata poolRedemption = execution.deltaPoolRedemption;
            if (poolShares == 0) {
                if (
                    poolRedemption.minimumOutputs.length != 0
                        || poolRedemption.adapterCalls.length != 0
                ) revert InvalidConfiguration();
            } else {
                IYieldBankRebalanceAccount(account).approveRebalance(previousPoolSleeve, poolShares);
                IYieldBankManagedSleeve(previousPoolSleeve)
                    .redeemManaged(
                        poolShares,
                        address(this),
                        account,
                        poolRedemption.minimumOutputs,
                        poolRedemption.adapterCalls
                    );
                IYieldBankRebalanceAccount(account).clearRebalanceApproval(previousPoolSleeve);
                IYieldBankRebalanceAccount(account).untrackEmptyAsset(previousPoolSleeve);
            }
        } else if (
            execution.deltaPoolRedemption.minimumOutputs.length != 0
                || execution.deltaPoolRedemption.adapterCalls.length != 0
        ) {
            revert InvalidConfiguration();
        }

        uint256 accountWeth = IERC20(weth_).balanceOf(account);
        if (accountWeth != 0) {
            IYieldBankRebalanceAccount(account).trackAsset(weth_);
            IYieldBankRebalanceAccount(account).approveRebalance(weth_, accountWeth);
            IERC20(weth_).safeTransferFrom(account, address(this), accountWeth);
            IYieldBankRebalanceAccount(account).clearRebalanceApproval(weth_);
        }

        bool[] memory usedConversions = new bool[](execution.conversions.length);
        for (uint256 i; i < universeLength; ++i) {
            address asset = universe[i];
            if (asset == weth_) continue;
            uint256 amount = IERC20(asset).balanceOf(address(this)) - balancesBefore[i];
            if (amount == 0) continue;
            uint256 callIndex = _findConversion(execution.conversions, usedConversions, asset);
            if (callIndex == type(uint256).max) revert MissingConversionRoute(asset);
            _convertForRebalance(amount, execution.conversions[callIndex]);
            usedConversions[callIndex] = true;
            uint256 currentBalance = IERC20(asset).balanceOf(address(this));
            if (currentBalance != balancesBefore[i]) {
                revert InexactReceipt(balancesBefore[i], currentBalance);
            }
        }
        for (uint256 i; i < usedConversions.length; ++i) {
            if (!usedConversions[i]) {
                revert MissingConversionRoute(execution.conversions[i].asset);
            }
        }

        wethRecovered = IERC20(weth_).balanceOf(address(this)) - wethBefore;
        if (wethRecovered < execution.minimumWethRecovered || wethRecovered == 0) {
            revert InexactReceipt(execution.minimumWethRecovered, wethRecovered);
        }
        address[3] memory targetSleeves = [sleeves[0], targetMarketMakingSleeve, sleeves[2]];
        (address[] memory assets, uint256[] memory minted) = _allocateWeighted(
            weth_, wethRecovered, account, weights, targetSleeves, execution.allocations
        );
        for (uint256 i; i < 3; ++i) {
            if (assets[i] != targetSleeves[i]) revert InvalidConfiguration();
            shares[i] = minted[i];
            if (shares[i] != 0) IYieldBankRebalanceAccount(account).trackAsset(assets[i]);
        }
        uint256 endingWeth = IERC20(weth_).balanceOf(address(this));
        if (endingWeth != wethBefore) {
            revert InexactReceipt(wethBefore, endingWeth);
        }
    }

    function _snapshotRebalanceAssets(address extraSleeve)
        private
        view
        returns (address[] memory universe, uint256 length, uint256[] memory balancesBefore)
    {
        universe = new address[](MAX_REBALANCE_ASSETS);
        balancesBefore = new uint256[](MAX_REBALANCE_ASSETS);
        uint256 sleeveCount = extraSleeve == address(0) || extraSleeve == sleeves[1] ? 3 : 4;
        for (uint256 i; i < sleeveCount; ++i) {
            address sleeve = i < 3 ? sleeves[i] : extraSleeve;
            address[] memory inventory = IYieldBankManagedSleeve(sleeve).inventoryAssets();
            for (uint256 j; j < inventory.length; ++j) {
                address asset = inventory[j];
                bool exists;
                for (uint256 k; k < length; ++k) {
                    if (universe[k] == asset) {
                        exists = true;
                        break;
                    }
                }
                if (exists) continue;
                if (length == MAX_REBALANCE_ASSETS) {
                    revert TooManyRebalanceAssets(length + 1);
                }
                universe[length] = asset;
                balancesBefore[length] = IERC20(asset).balanceOf(address(this));
                ++length;
            }
        }
    }

    function _findConversion(
        ConversionCall[] calldata conversions,
        bool[] memory used,
        address asset
    ) private pure returns (uint256 index) {
        index = type(uint256).max;
        for (uint256 i; i < conversions.length; ++i) {
            if (!used[i] && conversions[i].asset == asset) {
                index = i;
                break;
            }
        }
    }

    function _convertForRebalance(uint256 amount, ConversionCall calldata call_)
        private
        returns (uint256 output)
    {
        address weth_ = collection.weth();
        if (call_.asset == weth_ || call_.minimumWethOut == 0) revert InvalidConfiguration();
        RouteBinding memory binding = rebalanceRoute[call_.asset];
        if (binding.route == address(0)) revert MissingConversionRoute(call_.asset);
        IntegrationBinding.requireBound(binding.route, binding.runtimeCodeHash);
        IERC20 input = IERC20(call_.asset);
        IERC20 outputToken = IERC20(weth_);
        uint256 inputBefore = input.balanceOf(address(this));
        uint256 outputBefore = outputToken.balanceOf(address(this));
        input.forceApprove(binding.route, amount);
        IYieldBankAllocationRoute(binding.route)
            .convert(amount, call_.minimumWethOut, address(this), call_.routeData);
        input.forceApprove(binding.route, 0);
        uint256 consumed = inputBefore - input.balanceOf(address(this));
        if (consumed != amount) revert InexactReceipt(amount, consumed);
        output = outputToken.balanceOf(address(this)) - outputBefore;
        if (output < call_.minimumWethOut || output == 0) {
            revert InexactReceipt(call_.minimumWethOut, output);
        }
    }

    function _allocate(
        address asset,
        uint256 amount,
        address receiver,
        AllocationCall[3] memory calls
    ) private returns (address[] memory distributionAssets, uint256[] memory distributionAmounts) {
        uint16[3] memory weights = [coreWeightBps, marketMakingWeightBps, usdgWeightBps];
        return _allocateWeighted(asset, amount, receiver, weights, sleeves, calls);
    }

    function _allocateWeighted(
        address asset,
        uint256 amount,
        address receiver,
        uint16[3] memory weights,
        address[3] memory targetSleeves,
        AllocationCall[3] memory calls
    ) private returns (address[] memory distributionAssets, uint256[] memory distributionAmounts) {
        _validateWeights(weights);
        uint256[3] memory amountsIn;
        amountsIn[0] = Math.mulDiv(amount, weights[0], BPS);
        uint256 marketCumulative = Math.mulDiv(amount, uint256(weights[0]) + weights[1], BPS);
        amountsIn[1] = marketCumulative - amountsIn[0];
        amountsIn[2] = amount - marketCumulative;
        distributionAssets = new address[](3);
        distributionAmounts = new uint256[](3);
        for (uint256 i; i < 3; ++i) {
            address sleeve = targetSleeves[i];
            distributionAssets[i] = sleeve;
            if (amountsIn[i] == 0) {
                if (calls[i].minimumOutput != 0 || calls[i].minimumShares != 0) {
                    revert InvalidConfiguration();
                }
                continue;
            }
            if (calls[i].minimumOutput == 0 || calls[i].minimumShares == 0) {
                revert InvalidConfiguration();
            }
            uint256 converted = _convert(asset, sleeve, amountsIn[i], calls[i]);
            address accounting = IYieldBankSleeve(sleeve).accountingAsset();
            IERC20(accounting).forceApprove(sleeve, converted);
            uint256 shares = IYieldBankSleeve(sleeve)
                .deposit(converted, receiver, calls[i].minimumShares, calls[i].sleeveData);
            IERC20(accounting).forceApprove(sleeve, 0);
            distributionAmounts[i] = shares;
        }
        emit PortfolioAllocated(
            asset,
            amount,
            receiver,
            distributionAmounts[0],
            distributionAmounts[1],
            distributionAmounts[2]
        );
    }

    function _validateWeights(uint16[3] memory weights) private pure {
        if (uint256(weights[0]) + weights[1] + weights[2] != BPS) {
            revert InvalidConfiguration();
        }
    }

    function _convert(address input, address sleeve, uint256 amount, AllocationCall memory call_)
        private
        returns (uint256 output)
    {
        address accounting = IYieldBankSleeve(sleeve).accountingAsset();
        if (amount == 0 || call_.minimumOutput == 0) revert InvalidConfiguration();
        if (input == accounting) {
            if (amount < call_.minimumOutput) revert InvalidConfiguration();
            return amount;
        }
        RouteBinding memory binding = routeBinding[input][sleeve];
        if (binding.route == address(0)) revert RouteUnavailable(input, sleeve);
        IntegrationBinding.requireBound(binding.route, binding.runtimeCodeHash);
        IERC20 outputToken = IERC20(accounting);
        IERC20 inputToken = IERC20(input);
        uint256 inputBefore = inputToken.balanceOf(address(this));
        uint256 beforeBalance = outputToken.balanceOf(address(this));
        inputToken.forceApprove(binding.route, amount);
        IYieldBankAllocationRoute(binding.route)
            .convert(amount, call_.minimumOutput, address(this), call_.routeData);
        inputToken.forceApprove(binding.route, 0);
        uint256 consumed = inputBefore - inputToken.balanceOf(address(this));
        if (consumed != amount) revert InexactReceipt(amount, consumed);
        output = outputToken.balanceOf(address(this)) - beforeBalance;
        if (output < call_.minimumOutput || output == 0) revert InvalidConfiguration();
    }

    function _collect(address asset, address from, uint256 amount) private {
        if (asset.code.length == 0 || amount == 0) revert InvalidConfiguration();
        IERC20 token = IERC20(asset);
        uint256 beforeBalance = token.balanceOf(address(this));
        token.safeTransferFrom(from, address(this), amount);
        uint256 received = token.balanceOf(address(this)) - beforeBalance;
        if (received != amount) revert InexactReceipt(amount, received);
    }

    function _isSleeve(address sleeve) private view returns (bool) {
        return _isBaseSleeve(sleeve) || deltaPoolController.poolOfSleeve(sleeve) != address(0);
    }

    function _isBaseSleeve(address sleeve) private view returns (bool) {
        return sleeve == sleeves[0] || sleeve == sleeves[1] || sleeve == sleeves[2];
    }

    function _requireSleeveAdapterBinding(address sleeve, address adapter) private view {
        if (_isBaseSleeve(sleeve)) return;
        address registeredPool = deltaPoolController.poolOfSleeve(sleeve);
        if (registeredPool == address(0)) return;
        DeltaPoolBinding memory binding = _requireDeltaPool(registeredPool);
        if (binding.adapter != adapter) revert DeltaPoolUnavailable(registeredPool);
    }

    function _requireActiveDeltaPool(address pool)
        private
        view
        returns (DeltaPoolBinding memory binding)
    {
        binding = _requireDeltaPool(pool);
        if (
            !deltaPoolController.isAllocationPool(pool)
                || IYieldBankPoolSleeve(binding.sleeve).adapterState(binding.adapter)
                    != YieldBankAdapterState.ACTIVE
        ) revert DeltaPoolUnavailable(pool);
    }

    function _requireDeltaPool(address pool)
        private
        view
        returns (DeltaPoolBinding memory binding)
    {
        binding = deltaPoolBinding(pool);
        if (binding.sleeve == address(0)) revert DeltaPoolUnavailable(pool);
        IntegrationBinding.requireBound(pool, binding.poolRuntimeCodeHash);
        IntegrationBinding.requireBound(binding.sleeve, binding.sleeveRuntimeCodeHash);
        IntegrationBinding.requireBound(binding.adapter, binding.adapterRuntimeCodeHash);
        if (
            deltaPoolController.poolOfSleeve(binding.sleeve) != pool
                || IYieldBankPoolSleeve(binding.sleeve).maximumStrategies() != 1
                || uint8(IYieldBankPoolSleeve(binding.sleeve).adapterState(binding.adapter))
                    < uint8(YieldBankAdapterState.ACTIVE)
                || IYieldBankDeltaPoolAdapter(binding.adapter).sleeve() != binding.sleeve
                || IYieldBankDeltaPoolAdapter(binding.adapter).pool() != pool
        ) revert DeltaPoolUnavailable(pool);
    }
}
