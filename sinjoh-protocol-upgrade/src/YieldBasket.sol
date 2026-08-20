// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Governed } from "./governance/Governed.sol";
import { IGovernanceController } from "./interfaces/IGovernanceController.sol";
import { ISinjohFundable } from "./interfaces/ISinjohFundable.sol";
import { IYieldAdapter } from "./interfaces/IYieldAdapter.sol";

/// @notice Allowlisted, harvest-only treasury portfolio. Principal never becomes distributable.
contract YieldBasket is Governed, ReentrancyGuard, ISinjohFundable {
    using SafeERC20 for IERC20;

    uint16 public constant BPS = 10_000;
    uint8 public constant MAX_ADAPTERS = 16;
    uint8 public constant MAX_REWARDS_PER_HARVEST = 8;

    enum AdapterStatus {
        DISABLED,
        ACTIVE,
        DEPOSITS_PAUSED,
        FULLY_PAUSED
    }

    struct AdapterConfig {
        uint16 allocationLimitBps;
        uint32 distributionInterval;
        AdapterStatus status;
        uint48 lastDistributionAt;
        uint256 principalAllocated;
        uint256 sharesHeld;
    }

    struct RewardRouteInput {
        address rewardToken;
        address distributor;
        bytes distributionConfig;
    }

    struct RewardRoute {
        address distributor;
        bytes distributionConfig;
    }

    error InvalidAddress();
    error InvalidConfiguration();
    error AdapterNotApproved();
    error AllocationLimitExceeded();
    error DistributionNotDue(uint256 nextDistributionAt);
    error InvalidAmount();
    error InexactTransfer(uint256 expected, uint256 received);
    error SinkReceiptMismatch(uint256 expected, uint256 received);
    error RewardNotAllowlisted(address rewardToken);

    event Funded(address indexed funder, uint256 amount, uint256 totalPrincipal);
    event AdapterConfigured(
        address indexed adapter, uint16 allocationLimitBps, uint32 distributionInterval
    );
    event AdapterStatusChanged(address indexed adapter, AdapterStatus status);
    event AdapterRewardRouteSet(
        address indexed adapter, address indexed rewardToken, address indexed distributor
    );
    event AdapterRewardRoutesCleared(address indexed adapter);
    event Allocated(address indexed adapter, uint256 assets, uint256 shares);
    event WithdrawnFromAdapter(
        address indexed adapter,
        uint256 shares,
        uint256 assets,
        uint256 principalRecovered,
        uint256 realizedLoss
    );
    event IdlePrincipalWithdrawn(address indexed recipient, uint256 amount);
    event IdleValueRealized(address indexed recipient, uint256 amount);
    event AdapterWrittenOff(
        address indexed adapter, uint256 sharesWrittenOff, uint256 principalWrittenOff
    );
    event WrittenOffSharesRecovered(
        address indexed adapter, uint256 sharesRecovered, uint256 assetsRecovered
    );
    event Harvested(
        address indexed adapter, address indexed rewardToken, uint256 amount, address distributor
    );

    IERC20 public immutable depositAsset;
    uint256 public totalPrincipalContributed;
    uint256 public managedPrincipal;
    uint256 public idlePrincipal;
    uint256 public cumulativeRealizedLoss;
    uint8 public adapterCount;
    mapping(address adapter => AdapterConfig) private _adapterConfigs;
    mapping(address adapter => bool) public approvedAdapter;
    address[] private _adapters;
    mapping(address adapter => uint256 indexPlusOne) private _adapterIndex;
    mapping(address rewardToken => uint256 amount) public cumulativeRealizedYield;
    mapping(address adapter => address[] rewardTokens) private _adapterRewardTokens;
    mapping(address adapter => mapping(address rewardToken => bool)) public isAdapterRewardToken;
    mapping(address adapter => mapping(address rewardToken => RewardRoute)) private _rewardRoutes;
    mapping(address adapter => uint256 shares) public writtenOffShares;

    constructor(IGovernanceController controller, address guardian, IERC20 depositAsset_)
        Governed(controller, guardian)
    {
        if (address(depositAsset_).code.length == 0) revert InvalidAddress();
        depositAsset = depositAsset_;
    }

    /// @inheritdoc ISinjohFundable
    function fund(address asset, uint256 amount, bytes calldata config)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 received)
    {
        if (asset != address(depositAsset) || amount == 0 || config.length != 0) {
            revert InvalidConfiguration();
        }
        uint256 beforeBalance = depositAsset.balanceOf(address(this));
        depositAsset.safeTransferFrom(msg.sender, address(this), amount);
        received = depositAsset.balanceOf(address(this)) - beforeBalance;
        if (received != amount) revert InexactTransfer(amount, received);
        totalPrincipalContributed += amount;
        managedPrincipal += amount;
        idlePrincipal += amount;
        emit Funded(msg.sender, amount, totalPrincipalContributed);
    }

    function configureAdapter(
        IYieldAdapter adapter,
        uint16 allocationLimitBps,
        uint32 distributionInterval
    ) external onlyGovernance {
        address adapterAddress = address(adapter);
        if (
            adapterAddress.code.length == 0 || adapter.asset() != address(depositAsset)
                || allocationLimitBps == 0 || allocationLimitBps > BPS
                || distributionInterval < 30 minutes
        ) revert InvalidConfiguration();
        bool newlyApproved = !approvedAdapter[adapterAddress];
        if (newlyApproved) {
            if (adapterCount == MAX_ADAPTERS || writtenOffShares[adapterAddress] != 0) {
                revert InvalidConfiguration();
            }
            approvedAdapter[adapterAddress] = true;
            ++adapterCount;
            _adapterIndex[adapterAddress] = _adapters.length + 1;
            _adapters.push(adapterAddress);
        }
        AdapterConfig storage existing = _adapterConfigs[adapterAddress];
        if (existing.principalAllocated > managedPrincipal * allocationLimitBps / BPS) {
            revert AllocationLimitExceeded();
        }
        existing.allocationLimitBps = allocationLimitBps;
        existing.distributionInterval = distributionInterval;
        if (newlyApproved) existing.status = AdapterStatus.ACTIVE;
        emit AdapterConfigured(adapterAddress, allocationLimitBps, distributionInterval);
    }

    function setAdapterRewardRoutes(IYieldAdapter adapter, RewardRouteInput[] calldata routes)
        external
        onlyGovernance
    {
        address adapterAddress = address(adapter);
        if (
            !approvedAdapter[adapterAddress] || routes.length == 0
                || routes.length > MAX_REWARDS_PER_HARVEST
        ) revert InvalidConfiguration();
        _clearRewardRoutes(adapterAddress);
        for (uint256 i; i < routes.length; ++i) {
            address rewardToken = routes[i].rewardToken;
            if (
                rewardToken.code.length == 0 || rewardToken == address(depositAsset)
                    || routes[i].distributor.code.length == 0
                    || routes[i].distributionConfig.length > 2_048
                    || isAdapterRewardToken[adapterAddress][rewardToken]
            ) revert InvalidConfiguration();
            isAdapterRewardToken[adapterAddress][rewardToken] = true;
            _adapterRewardTokens[adapterAddress].push(rewardToken);
            _rewardRoutes[adapterAddress][rewardToken] = RewardRoute({
                distributor: routes[i].distributor, distributionConfig: routes[i].distributionConfig
            });
            emit AdapterRewardRouteSet(adapterAddress, rewardToken, routes[i].distributor);
        }
    }

    function setAdapterStatus(IYieldAdapter adapter, AdapterStatus status) external {
        address adapterAddress = address(adapter);
        if (!approvedAdapter[adapterAddress] || status == AdapterStatus.DISABLED) {
            revert AdapterNotApproved();
        }
        if (msg.sender == emergencyGuardian) {
            if (status != AdapterStatus.DEPOSITS_PAUSED && status != AdapterStatus.FULLY_PAUSED) {
                revert Unauthorized();
            }
        } else if (!governanceController.canCall(msg.sender, address(this), msg.sig)) {
            revert Unauthorized();
        }
        _adapterConfigs[adapterAddress].status = status;
        emit AdapterStatusChanged(adapterAddress, status);
    }

    function removeAdapter(IYieldAdapter adapter) external onlyGovernance {
        address adapterAddress = address(adapter);
        AdapterConfig storage config = _adapterConfigs[adapterAddress];
        if (
            !approvedAdapter[adapterAddress] || config.principalAllocated != 0
                || config.sharesHeld != 0
        ) {
            revert InvalidConfiguration();
        }
        approvedAdapter[adapterAddress] = false;
        _clearRewardRoutes(adapterAddress);
        --adapterCount;
        uint256 index = _adapterIndex[adapterAddress] - 1;
        uint256 lastIndex = _adapters.length - 1;
        if (index != lastIndex) {
            address moved = _adapters[lastIndex];
            _adapters[index] = moved;
            _adapterIndex[moved] = index + 1;
        }
        _adapters.pop();
        delete _adapterIndex[adapterAddress];
        delete _adapterConfigs[adapterAddress];
        emit AdapterStatusChanged(adapterAddress, AdapterStatus.DISABLED);
    }

    function allocate(IYieldAdapter adapter, uint128 amount)
        external
        onlyGovernance
        nonReentrant
        whenNotPaused
        returns (uint256 shares)
    {
        address adapterAddress = address(adapter);
        AdapterConfig storage config = _adapterConfigs[adapterAddress];
        if (
            !approvedAdapter[adapterAddress] || config.status != AdapterStatus.ACTIVE
                || writtenOffShares[adapterAddress] != 0
        ) {
            revert AdapterNotApproved();
        }
        if (amount == 0 || amount > idlePrincipal) revert InvalidAmount();
        uint256 newAllocation = uint256(config.principalAllocated) + amount;
        if (newAllocation > managedPrincipal * config.allocationLimitBps / BPS) {
            revert AllocationLimitExceeded();
        }
        uint256 beforeBalance = depositAsset.balanceOf(address(this));
        depositAsset.forceApprove(adapterAddress, amount);
        shares = adapter.deposit(amount);
        depositAsset.forceApprove(adapterAddress, 0);
        if (shares == 0) revert InvalidAmount();
        uint256 afterBalance = depositAsset.balanceOf(address(this));
        uint256 spent = beforeBalance >= afterBalance ? beforeBalance - afterBalance : 0;
        if (spent != amount) revert InexactTransfer(amount, spent);
        config.principalAllocated = newAllocation;
        config.sharesHeld += shares;
        idlePrincipal -= amount;
        emit Allocated(adapterAddress, amount, shares);
    }

    function withdrawFromAdapter(IYieldAdapter adapter, uint256 shares)
        external
        onlyGovernance
        nonReentrant
        returns (uint256 assets)
    {
        address adapterAddress = address(adapter);
        AdapterConfig storage config = _adapterConfigs[adapterAddress];
        if (!approvedAdapter[adapterAddress] || config.status == AdapterStatus.FULLY_PAUSED) {
            revert AdapterNotApproved();
        }
        uint256 oldShares = config.sharesHeld;
        if (shares == 0 || shares > oldShares) revert InvalidAmount();
        uint256 beforeBalance = depositAsset.balanceOf(address(this));
        assets = adapter.withdraw(shares);
        uint256 received = depositAsset.balanceOf(address(this)) - beforeBalance;
        if (assets == 0 || received != assets) revert InexactTransfer(assets, received);
        uint256 principalReduction = shares == oldShares
            ? config.principalAllocated
            : Math.mulDiv(config.principalAllocated, shares, oldShares);
        config.sharesHeld = oldShares - shares;
        config.principalAllocated -= principalReduction;
        uint256 recoveredPrincipal = assets < principalReduction ? assets : principalReduction;
        uint256 realizedLoss = principalReduction - recoveredPrincipal;
        idlePrincipal += recoveredPrincipal;
        if (realizedLoss != 0) {
            managedPrincipal -= realizedLoss;
            cumulativeRealizedLoss += realizedLoss;
        }
        // Assets above recovered principal remain idle, non-distributable value until governance
        // explicitly realizes them with `realizeIdleValue`.
        emit WithdrawnFromAdapter(adapterAddress, shares, assets, recoveredPrincipal, realizedLoss);
    }

    /// @notice Abandons an irrecoverable adapter position after governance has fully paused it.
    /// @dev Written-off shares remain recoverable as non-principal value if the adapter revives.
    function writeOffAdapter(IYieldAdapter adapter) external onlyGovernance {
        address adapterAddress = address(adapter);
        AdapterConfig storage config = _adapterConfigs[adapterAddress];
        if (
            !approvedAdapter[adapterAddress] || config.status != AdapterStatus.FULLY_PAUSED
                || config.principalAllocated == 0 || config.sharesHeld == 0
        ) revert InvalidConfiguration();
        uint256 principal = config.principalAllocated;
        uint256 shares = config.sharesHeld;
        config.principalAllocated = 0;
        config.sharesHeld = 0;
        writtenOffShares[adapterAddress] += shares;
        managedPrincipal -= principal;
        cumulativeRealizedLoss += principal;
        emit AdapterWrittenOff(adapterAddress, shares, principal);
    }

    /// @notice Recovers value from shares previously written off without restoring principal.
    function recoverWrittenOffShares(IYieldAdapter adapter, uint256 shares)
        external
        onlyGovernance
        nonReentrant
        returns (uint256 assets)
    {
        address adapterAddress = address(adapter);
        uint256 available = writtenOffShares[adapterAddress];
        if (shares == 0 || shares > available) revert InvalidAmount();
        uint256 beforeBalance = depositAsset.balanceOf(address(this));
        assets = adapter.withdraw(shares);
        uint256 received = depositAsset.balanceOf(address(this)) - beforeBalance;
        if (assets == 0 || received != assets) revert InexactTransfer(assets, received);
        writtenOffShares[adapterAddress] = available - shares;
        emit WrittenOffSharesRecovered(adapterAddress, shares, assets);
    }

    function withdrawIdlePrincipal(address recipient, uint256 amount)
        external
        onlyGovernance
        nonReentrant
    {
        if (
            recipient == address(0) || recipient == address(this) || amount == 0
                || amount > idlePrincipal
        ) revert InvalidAmount();
        _validateExposure(managedPrincipal - amount);
        idlePrincipal -= amount;
        managedPrincipal -= amount;
        _sendExact(depositAsset, recipient, amount);
        emit IdlePrincipalWithdrawn(recipient, amount);
    }

    function realizeIdleValue(address recipient, uint256 amount)
        external
        onlyGovernance
        nonReentrant
    {
        if (
            recipient == address(0) || recipient == address(this) || amount == 0
                || amount > idleUnrealizedValue()
        ) revert InvalidAmount();
        _sendExact(depositAsset, recipient, amount);
        emit IdleValueRealized(recipient, amount);
    }

    function harvest(IYieldAdapter adapter) external nonReentrant whenNotPaused {
        address adapterAddress = address(adapter);
        AdapterConfig storage config = _adapterConfigs[adapterAddress];
        if (!approvedAdapter[adapterAddress] || config.status == AdapterStatus.FULLY_PAUSED) {
            revert AdapterNotApproved();
        }
        uint256 nextDistributionAt =
            uint256(config.lastDistributionAt) + config.distributionInterval;
        if (block.timestamp < nextDistributionAt) {
            revert DistributionNotDue(nextDistributionAt);
        }
        address[] storage allowedRewards = _adapterRewardTokens[adapterAddress];
        if (allowedRewards.length == 0) revert InvalidConfiguration();
        uint256[] memory beforeBalances = new uint256[](allowedRewards.length);
        for (uint256 i; i < allowedRewards.length; ++i) {
            beforeBalances[i] = IERC20(allowedRewards[i]).balanceOf(address(this));
        }
        (address[] memory rewardTokens, uint256[] memory amounts) = adapter.harvest();
        if (
            rewardTokens.length == 0 || rewardTokens.length != amounts.length
                || rewardTokens.length > MAX_REWARDS_PER_HARVEST
        ) revert InvalidConfiguration();
        config.lastDistributionAt = uint48(block.timestamp);

        bool[] memory seen = new bool[](allowedRewards.length);

        for (uint256 i; i < rewardTokens.length; ++i) {
            address rewardToken = rewardTokens[i];
            uint256 amount = amounts[i];
            uint256 allowedIndex = type(uint256).max;
            for (uint256 j; j < allowedRewards.length; ++j) {
                if (allowedRewards[j] == rewardToken) allowedIndex = j;
            }
            if (allowedIndex == type(uint256).max) revert RewardNotAllowlisted(rewardToken);
            if (seen[allowedIndex] || amount == 0) revert InvalidConfiguration();
            seen[allowedIndex] = true;
            IERC20 token = IERC20(rewardToken);
            uint256 afterBalance = token.balanceOf(address(this));
            uint256 received = afterBalance >= beforeBalances[allowedIndex]
                ? afterBalance - beforeBalances[allowedIndex]
                : 0;
            if (received != amount) revert InexactTransfer(amount, received);
            cumulativeRealizedYield[rewardToken] += amount;
            RewardRoute storage route = _rewardRoutes[adapterAddress][rewardToken];
            uint256 beforeFundingBalance = afterBalance;
            token.forceApprove(route.distributor, amount);
            uint256 fundedReceived = ISinjohFundable(route.distributor)
                .fund(rewardToken, amount, route.distributionConfig);
            token.forceApprove(route.distributor, 0);
            if (fundedReceived != amount) revert SinkReceiptMismatch(amount, fundedReceived);
            uint256 finalBalance = token.balanceOf(address(this));
            uint256 spent =
                beforeFundingBalance >= finalBalance ? beforeFundingBalance - finalBalance : 0;
            if (spent != amount) revert InexactTransfer(amount, spent);
            emit Harvested(adapterAddress, rewardToken, amount, route.distributor);
        }
    }

    function getAdapterConfig(address adapter) external view returns (AdapterConfig memory) {
        return _adapterConfigs[adapter];
    }

    function getAdapterRewardTokens(address adapter) external view returns (address[] memory) {
        return _adapterRewardTokens[adapter];
    }

    function getAdapterRewardRoute(address adapter, address rewardToken)
        external
        view
        returns (RewardRoute memory)
    {
        return _rewardRoutes[adapter][rewardToken];
    }

    function getAdapters() external view returns (address[] memory) {
        return _adapters;
    }

    /// @notice Deposit-asset-denominated portfolio totals reported by allowlisted adapters.
    /// @dev Adapter values are trusted integration data and may revert or become stale.
    function basketValue()
        external
        view
        returns (
            uint256 currentAssets,
            uint256 principal,
            uint256 unrealizedGain,
            uint256 unrealizedLoss
        )
    {
        currentAssets = depositAsset.balanceOf(address(this));
        for (uint256 i; i < _adapters.length; ++i) {
            currentAssets += IYieldAdapter(_adapters[i]).totalAssets();
        }
        principal = managedPrincipal;
        if (currentAssets >= principal) {
            unrealizedGain = currentAssets - principal;
        } else {
            unrealizedLoss = principal - currentAssets;
        }
    }

    function idleUnrealizedValue() public view returns (uint256) {
        uint256 balance = depositAsset.balanceOf(address(this));
        return balance > idlePrincipal ? balance - idlePrincipal : 0;
    }

    function _sendExact(IERC20 token, address recipient, uint256 amount) private {
        uint256 beforeBalance = token.balanceOf(recipient);
        token.safeTransfer(recipient, amount);
        uint256 afterBalance = token.balanceOf(recipient);
        uint256 received = afterBalance >= beforeBalance ? afterBalance - beforeBalance : 0;
        if (received != amount) revert InexactTransfer(amount, received);
    }

    function _clearRewardRoutes(address adapter) private {
        address[] storage previous = _adapterRewardTokens[adapter];
        for (uint256 i; i < previous.length; ++i) {
            address rewardToken = previous[i];
            isAdapterRewardToken[adapter][rewardToken] = false;
            delete _rewardRoutes[adapter][rewardToken];
        }
        delete _adapterRewardTokens[adapter];
        emit AdapterRewardRoutesCleared(adapter);
    }

    function _validateExposure(uint256 principalAfterWithdrawal) private view {
        for (uint256 i; i < _adapters.length; ++i) {
            AdapterConfig storage config = _adapterConfigs[_adapters[i]];
            if (
                config.principalAllocated
                    > principalAfterWithdrawal * config.allocationLimitBps / BPS
            ) revert AllocationLimitExceeded();
        }
    }
}
