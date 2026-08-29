// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { YieldBankAdapterState, YieldBankRedemptionMode } from "../YieldBankTypes.sol";
import { IYieldBankEligibilityPolicy } from "../interfaces/IYieldBankEligibilityPolicy.sol";
import { IYieldBankSleeve } from "../interfaces/IYieldBankSleeve.sol";
import { IStrategyAdapter } from "../interfaces/IStrategyAdapter.sol";
import { IPriceHub } from "../interfaces/IPriceHub.sol";
import { StrategyRegistry } from "../StrategyRegistry.sol";

/// @notice Solvent, capped ERC-20 share base for a single Yield Banks risk category.
abstract contract BaseSleeve is ERC20, ReentrancyGuard, IYieldBankSleeve {
    using SafeERC20 for IERC20;

    uint16 internal constant BPS = 10_000;
    uint256 public constant MAX_INVENTORY_ASSETS = 8;
    uint256 public constant MAX_ADAPTERS = 8;
    uint256 internal constant VIRTUAL_USD_ASSETS = 1e18;
    uint256 internal constant VIRTUAL_SHARES = 1e18;

    bytes32 public immutable override category;
    address public immutable override accountingAsset;
    address public immutable allocator;
    address public immutable timelock;
    address public immutable guardian;
    IPriceHub public immutable priceHub;
    StrategyRegistry public immutable strategyRegistry;
    IYieldBankEligibilityPolicy public immutable eligibilityPolicy;
    uint8 public immutable accountingDecimals;
    uint8 public immutable maximumStrategies;
    uint16 public immutable maximumAdapterCapBps;
    uint16 public immutable maximumOperatorLossBps;
    bool public depositsPaused;

    address[] internal _inventoryAssets;
    address[] internal _adapters;
    mapping(address asset => bool supported) public isInventoryAsset;
    mapping(address adapter => YieldBankAdapterState state) public adapterState;
    mapping(address adapter => uint16 capBps) public adapterCapBps;

    error OnlyAllocator(address caller);
    error OnlyTimelock(address caller);
    error OnlyGuardian(address caller);
    error InvalidConfiguration();
    error InvalidAsset(address asset);
    error InvalidAdapter(address adapter);
    error InvalidAdapterState(address adapter, YieldBankAdapterState state);
    error TooManyAssets(uint256 supplied);
    error TooManyAdapters(uint256 supplied);
    error DepositsPaused();
    error InsufficientShares(uint256 minimum, uint256 actual);
    error UnsupportedRedemptionMode(YieldBankRedemptionMode mode);
    error IlliquidStrategy(address adapter, uint256 managedAssets);
    error Ineligible(address account);
    error InexactReceipt(uint256 expected, uint256 received);
    error InsufficientAdapterOutput(uint256 minimum, uint256 actual);
    error RuntimeCodeHashMismatch(address adapter);
    error CapExceeded(uint256 maximum, uint256 requested);

    event InventoryAssetAdded(address indexed asset);
    event InventoryAssetReplaced(address indexed previousAsset, address indexed replacementAsset);
    event Deposited(
        address indexed caller, address indexed receiver, uint256 assets, uint256 shares
    );
    event Redeemed(address indexed owner, address indexed receiver, uint256 shares);
    event AdapterStateChanged(
        address indexed adapter, YieldBankAdapterState previousState, YieldBankAdapterState newState
    );
    event AdapterDeposit(address indexed adapter, uint256 assets, uint256 positionUnits);
    event AdapterWithdrawal(
        address indexed adapter, uint256 assetsRequested, uint256 assetsReturned
    );
    event AdapterExited(address indexed adapter, address[] assets, uint256[] amounts);
    event AdapterCollected(address indexed adapter, address[] assets, uint256[] amounts);
    event AdapterCapSet(address indexed adapter, uint16 previousCapBps, uint16 newCapBps);
    event DepositsPauseSet(bool paused);

    constructor(
        string memory name_,
        string memory symbol_,
        bytes32 category_,
        address accountingAsset_,
        address allocator_,
        address timelock_,
        address guardian_,
        address priceHub_,
        address strategyRegistry_,
        address eligibilityPolicy_,
        uint8 maximumStrategies_,
        uint16 maximumAdapterCapBps_,
        uint16 maximumOperatorLossBps_
    ) ERC20(name_, symbol_) {
        if (
            category_ == bytes32(0) || accountingAsset_.code.length == 0 || allocator_ == address(0)
                || timelock_ == address(0) || guardian_ == address(0) || priceHub_.code.length == 0
                || strategyRegistry_.code.length == 0 || eligibilityPolicy_.code.length == 0
                || maximumStrategies_ > MAX_ADAPTERS || maximumAdapterCapBps_ > BPS
                || (maximumStrategies_ != 0 && maximumAdapterCapBps_ == 0)
                || maximumOperatorLossBps_ > BPS
        ) revert InvalidConfiguration();
        uint8 decimals_ = IERC20Metadata(accountingAsset_).decimals();
        if (decimals_ > 18) revert InvalidConfiguration();
        category = category_;
        accountingAsset = accountingAsset_;
        allocator = allocator_;
        timelock = timelock_;
        guardian = guardian_;
        priceHub = IPriceHub(priceHub_);
        strategyRegistry = StrategyRegistry(strategyRegistry_);
        eligibilityPolicy = IYieldBankEligibilityPolicy(eligibilityPolicy_);
        accountingDecimals = decimals_;
        maximumStrategies = maximumStrategies_;
        maximumAdapterCapBps = maximumAdapterCapBps_;
        maximumOperatorLossBps = maximumOperatorLossBps_;
        _addInventoryAsset(accountingAsset_);
    }

    modifier onlyAllocator() {
        if (msg.sender != allocator) revert OnlyAllocator(msg.sender);
        _;
    }

    modifier onlyTimelock() {
        if (msg.sender != timelock) revert OnlyTimelock(msg.sender);
        _;
    }

    modifier onlyGuardian() {
        if (msg.sender != guardian) revert OnlyGuardian(msg.sender);
        _;
    }

    function inventoryAssets() external view returns (address[] memory) {
        return _inventoryAssets;
    }

    function adapters() external view returns (address[] memory) {
        return _adapters;
    }

    function activeStrategyCount() public view override returns (uint256 count) {
        uint256 length = _adapters.length;
        for (uint256 i; i < length; ++i) {
            YieldBankAdapterState current = adapterState[_adapters[i]];
            if (
                current == YieldBankAdapterState.ACTIVE
                    || current == YieldBankAdapterState.DEPOSIT_PAUSED
                    || current == YieldBankAdapterState.EXIT_ONLY
            ) ++count;
        }
    }

    function totalAssetsUsd18() public view override returns (uint256 value, uint48 pricedAt) {
        pricedAt = type(uint48).max;
        uint256 length = _inventoryAssets.length;
        for (uint256 i; i < length; ++i) {
            address asset = _inventoryAssets[i];
            uint256 balance = IERC20(asset).balanceOf(address(this));
            if (balance == 0) continue;
            (uint256 price, uint48 timestamp, IPriceHub.FailureReason failure) =
                priceHub.quoteUsd18(asset);
            if (failure != IPriceHub.FailureReason.NONE) return (0, timestamp);
            uint8 decimals_ = IERC20Metadata(asset).decimals();
            value += Math.mulDiv(balance, price, 10 ** decimals_);
            if (timestamp < pricedAt) pricedAt = timestamp;
        }
        uint256 adapterLength = _adapters.length;
        for (uint256 i; i < adapterLength; ++i) {
            address adapter = _adapters[i];
            YieldBankAdapterState current = adapterState[adapter];
            if (current == YieldBankAdapterState.RETIRED) continue;
            uint256 managed = IStrategyAdapter(adapter).totalManagedAssets();
            if (managed != 0) {
                (uint256 price, uint48 timestamp, IPriceHub.FailureReason failure) =
                    priceHub.quoteUsd18(accountingAsset);
                if (failure != IPriceHub.FailureReason.NONE) return (0, timestamp);
                value += Math.mulDiv(managed, price, 10 ** accountingDecimals);
                if (timestamp < pricedAt) pricedAt = timestamp;
            }
        }
        if (pricedAt == type(uint48).max) pricedAt = 0;
    }

    function deposit(uint256 assets, address receiver, uint256 minShares, bytes calldata data)
        external
        override
        onlyAllocator
        nonReentrant
        returns (uint256 shares)
    {
        if (depositsPaused) revert DepositsPaused();
        if (assets == 0 || receiver == address(0)) revert InvalidConfiguration();
        (uint256 navBefore,) = totalAssetsUsd18();
        (uint256 price,, IPriceHub.FailureReason failure) = priceHub.quoteUsd18(accountingAsset);
        if (failure != IPriceHub.FailureReason.NONE || price == 0) revert InvalidConfiguration();
        uint256 assetValue = Math.mulDiv(assets, price, 10 ** accountingDecimals);
        IERC20 token = IERC20(accountingAsset);
        uint256 beforeBalance = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), assets);
        uint256 received = token.balanceOf(address(this)) - beforeBalance;
        if (received != assets) revert InexactReceipt(assets, received);
        uint256 creditedValue = _afterDeposit(assets, data, assetValue);
        shares = Math.mulDiv(
            creditedValue, totalSupply() + VIRTUAL_SHARES, navBefore + VIRTUAL_USD_ASSETS
        );
        if (shares < minShares || shares == 0) revert InsufficientShares(minShares, shares);
        _mint(receiver, shares);
        emit Deposited(msg.sender, receiver, assets, shares);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner,
        YieldBankRedemptionMode mode,
        uint256 minimumOutput,
        bytes calldata
    ) external override nonReentrant returns (address[] memory assets, uint256[] memory amounts) {
        if (mode != YieldBankRedemptionMode.IN_KIND) revert UnsupportedRedemptionMode(mode);
        if (shares == 0 || receiver == address(0) || owner == address(0)) {
            revert InvalidConfiguration();
        }
        if (!eligibilityPolicy.canRedeem(receiver, "")) revert Ineligible(receiver);
        uint256 adapterLength = _adapters.length;
        for (uint256 i; i < adapterLength; ++i) {
            uint256 managed = IStrategyAdapter(_adapters[i]).totalManagedAssets();
            if (managed != 0) revert IlliquidStrategy(_adapters[i], managed);
        }
        if (msg.sender != owner) _spendAllowance(owner, msg.sender, shares);
        uint256 supplyBefore = totalSupply();
        _burn(owner, shares);
        uint256 length = _inventoryAssets.length;
        assets = new address[](length);
        amounts = new uint256[](length);
        uint256 aggregate;
        for (uint256 i; i < length; ++i) {
            address asset = _inventoryAssets[i];
            uint256 amount =
                Math.mulDiv(IERC20(asset).balanceOf(address(this)), shares, supplyBefore);
            assets[i] = asset;
            amounts[i] = amount;
            aggregate += amount;
            if (amount != 0) IERC20(asset).safeTransfer(receiver, amount);
        }
        if (aggregate < minimumOutput) revert InsufficientShares(minimumOutput, aggregate);
        emit Redeemed(owner, receiver, shares);
    }

    function addAdapter(address adapter, uint16 capBps) external onlyTimelock {
        if (adapterState[adapter] != YieldBankAdapterState.UNREGISTERED) {
            revert InvalidAdapterState(adapter, adapterState[adapter]);
        }
        StrategyRegistry.StrategyRecord memory record = strategyRegistry.recordOf(adapter);
        if (
            record.state != YieldBankAdapterState.REGISTERED || record.sleeveCategory != category
                || record.accountingAsset != accountingAsset
                || IStrategyAdapter(adapter).sleeve() != address(this)
                || !strategyRegistry.isRuntimeValid(adapter)
        ) revert InvalidAdapter(adapter);
        if (capBps == 0 || capBps > maximumAdapterCapBps) {
            revert CapExceeded(maximumAdapterCapBps, capBps);
        }
        uint256 nextLength = _adapters.length + 1;
        if (nextLength > maximumStrategies) revert TooManyAdapters(nextLength);
        address[] memory outputs = IStrategyAdapter(adapter).positionAssets();
        if (outputs.length == 0) revert InvalidAdapter(adapter);
        for (uint256 i; i < outputs.length; ++i) {
            _addInventoryAsset(outputs[i]);
        }
        _adapters.push(adapter);
        adapterCapBps[adapter] = capBps;
        adapterState[adapter] = YieldBankAdapterState.ACTIVE;
        emit AdapterStateChanged(
            adapter, YieldBankAdapterState.UNREGISTERED, YieldBankAdapterState.ACTIVE
        );
    }

    function setAdapterCap(address adapter, uint16 capBps) external onlyTimelock {
        YieldBankAdapterState current = adapterState[adapter];
        if (
            current != YieldBankAdapterState.ACTIVE
                && current != YieldBankAdapterState.DEPOSIT_PAUSED
        ) revert InvalidAdapterState(adapter, current);
        if (capBps == 0 || capBps > maximumAdapterCapBps) {
            revert CapExceeded(maximumAdapterCapBps, capBps);
        }
        _requireRuntime(adapter);
        uint16 previous = adapterCapBps[adapter];
        adapterCapBps[adapter] = capBps;
        emit AdapterCapSet(adapter, previous, capBps);
    }

    function pauseAdapterDeposits(address adapter) external onlyGuardian {
        YieldBankAdapterState previous = adapterState[adapter];
        if (previous != YieldBankAdapterState.ACTIVE) {
            revert InvalidAdapterState(adapter, previous);
        }
        adapterState[adapter] = YieldBankAdapterState.DEPOSIT_PAUSED;
        emit AdapterStateChanged(adapter, previous, YieldBankAdapterState.DEPOSIT_PAUSED);
    }

    function setExitOnly(address adapter) external onlyGuardian {
        YieldBankAdapterState previous = adapterState[adapter];
        if (
            previous != YieldBankAdapterState.ACTIVE
                && previous != YieldBankAdapterState.DEPOSIT_PAUSED
        ) revert InvalidAdapterState(adapter, previous);
        adapterState[adapter] = YieldBankAdapterState.EXIT_ONLY;
        emit AdapterStateChanged(adapter, previous, YieldBankAdapterState.EXIT_ONLY);
    }

    function retireAdapter(address adapter) external onlyTimelock {
        YieldBankAdapterState previous = adapterState[adapter];
        if (
            previous != YieldBankAdapterState.EXIT_ONLY
                || IStrategyAdapter(adapter).totalManagedAssets() != 0
        ) revert InvalidAdapterState(adapter, previous);
        adapterState[adapter] = YieldBankAdapterState.RETIRED;
        adapterCapBps[adapter] = 0;
        emit AdapterStateChanged(adapter, previous, YieldBankAdapterState.RETIRED);
    }

    function depositToAdapter(
        address adapter,
        uint256 assets,
        uint256 minPositionUnits,
        bytes calldata data
    ) external onlyAllocator nonReentrant returns (uint256 positionUnits) {
        if (assets == 0) revert InvalidConfiguration();
        YieldBankAdapterState current = adapterState[adapter];
        if (depositsPaused || current != YieldBankAdapterState.ACTIVE) {
            revert InvalidAdapterState(adapter, current);
        }
        _requireRuntime(adapter);
        uint256 totalAccounting = IERC20(accountingAsset).balanceOf(address(this));
        uint256 adapterLength = _adapters.length;
        for (uint256 i; i < adapterLength; ++i) {
            totalAccounting += IStrategyAdapter(_adapters[i]).totalManagedAssets();
        }
        uint256 maximum = Math.mulDiv(totalAccounting, adapterCapBps[adapter], BPS);
        if (IStrategyAdapter(adapter).totalManagedAssets() + assets > maximum) {
            revert CapExceeded(maximum, IStrategyAdapter(adapter).totalManagedAssets() + assets);
        }
        IERC20 token = IERC20(accountingAsset);
        uint256 balanceBefore = token.balanceOf(address(this));
        token.forceApprove(adapter, assets);
        positionUnits = IStrategyAdapter(adapter).deposit(assets, minPositionUnits, data);
        token.forceApprove(adapter, 0);
        uint256 consumed = balanceBefore - token.balanceOf(address(this));
        if (consumed != assets) revert InexactReceipt(assets, consumed);
        if (positionUnits < minPositionUnits || positionUnits == 0) {
            revert InsufficientAdapterOutput(minPositionUnits, positionUnits);
        }
        emit AdapterDeposit(adapter, assets, positionUnits);
    }

    function withdrawFromAdapter(
        address adapter,
        uint256 assets,
        uint16 maxLossBps,
        bytes calldata data
    ) external onlyAllocator nonReentrant returns (uint256 assetsReturned) {
        if (assets == 0) revert InvalidConfiguration();
        if (maxLossBps > maximumOperatorLossBps) {
            revert CapExceeded(maximumOperatorLossBps, maxLossBps);
        }
        YieldBankAdapterState current = adapterState[adapter];
        if (
            current != YieldBankAdapterState.ACTIVE
                && current != YieldBankAdapterState.DEPOSIT_PAUSED
                && current != YieldBankAdapterState.EXIT_ONLY
        ) revert InvalidAdapterState(adapter, current);
        uint256 beforeBalance = IERC20(accountingAsset).balanceOf(address(this));
        assetsReturned = IStrategyAdapter(adapter).withdraw(assets, address(this), maxLossBps, data);
        uint256 measured = IERC20(accountingAsset).balanceOf(address(this)) - beforeBalance;
        if (assetsReturned != measured) revert InexactReceipt(assetsReturned, measured);
        uint256 minimum = Math.mulDiv(assets, BPS - maxLossBps, BPS);
        if (measured < minimum) revert InsufficientAdapterOutput(minimum, measured);
        emit AdapterWithdrawal(adapter, assets, assetsReturned);
    }

    function exitAdapter(address adapter, uint16 maxLossBps, bytes calldata data)
        external
        onlyAllocator
        nonReentrant
        returns (address[] memory assets, uint256[] memory amounts)
    {
        if (maxLossBps > maximumOperatorLossBps) {
            revert CapExceeded(maximumOperatorLossBps, maxLossBps);
        }
        YieldBankAdapterState current = adapterState[adapter];
        if (
            current != YieldBankAdapterState.DEPOSIT_PAUSED
                && current != YieldBankAdapterState.EXIT_ONLY
        ) revert InvalidAdapterState(adapter, current);
        uint256[] memory balancesBefore = _inventoryBalances();
        (assets, amounts) = IStrategyAdapter(adapter).exitAll(address(this), maxLossBps, data);
        _validateAdapterOutputs(assets, amounts, balancesBefore);
        emit AdapterExited(adapter, assets, amounts);
    }

    function collectAdapter(address adapter, bytes calldata data)
        external
        onlyAllocator
        nonReentrant
        returns (address[] memory assets, uint256[] memory amounts)
    {
        YieldBankAdapterState current = adapterState[adapter];
        if (
            current != YieldBankAdapterState.ACTIVE
                && current != YieldBankAdapterState.DEPOSIT_PAUSED
                && current != YieldBankAdapterState.EXIT_ONLY
        ) revert InvalidAdapterState(adapter, current);
        uint256[] memory balancesBefore = _inventoryBalances();
        (assets, amounts) = IStrategyAdapter(adapter).collect(address(this), data);
        _validateAdapterOutputs(assets, amounts, balancesBefore);
        emit AdapterCollected(adapter, assets, amounts);
    }

    function syncRuntimeStatus(address adapter) external {
        YieldBankAdapterState current = adapterState[adapter];
        if (
            current == YieldBankAdapterState.ACTIVE
                || current == YieldBankAdapterState.DEPOSIT_PAUSED
        ) {
            if (!strategyRegistry.isRuntimeValid(adapter)) {
                adapterState[adapter] = YieldBankAdapterState.EXIT_ONLY;
                emit AdapterStateChanged(adapter, current, YieldBankAdapterState.EXIT_ONLY);
            }
        }
    }

    function setDepositsPaused(bool paused) external {
        if (paused) {
            if (msg.sender != guardian && msg.sender != timelock) revert OnlyGuardian(msg.sender);
        } else if (msg.sender != timelock) {
            revert OnlyTimelock(msg.sender);
        }
        depositsPaused = paused;
        emit DepositsPauseSet(paused);
    }

    function addInventoryAsset(address asset) external onlyTimelock {
        _addInventoryAsset(asset);
    }

    function _addInventoryAsset(address asset) internal {
        if (asset.code.length == 0) revert InvalidAsset(asset);
        if (isInventoryAsset[asset]) return;
        uint256 nextLength = _inventoryAssets.length + 1;
        if (nextLength > MAX_INVENTORY_ASSETS) revert TooManyAssets(nextLength);
        if (IERC20Metadata(asset).decimals() > 18) revert InvalidAsset(asset);
        isInventoryAsset[asset] = true;
        _inventoryAssets.push(asset);
        emit InventoryAssetAdded(asset);
    }

    function _replaceInventoryAsset(address previousAsset, address replacementAsset) internal {
        if (
            replacementAsset.code.length == 0 || !isInventoryAsset[previousAsset]
                || isInventoryAsset[replacementAsset]
                || IERC20Metadata(replacementAsset).decimals() > 18
        ) revert InvalidAsset(replacementAsset);
        uint256 length = _inventoryAssets.length;
        for (uint256 i; i < length; ++i) {
            if (_inventoryAssets[i] != previousAsset) continue;
            _inventoryAssets[i] = replacementAsset;
            isInventoryAsset[previousAsset] = false;
            isInventoryAsset[replacementAsset] = true;
            emit InventoryAssetReplaced(previousAsset, replacementAsset);
            return;
        }
        revert InvalidAsset(previousAsset);
    }

    function _requireRuntime(address adapter) internal view {
        if (!strategyRegistry.isRuntimeValid(adapter)) revert RuntimeCodeHashMismatch(adapter);
    }

    function _inventoryBalances() private view returns (uint256[] memory balances) {
        uint256 length = _inventoryAssets.length;
        balances = new uint256[](length);
        for (uint256 i; i < length; ++i) {
            balances[i] = IERC20(_inventoryAssets[i]).balanceOf(address(this));
        }
    }

    function _validateAdapterOutputs(
        address[] memory assets,
        uint256[] memory amounts,
        uint256[] memory balancesBefore
    ) private view {
        if (assets.length != amounts.length || balancesBefore.length != _inventoryAssets.length) {
            revert InvalidConfiguration();
        }
        bool[] memory reported = new bool[](_inventoryAssets.length);
        for (uint256 i; i < assets.length; ++i) {
            address asset = assets[i];
            if (!isInventoryAsset[asset]) revert InvalidAsset(asset);
            for (uint256 j; j < i; ++j) {
                if (assets[j] == asset) revert InvalidConfiguration();
            }
            uint256 searchLength = _inventoryAssets.length;
            for (uint256 j; j < searchLength; ++j) {
                if (_inventoryAssets[j] == asset) {
                    uint256 measured = IERC20(asset).balanceOf(address(this)) - balancesBefore[j];
                    if (measured != amounts[i]) revert InexactReceipt(amounts[i], measured);
                    reported[j] = true;
                    break;
                }
            }
        }
        uint256 inventoryLength = _inventoryAssets.length;
        for (uint256 i; i < inventoryLength; ++i) {
            if (reported[i]) continue;
            uint256 measured =
                IERC20(_inventoryAssets[i]).balanceOf(address(this)) - balancesBefore[i];
            if (measured != 0) revert InexactReceipt(0, measured);
        }
    }

    function _afterDeposit(uint256, bytes calldata, uint256 defaultValue)
        internal
        virtual
        returns (uint256 creditedValue)
    {
        return defaultValue;
    }

    function _update(address from, address to, uint256 value) internal override {
        if (to != address(0) && !eligibilityPolicy.canReceiveRestrictedShares(to, "")) {
            revert Ineligible(to);
        }
        super._update(from, to, value);
    }
}
