// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Time } from "@openzeppelin/contracts/utils/types/Time.sol";
import { IProjectControlled } from "../interfaces/IProjectControlled.sol";
import { IProjectFundable } from "../interfaces/IProjectFundable.sol";
import { IProjectModule } from "../interfaces/IProjectModule.sol";
import { IProjectPriceGuard } from "../interfaces/IProjectPriceGuard.sol";
import { IProjectRegistryView } from "../interfaces/IProjectRegistryView.sol";
import { IProjectSwapAdapter } from "../interfaces/IProjectSwapAdapter.sol";
import { IProjectTokenIdentity } from "../interfaces/IProjectTokenIdentity.sol";
import { IProjectTreasuryReceiver } from "../interfaces/IProjectTreasuryReceiver.sol";
import { ProjectIds } from "../libraries/ProjectIds.sol";
import { SinjohV2Constants } from "../libraries/SinjohV2Constants.sol";
import {
    RouterAction,
    RouterActionType,
    RouterRouteInput,
    RouterSwapConfig
} from "./RouterTypes.sol";

interface IProjectBurnableToken is IERC20 {
    function burn(uint256 amount) external;
}

/// @notice Project revenue Router with immutable typed destinations and versioned allocation plans.
/// @dev There is no generic call action. Failed shares remain exact same-asset/version escrow.
contract ProjectRouterV2 is IProjectModule, IProjectControlled, IProjectFundable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public constant NATIVE_ASSET = address(0);
    address public constant BURN_ADDRESS = SinjohV2Constants.BURN_ADDRESS;
    uint16 public constant BPS = 10_000;
    uint16 public constant PROTOCOL_FEE_BPS = 100;
    uint256 public constant MAX_ACTIONS = 16;
    uint256 public constant MAX_INITIAL_ROUTES = 16;
    uint256 public constant MAX_INITIAL_ROUTE_DATA_BYTES = 16_384;
    uint256 public constant MAX_ACTION_CONFIG_BYTES = 4_096;
    uint256 public constant MAX_TOTAL_CONFIG_BYTES = 24_576;
    bytes32 public constant SWAP_APPROVAL_DOMAIN = keccak256("SINJOH_V2_ROUTER_SWAP_APPROVAL");
    bytes32 public constant PAUSED_REASON_HASH = keccak256("SINJOH_V2_ROUTER_ACTION_PAUSED");

    struct RouteHeader {
        uint64 version;
        uint48 activatedAt;
        uint8 actionCount;
        bytes32 routeHash;
        uint256 totalRouted;
        bool exists;
    }

    address public immutable override registry;
    address public immutable override subject;
    address public immutable creator;
    bytes32 public immutable override(IProjectModule, IProjectControlled) projectId;
    address public immutable override controller;
    address public immutable protocolFeeRecipient;
    address public immutable treasury;
    address public immutable airdrop;
    address public immutable raffle;
    address public immutable liquidityManager;
    bytes32 public immutable integrationApprovalRoot;
    bool public launchRoutesInitialized;

    mapping(address asset => uint256 amount) public pending;
    mapping(address asset => uint256 amount) public totalEscrowed;
    mapping(address asset => uint256 amount) public protocolOwed;
    mapping(address asset => uint16 remainder) public protocolFeeRemainder;
    mapping(address asset => uint64 version) public activeRouteVersion;
    mapping(address asset => mapping(uint64 version => RouteHeader header)) private _routeHeaders;
    mapping(address asset => mapping(uint64 version => RouterAction[] actions)) private
        _routeActions;
    mapping(
        address asset => mapping(uint64 version => mapping(uint256 index => uint256 amount))
    ) private _allocated;
    mapping(address asset => mapping(uint64 version => mapping(uint256 index => bool paused)))
        public actionPaused;
    mapping(
        address asset => mapping(uint64 version => mapping(uint256 index => uint256 amount))
    ) public escrowed;

    error OnlyController(address caller);
    error OnlyLauncher(address caller);
    error LaunchWindowClosed();
    error LaunchRoutesAlreadyInitialized();
    error OnlySelf(address caller);
    error InvalidRegistry(address candidate);
    error InvalidSubject(address candidate);
    error InvalidCreator(address candidate);
    error InvalidController(address candidate);
    error InvalidFeeRecipient(address candidate);
    error ProjectIdentityMismatch(bytes32 expected, bytes32 actual);
    error InvalidDestination(address destination);
    error DestinationIdentityMismatch(address destination);
    error InvalidFundingIdentity(bytes32 projectId, address subject);
    error InvalidFundingConfig();
    error InvalidAsset(address asset);
    error InvalidAmount(uint256 supplied);
    error NativeValueMismatch(uint256 expected, uint256 supplied);
    error InexactAssetReceipt(address asset, uint256 expected, uint256 measured);
    error InexactAssetSpend(address asset, uint256 expected, uint256 measured);
    error AssetUnderbacked(address asset, uint256 measured, uint256 liability);
    error NoSurplus(address asset);
    error NoPending(address asset);
    error NoProtocolFee(address asset);
    error NoActiveRoute(address asset);
    error UnknownRoute(address asset, uint64 version);
    error InvalidActionCount(uint256 supplied);
    error InvalidAllocation(uint256 index, uint16 supplied);
    error InvalidAllocationTotal(uint256 supplied);
    error ActionConfigTooLarge(uint256 index, uint256 supplied);
    error TotalConfigTooLarge(uint256 supplied);
    error InvalidAction(uint256 index, RouterActionType actionType);
    error InvalidRecipient(uint256 index, address recipient);
    error InvalidIntegration(uint256 index, address adapter, address priceGuard);
    error IntegrationNotApproved(uint256 index, bytes32 leaf);
    error SinkNotRegistered(address sink);
    error RouteAlreadyConfigured(address asset);
    error InitialRouteDataTooLarge(uint256 supplied, uint256 maximum);
    error InputArrayLengthMismatch(uint256 actions, uint256 minima, uint256 guardData);
    error InvalidGuardMinimum(uint256 supplied);
    error GuardQuoteExpired(uint48 validUntil, uint48 currentTime);
    error InsufficientSwapOutput(uint256 minimum, uint256 measured);
    error ActionAlreadyPaused(uint256 index);
    error ActionNotPaused(uint256 index);
    error ActionIsPaused(uint256 index);
    error NoEscrow(address asset, uint64 version, uint256 index);
    error InvalidRecoveryTarget(address asset, uint64 version, uint256 index);
    error NativeTransferFailed(address recipient, uint256 amount);
    error InexactBurn(uint256 expected, uint256 measured);
    error InexactSinkFunding(uint256 expected, uint256 reported);

    event RouterCreated(
        bytes32 indexed projectId,
        address indexed subject,
        address indexed controller,
        address creator,
        address protocolFeeRecipient,
        bytes32 integrationApprovalRoot
    );
    event Funded(
        bytes32 indexed projectId,
        address indexed source,
        address indexed asset,
        uint256 gross,
        uint256 protocolFee,
        uint256 net,
        bool attributed
    );
    event RouteActivated(address indexed asset, uint64 indexed version, bytes32 routeHash);
    event RoutePaused(address indexed asset, uint64 indexed version, uint256 indexed actionIndex);
    event RouteResumed(address indexed asset, uint64 indexed version, uint256 indexed actionIndex);
    event ActionExecuted(
        address indexed asset,
        uint64 indexed version,
        uint256 indexed actionIndex,
        uint256 amountIn,
        address assetOut,
        uint256 amountOut
    );
    event ActionEscrowed(
        address indexed asset,
        uint64 indexed version,
        uint256 indexed actionIndex,
        uint256 amount,
        bytes32 reasonHash
    );
    event EscrowRetried(
        address indexed asset,
        uint64 indexed version,
        uint256 indexed actionIndex,
        uint256 amount,
        bool succeeded,
        bytes32 reasonHash
    );
    event EscrowRecovered(
        address indexed asset,
        uint64 indexed fromVersion,
        uint256 indexed fromActionIndex,
        uint64 toVersion,
        uint256 toActionIndex,
        uint256 amount
    );
    event ProtocolFeeSent(address indexed asset, uint256 amount);
    event RawNativeReceived(address indexed sender, uint256 amount);

    modifier onlyController() {
        if (msg.sender != controller) revert OnlyController(msg.sender);
        _;
    }

    modifier onlySelf() {
        if (msg.sender != address(this)) revert OnlySelf(msg.sender);
        _;
    }

    constructor(
        address registry_,
        address subject_,
        address creator_,
        address controller_,
        address protocolFeeRecipient_,
        address treasury_,
        address airdrop_,
        address raffle_,
        address liquidityManager_,
        bytes32 integrationApprovalRoot_,
        RouterRouteInput[] memory initialRoutes
    ) {
        if (registry_.code.length == 0) {
            revert InvalidRegistry(registry_);
        }
        if (subject_.code.length == 0) revert InvalidSubject(subject_);
        if (creator_ == address(0) || creator_ == BURN_ADDRESS) revert InvalidCreator(creator_);
        if (controller_.code.length == 0 || controller_ == BURN_ADDRESS) {
            revert InvalidController(controller_);
        }
        if (
            protocolFeeRecipient_ == address(0) || protocolFeeRecipient_ == BURN_ADDRESS
                || protocolFeeRecipient_ == address(this)
        ) revert InvalidFeeRecipient(protocolFeeRecipient_);

        bytes32 expectedProjectId = ProjectIds.derive(block.chainid, registry_, subject_);
        bytes32 actualProjectId = IProjectTokenIdentity(subject_).projectId();
        if (
            IProjectTokenIdentity(subject_).registry() != registry_
                || actualProjectId != expectedProjectId
        ) revert ProjectIdentityMismatch(expectedProjectId, actualProjectId);
        if (
            IProjectControlled(controller_).projectId() != expectedProjectId
                || IProjectControlled(controller_).controller() != controller_
        ) revert InvalidController(controller_);

        registry = registry_;
        subject = subject_;
        creator = creator_;
        projectId = expectedProjectId;
        controller = controller_;
        protocolFeeRecipient = protocolFeeRecipient_;
        treasury = treasury_;
        airdrop = airdrop_;
        raffle = raffle_;
        liquidityManager = liquidityManager_;
        integrationApprovalRoot = integrationApprovalRoot_;

        _validateDestination(treasury_, true);
        _validateDestination(airdrop_, false);
        _validateDestination(raffle_, false);
        _validateDestination(liquidityManager_, false);
        _configureInitialRoutes(initialRoutes);
        if (initialRoutes.length != 0) launchRoutesInitialized = true;

        emit RouterCreated(
            expectedProjectId,
            subject_,
            controller_,
            creator_,
            protocolFeeRecipient_,
            integrationApprovalRoot_
        );
    }

    /// @notice Applies the complete creator-selected route set inside the atomic launch.
    /// @dev Registration permanently closes this permission; governance owns all later versions.
    function initializeRoutesFromLauncher(RouterRouteInput[] calldata initialRoutes)
        external
        nonReentrant
    {
        if (msg.sender != IProjectRegistryView(registry).launcher()) {
            revert OnlyLauncher(msg.sender);
        }
        if (IProjectRegistryView(registry).projectIdBySubject(subject) != bytes32(0)) {
            revert LaunchWindowClosed();
        }
        if (launchRoutesInitialized) revert LaunchRoutesAlreadyInitialized();

        launchRoutesInitialized = true;
        _configureInitialRoutes(initialRoutes);
    }

    function _configureInitialRoutes(RouterRouteInput[] memory initialRoutes) private {
        uint256 initialRouteDataLength = abi.encode(initialRoutes).length;
        if (initialRouteDataLength > MAX_INITIAL_ROUTE_DATA_BYTES) {
            revert InitialRouteDataTooLarge(initialRouteDataLength, MAX_INITIAL_ROUTE_DATA_BYTES);
        }
        uint256 routeCount = initialRoutes.length;
        if (routeCount > MAX_INITIAL_ROUTES) revert InvalidActionCount(routeCount);
        for (uint256 i; i < routeCount; ++i) {
            if (activeRouteVersion[initialRoutes[i].inputAsset] != 0) {
                revert RouteAlreadyConfigured(initialRoutes[i].inputAsset);
            }
            _activateRoute(initialRoutes[i]);
        }
    }

    receive() external payable {
        emit RawNativeReceived(msg.sender, msg.value);
    }

    function fund(
        bytes32 projectId_,
        address subject_,
        address asset,
        uint256 amount,
        bytes calldata config
    ) external payable nonReentrant returns (uint256 received) {
        if (projectId_ != projectId || subject_ != subject) {
            revert InvalidFundingIdentity(projectId_, subject_);
        }
        if (config.length != 0) revert InvalidFundingConfig();
        if (amount == 0) revert InvalidAmount(amount);
        _validateAsset(asset);
        if (asset == NATIVE_ASSET) {
            if (msg.value != amount) revert NativeValueMismatch(amount, msg.value);
            uint256 measuredBefore = address(this).balance - msg.value;
            uint256 liabilityBefore = totalLiability(asset);
            if (measuredBefore < liabilityBefore) {
                revert AssetUnderbacked(asset, measuredBefore, liabilityBefore);
            }
            received = amount;
        } else {
            _validateErc20(asset);
            if (msg.value != 0) revert NativeValueMismatch(0, msg.value);
            _assertBacked(asset);
            uint256 beforeBalance = IERC20(asset).balanceOf(address(this));
            IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
            received = IERC20(asset).balanceOf(address(this)) - beforeBalance;
            if (received != amount) revert InexactAssetReceipt(asset, amount, received);
        }
        _creditIntake(asset, received, msg.sender, true);
    }

    function sync(address asset) external nonReentrant returns (uint256 surplus, uint256 net) {
        _validateAsset(asset);
        uint256 measured = _measuredBalance(asset);
        uint256 liability = totalLiability(asset);
        if (measured < liability) revert AssetUnderbacked(asset, measured, liability);
        surplus = measured - liability;
        if (surplus == 0) revert NoSurplus(asset);
        net = _creditIntake(asset, surplus, msg.sender, false);
    }

    function sendProtocolFee(address asset, uint256 maxAmount)
        external
        nonReentrant
        returns (uint256 amount)
    {
        if (maxAmount == 0) revert InvalidAmount(0);
        uint256 owed = protocolOwed[asset];
        if (owed == 0) revert NoProtocolFee(asset);
        amount = Math.min(owed, maxAmount);
        protocolOwed[asset] = owed - amount;
        _sendExact(asset, protocolFeeRecipient, amount);
        emit ProtocolFeeSent(asset, amount);
    }

    function activateRoute(RouterRouteInput calldata route) external nonReentrant onlyController {
        _activateRoute(route);
    }

    function pauseAction(address asset, uint64 version, uint256 actionIndex)
        external
        nonReentrant
        onlyController
    {
        _requireAction(asset, version, actionIndex);
        if (actionPaused[asset][version][actionIndex]) revert ActionAlreadyPaused(actionIndex);
        actionPaused[asset][version][actionIndex] = true;
        emit RoutePaused(asset, version, actionIndex);
    }

    function resumeAction(address asset, uint64 version, uint256 actionIndex)
        external
        nonReentrant
        onlyController
    {
        _requireAction(asset, version, actionIndex);
        if (!actionPaused[asset][version][actionIndex]) revert ActionNotPaused(actionIndex);
        actionPaused[asset][version][actionIndex] = false;
        emit RouteResumed(asset, version, actionIndex);
    }

    function execute(
        address asset,
        uint256 maxAmount,
        uint256[] calldata callerMinOuts,
        bytes[] calldata guardData
    ) external nonReentrant returns (uint256 batchAmount) {
        if (maxAmount == 0) revert InvalidAmount(0);
        uint64 version = _activeVersion(asset);
        RouteHeader storage header = _routeHeaders[asset][version];
        uint256 count = header.actionCount;
        if (callerMinOuts.length != count || guardData.length != count) {
            revert InputArrayLengthMismatch(count, callerMinOuts.length, guardData.length);
        }
        uint256 available = pending[asset];
        if (available == 0) revert NoPending(asset);
        batchAmount = Math.min(available, maxAmount);
        pending[asset] = available - batchAmount;
        uint256[] memory shares = _allocateBatch(asset, version, batchAmount);
        for (uint256 i; i < count; ++i) {
            uint256 share = shares[i];
            if (share == 0) continue;
            if (actionPaused[asset][version][i]) {
                _recordEscrow(asset, version, i, share, PAUSED_REASON_HASH);
                continue;
            }
            (bool succeeded, address assetOut, uint256 amountOut, bytes32 reasonHash) =
                _isolatedExecute(asset, version, i, share, callerMinOuts[i], guardData[i]);
            if (succeeded) {
                emit ActionExecuted(asset, version, i, share, assetOut, amountOut);
            } else {
                _recordEscrow(asset, version, i, share, reasonHash);
            }
        }
    }

    function retryEscrow(
        address asset,
        uint64 version,
        uint256 actionIndex,
        uint256 maxAmount,
        uint256 callerMinOut,
        bytes calldata guardData
    ) external nonReentrant returns (uint256 amount, bool succeeded) {
        if (maxAmount == 0) revert InvalidAmount(0);
        _requireAction(asset, version, actionIndex);
        if (actionPaused[asset][version][actionIndex]) revert ActionIsPaused(actionIndex);
        uint256 current = escrowed[asset][version][actionIndex];
        if (current == 0) revert NoEscrow(asset, version, actionIndex);
        amount = Math.min(current, maxAmount);
        escrowed[asset][version][actionIndex] = current - amount;
        totalEscrowed[asset] -= amount;
        address assetOut;
        uint256 amountOut;
        bytes32 reasonHash;
        (succeeded, assetOut, amountOut, reasonHash) =
            _isolatedExecute(asset, version, actionIndex, amount, callerMinOut, guardData);
        if (succeeded) {
            emit ActionExecuted(asset, version, actionIndex, amount, assetOut, amountOut);
        } else {
            escrowed[asset][version][actionIndex] += amount;
            totalEscrowed[asset] += amount;
        }
        emit EscrowRetried(asset, version, actionIndex, amount, succeeded, reasonHash);
    }

    function recoverEscrow(
        address asset,
        uint64 fromVersion,
        uint256 fromActionIndex,
        uint256 maxAmount,
        uint256 toActionIndex
    ) external nonReentrant onlyController returns (uint256 amount) {
        if (maxAmount == 0) revert InvalidAmount(0);
        _requireAction(asset, fromVersion, fromActionIndex);
        uint64 toVersion = _activeVersion(asset);
        _requireAction(asset, toVersion, toActionIndex);
        if (fromVersion == toVersion && fromActionIndex == toActionIndex) {
            revert InvalidRecoveryTarget(asset, toVersion, toActionIndex);
        }
        uint256 current = escrowed[asset][fromVersion][fromActionIndex];
        if (current == 0) revert NoEscrow(asset, fromVersion, fromActionIndex);
        amount = Math.min(current, maxAmount);
        escrowed[asset][fromVersion][fromActionIndex] = current - amount;
        escrowed[asset][toVersion][toActionIndex] += amount;
        emit EscrowRecovered(asset, fromVersion, fromActionIndex, toVersion, toActionIndex, amount);
    }

    function executeAction(
        address asset,
        uint64 version,
        uint256 actionIndex,
        uint256 amount,
        uint256 callerMinOut,
        bytes calldata guardData
    ) external onlySelf returns (address assetOut, uint256 amountOut) {
        RouterAction storage action = _routeActions[asset][version][actionIndex];
        RouterActionType actionType = action.actionType;
        if (actionType == RouterActionType.SEND) {
            _sendExact(asset, action.recipient, amount);
            return (asset, amount);
        }
        if (actionType == RouterActionType.SWAP_AND_SEND) {
            RouterSwapConfig memory swapConfig = abi.decode(action.actionConfig, (RouterSwapConfig));
            amountOut = _swap(action, asset, amount, callerMinOut, guardData, swapConfig);
            _sendExact(swapConfig.outputAsset, action.recipient, amountOut);
            return (swapConfig.outputAsset, amountOut);
        }
        if (actionType == RouterActionType.BURN_PROJECT_TOKEN) {
            amountOut = amount;
            if (asset != subject) {
                RouterSwapConfig memory swapConfig =
                    abi.decode(action.actionConfig, (RouterSwapConfig));
                amountOut = _swap(action, asset, amount, callerMinOut, guardData, swapConfig);
            }
            uint256 supplyBefore = IERC20(subject).totalSupply();
            IProjectBurnableToken(subject).burn(amountOut);
            uint256 burned = supplyBefore - IERC20(subject).totalSupply();
            if (burned != amountOut) revert InexactBurn(amountOut, burned);
            return (subject, amountOut);
        }
        if (actionType == RouterActionType.FUND_TREASURY) {
            bool routeToBasket = abi.decode(action.actionConfig, (bool));
            _fundTreasury(asset, amount, routeToBasket);
            return (asset, amount);
        }
        bytes memory sinkConfig = action.actionConfig;
        if (actionType == RouterActionType.FUND_PROJECT_SINK) {
            if (!IProjectRegistryView(registry).isProjectModule(projectId, action.recipient)) {
                revert SinkNotRegistered(action.recipient);
            }
        }
        _fundSink(action.recipient, asset, amount, sinkConfig);
        return (asset, amount);
    }

    function totalLiability(address asset) public view returns (uint256) {
        return pending[asset] + totalEscrowed[asset] + protocolOwed[asset];
    }

    function isAssetBacked(address asset) external view returns (bool) {
        return _measuredBalance(asset) >= totalLiability(asset);
    }

    function routeHeader(address asset, uint64 version) external view returns (RouteHeader memory) {
        RouteHeader memory header = _routeHeaders[asset][version];
        if (!header.exists) revert UnknownRoute(asset, version);
        return header;
    }

    function activeRoute(address asset)
        external
        view
        returns (RouteHeader memory header, RouterAction[] memory actions)
    {
        uint64 version = _activeVersion(asset);
        return (_routeHeaders[asset][version], _routeActions[asset][version]);
    }

    function routeActions(address asset, uint64 version)
        external
        view
        returns (RouterAction[] memory)
    {
        if (!_routeHeaders[asset][version].exists) revert UnknownRoute(asset, version);
        return _routeActions[asset][version];
    }

    function routeAction(address asset, uint64 version, uint256 index)
        external
        view
        returns (RouterAction memory)
    {
        _requireAction(asset, version, index);
        return _routeActions[asset][version][index];
    }

    function allocatedToAction(address asset, uint64 version, uint256 index)
        external
        view
        returns (uint256)
    {
        _requireAction(asset, version, index);
        return _allocated[asset][version][index];
    }

    function actionStatus(address asset, uint64 version, uint256 index)
        external
        view
        returns (
            RouterAction memory action,
            bool paused,
            uint256 cumulativeAllocation,
            uint256 retryableEscrow
        )
    {
        _requireAction(asset, version, index);
        return (
            _routeActions[asset][version][index],
            actionPaused[asset][version][index],
            _allocated[asset][version][index],
            escrowed[asset][version][index]
        );
    }

    function projectedAllocations(address asset, uint64 version, uint256 amount)
        external
        view
        returns (uint256[] memory)
    {
        if (!_routeHeaders[asset][version].exists) revert UnknownRoute(asset, version);
        return _projectAllocations(asset, version, amount);
    }

    function workStatus(address asset)
        external
        view
        returns (
            uint64 routeVersion,
            uint256 pendingAmount,
            uint256 escrowAmount,
            uint256 feeAmount
        )
    {
        return (
            activeRouteVersion[asset], pending[asset], totalEscrowed[asset], protocolOwed[asset]
        );
    }

    function swapApprovalLeaf(
        address adapter,
        address priceGuard,
        address assetIn,
        address assetOut,
        bytes32 routeHash
    ) public view returns (bytes32) {
        bytes32 inner = keccak256(
            abi.encode(
                SWAP_APPROVAL_DOMAIN,
                block.chainid,
                adapter.codehash,
                priceGuard.codehash,
                assetIn,
                assetOut,
                routeHash
            )
        );
        return keccak256(bytes.concat(inner));
    }

    function isSwapApproved(
        address adapter,
        address priceGuard,
        address assetIn,
        address assetOut,
        bytes32 routeHash,
        bytes32[] calldata proof
    ) external view returns (bool) {
        if (
            integrationApprovalRoot == bytes32(0) || adapter.code.length == 0
                || priceGuard.code.length == 0
        ) return false;
        return MerkleProof.verifyCalldata(
            proof,
            integrationApprovalRoot,
            swapApprovalLeaf(adapter, priceGuard, assetIn, assetOut, routeHash)
        );
    }

    function isSinkApproved(address sink) external view returns (bool) {
        return
            sink.code.length != 0 && IProjectRegistryView(registry).isProjectModule(projectId, sink);
    }

    function _activateRoute(RouterRouteInput memory route) private {
        _validateAsset(route.inputAsset);
        uint256 count = route.actions.length;
        if (count == 0 || count > MAX_ACTIONS) revert InvalidActionCount(count);
        uint256 allocationTotal;
        uint256 configTotal;
        for (uint256 i; i < count; ++i) {
            RouterAction memory action = route.actions[i];
            if (action.allocationBps == 0) revert InvalidAllocation(i, action.allocationBps);
            allocationTotal += action.allocationBps;
            uint256 configLength = action.actionConfig.length;
            if (configLength > MAX_ACTION_CONFIG_BYTES) {
                revert ActionConfigTooLarge(i, configLength);
            }
            configTotal += configLength;
            _validateAction(route.inputAsset, i, action);
        }
        if (allocationTotal != BPS) revert InvalidAllocationTotal(allocationTotal);
        if (configTotal > MAX_TOTAL_CONFIG_BYTES) revert TotalConfigTooLarge(configTotal);

        uint64 version = activeRouteVersion[route.inputAsset] + 1;
        activeRouteVersion[route.inputAsset] = version;
        bytes32 routeHash = keccak256(
            abi.encode(block.chainid, address(this), projectId, route.inputAsset, route.actions)
        );
        RouteHeader storage header = _routeHeaders[route.inputAsset][version];
        header.version = version;
        header.activatedAt = Time.timestamp();
        // `count` is bounded to MAX_ACTIONS (16) above.
        // forge-lint: disable-next-line(unsafe-typecast)
        header.actionCount = uint8(count);
        header.routeHash = routeHash;
        header.exists = true;
        for (uint256 i; i < count; ++i) {
            _routeActions[route.inputAsset][version].push(route.actions[i]);
        }
        emit RouteActivated(route.inputAsset, version, routeHash);
    }

    function _validateAction(address inputAsset, uint256 index, RouterAction memory action)
        private
        view
    {
        RouterActionType actionType = action.actionType;
        if (actionType == RouterActionType.SEND) {
            _validateRecipient(index, action.recipient);
            if (
                action.adapter != address(0) || action.priceGuard != address(0)
                    || action.actionConfig.length != 0
            ) revert InvalidAction(index, actionType);
            return;
        }
        if (actionType == RouterActionType.SWAP_AND_SEND) {
            _validateRecipient(index, action.recipient);
            _validateSwapAction(inputAsset, index, action, false);
            return;
        }
        if (actionType == RouterActionType.BURN_PROJECT_TOKEN) {
            if (action.recipient != address(0)) revert InvalidRecipient(index, action.recipient);
            if (inputAsset == subject) {
                if (
                    action.adapter != address(0) || action.priceGuard != address(0)
                        || action.actionConfig.length != 0
                ) revert InvalidAction(index, actionType);
            } else {
                _validateSwapAction(inputAsset, index, action, true);
            }
            return;
        }
        if (
            action.adapter != address(0) || action.priceGuard != address(0)
                || action.recipient.code.length == 0
        ) revert InvalidAction(index, actionType);
        if (actionType == RouterActionType.ADD_LIQUIDITY) {
            if (action.recipient != liquidityManager || liquidityManager == address(0)) {
                revert InvalidRecipient(index, action.recipient);
            }
            return;
        }
        if (actionType == RouterActionType.FUND_AIRDROP) {
            if (action.recipient != airdrop || airdrop == address(0)) {
                revert InvalidRecipient(index, action.recipient);
            }
            return;
        }
        if (actionType == RouterActionType.FUND_RAFFLE) {
            if (action.recipient != raffle || raffle == address(0)) {
                revert InvalidRecipient(index, action.recipient);
            }
            return;
        }
        if (actionType == RouterActionType.FUND_TREASURY) {
            if (action.recipient != treasury || treasury == address(0)) {
                revert InvalidRecipient(index, action.recipient);
            }
            abi.decode(action.actionConfig, (bool));
            return;
        }
        if (actionType == RouterActionType.FUND_PROJECT_SINK) {
            _validateProjectModule(action.recipient);
            return;
        }
        revert InvalidAction(index, actionType);
    }

    function _validateSwapAction(
        address inputAsset,
        uint256 index,
        RouterAction memory action,
        bool burn
    ) private view {
        if (action.adapter.code.length == 0 || action.priceGuard.code.length == 0) {
            revert InvalidIntegration(index, action.adapter, action.priceGuard);
        }
        RouterSwapConfig memory swapConfig = abi.decode(action.actionConfig, (RouterSwapConfig));
        _validateAsset(swapConfig.outputAsset);
        if (swapConfig.outputAsset == inputAsset || (burn && swapConfig.outputAsset != subject)) {
            revert InvalidAction(index, action.actionType);
        }
        bytes32 leaf = swapApprovalLeaf(
            action.adapter,
            action.priceGuard,
            inputAsset,
            swapConfig.outputAsset,
            keccak256(swapConfig.routeData)
        );
        if (
            integrationApprovalRoot == bytes32(0)
                || !MerkleProof.verify(swapConfig.approvalProof, integrationApprovalRoot, leaf)
        ) revert IntegrationNotApproved(index, leaf);
    }

    function _allocateBatch(address asset, uint64 version, uint256 batchAmount)
        private
        returns (uint256[] memory shares)
    {
        RouteHeader storage header = _routeHeaders[asset][version];
        shares = _projectAllocations(asset, version, batchAmount);
        header.totalRouted += batchAmount;
        for (uint256 i; i < shares.length; ++i) {
            _allocated[asset][version][i] += shares[i];
        }
    }

    function _projectAllocations(address asset, uint64 version, uint256 batchAmount)
        private
        view
        returns (uint256[] memory shares)
    {
        RouteHeader storage header = _routeHeaders[asset][version];
        uint256 count = header.actionCount;
        shares = new uint256[](count);
        uint256 cumulativeAfter = header.totalRouted + batchAmount;
        uint256 cumulativeBps;
        uint256 totalTarget;
        for (uint256 i; i < count; ++i) {
            cumulativeBps += _routeActions[asset][version][i].allocationBps;
            uint256 target =
                i + 1 == count ? cumulativeAfter : Math.mulDiv(cumulativeAfter, cumulativeBps, BPS);
            shares[i] = target - totalTarget - _allocated[asset][version][i];
            totalTarget = target;
        }
    }

    function _swap(
        RouterAction storage action,
        address assetIn,
        uint256 amountIn,
        uint256 callerMinOut,
        bytes calldata guardData,
        RouterSwapConfig memory swapConfig
    ) private returns (uint256 amountOut) {
        bytes32 routeHash = keccak256(swapConfig.routeData);
        (uint256 guardMinOut, uint48 validUntil) = IProjectPriceGuard(action.priceGuard)
            .minimumOutput(assetIn, swapConfig.outputAsset, amountIn, routeHash, guardData);
        if (guardMinOut == 0) revert InvalidGuardMinimum(guardMinOut);
        uint48 currentTime = Time.timestamp();
        if (validUntil < currentTime) revert GuardQuoteExpired(validUntil, currentTime);
        uint256 minimum = Math.max(guardMinOut, callerMinOut);
        uint256 beforeInput = _measuredBalance(assetIn);
        uint256 beforeOutput = _measuredBalance(swapConfig.outputAsset);
        if (assetIn == NATIVE_ASSET) {
            IProjectSwapAdapter(action.adapter).swap{ value: amountIn }(
                assetIn, swapConfig.outputAsset, amountIn, minimum, swapConfig.routeData
            );
        } else {
            IERC20(assetIn).forceApprove(action.adapter, amountIn);
            IProjectSwapAdapter(action.adapter)
                .swap(assetIn, swapConfig.outputAsset, amountIn, minimum, swapConfig.routeData);
            IERC20(assetIn).forceApprove(action.adapter, 0);
        }
        uint256 afterInput = _measuredBalance(assetIn);
        uint256 spent = beforeInput >= afterInput ? beforeInput - afterInput : 0;
        if (spent != amountIn) revert InexactAssetSpend(assetIn, amountIn, spent);
        uint256 afterOutput = _measuredBalance(swapConfig.outputAsset);
        amountOut = afterOutput >= beforeOutput ? afterOutput - beforeOutput : 0;
        if (amountOut < minimum) revert InsufficientSwapOutput(minimum, amountOut);
    }

    function _fundTreasury(address asset, uint256 amount, bool routeToBasket) private {
        uint256 beforeBalance = _measuredBalance(asset);
        if (asset == NATIVE_ASSET) {
            IProjectTreasuryReceiver(treasury).depositNative{ value: amount }(routeToBasket);
        } else {
            IERC20(asset).forceApprove(treasury, amount);
            IProjectTreasuryReceiver(treasury).deposit(asset, amount, routeToBasket);
            IERC20(asset).forceApprove(treasury, 0);
        }
        _requireExactSpend(asset, beforeBalance, amount);
    }

    function _fundSink(address sink, address asset, uint256 amount, bytes memory config) private {
        uint256 beforeBalance = _measuredBalance(asset);
        uint256 reported;
        if (asset == NATIVE_ASSET) {
            reported = IProjectFundable(sink).fund{ value: amount }(
                projectId, subject, asset, amount, config
            );
        } else {
            IERC20(asset).forceApprove(sink, amount);
            reported = IProjectFundable(sink).fund(projectId, subject, asset, amount, config);
            IERC20(asset).forceApprove(sink, 0);
        }
        if (reported != amount) revert InexactSinkFunding(amount, reported);
        _requireExactSpend(asset, beforeBalance, amount);
    }

    function _sendExact(address asset, address recipient, uint256 amount) private {
        uint256 beforeRouter = _measuredBalance(asset);
        if (asset == NATIVE_ASSET) {
            (bool success,) = recipient.call{ value: amount }("");
            if (!success) revert NativeTransferFailed(recipient, amount);
        } else {
            uint256 beforeRecipient = IERC20(asset).balanceOf(recipient);
            IERC20(asset).safeTransfer(recipient, amount);
            uint256 received = IERC20(asset).balanceOf(recipient) - beforeRecipient;
            if (received != amount) revert InexactAssetReceipt(asset, amount, received);
        }
        _requireExactSpend(asset, beforeRouter, amount);
    }

    function _creditIntake(address asset, uint256 gross, address source, bool attributed)
        private
        returns (uint256 net)
    {
        (uint256 fee, uint16 nextRemainder) = _accrueProtocolFee(gross, protocolFeeRemainder[asset]);
        protocolFeeRemainder[asset] = nextRemainder;
        protocolOwed[asset] += fee;
        net = gross - fee;
        pending[asset] += net;
        emit Funded(projectId, source, asset, gross, fee, net, attributed);
    }

    function _accrueProtocolFee(uint256 amount, uint16 remainder)
        private
        pure
        returns (uint256 fee, uint16 nextRemainder)
    {
        uint256 scaledRemainder = (amount % BPS) * PROTOCOL_FEE_BPS + remainder;
        // Quotient/remainder decomposition avoids overflow without losing cumulative precision.
        // forge-lint: disable-next-line(divide-before-multiply)
        fee = (amount / BPS) * PROTOCOL_FEE_BPS + scaledRemainder / BPS;
        // The modulo result is strictly below BPS and therefore fits uint16.
        // forge-lint: disable-next-line(unsafe-typecast)
        nextRemainder = uint16(scaledRemainder % BPS);
    }

    /// @dev Calls the typed self-entrypoint without copying unbounded downstream revert data.
    function _isolatedExecute(
        address asset,
        uint64 version,
        uint256 actionIndex,
        uint256 amount,
        uint256 callerMinOut,
        bytes calldata guardData
    ) private returns (bool succeeded, address assetOut, uint256 amountOut, bytes32 reasonHash) {
        bytes memory callData = abi.encodeCall(
            this.executeAction, (asset, version, actionIndex, amount, callerMinOut, guardData)
        );
        bytes memory result = new bytes(64);
        uint256 returnSize;
        assembly ("memory-safe") {
            succeeded := call(
                gas(),
                address(),
                0,
                add(callData, 0x20),
                mload(callData),
                add(result, 0x20),
                0x40
            )
            returnSize := returndatasize()
        }
        if (succeeded && returnSize >= 64) {
            (assetOut, amountOut) = abi.decode(result, (address, uint256));
            return (true, assetOut, amountOut, bytes32(0));
        }
        succeeded = false;
        uint256 copySize = Math.min(returnSize, 256);
        bytes memory boundedReason = new bytes(copySize + 32);
        assembly ("memory-safe") {
            returndatacopy(add(boundedReason, 0x20), 0, copySize)
            mstore(add(add(boundedReason, 0x20), copySize), returnSize)
        }
        reasonHash = keccak256(boundedReason);
    }

    function _recordEscrow(
        address asset,
        uint64 version,
        uint256 actionIndex,
        uint256 amount,
        bytes32 reasonHash
    ) private {
        escrowed[asset][version][actionIndex] += amount;
        totalEscrowed[asset] += amount;
        emit ActionEscrowed(asset, version, actionIndex, amount, reasonHash);
    }

    function _validateDestination(address destination, bool controlled) private view {
        if (destination == address(0)) return;
        if (destination.code.length == 0) revert InvalidDestination(destination);
        _validateProjectModule(destination);
        if (controlled && IProjectControlled(destination).controller() != controller) {
            revert DestinationIdentityMismatch(destination);
        }
    }

    function _validateProjectModule(address module) private view {
        if (
            IProjectModule(module).registry() != registry
                || IProjectModule(module).subject() != subject
                || IProjectModule(module).projectId() != projectId
        ) revert DestinationIdentityMismatch(module);
    }

    function _validateRecipient(uint256 index, address recipient) private view {
        if (recipient == address(0) || recipient == BURN_ADDRESS || recipient == address(this)) {
            revert InvalidRecipient(index, recipient);
        }
    }

    function _assertBacked(address asset) private view {
        _validateAsset(asset);
        uint256 measured = _measuredBalance(asset);
        uint256 liability = totalLiability(asset);
        if (measured < liability) revert AssetUnderbacked(asset, measured, liability);
    }

    function _requireExactSpend(address asset, uint256 beforeBalance, uint256 amount) private view {
        uint256 afterBalance = _measuredBalance(asset);
        uint256 spent = beforeBalance >= afterBalance ? beforeBalance - afterBalance : 0;
        if (spent != amount) revert InexactAssetSpend(asset, amount, spent);
    }

    function _activeVersion(address asset) private view returns (uint64 version) {
        version = activeRouteVersion[asset];
        if (version == 0) revert NoActiveRoute(asset);
    }

    function _requireAction(address asset, uint64 version, uint256 index) private view {
        RouteHeader storage header = _routeHeaders[asset][version];
        if (!header.exists) revert UnknownRoute(asset, version);
        if (index >= header.actionCount) revert InvalidActionCount(index);
    }

    function _measuredBalance(address asset) private view returns (uint256) {
        return
            asset == NATIVE_ASSET ? address(this).balance : IERC20(asset).balanceOf(address(this));
    }

    function _validateAsset(address asset) private view {
        if (asset != NATIVE_ASSET && asset.code.length == 0) revert InvalidAsset(asset);
    }

    function _validateErc20(address asset) private view {
        if (asset == NATIVE_ASSET || asset.code.length == 0) revert InvalidAsset(asset);
    }
}
