// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IYieldBankCollection } from "./interfaces/IYieldBankCollection.sol";
import { IYieldBankAllocationReceiver } from "./interfaces/IYieldBankAllocationReceiver.sol";
import { IYieldBankAllocationRoute } from "./interfaces/IYieldBankAllocationRoute.sol";
import { IYieldBankSleeve } from "./interfaces/IYieldBankSleeve.sol";
import { IYieldBankManagedSleeve } from "./interfaces/IYieldBankManagedSleeve.sol";
import { IntegrationBinding } from "./libraries/IntegrationBinding.sol";

interface IYieldBankAllocationOperatorSource {
    function allocationOperator() external view returns (address);
}

/// @notice Enforces collection-configured immutable weights for primary proceeds and ongoing contributions.
contract CollectionPortfolioAllocator is IYieldBankAllocationReceiver, ReentrancyGuard {
    using SafeERC20 for IERC20;

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

    uint16 private constant BPS = 10_000;

    IYieldBankCollection public immutable collection;
    address public immutable revenueRouter;
    address public immutable timelock;
    address public immutable guardian;
    uint16 public immutable coreWeightBps;
    uint16 public immutable marketMakingWeightBps;
    uint16 public immutable usdgWeightBps;
    address[3] public sleeves;
    mapping(address inputAsset => mapping(address sleeve => RouteBinding binding)) public
        routeBinding;

    error OnlyRevenueRouter(address caller);
    error OnlyProceedsVault(address caller);
    error OnlyTimelock(address caller);
    error OnlyAllocationOperator(address caller);
    error OnlyOperatorOrGuardian(address caller);
    error InvalidConfiguration();
    error InexactReceipt(uint256 expected, uint256 received);
    error RouteUnavailable(address inputAsset, address sleeve);

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

    constructor(
        address collection_,
        address revenueRouter_,
        address timelock_,
        address guardian_,
        address coreSleeve_,
        address marketMakingSleeve_,
        address usdgSleeve_,
        uint16 coreWeightBps_,
        uint16 marketMakingWeightBps_,
        uint16 usdgWeightBps_
    ) {
        if (
            collection_ == address(0) || revenueRouter_ == address(0) || timelock_ == address(0)
                || guardian_ == address(0) || coreSleeve_.code.length == 0
                || marketMakingSleeve_.code.length == 0 || usdgSleeve_.code.length == 0
                || coreWeightBps_ == 0 || marketMakingWeightBps_ == 0 || usdgWeightBps_ == 0
                || uint256(coreWeightBps_) + marketMakingWeightBps_ + usdgWeightBps_ != BPS
        ) revert InvalidConfiguration();
        collection = IYieldBankCollection(collection_);
        revenueRouter = revenueRouter_;
        timelock = timelock_;
        guardian = guardian_;
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

    function allocate(address asset, uint256 amount, bytes calldata data)
        external
        onlyRevenueRouter
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
    ) external onlyAllocationOperator nonReentrant returns (uint256 positionUnits) {
        if (!_isSleeve(sleeve)) revert InvalidConfiguration();
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
        return
            IYieldBankManagedSleeve(sleeve).withdrawFromAdapter(adapter, assets, maxLossBps, data);
    }

    function collectAdapter(address sleeve, address adapter, bytes calldata data)
        external
        onlyAllocationOperator
        nonReentrant
        returns (address[] memory assets, uint256[] memory amounts)
    {
        if (!_isSleeve(sleeve)) revert InvalidConfiguration();
        return IYieldBankManagedSleeve(sleeve).collectAdapter(adapter, data);
    }

    function exitAdapter(address sleeve, address adapter, uint16 maxLossBps, bytes calldata data)
        external
        onlyOperatorOrGuardian
        nonReentrant
        returns (address[] memory assets, uint256[] memory amounts)
    {
        if (!_isSleeve(sleeve)) revert InvalidConfiguration();
        return IYieldBankManagedSleeve(sleeve).exitAdapter(adapter, maxLossBps, data);
    }

    function _allocate(
        address asset,
        uint256 amount,
        address receiver,
        AllocationCall[3] memory calls
    ) private returns (address[] memory distributionAssets, uint256[] memory distributionAmounts) {
        uint256[3] memory amountsIn;
        amountsIn[0] = Math.mulDiv(amount, coreWeightBps, BPS);
        uint256 marketCumulative =
            Math.mulDiv(amount, uint256(coreWeightBps) + marketMakingWeightBps, BPS);
        amountsIn[1] = marketCumulative - amountsIn[0];
        amountsIn[2] = amount - marketCumulative;
        distributionAssets = new address[](3);
        distributionAmounts = new uint256[](3);
        for (uint256 i; i < 3; ++i) {
            if (calls[i].minimumOutput == 0 || calls[i].minimumShares == 0) {
                revert InvalidConfiguration();
            }
            address sleeve = sleeves[i];
            uint256 converted = _convert(asset, sleeve, amountsIn[i], calls[i]);
            address accounting = IYieldBankSleeve(sleeve).accountingAsset();
            IERC20(accounting).forceApprove(sleeve, converted);
            uint256 shares = IYieldBankSleeve(sleeve)
                .deposit(converted, receiver, calls[i].minimumShares, calls[i].sleeveData);
            IERC20(accounting).forceApprove(sleeve, 0);
            distributionAssets[i] = sleeve;
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
        return sleeve == sleeves[0] || sleeve == sleeves[1] || sleeve == sleeves[2];
    }
}
