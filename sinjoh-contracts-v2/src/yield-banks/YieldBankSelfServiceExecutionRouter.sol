// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { CollectionPortfolioAllocator } from "./CollectionPortfolioAllocator.sol";
import { IPriceHub } from "./interfaces/IPriceHub.sol";
import { IYieldBankCollection } from "./interfaces/IYieldBankCollection.sol";
import { IDeltaPositionBuilder } from "./interfaces/IDeltaPositionBuilder.sol";
import { IYieldBankV3Pool } from "./interfaces/IYieldBankV3.sol";
import { DeltaV3LPAdapter } from "./adapters/DeltaV3LPAdapter.sol";

interface IYieldBankSelfServiceOwnerNFT {
    function ownerOf(uint256 tokenId) external view returns (address);
}

/// @notice Lets Piggy Bank owners execute their saved allocations and lets anyone place idle
///         Delta sleeve capital under one deterministic, oracle-bounded policy.
/// @dev Intended to be the collection allocation operator. Governance retains configuration
///      authority, but ordinary allocation and Delta deployment need no operator approval.
contract YieldBankSelfServiceExecutionRouter is ReentrancyGuard {
    uint16 private constant BPS = 10_000;

    uint16 public constant WETH_CONVERSION_BPS = 5_000;
    uint16 public constant MAXIMUM_SWAP_SLIPPAGE_BPS = 500;
    uint16 public constant IDLE_UTILIZATION_BPS = 9_500;
    uint16 public constant MINIMUM_RUNG_FILL_BPS = 9_000;
    int24 public constant RANGE_HALF_WIDTH_SPACINGS = 1_000;
    int24 public constant MAXIMUM_SPOT_DRIFT_SPACINGS = 100;
    uint256 public constant MAXIMUM_DEADLINE_WINDOW = 15 minutes;
    uint256 public constant MINIMUM_DEPLOYMENT_ASSETS = 0.001 ether;

    struct DeltaDeploymentPreview {
        address sleeve;
        address adapter;
        uint256 idleAssets;
        uint256 assets;
        uint256 wethToConvert;
        uint256 minimumPairedAssetOut;
        int24 tickLower;
        int24 tickUpper;
        uint256 managedAssets;
        uint256 positionCount;
        bool ready;
    }

    CollectionPortfolioAllocator public immutable allocator;
    IYieldBankSelfServiceOwnerNFT public immutable nft;
    address public immutable proceedsVault;
    address public immutable revenueRouter;
    address public immutable deltaPoolController;
    address public immutable timelock;
    address public immutable weth;

    error InvalidConfiguration();
    error OnlyTokenOwner(uint256 tokenId, address caller, address currentOwner);
    error OnlyTimelock(address caller);
    error RouterNotActive(address currentOperator);
    error InvalidGovernanceTarget(address target);
    error GovernanceCallFailed(address target, bytes revertData);
    error InvalidDeltaPool(address pool);
    error DeltaPoolMismatch(uint256 tokenId, address expectedPool, address suppliedPool);
    error DeltaDeploymentNotReady(uint256 idleAssets, uint256 managedAssets, uint256 positionCount);
    error UnsafeDeltaParameters();

    event OwnerAllocationExecuted(
        uint256 indexed tokenId,
        address indexed owner,
        uint64 indexed revision,
        uint256 wethRecovered,
        uint256 coreShares,
        uint256 marketMakingShares,
        uint256 usdgShares
    );
    event DeltaIdleCapitalDeployed(
        address indexed pool,
        address indexed sleeve,
        address indexed caller,
        uint256 assets,
        uint256 positionUnits
    );
    event GovernanceCallExecuted(address indexed target, bytes4 indexed selector);

    constructor(address allocator_) {
        if (allocator_.code.length == 0) revert InvalidConfiguration();
        CollectionPortfolioAllocator allocatorContract = CollectionPortfolioAllocator(allocator_);
        IYieldBankCollection collection = allocatorContract.collection();
        address nft_ = collection.nft();
        address proceedsVault_ = collection.proceedsVault();
        address revenueRouter_ = allocatorContract.revenueRouter();
        address deltaPoolController_ = address(allocatorContract.deltaPoolController());
        address timelock_ = allocatorContract.timelock();
        address weth_ = collection.weth();
        if (
            nft_.code.length == 0 || proceedsVault_.code.length == 0
                || revenueRouter_.code.length == 0 || deltaPoolController_.code.length == 0
                || timelock_.code.length == 0 || weth_.code.length == 0
        ) revert InvalidConfiguration();

        allocator = allocatorContract;
        nft = IYieldBankSelfServiceOwnerNFT(nft_);
        proceedsVault = proceedsVault_;
        revenueRouter = revenueRouter_;
        deltaPoolController = deltaPoolController_;
        timelock = timelock_;
        weth = weth_;
    }

    modifier onlyTimelock() {
        if (msg.sender != timelock) revert OnlyTimelock(msg.sender);
        _;
    }

    /// @notice Executes the current allocation request for a Piggy Bank owned by the caller.
    /// @dev Preserves the V1 bridge ABI for clients that do not need a Delta deployment.
    function executeOwnerAllocation(
        uint256 tokenId,
        uint64 expectedRevision,
        CollectionPortfolioAllocator.RebalanceExecution calldata execution
    ) external nonReentrant returns (uint256 wethRecovered, uint256[3] memory shares) {
        return _executeOwnerAllocation(tokenId, expectedRevision, execution);
    }

    /// @notice Atomically applies an owner's saved allocation and deploys pooled Delta capital.
    function executeOwnerAllocationAndDeploy(
        uint256 tokenId,
        uint64 expectedRevision,
        CollectionPortfolioAllocator.RebalanceExecution calldata execution,
        address deltaPool
    )
        external
        nonReentrant
        returns (uint256 wethRecovered, uint256[3] memory shares, uint256 positionUnits)
    {
        (wethRecovered, shares) = _executeOwnerAllocation(tokenId, expectedRevision, execution);
        address activePool = allocator.activeDeltaPoolOf(tokenId);
        if (deltaPool != activePool) {
            revert DeltaPoolMismatch(tokenId, activePool, deltaPool);
        }
        (DeltaDeploymentPreview memory preview, bytes memory adapterData) =
            _buildDeltaDeployment(deltaPool);
        if (preview.ready) positionUnits = _deployIdleDelta(deltaPool, preview, adapterData);
    }

    /// @notice Permissionlessly places idle capital for a registered Delta sleeve.
    function deployIdleDelta(address pool) external nonReentrant returns (uint256 positionUnits) {
        _requireActiveRouter();
        (DeltaDeploymentPreview memory preview, bytes memory adapterData) =
            _buildDeltaDeployment(pool);
        if (!preview.ready) {
            revert DeltaDeploymentNotReady(
                preview.idleAssets, preview.managedAssets, preview.positionCount
            );
        }
        return _deployIdleDelta(pool, preview, adapterData);
    }

    /// @notice Returns the exact deterministic deployment that would be used now.
    function previewDeltaDeployment(address pool)
        external
        view
        returns (DeltaDeploymentPreview memory preview)
    {
        (preview,) = _buildDeltaDeployment(pool);
    }

    /// @notice Preserves collection-wide maintenance after this router becomes operator.
    function executeGovernanceCall(address target, bytes calldata data)
        external
        onlyTimelock
        nonReentrant
        returns (bytes memory result)
    {
        if (!_isGovernanceTarget(target) || data.length < 4) {
            revert InvalidGovernanceTarget(target);
        }
        (bool success, bytes memory returnData) = target.call(data);
        if (!success) revert GovernanceCallFailed(target, returnData);
        bytes4 selector;
        assembly ("memory-safe") {
            selector := calldataload(data.offset)
        }
        emit GovernanceCallExecuted(target, selector);
        return returnData;
    }

    function isGovernanceTarget(address target) external view returns (bool) {
        return _isGovernanceTarget(target);
    }

    function _executeOwnerAllocation(
        uint256 tokenId,
        uint64 expectedRevision,
        CollectionPortfolioAllocator.RebalanceExecution calldata execution
    ) private returns (uint256 wethRecovered, uint256[3] memory shares) {
        address currentOwner = nft.ownerOf(tokenId);
        if (currentOwner != msg.sender) {
            revert OnlyTokenOwner(tokenId, msg.sender, currentOwner);
        }
        _requireActiveRouter();
        (wethRecovered, shares) =
            allocator.executeTargetAllocation(tokenId, expectedRevision, execution);
        emit OwnerAllocationExecuted(
            tokenId, currentOwner, expectedRevision, wethRecovered, shares[0], shares[1], shares[2]
        );
    }

    function _deployIdleDelta(
        address pool,
        DeltaDeploymentPreview memory preview,
        bytes memory adapterData
    ) private returns (uint256 positionUnits) {
        positionUnits = allocator.depositToAdapter(
            preview.sleeve, preview.adapter, preview.assets, 1, adapterData
        );
        emit DeltaIdleCapitalDeployed(
            pool, preview.sleeve, msg.sender, preview.assets, positionUnits
        );
    }

    function _buildDeltaDeployment(address poolAddress)
        private
        view
        returns (DeltaDeploymentPreview memory preview, bytes memory adapterData)
    {
        CollectionPortfolioAllocator.DeltaPoolBinding memory binding =
            allocator.deltaPoolBinding(poolAddress);
        if (
            poolAddress == address(0) || binding.sleeve.code.length == 0
                || binding.adapter.code.length == 0
                || !allocator.deltaPoolController().isAllocationPool(poolAddress)
        ) revert InvalidDeltaPool(poolAddress);

        DeltaV3LPAdapter adapter = DeltaV3LPAdapter(binding.adapter);
        if (
            adapter.sleeve() != binding.sleeve || address(adapter.pool()) != poolAddress
                || address(adapter.weth()) != weth
        ) revert InvalidDeltaPool(poolAddress);

        uint256 idleAssets = IERC20(weth).balanceOf(binding.sleeve);
        uint256 assets = Math.mulDiv(idleAssets, IDLE_UTILIZATION_BPS, BPS);
        uint256 managedAssets = adapter.totalManagedAssets();
        uint256 positionCount = adapter.positionIds().length;
        bool ready = assets >= MINIMUM_DEPLOYMENT_ASSETS && assets <= idleAssets
            && positionCount < adapter.maximumPositions()
            && (positionCount == 0 || idleAssets >= managedAssets);
        if (!ready) {
            return (
                DeltaDeploymentPreview({
                    sleeve: binding.sleeve,
                    adapter: binding.adapter,
                    idleAssets: idleAssets,
                    assets: assets,
                    wethToConvert: 0,
                    minimumPairedAssetOut: 0,
                    tickLower: 0,
                    tickUpper: 0,
                    managedAssets: managedAssets,
                    positionCount: positionCount,
                    ready: false
                }),
                bytes("")
            );
        }
        uint256 wethToConvert = Math.mulDiv(assets, WETH_CONVERSION_BPS, BPS);
        uint256 minimumPairedAssetOut = _oracleMinimumPairedOut(adapter, wethToConvert);

        IYieldBankV3Pool pool = adapter.pool();
        (, int24 currentTick,,,,,) = pool.slot0();
        int24 spacing = pool.tickSpacing();
        if (spacing <= 0) revert UnsafeDeltaParameters();
        int24 alignedTick = currentTick / spacing * spacing;
        int24 halfWidth = spacing * RANGE_HALF_WIDTH_SPACINGS;
        int24 maximumDrift = spacing * MAXIMUM_SPOT_DRIFT_SPACINGS;
        if (
            alignedTick < TickMath.MIN_TICK + halfWidth
                || alignedTick > TickMath.MAX_TICK - halfWidth
        ) revert UnsafeDeltaParameters();

        uint256 wethForPosition = assets - wethToConvert;
        uint256 wethMinimum = Math.mulDiv(wethForPosition, MINIMUM_RUNG_FILL_BPS, BPS);
        uint256 pairedMinimum = Math.mulDiv(minimumPairedAssetOut, MINIMUM_RUNG_FILL_BPS, BPS);
        IDeltaPositionBuilder.Rung[] memory rungs = new IDeltaPositionBuilder.Rung[](1);
        rungs[0] = IDeltaPositionBuilder.Rung({
            tickLower: alignedTick - halfWidth,
            tickUpper: alignedTick + halfWidth,
            amount0: adapter.wethIsToken0() ? wethForPosition : minimumPairedAssetOut,
            amount1: adapter.wethIsToken0() ? minimumPairedAssetOut : wethForPosition,
            amount0Min: adapter.wethIsToken0() ? wethMinimum : pairedMinimum,
            amount1Min: adapter.wethIsToken0() ? pairedMinimum : wethMinimum
        });
        adapterData = abi.encode(
            DeltaV3LPAdapter.DepositParams({
                wethToConvert: wethToConvert,
                minimumPairedAssetOut: minimumPairedAssetOut,
                routeData: "",
                rungs: rungs,
                minimumCurrentTick: currentTick - maximumDrift,
                maximumCurrentTick: currentTick + maximumDrift,
                deadline: block.timestamp + MAXIMUM_DEADLINE_WINDOW
            })
        );
        preview = DeltaDeploymentPreview({
            sleeve: binding.sleeve,
            adapter: binding.adapter,
            idleAssets: idleAssets,
            assets: assets,
            wethToConvert: wethToConvert,
            minimumPairedAssetOut: minimumPairedAssetOut,
            tickLower: alignedTick - halfWidth,
            tickUpper: alignedTick + halfWidth,
            managedAssets: managedAssets,
            positionCount: positionCount,
            ready: true
        });
    }

    function _oracleMinimumPairedOut(DeltaV3LPAdapter adapter, uint256 wethAmount)
        private
        view
        returns (uint256 minimumPairedOut)
    {
        IPriceHub priceHub = adapter.priceHub();
        (uint256 wethPrice,, IPriceHub.FailureReason wethFailure) = priceHub.quoteUsd18(weth);
        address pairedAsset = address(adapter.pairedAsset());
        (uint256 pairedPrice,, IPriceHub.FailureReason pairedFailure) =
            priceHub.quoteUsd18(pairedAsset);
        if (
            wethFailure != IPriceHub.FailureReason.NONE
                || pairedFailure != IPriceHub.FailureReason.NONE || wethPrice == 0
                || pairedPrice == 0
        ) revert UnsafeDeltaParameters();

        uint256 valueUsd18 = Math.mulDiv(wethAmount, wethPrice, 10 ** adapter.wethDecimals());
        uint256 oraclePairedOut =
            Math.mulDiv(valueUsd18, 10 ** adapter.pairedAssetDecimals(), pairedPrice);
        minimumPairedOut = Math.mulDiv(oraclePairedOut, BPS - MAXIMUM_SWAP_SLIPPAGE_BPS, BPS);
        if (minimumPairedOut == 0) revert UnsafeDeltaParameters();
    }

    function _requireActiveRouter() private view {
        address currentOperator = allocator.allocationOperator();
        if (currentOperator != address(this)) revert RouterNotActive(currentOperator);
    }

    function _isGovernanceTarget(address target) private view returns (bool) {
        return target == address(allocator) || target == proceedsVault || target == revenueRouter
            || target == deltaPoolController;
    }
}
