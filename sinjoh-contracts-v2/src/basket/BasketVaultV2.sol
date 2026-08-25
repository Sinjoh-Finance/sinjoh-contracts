// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Time } from "@openzeppelin/contracts/utils/types/Time.sol";
import {
    BasketAllocationConfig,
    BasketConfig,
    BasketBurnTaxDestination,
    BasketEligibilityMode,
    BasketHarvestCadence,
    BasketSwapLeg,
    BasketTarget
} from "./BasketTypes.sol";
import { IBasketYieldAdapter } from "../interfaces/IBasketYieldAdapter.sol";
import { IProjectFundable } from "../interfaces/IProjectFundable.sol";
import { IProjectPriceGuard } from "../interfaces/IProjectPriceGuard.sol";
import { IProjectSwapAdapter } from "../interfaces/IProjectSwapAdapter.sol";

/// @notice Asset/position custody for exactly one Basket NFT.
/// @dev The Manager is the only mutator; principal release exists only in the burn lifecycle.
contract BasketVaultV2 is ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public constant NATIVE_ASSET = address(0);
    uint16 public constant BPS = 10_000;
    uint256 public constant MAX_TARGETS = 8;
    uint256 public constant MAX_INPUT_ASSETS = 8;
    uint256 public constant MAX_REWARD_ASSETS_PER_TARGET = 8;
    uint256 public constant MAX_TRACKED_ASSETS = 32;
    bytes32 public constant YIELD_APPROVAL_DOMAIN = keccak256("SINJOH_V2_BASKET_YIELD_APPROVAL");
    bytes32 public constant SWAP_APPROVAL_DOMAIN = keccak256("SINJOH_V2_BASKET_SWAP_APPROVAL");

    struct StoredTarget {
        address depositAsset;
        address yieldAdapter;
        uint16 targetWeightBps;
        uint256 lockedPrincipal;
        bool burnProcessed;
        address[] rewardAssets;
    }

    struct StoredSwapLeg {
        address swapAdapter;
        address priceGuard;
        uint16 maxSlippageBps;
        bytes routeData;
        bytes32[] approvalProof;
        bool exists;
    }

    address public manager;
    address public registry;
    address public subject;
    bytes32 public projectId;
    uint256 public basketId;
    address public creator;
    address public treasury;
    address public router;
    address public airdrop;
    bytes32 public integrationApprovalRoot;
    BasketHarvestCadence public cadence;
    BasketEligibilityMode public eligibilityMode;
    uint16 public burnTaxBps;
    BasketBurnTaxDestination public burnTaxDestination;
    bytes32 public initialConfigurationHash;

    bool public configurationValidated;
    bool public activated;
    bool private _initialized;
    bool public burnBegun;
    bool public closed;
    uint48 public lastHarvestAt;
    uint256 public processedBurnTargets;
    uint256 public pendingDividendAssetCount;

    address[] private _inputAssets;
    mapping(address asset => bool accepted) private _acceptedInput;
    StoredTarget[] private _targets;
    mapping(uint256 targetIndex => bytes32[] proof) private _yieldApprovalProof;
    mapping(bytes32 legKey => StoredSwapLeg leg) private _swapLegs;
    mapping(address inputAsset => uint256 total) public totalFunded;
    mapping(address inputAsset => mapping(uint256 targetIndex => uint256 amount)) public allocated;
    mapping(address asset => uint256 amount) public pendingDividend;
    address[] private _trackedAssets;
    mapping(address asset => bool tracked) private _isTrackedAsset;
    bytes public airdropAccountConfig;

    error OnlyManager(address caller);
    error OnlySelf(address caller);
    error InvalidConfiguration();
    error ConfigurationAlreadyValidated();
    error ConfigurationNotValidated();
    error AlreadyActivated();
    error InvalidTargetCount(uint256 supplied);
    error InvalidInputCount(uint256 supplied);
    error InvalidTarget(uint256 index);
    error InvalidTargetWeights(uint256 supplied);
    error InvalidRewardAssets(uint256 targetIndex);
    error InvalidSwapLeg(uint256 index);
    error DuplicateSwapLeg(address inputAsset, uint256 targetIndex);
    error MissingSwapLeg(address inputAsset, uint256 targetIndex);
    error UnsortedAddresses(uint256 index, address previous, address current);
    error IntegrationNotApproved(bytes32 leaf);
    error YieldAdapterBindingMismatch(uint256 targetIndex, address adapter);
    error BurnInProgress();
    error BurnNotBegun();
    error BurnTargetAlreadyProcessed(uint256 targetIndex);
    error InvalidAsset(address asset);
    error InvalidAmount(uint256 amount);
    error NativeValueMismatch(uint256 expected, uint256 supplied);
    error InexactAssetReceipt(address asset, uint256 expected, uint256 measured);
    error InexactAssetSpend(address asset, uint256 expected, uint256 measured);
    error InvalidGuardMinimum(uint256 supplied);
    error GuardQuoteExpired(uint48 validUntil, uint48 currentTime);
    error InsufficientSwapOutput(uint256 minimum, uint256 measured);
    error InexactYieldDeposit(uint256 targetIndex, uint256 expected, uint256 measured);
    error InvalidPositionUnits(uint256 targetIndex);
    error TooManyTrackedAssets(uint256 supplied);
    error InvalidFundingIdentity(bytes32 projectId, address subject);
    error InvalidAirdropReceipt(uint256 expected, uint256 reported);
    error NativeTransferFailed(address recipient, uint256 amount);
    error BurnTargetsIncomplete(uint256 processed, uint256 total);
    error HarvestNotDue(uint48 earliest, uint48 currentTime);
    error PrincipalNotRestored(uint256 targetIndex, uint256 principal, uint256 positionValue);
    error AdapterOutputMismatch(uint256 targetIndex);
    error NoPendingDividend(address asset);
    error PendingDividendsExist(uint256 assetCount);
    error AlreadyInitialized();

    event ConfigurationValidated(bytes32 indexed configurationHash);
    event BasketActivated(uint48 indexed activatedAt, uint48 indexed firstHarvestAt);
    event FundingAllocated(
        address indexed inputAsset,
        uint256 indexed targetIndex,
        address indexed depositAsset,
        uint256 inputAmount,
        uint256 depositedAmount
    );
    event DividendPending(address indexed asset, uint256 amount, bytes32 reasonHash);
    event DividendFunded(address indexed asset, uint256 amount);
    event DividendRedirectedToTreasury(address indexed asset, uint256 amount);
    event HarvestCompleted(uint48 indexed harvestedAt, uint48 indexed nextHarvestAt);
    event AllocationConfigurationUpdated(bytes32 indexed configurationHash);
    event BurnStarted(uint256 indexed basketId);
    event BurnTargetProcessed(uint256 indexed targetIndex, address indexed adapter);

    modifier onlyManager() {
        if (msg.sender != manager) revert OnlyManager(msg.sender);
        _;
    }

    modifier onlySelf() {
        if (msg.sender != address(this)) revert OnlySelf(msg.sender);
        _;
    }

    constructor() {
        _initialized = true;
    }

    function initialize(
        address manager_,
        address registry_,
        address subject_,
        bytes32 projectId_,
        uint256 basketId_,
        address creator_,
        address treasury_,
        address router_,
        address airdrop_,
        bytes32 integrationApprovalRoot_,
        BasketConfig memory config
    ) external {
        if (_initialized) revert AlreadyInitialized();
        _initialized = true;
        manager = manager_;
        registry = registry_;
        subject = subject_;
        projectId = projectId_;
        basketId = basketId_;
        creator = creator_;
        treasury = treasury_;
        router = router_;
        airdrop = airdrop_;
        integrationApprovalRoot = integrationApprovalRoot_;
        cadence = config.cadence;
        eligibilityMode = config.eligibilityMode;
        burnTaxBps = config.burnTaxBps;
        burnTaxDestination = config.burnTaxDestination;
        airdropAccountConfig = config.airdropAccountConfig;
        initialConfigurationHash = keccak256(abi.encode(config.allocation));
        _trackAsset(NATIVE_ASSET);
        _storeAllocation(config.allocation);
    }

    receive() external payable {
        _trackAsset(NATIVE_ASSET);
    }

    function validateConfiguration() external {
        if (configurationValidated) revert ConfigurationAlreadyValidated();
        _validateStoredConfiguration();
        configurationValidated = true;
        emit ConfigurationValidated(initialConfigurationHash);
    }

    function activate() external onlyManager {
        if (!configurationValidated) revert ConfigurationNotValidated();
        if (activated) revert AlreadyActivated();
        activated = true;
        lastHarvestAt = Time.timestamp();
        emit BasketActivated(lastHarvestAt, nextHarvestAt());
    }

    function allocateFunding(address inputAsset, uint256 amount)
        external
        payable
        onlyManager
        nonReentrant
        returns (uint256 received)
    {
        if (!configurationValidated || !activated) revert ConfigurationNotValidated();
        if (burnBegun || closed) revert BurnInProgress();
        if (amount == 0) revert InvalidAmount(amount);
        if (!_acceptedInput[inputAsset]) revert InvalidAsset(inputAsset);
        if (inputAsset == NATIVE_ASSET) {
            if (msg.value != amount) revert NativeValueMismatch(amount, msg.value);
        } else {
            if (msg.value != 0) revert NativeValueMismatch(0, msg.value);
            uint256 beforeBalance = IERC20(inputAsset).balanceOf(address(this));
            IERC20(inputAsset).safeTransferFrom(msg.sender, address(this), amount);
            received = IERC20(inputAsset).balanceOf(address(this)) - beforeBalance;
            if (received != amount) revert InexactAssetReceipt(inputAsset, amount, received);
        }
        received = amount;
        _allocate(inputAsset, amount);
    }

    /// @notice Harvest every configured adapter and safely queue/fund all measured yield.
    function harvest() external nonReentrant {
        if (!configurationValidated || !activated) revert ConfigurationNotValidated();
        if (burnBegun || closed) revert BurnInProgress();
        uint48 currentTime = Time.timestamp();
        uint48 dueAt = nextHarvestAt();
        if (currentTime < dueAt) revert HarvestNotDue(dueAt, currentTime);

        uint256 targetLength = _targets.length;
        for (uint256 i; i < targetLength; ++i) {
            _harvestTarget(i, _targets[i]);
        }
        lastHarvestAt = currentTime;
        _tryAllPendingDividends();
        emit HarvestCompleted(currentTime, nextHarvestAt());
    }

    /// @notice Retry one previously harvested dividend without waiting for another cadence.
    function retryPendingDividend(address asset) external nonReentrant returns (bool funded) {
        if (burnBegun || closed) revert BurnInProgress();
        if (pendingDividend[asset] == 0) revert NoPendingDividend(asset);
        return _tryPendingDividend(asset);
    }

    function redirectPendingDividendToTreasury(address asset)
        external
        onlyManager
        nonReentrant
        returns (uint256 amount)
    {
        if (burnBegun || closed) revert BurnInProgress();
        amount = pendingDividend[asset];
        if (amount == 0) revert NoPendingDividend(asset);
        pendingDividend[asset] = 0;
        pendingDividendAssetCount -= 1;
        _sendExact(asset, treasury, amount);
        emit DividendRedirectedToTreasury(asset, amount);
    }

    /// @dev External self-call boundary lets a failed downstream Airdrop become retryable state.
    function fundPendingDividend(address asset) external onlySelf {
        uint256 amount = pendingDividend[asset];
        if (amount == 0) revert NoPendingDividend(asset);
        _fundSink(airdrop, asset, amount, airdropAccountConfig);
        pendingDividend[asset] = 0;
        pendingDividendAssetCount -= 1;
        emit DividendFunded(asset, amount);
    }

    function nextHarvestAt() public view returns (uint48) {
        uint48 interval = cadence == BasketHarvestCadence.ONE_DAY ? uint48(1 days) : uint48(7 days);
        return lastHarvestAt + interval;
    }

    /// @notice Atomically exit the old positions, validate a complete approved config, and reallocate.
    function updateAllocation(BasketAllocationConfig calldata allocation)
        external
        onlyManager
        nonReentrant
        returns (bytes32 configurationHash)
    {
        if (!configurationValidated || !activated) revert ConfigurationNotValidated();
        if (burnBegun || closed) revert BurnInProgress();
        if (pendingDividendAssetCount != 0) {
            revert PendingDividendsExist(pendingDividendAssetCount);
        }

        uint256 oldTargetCount = _targets.length;
        for (uint256 i; i < oldTargetCount; ++i) {
            _exitTarget(i, _targets[i]);
        }
        _clearAllocation();
        _storeAllocation(allocation);
        _validateStoredConfiguration();

        uint256 inputCount = _inputAssets.length;
        for (uint256 i; i < inputCount; ++i) {
            address input = _inputAssets[i];
            uint256 amount = _balance(input);
            if (amount != 0) _allocate(input, amount);
        }
        configurationHash = keccak256(abi.encode(allocation));
        emit AllocationConfigurationUpdated(configurationHash);
    }

    function beginBurn() external onlyManager nonReentrant {
        if (!configurationValidated || !activated) revert ConfigurationNotValidated();
        if (burnBegun || closed) revert BurnInProgress();
        if (pendingDividendAssetCount != 0) {
            revert PendingDividendsExist(pendingDividendAssetCount);
        }
        burnBegun = true;
        emit BurnStarted(basketId);
    }

    function processBurnTarget(uint256 targetIndex) external onlyManager nonReentrant {
        if (!burnBegun || closed) revert BurnNotBegun();
        StoredTarget storage target = _targets[targetIndex];
        if (target.burnProcessed) revert BurnTargetAlreadyProcessed(targetIndex);
        _exitTarget(targetIndex, target);
        target.burnProcessed = true;
        processedBurnTargets += 1;
        emit BurnTargetProcessed(targetIndex, target.yieldAdapter);
    }

    function finalizeRedemption(address owner)
        external
        onlyManager
        nonReentrant
        returns (address[] memory assets, uint256[] memory ownerAmounts)
    {
        if (!burnBegun || closed) revert BurnNotBegun();
        uint256 targetLength = _targets.length;
        if (processedBurnTargets != targetLength) {
            revert BurnTargetsIncomplete(processedBurnTargets, targetLength);
        }
        closed = true;
        assets = _trackedAssets;
        uint256 count = assets.length;
        ownerAmounts = new uint256[](count);
        address taxRecipient = _taxRecipient();
        for (uint256 i; i < count; ++i) {
            address asset = assets[i];
            uint256 balance = _balance(asset);
            if (balance == 0) continue;
            uint256 tax = Math.mulDiv(balance, burnTaxBps, BPS);
            uint256 ownerAmount = balance - tax;
            if (tax != 0) _sendTax(asset, tax, taxRecipient);
            if (ownerAmount != 0) _sendExact(asset, owner, ownerAmount);
            ownerAmounts[i] = ownerAmount + (taxRecipient == owner ? tax : 0);
        }
    }

    function targetCount() external view returns (uint256) {
        return _targets.length;
    }

    function inputAssets() external view returns (address[] memory) {
        return _inputAssets;
    }

    function targetStatus(uint256 index)
        external
        view
        returns (
            address depositAsset,
            address yieldAdapter,
            uint16 targetWeightBps,
            uint256 lockedPrincipal,
            uint256 positionValue,
            uint256 unrealizedGain,
            uint256 unrealizedLoss,
            bool burnProcessed,
            address[] memory rewardAssets
        )
    {
        StoredTarget storage target = _targets[index];
        positionValue = IBasketYieldAdapter(target.yieldAdapter).totalAssets();
        if (positionValue >= target.lockedPrincipal) {
            unrealizedGain = positionValue - target.lockedPrincipal;
        } else {
            unrealizedLoss = target.lockedPrincipal - positionValue;
        }
        return (
            target.depositAsset,
            target.yieldAdapter,
            target.targetWeightBps,
            target.lockedPrincipal,
            positionValue,
            unrealizedGain,
            unrealizedLoss,
            target.burnProcessed,
            target.rewardAssets
        );
    }

    function trackedAssets() external view returns (address[] memory) {
        return _trackedAssets;
    }

    function yieldApprovalLeaf(address adapter, address depositAsset)
        public
        view
        returns (bytes32)
    {
        bytes32 inner = keccak256(
            abi.encode(
                YIELD_APPROVAL_DOMAIN,
                block.chainid,
                adapter.codehash,
                depositAsset,
                IBasketYieldAdapter(adapter).yieldSource()
            )
        );
        return keccak256(bytes.concat(inner));
    }

    function swapApprovalLeaf(
        address inputAsset,
        uint256 targetIndex,
        address adapter,
        address priceGuard,
        uint16 maxSlippageBps,
        bytes32 routeHash
    ) public view returns (bytes32) {
        bytes32 inner = keccak256(
            abi.encode(
                SWAP_APPROVAL_DOMAIN,
                block.chainid,
                inputAsset,
                _targets[targetIndex].depositAsset,
                adapter.codehash,
                priceGuard,
                maxSlippageBps,
                routeHash
            )
        );
        return keccak256(bytes.concat(inner));
    }

    function _storeAllocation(BasketAllocationConfig memory allocation) private {
        uint256 inputCount = allocation.inputAssets.length;
        uint256 targetLength = allocation.targets.length;
        if (inputCount == 0 || inputCount > MAX_INPUT_ASSETS) {
            revert InvalidInputCount(inputCount);
        }
        if (targetLength == 0 || targetLength > MAX_TARGETS) {
            revert InvalidTargetCount(targetLength);
        }
        address previous;
        for (uint256 i; i < inputCount; ++i) {
            address input = allocation.inputAssets[i];
            if (i != 0 && input <= previous) revert UnsortedAddresses(i, previous, input);
            if (input != NATIVE_ASSET && input.code.length == 0) revert InvalidAsset(input);
            previous = input;
            _inputAssets.push(input);
            _acceptedInput[input] = true;
            _trackAsset(input);
        }
        for (uint256 i; i < targetLength; ++i) {
            BasketTarget memory target = allocation.targets[i];
            StoredTarget storage stored = _targets.push();
            stored.depositAsset = target.depositAsset;
            stored.yieldAdapter = target.yieldAdapter;
            stored.targetWeightBps = target.targetWeightBps;
            stored.rewardAssets = target.rewardAssets;
            _yieldApprovalProof[i] = target.yieldApprovalProof;
            _trackAsset(target.depositAsset);
            for (uint256 j; j < target.rewardAssets.length; ++j) {
                _trackAsset(target.rewardAssets[j]);
            }
        }
        uint256 legCount = allocation.swapLegs.length;
        uint256 requiredLegCount;
        for (uint256 i; i < inputCount; ++i) {
            for (uint256 j; j < targetLength; ++j) {
                if (allocation.inputAssets[i] != allocation.targets[j].depositAsset) {
                    requiredLegCount += 1;
                }
            }
        }
        if (legCount != requiredLegCount) revert InvalidConfiguration();
        for (uint256 i; i < legCount; ++i) {
            BasketSwapLeg memory leg = allocation.swapLegs[i];
            if (
                leg.targetIndex >= targetLength || !_acceptedInput[leg.inputAsset]
                    || leg.inputAsset == _targets[leg.targetIndex].depositAsset
            ) revert InvalidSwapLeg(i);
            bytes32 key = _legKey(leg.inputAsset, leg.targetIndex);
            if (_swapLegs[key].exists) {
                revert DuplicateSwapLeg(leg.inputAsset, leg.targetIndex);
            }
            StoredSwapLeg storage storedLeg = _swapLegs[key];
            storedLeg.swapAdapter = leg.swapAdapter;
            storedLeg.priceGuard = leg.priceGuard;
            storedLeg.maxSlippageBps = leg.maxSlippageBps;
            storedLeg.routeData = leg.routeData;
            storedLeg.approvalProof = leg.approvalProof;
            storedLeg.exists = true;
        }
    }

    function _validateStoredConfiguration() private view {
        if (integrationApprovalRoot == bytes32(0)) revert InvalidConfiguration();
        uint256 targetLength = _targets.length;
        uint256 totalWeight;
        for (uint256 i; i < targetLength; ++i) {
            StoredTarget storage target = _targets[i];
            if (
                target.depositAsset.code.length == 0 || target.yieldAdapter.code.length == 0
                    || target.targetWeightBps == 0
            ) revert InvalidTarget(i);
            for (uint256 j; j < i; ++j) {
                if (
                    _targets[j].depositAsset == target.depositAsset
                        || _targets[j].yieldAdapter == target.yieldAdapter
                ) revert InvalidTarget(i);
            }
            if (
                IBasketYieldAdapter(target.yieldAdapter).basketVault() != address(this)
                    || IBasketYieldAdapter(target.yieldAdapter).depositAsset()
                        != target.depositAsset
            ) revert YieldAdapterBindingMismatch(i, target.yieldAdapter);
            bytes32 yieldLeaf = yieldApprovalLeaf(target.yieldAdapter, target.depositAsset);
            if (!MerkleProof.verify(_yieldApprovalProof[i], integrationApprovalRoot, yieldLeaf)) {
                revert IntegrationNotApproved(yieldLeaf);
            }
            _validateRewardAssets(i, target.rewardAssets);
            totalWeight += target.targetWeightBps;
        }
        if (totalWeight != BPS) revert InvalidTargetWeights(totalWeight);
        uint256 inputCount = _inputAssets.length;
        for (uint256 i; i < inputCount; ++i) {
            address inputAsset = _inputAssets[i];
            for (uint256 j; j < targetLength; ++j) {
                if (inputAsset == _targets[j].depositAsset) continue;
                StoredSwapLeg storage leg = _swapLegs[_legKey(inputAsset, j)];
                if (!leg.exists) revert MissingSwapLeg(inputAsset, j);
                _validateSwapLeg(inputAsset, j, leg);
            }
        }
    }

    function _validateRewardAssets(uint256 targetIndex, address[] storage rewards) private view {
        uint256 count = rewards.length;
        if (count > MAX_REWARD_ASSETS_PER_TARGET) revert InvalidRewardAssets(targetIndex);
        address previous;
        for (uint256 i; i < count; ++i) {
            address asset = rewards[i];
            if (i != 0 && asset <= previous) revert InvalidRewardAssets(targetIndex);
            if (asset == _targets[targetIndex].depositAsset) {
                revert InvalidRewardAssets(targetIndex);
            }
            if (asset != NATIVE_ASSET && asset.code.length == 0) {
                revert InvalidRewardAssets(targetIndex);
            }
            previous = asset;
        }
    }

    function _validateSwapLeg(address inputAsset, uint256 targetIndex, StoredSwapLeg storage leg)
        private
        view
    {
        if (
            leg.swapAdapter.code.length == 0 || leg.priceGuard.code.length == 0
                || leg.maxSlippageBps == 0 || leg.maxSlippageBps > BPS
        ) revert InvalidSwapLeg(targetIndex);
        bytes32 leaf = swapApprovalLeaf(
            inputAsset,
            targetIndex,
            leg.swapAdapter,
            leg.priceGuard,
            leg.maxSlippageBps,
            keccak256(leg.routeData)
        );
        if (!MerkleProof.verify(leg.approvalProof, integrationApprovalRoot, leaf)) {
            revert IntegrationNotApproved(leaf);
        }
    }

    function _allocate(address inputAsset, uint256 amount) private {
        uint256 targetLength = _targets.length;
        uint256 cumulativeAfter = totalFunded[inputAsset] + amount;
        uint256 cumulativeBps;
        uint256 totalTarget;
        totalFunded[inputAsset] = cumulativeAfter;
        for (uint256 i; i < targetLength; ++i) {
            cumulativeBps += _targets[i].targetWeightBps;
            uint256 targetAmount = i + 1 == targetLength
                ? cumulativeAfter
                : Math.mulDiv(cumulativeAfter, cumulativeBps, BPS);
            uint256 share = targetAmount - totalTarget - allocated[inputAsset][i];
            totalTarget = targetAmount;
            allocated[inputAsset][i] += share;
            if (share == 0) continue;
            uint256 depositAmount =
                inputAsset == _targets[i].depositAsset ? share : _swap(inputAsset, i, share);
            _deposit(i, depositAmount);
            emit FundingAllocated(inputAsset, i, _targets[i].depositAsset, share, depositAmount);
        }
    }

    function _swap(address inputAsset, uint256 targetIndex, uint256 amountIn)
        private
        returns (uint256 amountOut)
    {
        StoredSwapLeg storage leg = _swapLegs[_legKey(inputAsset, targetIndex)];
        _validateSwapLeg(inputAsset, targetIndex, leg);
        address outputAsset = _targets[targetIndex].depositAsset;
        bytes32 routeHash = keccak256(leg.routeData);
        (uint256 minimum, uint48 validUntil) = IProjectPriceGuard(leg.priceGuard)
            .minimumOutput(subject, inputAsset, outputAsset, amountIn, routeHash, "");
        if (minimum == 0) revert InvalidGuardMinimum(minimum);
        uint48 currentTime = Time.timestamp();
        if (validUntil < currentTime) {
            revert GuardQuoteExpired(validUntil, currentTime);
        }
        uint256 beforeInput = _balance(inputAsset);
        uint256 beforeOutput = _balance(outputAsset);
        if (inputAsset == NATIVE_ASSET) {
            IProjectSwapAdapter(leg.swapAdapter).swap{ value: amountIn }(
                inputAsset, outputAsset, amountIn, minimum, leg.routeData
            );
        } else {
            IERC20(inputAsset).forceApprove(leg.swapAdapter, amountIn);
            IProjectSwapAdapter(leg.swapAdapter)
                .swap(inputAsset, outputAsset, amountIn, minimum, leg.routeData);
            IERC20(inputAsset).forceApprove(leg.swapAdapter, 0);
        }
        uint256 afterInput = _balance(inputAsset);
        uint256 spent = beforeInput >= afterInput ? beforeInput - afterInput : 0;
        if (spent != amountIn) revert InexactAssetSpend(inputAsset, amountIn, spent);
        uint256 afterOutput = _balance(outputAsset);
        amountOut = afterOutput >= beforeOutput ? afterOutput - beforeOutput : 0;
        if (amountOut < minimum) revert InsufficientSwapOutput(minimum, amountOut);
    }

    function _deposit(uint256 targetIndex, uint256 amount) private {
        StoredTarget storage target = _targets[targetIndex];
        uint256 balanceBefore = IERC20(target.depositAsset).balanceOf(address(this));
        uint256 positionBefore = IBasketYieldAdapter(target.yieldAdapter).totalAssets();
        IERC20(target.depositAsset).forceApprove(target.yieldAdapter, amount);
        uint256 units = IBasketYieldAdapter(target.yieldAdapter).deposit(amount);
        IERC20(target.depositAsset).forceApprove(target.yieldAdapter, 0);
        uint256 balanceAfter = IERC20(target.depositAsset).balanceOf(address(this));
        uint256 spent = balanceBefore >= balanceAfter ? balanceBefore - balanceAfter : 0;
        if (spent != amount) revert InexactYieldDeposit(targetIndex, amount, spent);
        if (units == 0) revert InvalidPositionUnits(targetIndex);
        uint256 positionAfter = IBasketYieldAdapter(target.yieldAdapter).totalAssets();
        if (positionAfter < positionBefore + amount) {
            revert InexactYieldDeposit(targetIndex, amount, positionAfter - positionBefore);
        }
        target.lockedPrincipal += amount;
    }

    function _harvestTarget(uint256 targetIndex, StoredTarget storage target) private {
        uint256 positionBefore = IBasketYieldAdapter(target.yieldAdapter).totalAssets();
        if (positionBefore < target.lockedPrincipal) {
            revert PrincipalNotRestored(targetIndex, target.lockedPrincipal, positionBefore);
        }
        address[] memory expected = _expectedTargetAssets(target);
        uint256[] memory balancesBefore = _snapshotBalances(expected);
        (address[] memory assets, uint256[] memory amounts) =
            IBasketYieldAdapter(target.yieldAdapter).harvest(address(this));
        uint256 positionAfter = IBasketYieldAdapter(target.yieldAdapter).totalAssets();
        if (positionAfter < target.lockedPrincipal) {
            revert PrincipalNotRestored(targetIndex, target.lockedPrincipal, positionAfter);
        }
        _validateAdapterOutput(targetIndex, expected, balancesBefore, assets, amounts);
        uint256 count = expected.length;
        for (uint256 i; i < count; ++i) {
            uint256 amount = amounts[i];
            if (amount == 0) continue;
            address asset = expected[i];
            if (pendingDividend[asset] == 0) pendingDividendAssetCount += 1;
            pendingDividend[asset] += amount;
        }
    }

    function _tryAllPendingDividends() private {
        uint256 count = _trackedAssets.length;
        for (uint256 i; i < count; ++i) {
            address asset = _trackedAssets[i];
            if (pendingDividend[asset] != 0) _tryPendingDividend(asset);
        }
    }

    function _tryPendingDividend(address asset) private returns (bool funded) {
        uint256 amount = pendingDividend[asset];
        try this.fundPendingDividend(asset) {
            return true;
        } catch {
            emit DividendPending(asset, amount, bytes32(0));
            return false;
        }
    }

    function _exitTarget(uint256 targetIndex, StoredTarget storage target) private {
        address[] memory expected = _expectedTargetAssets(target);
        uint256[] memory balancesBefore = _snapshotBalances(expected);
        (address[] memory assets, uint256[] memory amounts) =
            IBasketYieldAdapter(target.yieldAdapter).exitAll(address(this));
        if (IBasketYieldAdapter(target.yieldAdapter).totalAssets() != 0) {
            revert InvalidConfiguration();
        }
        _validateAdapterOutput(targetIndex, expected, balancesBefore, assets, amounts);
        target.lockedPrincipal = 0;
    }

    function _expectedTargetAssets(StoredTarget storage target)
        private
        view
        returns (address[] memory expected)
    {
        uint256 rewards = target.rewardAssets.length;
        expected = new address[](rewards + 1);
        uint256 sourceIndex;
        bool depositInserted;
        for (uint256 i; i < expected.length; ++i) {
            if (
                !depositInserted
                    && (sourceIndex == rewards
                        || target.depositAsset < target.rewardAssets[sourceIndex])
            ) {
                expected[i] = target.depositAsset;
                depositInserted = true;
            } else {
                expected[i] = target.rewardAssets[sourceIndex];
                sourceIndex += 1;
            }
        }
    }

    function _snapshotBalances(address[] memory assets)
        private
        view
        returns (uint256[] memory balances)
    {
        uint256 count = assets.length;
        balances = new uint256[](count);
        for (uint256 i; i < count; ++i) {
            balances[i] = _balance(assets[i]);
        }
    }

    function _validateAdapterOutput(
        uint256 targetIndex,
        address[] memory expected,
        uint256[] memory balancesBefore,
        address[] memory assets,
        uint256[] memory amounts
    ) private view {
        uint256 count = expected.length;
        if (assets.length != count || amounts.length != count) {
            revert AdapterOutputMismatch(targetIndex);
        }
        for (uint256 i; i < count; ++i) {
            if (assets[i] != expected[i]) revert AdapterOutputMismatch(targetIndex);
            uint256 afterBalance = _balance(expected[i]);
            if (afterBalance < balancesBefore[i]) revert AdapterOutputMismatch(targetIndex);
            if (amounts[i] != afterBalance - balancesBefore[i]) {
                revert AdapterOutputMismatch(targetIndex);
            }
        }
    }

    function _clearAllocation() private {
        uint256 inputCount = _inputAssets.length;
        uint256 targetLength = _targets.length;
        for (uint256 i; i < inputCount; ++i) {
            address input = _inputAssets[i];
            _acceptedInput[input] = false;
            totalFunded[input] = 0;
            for (uint256 j; j < targetLength; ++j) {
                allocated[input][j] = 0;
                delete _swapLegs[_legKey(input, j)];
            }
        }
        delete _inputAssets;
        for (uint256 i; i < targetLength; ++i) {
            delete _yieldApprovalProof[i];
        }
        delete _targets;
    }

    function _sendTax(address asset, uint256 amount, address taxRecipient) private {
        if (
            burnTaxDestination == BasketBurnTaxDestination.ROUTER
                || burnTaxDestination == BasketBurnTaxDestination.AIRDROP
        ) {
            bytes memory config = burnTaxDestination == BasketBurnTaxDestination.AIRDROP
                ? airdropAccountConfig
                : bytes("");
            _fundSink(taxRecipient, asset, amount, config);
        } else {
            _sendExact(asset, taxRecipient, amount);
        }
    }

    function _fundSink(address sink, address asset, uint256 amount, bytes memory config) private {
        uint256 beforeBalance = _balance(asset);
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
        if (reported != amount) revert InvalidAirdropReceipt(amount, reported);
        uint256 afterBalance = _balance(asset);
        uint256 spent = beforeBalance >= afterBalance ? beforeBalance - afterBalance : 0;
        if (spent != amount) revert InexactAssetSpend(asset, amount, spent);
    }

    function _sendExact(address asset, address recipient, uint256 amount) private {
        uint256 beforeVault = _balance(asset);
        if (asset == NATIVE_ASSET) {
            (bool success,) = recipient.call{ value: amount }("");
            if (!success) revert NativeTransferFailed(recipient, amount);
        } else {
            uint256 beforeRecipient = IERC20(asset).balanceOf(recipient);
            IERC20(asset).safeTransfer(recipient, amount);
            uint256 received = IERC20(asset).balanceOf(recipient) - beforeRecipient;
            if (received != amount) revert InexactAssetReceipt(asset, amount, received);
        }
        uint256 afterVault = _balance(asset);
        uint256 spent = beforeVault >= afterVault ? beforeVault - afterVault : 0;
        if (spent != amount) revert InexactAssetSpend(asset, amount, spent);
    }

    function _taxRecipient() private view returns (address) {
        if (burnTaxDestination == BasketBurnTaxDestination.CREATOR) return creator;
        if (burnTaxDestination == BasketBurnTaxDestination.TREASURY) return treasury;
        if (burnTaxDestination == BasketBurnTaxDestination.ROUTER) return router;
        return airdrop;
    }

    function _trackAsset(address asset) private {
        if (_isTrackedAsset[asset]) return;
        uint256 nextCount = _trackedAssets.length + 1;
        if (nextCount > MAX_TRACKED_ASSETS) revert TooManyTrackedAssets(nextCount);
        _isTrackedAsset[asset] = true;
        uint256 insertAt = _trackedAssets.length;
        _trackedAssets.push(asset);
        while (insertAt != 0 && _trackedAssets[insertAt - 1] > asset) {
            _trackedAssets[insertAt] = _trackedAssets[insertAt - 1];
            --insertAt;
        }
        _trackedAssets[insertAt] = asset;
    }

    function _legKey(address inputAsset, uint256 targetIndex) private pure returns (bytes32) {
        return keccak256(abi.encode(inputAsset, targetIndex));
    }

    function _balance(address asset) private view returns (uint256) {
        return
            asset == NATIVE_ASSET ? address(this).balance : IERC20(asset).balanceOf(address(this));
    }
}
