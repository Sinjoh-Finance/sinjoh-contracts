// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { Time } from "@openzeppelin/contracts/utils/types/Time.sol";
import { IProjectBasketManager } from "../interfaces/IProjectBasketManager.sol";
import { IProjectControlled } from "../interfaces/IProjectControlled.sol";
import { IProjectModule } from "../interfaces/IProjectModule.sol";
import { IProjectPriceGuard } from "../interfaces/IProjectPriceGuard.sol";
import { IProjectRegistryView } from "../interfaces/IProjectRegistryView.sol";
import { IProjectSwapAdapter } from "../interfaces/IProjectSwapAdapter.sol";
import { IProjectTokenIdentity } from "../interfaces/IProjectTokenIdentity.sol";
import { ProjectIds } from "../libraries/ProjectIds.sol";
import { IntegrationApproval } from "../libraries/IntegrationApproval.sol";
import { SinjohV2Constants } from "../libraries/SinjohV2Constants.sol";

/// @notice Narrow project Treasury controlled by one immutable Multisig Account or Timelock.
/// @dev There is no generic execution surface. External calls use fixed adapter, guard, funding,
/// configuration, and Basket lifecycle selectors whose addresses are immutable/proof-approved.
contract ProjectTreasuryVaultV2 is
    IProjectModule,
    IProjectControlled,
    IERC721Receiver,
    ReentrancyGuard
{
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeERC20 for IERC20;

    address public constant NATIVE_ASSET = address(0);
    address public constant BURN_ADDRESS = SinjohV2Constants.BURN_ADDRESS;
    uint256 public constant MAX_BASKET_ROUTE_ASSETS = 8;
    uint256 public constant MAX_REDEMPTION_ASSETS = 16;
    bytes32 public constant TREASURY_SWAP_APPROVAL_DOMAIN =
        keccak256("SINJOH_V2_TREASURY_SWAP_APPROVAL");
    uint256 private constant BPS_DENOMINATOR = 10_000;

    address public immutable override registry;
    address public immutable override subject;
    address public immutable creator;
    bytes32 public immutable override(IProjectModule, IProjectControlled) projectId;
    address public immutable override controller;
    bytes32 public immutable integrationApprovalRoot;
    address public immutable basketManager;

    mapping(address asset => uint256 amount) public accountedBalance;
    mapping(address asset => uint256 amount) public reservedForBasket;

    bool public launchBasketRouteInitialized;
    bool public basketRouteEnabled;
    uint16 public basketAllocationBps;
    uint256 public routedBasketId;
    bytes32 public basketRouteConfigHash;
    uint48 public basketRouteActivatedAt;
    address[] private _basketRouteAssets;
    mapping(address asset => bool eligible) private _basketRouteAsset;
    EnumerableSet.UintSet private _ownedBasketIds;

    error OnlyController(address caller);
    error OnlyLauncher(address caller);
    error LaunchWindowClosed();
    error LaunchBasketRouteAlreadyInitialized();
    error InvalidRegistry(address candidate);
    error InvalidSubject(address candidate);
    error InvalidCreator(address candidate);
    error InvalidController(address candidate);
    error InvalidBasketManager(address candidate);
    error ProjectIdentityMismatch(bytes32 expected, bytes32 actual);
    error InvalidAsset(address asset);
    error InvalidRecipient(address recipient);
    error InvalidAmount(uint256 amount);
    error InsufficientAvailableBalance(address asset, uint256 available, uint256 requested);
    error AssetUnderbacked(address asset, uint256 measured, uint256 accounted);
    error InexactAssetReceipt(address asset, uint256 expected, uint256 measured);
    error InexactAssetSpend(address asset, uint256 expected, uint256 measured);
    error NativeTransferFailed(address recipient, uint256 amount);
    error InvalidSwapPair(address assetIn, address assetOut);
    error InvalidSwapIntegration(address adapter, address priceGuard);
    error SwapNotApproved(bytes32 leaf);
    error InvalidGuardMinimum(uint256 supplied);
    error GuardQuoteExpired(uint48 validUntil, uint48 currentTime);
    error InsufficientSwapOutput(uint256 minimum, uint256 measured);
    error BasketRoutingUnavailable(address asset);
    error BasketRouteNotEnabled();
    error InvalidBasketAllocation(uint16 supplied);
    error InvalidBasketRouteAssets(uint256 count);
    error UnsortedBasketRouteAssets(uint256 index, address previous, address current);
    error InvalidRedemptionAssets(uint256 count);
    error UnsortedRedemptionAssets(uint256 index, address previous, address current);
    error NoBasketReservation(address asset);
    error InvalidBasketProject(uint256 basketId, bytes32 expected, bytes32 actual);
    error BasketNotOwned(uint256 basketId, address owner);
    error InvalidBasketNft(address caller);
    error BasketAlreadyRegistered(uint256 basketId);
    error BasketNotRegistered(uint256 basketId);
    error InexactBasketFunding(uint256 expected, uint256 reported);
    error BasketRedemptionMismatch();
    error BasketNftStillExists(uint256 basketId, address owner);

    event TreasuryVaultCreated(
        bytes32 indexed projectId,
        address indexed subject,
        address indexed controller,
        address creator,
        bytes32 integrationApprovalRoot,
        address basketManager
    );
    event AssetReceived(
        address indexed asset, address indexed sender, uint256 amount, bool basketRequested
    );
    event AssetSynced(address indexed asset, uint256 surplus);
    event AssetSent(address indexed asset, address indexed recipient, uint256 amount);
    event TreasurySwap(
        address indexed assetIn,
        address indexed assetOut,
        uint256 amountIn,
        uint256 amountOut,
        bytes32 routeHash
    );
    event BasketRouteConfigured(bytes32 indexed configHash, uint256 basketId, uint16 allocationBps);
    event BasketRouteDisabled(bytes32 indexed previousConfigHash);
    event BasketRouteReserved(address indexed asset, uint256 amount);
    event BasketRouteReleased(address indexed asset, uint256 amount);
    event BasketRouteExecuted(address indexed asset, uint256 amount, uint256 indexed basketId);
    event BasketNftReceived(
        uint256 indexed basketId, address indexed from, address indexed operator
    );
    event BasketNftTransferred(uint256 indexed basketId, address indexed recipient);
    event BasketNftConfigurationUpdated(uint256 indexed basketId, bytes32 indexed configHash);
    event BasketNftBurnStarted(uint256 indexed basketId);
    event BasketNftBurned(uint256 indexed basketId, uint256 subjectBurnPrice);

    modifier onlyController() {
        if (msg.sender != controller) revert OnlyController(msg.sender);
        _;
    }

    constructor(
        address registry_,
        address subject_,
        address creator_,
        address controller_,
        bytes32 integrationApprovalRoot_,
        address basketManager_
    ) {
        if (registry_.code.length == 0) revert InvalidRegistry(registry_);
        if (subject_.code.length == 0) revert InvalidSubject(subject_);
        if (creator_ == address(0) || creator_ == BURN_ADDRESS) {
            revert InvalidCreator(creator_);
        }
        if (controller_.code.length == 0 || controller_ == BURN_ADDRESS) {
            revert InvalidController(controller_);
        }
        // The CREATE3 Launcher supplies the Manager's final address before deploying its bytecode.
        // Every operational path and Registry registration validate the deployed contract later.
        if (basketManager_ == BURN_ADDRESS) {
            revert InvalidBasketManager(basketManager_);
        }

        bytes32 expectedProjectId = ProjectIds.derive(block.chainid, registry_, subject_);
        (bool declaresIdentity, address subjectRegistry, bytes32 subjectProjectId) =
            ProjectIds.declaredIdentity(subject_);
        if (
            declaresIdentity
                && (subjectRegistry != registry_ || subjectProjectId != expectedProjectId)
        ) revert ProjectIdentityMismatch(expectedProjectId, subjectProjectId);

        bytes32 controllerProjectId;
        address controllerSelf;
        try IProjectControlled(controller_).projectId() returns (bytes32 suppliedProjectId) {
            controllerProjectId = suppliedProjectId;
        } catch {
            revert InvalidController(controller_);
        }
        try IProjectControlled(controller_).controller() returns (address suppliedController) {
            controllerSelf = suppliedController;
        } catch {
            revert InvalidController(controller_);
        }
        if (controllerProjectId != expectedProjectId || controllerSelf != controller_) {
            revert InvalidController(controller_);
        }

        registry = registry_;
        subject = subject_;
        creator = creator_;
        projectId = expectedProjectId;
        controller = controller_;
        integrationApprovalRoot = integrationApprovalRoot_;
        basketManager = basketManager_;

        emit TreasuryVaultCreated(
            expectedProjectId,
            subject_,
            controller_,
            creator_,
            integrationApprovalRoot_,
            basketManager_
        );
    }

    receive() external payable {
        accountedBalance[NATIVE_ASSET] += msg.value;
        emit AssetReceived(NATIVE_ASSET, msg.sender, msg.value, false);
    }

    function depositNative(bool routeToBasket) external payable nonReentrant {
        if (msg.value == 0) revert InvalidAmount(0);
        if (routeToBasket) _requireRouteable(NATIVE_ASSET);
        accountedBalance[NATIVE_ASSET] += msg.value;
        emit AssetReceived(NATIVE_ASSET, msg.sender, msg.value, routeToBasket);
        if (routeToBasket) _reservePolicyShare(NATIVE_ASSET, msg.value);
    }

    function deposit(address asset, uint256 amount, bool routeToBasket) external nonReentrant {
        _validateErc20(asset);
        if (amount == 0) revert InvalidAmount(0);
        if (routeToBasket) _requireRouteable(asset);
        _assertBacked(asset);

        IERC20 token = IERC20(asset);
        uint256 beforeBalance = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), amount);
        uint256 afterBalance = token.balanceOf(address(this));
        uint256 received = afterBalance >= beforeBalance ? afterBalance - beforeBalance : 0;
        if (received != amount) revert InexactAssetReceipt(asset, amount, received);

        accountedBalance[asset] += amount;
        emit AssetReceived(asset, msg.sender, amount, routeToBasket);
        if (routeToBasket) _reservePolicyShare(asset, amount);
    }

    function syncAsset(address asset) external nonReentrant returns (uint256 surplus) {
        surplus = _syncAsset(asset);
    }

    function syncAndReserve(address asset)
        external
        nonReentrant
        returns (uint256 surplus, uint256 reserved)
    {
        _requireRouteable(asset);
        surplus = _syncAsset(asset);
        reserved = _reservePolicyShare(asset, surplus);
    }

    function reserveForBasket(address asset, uint256 amount) external onlyController {
        _requireRouteable(asset);
        if (amount == 0) revert InvalidAmount(0);
        uint256 available = availableBalance(asset);
        if (amount > available) {
            revert InsufficientAvailableBalance(asset, available, amount);
        }
        reservedForBasket[asset] += amount;
        emit BasketRouteReserved(asset, amount);
    }

    function send(address asset, uint256 amount, address recipient)
        external
        onlyController
        nonReentrant
    {
        _validateAsset(asset);
        _validateRecipient(recipient);
        if (amount == 0) revert InvalidAmount(0);
        _assertBacked(asset);
        uint256 available = availableBalance(asset);
        if (amount > available) {
            revert InsufficientAvailableBalance(asset, available, amount);
        }

        uint256 beforeVault = _measuredBalance(asset);
        if (asset == NATIVE_ASSET) {
            (bool success,) = recipient.call{ value: amount }("");
            if (!success) revert NativeTransferFailed(recipient, amount);
        } else {
            IERC20 token = IERC20(asset);
            uint256 beforeRecipient = token.balanceOf(recipient);
            token.safeTransfer(recipient, amount);
            uint256 afterRecipient = token.balanceOf(recipient);
            uint256 received =
                afterRecipient >= beforeRecipient ? afterRecipient - beforeRecipient : 0;
            if (received != amount) revert InexactAssetReceipt(asset, amount, received);
        }
        uint256 afterVault = _measuredBalance(asset);
        uint256 spent = beforeVault >= afterVault ? beforeVault - afterVault : 0;
        if (spent != amount) revert InexactAssetSpend(asset, amount, spent);

        accountedBalance[asset] -= amount;
        emit AssetSent(asset, recipient, amount);
    }

    function swap(
        address adapter,
        address priceGuard,
        address assetIn,
        address assetOut,
        uint256 amountIn,
        uint256 callerMinOut,
        bytes calldata routeData,
        bytes calldata guardData,
        bytes32[] calldata approvalProof
    ) external onlyController nonReentrant returns (uint256 amountOut) {
        _validateAsset(assetIn);
        _validateAsset(assetOut);
        if (assetIn == assetOut) revert InvalidSwapPair(assetIn, assetOut);
        if (adapter.code.length == 0 || priceGuard.code.length == 0) {
            revert InvalidSwapIntegration(adapter, priceGuard);
        }
        if (amountIn == 0) revert InvalidAmount(0);
        _assertBacked(assetIn);
        _assertBacked(assetOut);
        uint256 available = availableBalance(assetIn);
        if (amountIn > available) {
            revert InsufficientAvailableBalance(assetIn, available, amountIn);
        }

        bytes32 routeHash = keccak256(routeData);
        bytes32 approvalLeaf = swapApprovalLeaf(adapter, priceGuard);
        if (
            integrationApprovalRoot == bytes32(0)
                || !MerkleProof.verifyCalldata(approvalProof, integrationApprovalRoot, approvalLeaf)
        ) {
            revert SwapNotApproved(approvalLeaf);
        }

        (uint256 guardMinOut, uint48 validUntil) = IProjectPriceGuard(priceGuard)
            .minimumOutput(subject, assetIn, assetOut, amountIn, routeHash, guardData);
        if (guardMinOut == 0) revert InvalidGuardMinimum(guardMinOut);
        uint48 currentTime = Time.timestamp();
        if (validUntil < currentTime) revert GuardQuoteExpired(validUntil, currentTime);
        uint256 effectiveMinimum = Math.max(callerMinOut, guardMinOut);

        uint256 beforeInput = _measuredBalance(assetIn);
        uint256 beforeOutput = _measuredBalance(assetOut);
        uint256 outputAccountedBefore = accountedBalance[assetOut];

        if (assetIn == NATIVE_ASSET) {
            IProjectSwapAdapter(adapter).swap{ value: amountIn }(
                assetIn, assetOut, amountIn, effectiveMinimum, routeData
            );
        } else {
            IERC20 inputToken = IERC20(assetIn);
            inputToken.forceApprove(adapter, amountIn);
            IProjectSwapAdapter(adapter)
                .swap(assetIn, assetOut, amountIn, effectiveMinimum, routeData);
            inputToken.forceApprove(adapter, 0);
        }

        uint256 afterInput = _measuredBalance(assetIn);
        uint256 afterOutput = _measuredBalance(assetOut);
        uint256 spent = beforeInput >= afterInput ? beforeInput - afterInput : 0;
        if (spent != amountIn) revert InexactAssetSpend(assetIn, amountIn, spent);
        amountOut = afterOutput >= beforeOutput ? afterOutput - beforeOutput : 0;
        if (amountOut < effectiveMinimum) {
            revert InsufficientSwapOutput(effectiveMinimum, amountOut);
        }

        accountedBalance[assetIn] -= amountIn;
        _creditMeasuredReceipt(assetOut, amountOut, outputAccountedBefore);
        emit TreasurySwap(assetIn, assetOut, amountIn, amountOut, routeHash);
    }

    function swapApprovalLeaf(address adapter, address priceGuard) public view returns (bytes32) {
        return IntegrationApproval.swapLeaf(adapter, priceGuard);
    }

    /// @notice Frontend-safe approval check for an exact adapter, guard, pair, and route.
    /// @dev This keeps clients from having to reproduce the leaf's domain separation and hashing.
    function isSwapApproved(address adapter, address priceGuard, bytes32[] calldata approvalProof)
        external
        view
        returns (bool)
    {
        if (
            integrationApprovalRoot == bytes32(0) || adapter.code.length == 0
                || priceGuard.code.length == 0
        ) return false;
        bytes32 leaf = swapApprovalLeaf(adapter, priceGuard);
        return MerkleProof.verifyCalldata(approvalProof, integrationApprovalRoot, leaf);
    }

    function configureBasketRoute(uint256 basketId, uint16 allocationBps, address[] calldata assets)
        external
        onlyController
        nonReentrant
        returns (bytes32 configHash)
    {
        configHash = _configureBasketRoute(basketId, allocationBps, assets);
    }

    /// @notice Applies the creator-selected initial Basket route inside the atomic launch.
    /// @dev Registration permanently closes this narrow launcher permission. Governance remains
    /// the only authority able to update or disable the route after launch.
    function initializeBasketRouteFromLauncher(
        uint256 basketId,
        uint16 allocationBps,
        address[] calldata assets
    ) external nonReentrant returns (bytes32 configHash) {
        if (msg.sender != IProjectRegistryView(registry).launcher()) {
            revert OnlyLauncher(msg.sender);
        }
        if (IProjectRegistryView(registry).projectIdBySubject(subject) != bytes32(0)) {
            revert LaunchWindowClosed();
        }
        if (launchBasketRouteInitialized) revert LaunchBasketRouteAlreadyInitialized();

        launchBasketRouteInitialized = true;
        configHash = _configureBasketRoute(basketId, allocationBps, assets);
    }

    function _configureBasketRoute(uint256 basketId, uint16 allocationBps, address[] memory assets)
        private
        returns (bytes32 configHash)
    {
        if (allocationBps == 0 || allocationBps > BPS_DENOMINATOR) {
            revert InvalidBasketAllocation(allocationBps);
        }
        uint256 count = assets.length;
        if (count == 0 || count > MAX_BASKET_ROUTE_ASSETS) {
            revert InvalidBasketRouteAssets(count);
        }
        _requireOwnedBasket(basketId);
        _validateSortedRouteAssets(assets);

        _releaseBasketRoute();
        for (uint256 i; i < count; ++i) {
            address asset = assets[i];
            _basketRouteAssets.push(asset);
            _basketRouteAsset[asset] = true;
        }

        basketRouteEnabled = true;
        basketAllocationBps = allocationBps;
        routedBasketId = basketId;
        basketRouteActivatedAt = Time.timestamp();
        configHash = keccak256(abi.encode(projectId, basketId, allocationBps, assets));
        basketRouteConfigHash = configHash;
        emit BasketRouteConfigured(configHash, basketId, allocationBps);
    }

    function disableBasketRoute() external onlyController {
        if (!basketRouteEnabled) revert BasketRouteNotEnabled();
        _disableBasketRoute();
    }

    function executeBasketRoute(address asset, uint256 maxAmount)
        external
        nonReentrant
        returns (uint256 amount)
    {
        _requireRouteable(asset);
        if (maxAmount == 0) revert InvalidAmount(0);
        uint256 pending = reservedForBasket[asset];
        if (pending == 0) revert NoBasketReservation(asset);
        amount = Math.min(pending, maxAmount);
        _assertBacked(asset);
        _requireOwnedBasket(routedBasketId);

        uint256 beforeBalance = _measuredBalance(asset);
        reservedForBasket[asset] = pending - amount;
        uint256 reportedReceived;
        if (asset == NATIVE_ASSET) {
            reportedReceived = IProjectBasketManager(basketManager).fund{ value: amount }(
                projectId, subject, asset, amount, abi.encode(routedBasketId)
            );
        } else {
            IERC20 token = IERC20(asset);
            token.forceApprove(basketManager, amount);
            reportedReceived = IProjectBasketManager(basketManager)
                .fund(projectId, subject, asset, amount, abi.encode(routedBasketId));
            token.forceApprove(basketManager, 0);
        }
        if (reportedReceived != amount) {
            revert InexactBasketFunding(amount, reportedReceived);
        }

        uint256 afterBalance = _measuredBalance(asset);
        uint256 spent = beforeBalance >= afterBalance ? beforeBalance - afterBalance : 0;
        if (spent != amount) revert InexactAssetSpend(asset, amount, spent);
        accountedBalance[asset] -= amount;
        emit BasketRouteExecuted(asset, amount, routedBasketId);
    }

    function syncBasketNft(uint256 basketId) external onlyController nonReentrant {
        _requireOwnedBasket(basketId);
        if (!_ownedBasketIds.add(basketId)) revert BasketAlreadyRegistered(basketId);
        emit BasketNftReceived(basketId, address(0), msg.sender);
    }

    function transferBasketNft(uint256 basketId, address recipient)
        external
        onlyController
        nonReentrant
    {
        _validateRecipient(recipient);
        _requireRegisteredOwnedBasket(basketId);
        if (basketRouteEnabled && routedBasketId == basketId) _disableBasketRoute();
        _ownedBasketIds.remove(basketId);
        _basketNft().safeTransferFrom(address(this), recipient, basketId);
        emit BasketNftTransferred(basketId, recipient);
    }

    function updateOwnedBasket(uint256 basketId, bytes calldata config)
        external
        onlyController
        nonReentrant
    {
        _requireRegisteredOwnedBasket(basketId);
        IProjectBasketManager(basketManager).updateConfiguration(basketId, config);
        emit BasketNftConfigurationUpdated(basketId, keccak256(config));
    }

    function beginOwnedBasketBurn(uint256 basketId) external onlyController nonReentrant {
        _requireRegisteredOwnedBasket(basketId);
        if (basketRouteEnabled && routedBasketId == basketId) _disableBasketRoute();
        IProjectBasketManager(basketManager).beginBurn(basketId);
        emit BasketNftBurnStarted(basketId);
    }

    function finalizeOwnedBasketBurn(uint256 basketId)
        external
        onlyController
        nonReentrant
        returns (address[] memory assets, uint256[] memory amounts)
    {
        _requireRegisteredOwnedBasket(basketId);
        IProjectBasketManager manager = IProjectBasketManager(basketManager);
        assets = manager.redemptionAssets(basketId);
        _validateSortedRedemptionAssets(assets);

        uint256 count = assets.length;
        uint256[] memory balancesBefore = new uint256[](count);
        uint256[] memory accountedBefore = new uint256[](count);
        for (uint256 i; i < count; ++i) {
            address asset = assets[i];
            _assertBacked(asset);
            balancesBefore[i] = _measuredBalance(asset);
            accountedBefore[i] = accountedBalance[asset];
        }

        uint256 subjectBurnPrice = manager.burnPriceSubject(basketId);
        _assertBacked(subject);
        uint256 subjectAvailable = availableBalance(subject);
        if (subjectBurnPrice > subjectAvailable) {
            revert InsufficientAvailableBalance(subject, subjectAvailable, subjectBurnPrice);
        }
        uint256 subjectBalanceBefore = _measuredBalance(subject);
        uint256 subjectAccountedBefore = accountedBalance[subject];

        if (subjectBurnPrice != 0) {
            IERC20(subject).forceApprove(basketManager, subjectBurnPrice);
        }
        _ownedBasketIds.remove(basketId);
        (address[] memory returnedAssets, uint256[] memory returnedAmounts) =
            manager.finalizeBurn(basketId);
        if (subjectBurnPrice != 0) IERC20(subject).forceApprove(basketManager, 0);

        if (returnedAssets.length != count || returnedAmounts.length != count) {
            revert BasketRedemptionMismatch();
        }
        uint256 subjectReceived;
        for (uint256 i; i < count; ++i) {
            if (returnedAssets[i] != assets[i]) revert BasketRedemptionMismatch();
            address asset = assets[i];
            uint256 amount = returnedAmounts[i];
            uint256 expectedAfter = balancesBefore[i] + amount;
            if (asset == subject) {
                subjectReceived = amount;
                expectedAfter = balancesBefore[i] - subjectBurnPrice + amount;
            }
            if (_measuredBalance(asset) != expectedAfter) revert BasketRedemptionMismatch();
            if (asset != subject) {
                _creditMeasuredReceipt(asset, amount, accountedBefore[i]);
            }
        }
        if (_measuredBalance(subject) != subjectBalanceBefore - subjectBurnPrice + subjectReceived)
        {
            revert BasketRedemptionMismatch();
        }
        accountedBalance[subject] = subjectAccountedBefore - subjectBurnPrice + subjectReceived;

        IERC721 basketNft = _basketNft();
        (bool nftStillExists, bytes memory ownerResult) =
            address(basketNft).staticcall(abi.encodeCall(basketNft.ownerOf, (basketId)));
        if (nftStillExists && ownerResult.length >= 32) {
            revert BasketNftStillExists(basketId, abi.decode(ownerResult, (address)));
        }
        if (nftStillExists) revert BasketRedemptionMismatch();

        amounts = returnedAmounts;
        emit BasketNftBurned(basketId, subjectBurnPrice);
    }

    function onERC721Received(address operator, address from, uint256 basketId, bytes calldata)
        external
        override
        returns (bytes4)
    {
        if (msg.sender != address(_basketNft())) revert InvalidBasketNft(msg.sender);
        _requireOwnedBasket(basketId);
        if (!_ownedBasketIds.add(basketId)) revert BasketAlreadyRegistered(basketId);
        emit BasketNftReceived(basketId, from, operator);
        return IERC721Receiver.onERC721Received.selector;
    }

    function measuredBalance(address asset) external view returns (uint256) {
        return _measuredBalance(asset);
    }

    function availableBalance(address asset) public view returns (uint256) {
        return accountedBalance[asset] - reservedForBasket[asset];
    }

    function isAssetBacked(address asset) external view returns (bool) {
        uint256 accounted = accountedBalance[asset];
        return _measuredBalance(asset) >= accounted && accounted >= reservedForBasket[asset];
    }

    function basketRoute()
        external
        view
        returns (
            bool enabled,
            uint16 allocationBps,
            uint256 basketId,
            bytes32 configHash,
            uint48 activatedAt,
            address[] memory assets
        )
    {
        return (
            basketRouteEnabled,
            basketAllocationBps,
            routedBasketId,
            basketRouteConfigHash,
            basketRouteActivatedAt,
            _basketRouteAssets
        );
    }

    function isBasketRouteAsset(address asset) external view returns (bool) {
        return _basketRouteAsset[asset];
    }

    /// @notice Single-call keeper/frontend view for the active route and an asset's pending work.
    function basketRouteStatus(address asset)
        external
        view
        returns (
            bool enabled,
            bool eligible,
            uint256 basketId,
            uint16 allocationBps,
            uint256 pendingAmount
        )
    {
        return (
            basketRouteEnabled,
            _basketRouteAsset[asset],
            routedBasketId,
            basketAllocationBps,
            reservedForBasket[asset]
        );
    }

    function ownedBasketCount() external view returns (uint256) {
        return _ownedBasketIds.length();
    }

    function ownedBasketAt(uint256 index) external view returns (uint256) {
        return _ownedBasketIds.at(index);
    }

    function ownedBasketIds() external view returns (uint256[] memory) {
        return _ownedBasketIds.values();
    }

    function isOwnedBasketRegistered(uint256 basketId) external view returns (bool) {
        return _ownedBasketIds.contains(basketId);
    }

    function _syncAsset(address asset) private returns (uint256 surplus) {
        _validateAsset(asset);
        uint256 measured = _measuredBalance(asset);
        uint256 accounted = accountedBalance[asset];
        if (measured < accounted) revert AssetUnderbacked(asset, measured, accounted);
        surplus = measured - accounted;
        accountedBalance[asset] = measured;
        emit AssetSynced(asset, surplus);
    }

    function _reservePolicyShare(address asset, uint256 amount) private returns (uint256 reserved) {
        reserved = Math.mulDiv(amount, basketAllocationBps, BPS_DENOMINATOR);
        if (reserved != 0) {
            reservedForBasket[asset] += reserved;
            emit BasketRouteReserved(asset, reserved);
        }
    }

    function _releaseBasketRoute() private {
        uint256 count = _basketRouteAssets.length;
        for (uint256 i; i < count; ++i) {
            address asset = _basketRouteAssets[i];
            uint256 released = reservedForBasket[asset];
            if (released != 0) {
                reservedForBasket[asset] = 0;
                emit BasketRouteReleased(asset, released);
            }
            _basketRouteAsset[asset] = false;
        }
        delete _basketRouteAssets;
        basketRouteEnabled = false;
        basketAllocationBps = 0;
        routedBasketId = 0;
        basketRouteConfigHash = bytes32(0);
        basketRouteActivatedAt = 0;
    }

    function _disableBasketRoute() private {
        bytes32 previousConfigHash = basketRouteConfigHash;
        _releaseBasketRoute();
        emit BasketRouteDisabled(previousConfigHash);
    }

    function _requireRouteable(address asset) private view {
        if (!basketRouteEnabled || !_basketRouteAsset[asset]) {
            revert BasketRoutingUnavailable(asset);
        }
    }

    function _requireRegisteredOwnedBasket(uint256 basketId) private view {
        if (!_ownedBasketIds.contains(basketId)) revert BasketNotRegistered(basketId);
        _requireOwnedBasket(basketId);
    }

    function _requireOwnedBasket(uint256 basketId) private view {
        if (basketManager.code.length == 0) revert InvalidBasketManager(basketManager);
        bytes32 actualProjectId = IProjectBasketManager(basketManager).basketProjectId(basketId);
        if (actualProjectId != projectId) {
            revert InvalidBasketProject(basketId, projectId, actualProjectId);
        }
        address owner = _basketNft().ownerOf(basketId);
        if (owner != address(this)) revert BasketNotOwned(basketId, owner);
    }

    function _basketNft() private view returns (IERC721 nft) {
        if (basketManager.code.length == 0) revert InvalidBasketManager(basketManager);
        nft = IProjectBasketManager(basketManager).basketNFT();
        if (address(nft).code.length == 0) revert InvalidBasketNft(address(nft));
    }

    function _validateSortedRouteAssets(address[] memory assets) private view {
        uint256 count = assets.length;
        if (count == 0 || count > MAX_BASKET_ROUTE_ASSETS) {
            revert InvalidBasketRouteAssets(count);
        }
        address previous;
        for (uint256 i; i < count; ++i) {
            address asset = assets[i];
            _validateAsset(asset);
            if (i != 0 && asset <= previous) {
                revert UnsortedBasketRouteAssets(i, previous, asset);
            }
            previous = asset;
        }
    }

    function _validateSortedRedemptionAssets(address[] memory assets) private view {
        uint256 count = assets.length;
        if (count == 0 || count > MAX_REDEMPTION_ASSETS) {
            revert InvalidRedemptionAssets(count);
        }
        address previous;
        for (uint256 i; i < count; ++i) {
            address asset = assets[i];
            _validateAsset(asset);
            if (i != 0 && asset <= previous) {
                revert UnsortedRedemptionAssets(i, previous, asset);
            }
            previous = asset;
        }
    }

    function _creditMeasuredReceipt(address asset, uint256 amount, uint256 accountedBefore)
        private
    {
        uint256 currentAccounted = accountedBalance[asset];
        if (currentAccounted < accountedBefore) revert BasketRedemptionMismatch();
        uint256 alreadyCredited = currentAccounted - accountedBefore;
        if (alreadyCredited > amount) revert BasketRedemptionMismatch();
        accountedBalance[asset] = currentAccounted + (amount - alreadyCredited);
    }

    function _assertBacked(address asset) private view {
        uint256 measured = _measuredBalance(asset);
        uint256 accounted = accountedBalance[asset];
        if (measured < accounted) revert AssetUnderbacked(asset, measured, accounted);
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

    function _validateRecipient(address recipient) private view {
        if (recipient == address(0) || recipient == address(this)) {
            revert InvalidRecipient(recipient);
        }
    }
}
