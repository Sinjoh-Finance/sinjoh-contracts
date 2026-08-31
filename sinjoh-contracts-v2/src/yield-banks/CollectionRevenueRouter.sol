// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IYieldBankCollection } from "./interfaces/IYieldBankCollection.sol";
import { IYieldBankFundable } from "./interfaces/IYieldBankFundable.sol";
import { IYieldBankAllocationReceiver } from "./interfaces/IYieldBankAllocationReceiver.sol";
import { YieldBankIds } from "./libraries/YieldBankIds.sol";

interface IYieldBankRoyaltyWETH is IERC20 {
    function deposit() external payable;
}

interface IYieldBankRoyaltyOperator {
    function allocationOperator() external view returns (address);
}

/// @notice Authenticated revenue ingress with immutable per-collection project-revenue weights.
contract CollectionRevenueRouter is IYieldBankFundable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint16 private constant BPS = 10_000;
    IYieldBankCollection public immutable collection;
    IYieldBankAllocationReceiver public immutable allocator;
    address public immutable timelock;
    uint16 public immutable primaryBackingBps;
    uint16 public immutable primaryCreatorBps;
    uint16 public immutable primarySinjohBps;
    uint16 public immutable primaryOperationsBps;
    uint16 public immutable royaltyBackingBps;
    uint16 public immutable royaltyCreatorBps;
    uint16 public immutable royaltySinjohBps;
    uint16 public immutable royaltyOperationsBps;

    address public creatorRecipient;
    address public sinjohRecipient;
    address public operationsRecipient;
    mapping(address recipient => address proposed) public proposedRecipient;
    mapping(address source => mapping(bytes32 sourceType => bool allowed)) public authorizedSource;
    mapping(address asset => mapping(address recipient => uint256 amount)) public failedTransfer;
    mapping(address asset => mapping(bytes32 routeHash => uint256 amount)) public
        failedNftAllocation;
    mapping(address asset => uint256 amount) public accountedEscrow;

    error OnlyTimelock(address caller);
    error UnauthorizedSource(address source, bytes32 sourceType);
    error InvalidConfiguration();
    error InexactReceipt(uint256 expected, uint256 received);
    error NothingToRetry();
    error OnlyProposedRecipient(address caller);
    error OnlySelf(address caller);
    error OnlyAllocationOperator(address caller);

    event SourceAuthorizationSet(address indexed source, bytes32 indexed sourceType, bool allowed);
    event RevenueFunded(
        address indexed source,
        address indexed asset,
        bytes32 indexed sourceType,
        uint256 received,
        uint256 nftAmount
    );
    event LegEscrowed(address indexed asset, address indexed recipient, uint256 amount);
    event NftLegEscrowed(address indexed asset, bytes32 indexed routeHash, uint256 amount);
    event FailedNftRouteMigrated(
        address indexed asset,
        bytes32 indexed previousRouteHash,
        bytes32 indexed nextRouteHash,
        uint256 amount
    );
    event RoyaltySynced(address indexed caller, address indexed asset, uint256 amount);
    event NativeRoyaltyReceived(address indexed sender, uint256 amount);
    event FailedLegRetried(address indexed asset, address indexed recipient, uint256 amount);
    event RecipientProposed(address indexed currentRecipient, address indexed proposedRecipient);
    event RecipientAccepted(address indexed previousRecipient, address indexed newRecipient);

    constructor(
        address collection_,
        address allocator_,
        address timelock_,
        address creator_,
        address sinjoh_,
        address operations_,
        uint16 primaryBackingBps_,
        uint16 primaryCreatorBps_,
        uint16 primarySinjohBps_,
        uint16 primaryOperationsBps_,
        uint16 royaltyBackingBps_,
        uint16 royaltyCreatorBps_,
        uint16 royaltySinjohBps_,
        uint16 royaltyOperationsBps_
    ) {
        if (
            collection_ == address(0) || allocator_.code.length == 0 || timelock_ == address(0)
                || creator_ == address(0) || sinjoh_ == address(0) || operations_ == address(0)
                || primaryBackingBps_ == 0
                || uint256(primaryBackingBps_) + primaryCreatorBps_ + primarySinjohBps_
                        + primaryOperationsBps_ != BPS || royaltyBackingBps_ == 0
                || uint256(royaltyBackingBps_) + royaltyCreatorBps_ + royaltySinjohBps_
                        + royaltyOperationsBps_ != BPS
        ) revert InvalidConfiguration();
        collection = IYieldBankCollection(collection_);
        allocator = IYieldBankAllocationReceiver(allocator_);
        timelock = timelock_;
        primaryBackingBps = primaryBackingBps_;
        primaryCreatorBps = primaryCreatorBps_;
        primarySinjohBps = primarySinjohBps_;
        primaryOperationsBps = primaryOperationsBps_;
        royaltyBackingBps = royaltyBackingBps_;
        royaltyCreatorBps = royaltyCreatorBps_;
        royaltySinjohBps = royaltySinjohBps_;
        royaltyOperationsBps = royaltyOperationsBps_;
        creatorRecipient = creator_;
        sinjohRecipient = sinjoh_;
        operationsRecipient = operations_;
    }

    modifier onlyTimelock() {
        if (msg.sender != timelock) revert OnlyTimelock(msg.sender);
        _;
    }

    modifier onlyAllocationOperator() {
        if (msg.sender != IYieldBankRoyaltyOperator(address(allocator)).allocationOperator()) {
            revert OnlyAllocationOperator(msg.sender);
        }
        _;
    }

    receive() external payable {
        emit NativeRoyaltyReceived(msg.sender, msg.value);
    }

    function setSourceAuthorization(address source, bytes32 sourceType, bool allowed)
        external
        onlyTimelock
    {
        if (source == address(0) || sourceType == bytes32(0)) {
            revert InvalidConfiguration();
        }
        authorizedSource[source][sourceType] = allowed;
        emit SourceAuthorizationSet(source, sourceType, allowed);
    }

    function fund(
        bytes32 collectionId,
        address sourceAsset,
        uint256 amount,
        bytes32 sourceType,
        bytes calldata sourceData
    ) external nonReentrant returns (uint256 received) {
        if (!authorizedSource[msg.sender][sourceType]) {
            revert UnauthorizedSource(msg.sender, sourceType);
        }
        if (
            collectionId != collection.collectionId() || sourceAsset.code.length == 0 || amount == 0
        ) {
            revert InvalidConfiguration();
        }
        IERC20 token = IERC20(sourceAsset);
        uint256 beforeBalance = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), amount);
        received = token.balanceOf(address(this)) - beforeBalance;
        if (received != amount) revert InexactReceipt(amount, received);

        uint256 nftAmount = _routeReceived(sourceAsset, received, sourceType, sourceData);
        emit RevenueFunded(msg.sender, sourceAsset, sourceType, received, nftAmount);
    }

    function syncRoyalty(address asset, bytes calldata sourceData)
        external
        onlyAllocationOperator
        nonReentrant
        returns (uint256 amount)
    {
        if (asset.code.length == 0) revert InvalidConfiguration();
        uint256 balance = IERC20(asset).balanceOf(address(this));
        uint256 escrow = accountedEscrow[asset];
        if (balance < escrow) revert InvalidConfiguration();
        amount = balance - escrow;
        if (amount == 0) revert NothingToRetry();
        _routeReceived(asset, amount, YieldBankIds.ROYALTY_REVENUE, sourceData);
        emit RoyaltySynced(msg.sender, asset, amount);
    }

    function syncNativeRoyalty(bytes calldata sourceData)
        external
        onlyAllocationOperator
        nonReentrant
        returns (uint256 amount)
    {
        uint256 escrow = accountedEscrow[address(0)];
        uint256 balance = address(this).balance;
        if (balance < escrow) revert InvalidConfiguration();
        amount = balance - escrow;
        if (amount == 0) revert NothingToRetry();

        address weth = collection.weth();
        (uint256 nftAmount, uint256 creatorAmount, uint256 sinjohAmount, uint256 operationsAmount) =
            _splitAmounts(amount, YieldBankIds.ROYALTY_REVENUE);
        _tryLeg(address(0), creatorRecipient, creatorAmount);
        _tryLeg(address(0), sinjohRecipient, sinjohAmount);
        _tryLeg(address(0), operationsRecipient, operationsAmount);
        IYieldBankRoyaltyWETH(weth).deposit{ value: nftAmount }();
        _tryNftAllocation(weth, nftAmount, sourceData);
        emit RoyaltySynced(msg.sender, address(0), amount);
    }

    function _routeReceived(
        address sourceAsset,
        uint256 received,
        bytes32 sourceType,
        bytes memory sourceData
    ) private returns (uint256 nftAmount) {
        uint256 creatorAmount;
        uint256 sinjohAmount;
        uint256 operationsAmount;
        (nftAmount, creatorAmount, sinjohAmount, operationsAmount) =
            _splitAmounts(received, sourceType);
        _tryLeg(sourceAsset, creatorRecipient, creatorAmount);
        _tryLeg(sourceAsset, sinjohRecipient, sinjohAmount);
        _tryLeg(sourceAsset, operationsRecipient, operationsAmount);
        _tryNftAllocation(sourceAsset, nftAmount, sourceData);
    }

    function retryTransfer(address asset, address recipient) external nonReentrant {
        uint256 amount = failedTransfer[asset][recipient];
        if (amount == 0) revert NothingToRetry();
        failedTransfer[asset][recipient] = 0;
        accountedEscrow[asset] -= amount;
        if (!_rawTransfer(asset, recipient, amount)) {
            revert NothingToRetry();
        }
        emit FailedLegRetried(asset, recipient, amount);
    }

    function retryNftAllocation(address asset, bytes calldata sourceData) external nonReentrant {
        bytes32 routeHash = keccak256(sourceData);
        uint256 amount = failedNftAllocation[asset][routeHash];
        if (amount == 0) revert NothingToRetry();
        failedNftAllocation[asset][routeHash] = 0;
        accountedEscrow[asset] -= amount;
        _tryNftAllocation(asset, amount, sourceData);
    }

    function migrateFailedNftRoute(
        address asset,
        bytes calldata previousSourceData,
        bytes calldata nextSourceData
    ) external onlyTimelock {
        bytes32 previousRouteHash = keccak256(previousSourceData);
        bytes32 nextRouteHash = keccak256(nextSourceData);
        uint256 amount = failedNftAllocation[asset][previousRouteHash];
        if (amount == 0 || previousRouteHash == nextRouteHash) revert NothingToRetry();
        failedNftAllocation[asset][previousRouteHash] = 0;
        failedNftAllocation[asset][nextRouteHash] += amount;
        emit FailedNftRouteMigrated(asset, previousRouteHash, nextRouteHash, amount);
    }

    function executeNftAllocation(address asset, uint256 amount, bytes calldata sourceData)
        external
    {
        if (msg.sender != address(this)) revert OnlySelf(msg.sender);
        IERC20(asset).forceApprove(address(allocator), amount);
        (address[] memory distributionAssets, uint256[] memory distributionAmounts) =
            allocator.allocate(asset, amount, sourceData);
        IERC20(asset).forceApprove(address(allocator), 0);
        uint256 length = distributionAssets.length;
        if (length != 3 || distributionAmounts.length != length) {
            revert InvalidConfiguration();
        }
        for (uint256 i; i < length; ++i) {
            address distributionAsset = distributionAssets[i];
            uint256 distributionAmount = distributionAmounts[i];
            if (distributionAsset.code.length == 0 || distributionAmount == 0) {
                revert InvalidConfiguration();
            }
            IERC20(distributionAsset).forceApprove(address(collection), distributionAmount);
            collection.accrueDistribution(distributionAsset, distributionAmount);
            IERC20(distributionAsset).forceApprove(address(collection), 0);
        }
    }

    function proposeRecipient(address currentRecipient, address nextRecipient)
        external
        onlyTimelock
    {
        if (!_isCurrentRecipient(currentRecipient) || nextRecipient == address(0)) {
            revert InvalidConfiguration();
        }
        proposedRecipient[currentRecipient] = nextRecipient;
        emit RecipientProposed(currentRecipient, nextRecipient);
    }

    function acceptRecipient(address currentRecipient) external {
        if (proposedRecipient[currentRecipient] != msg.sender) {
            revert OnlyProposedRecipient(msg.sender);
        }
        delete proposedRecipient[currentRecipient];
        if (currentRecipient == creatorRecipient) creatorRecipient = msg.sender;
        else if (currentRecipient == sinjohRecipient) sinjohRecipient = msg.sender;
        else if (currentRecipient == operationsRecipient) operationsRecipient = msg.sender;
        else revert InvalidConfiguration();
        emit RecipientAccepted(currentRecipient, msg.sender);
    }

    function _split(bytes32 sourceType)
        private
        view
        returns (uint16 nftBps, uint16 creatorBps, uint16 sinjohBps, uint16 operationsBps)
    {
        if (sourceType == YieldBankIds.PROJECT_REVENUE) {
            return (primaryBackingBps, primaryCreatorBps, primarySinjohBps, primaryOperationsBps);
        }
        if (sourceType == YieldBankIds.ROYALTY_REVENUE) {
            return (royaltyBackingBps, royaltyCreatorBps, royaltySinjohBps, royaltyOperationsBps);
        }
        if (sourceType == YieldBankIds.OPERATIONS_RESERVE_SWEEP) return (10_000, 0, 0, 0);
        revert InvalidConfiguration();
    }

    function _tryLeg(address asset, address recipient, uint256 amount) private {
        if (amount == 0) return;
        if (!_rawTransfer(asset, recipient, amount)) {
            failedTransfer[asset][recipient] += amount;
            accountedEscrow[asset] += amount;
            emit LegEscrowed(asset, recipient, amount);
        }
    }

    function _tryNftAllocation(address asset, uint256 amount, bytes memory sourceData) private {
        if (amount == 0) return;
        try this.executeNftAllocation(asset, amount, sourceData) { }
        catch {
            bytes32 routeHash = keccak256(sourceData);
            failedNftAllocation[asset][routeHash] += amount;
            accountedEscrow[asset] += amount;
            emit NftLegEscrowed(asset, routeHash, amount);
        }
    }

    function _rawTransfer(address asset, address recipient, uint256 amount)
        private
        returns (bool ok)
    {
        if (asset == address(0)) {
            (ok,) = payable(recipient).call{ value: amount }("");
            return ok;
        }
        (bool success, bytes memory result) =
            asset.call(abi.encodeCall(IERC20.transfer, (recipient, amount)));
        return
            success && (result.length == 0 || (result.length == 32 && abi.decode(result, (bool))));
    }

    function _isCurrentRecipient(address recipient) private view returns (bool) {
        return recipient == creatorRecipient || recipient == sinjohRecipient
            || recipient == operationsRecipient;
    }

    function _splitAmounts(uint256 received, bytes32 sourceType)
        private
        view
        returns (
            uint256 nftAmount,
            uint256 creatorAmount,
            uint256 sinjohAmount,
            uint256 operationsAmount
        )
    {
        (uint16 nftBps, uint16 creatorBps, uint16 sinjohBps, uint16 operationsBps) =
            _split(sourceType);
        if (nftBps == 0 || uint256(nftBps) + creatorBps + sinjohBps + operationsBps != BPS) {
            revert InvalidConfiguration();
        }
        nftAmount = Math.mulDiv(received, nftBps, BPS);
        uint256 creatorCumulative = Math.mulDiv(received, uint256(nftBps) + creatorBps, BPS);
        creatorAmount = creatorCumulative - nftAmount;
        uint256 sinjohCumulative =
            Math.mulDiv(received, uint256(nftBps) + creatorBps + sinjohBps, BPS);
        sinjohAmount = sinjohCumulative - creatorCumulative;
        operationsAmount = received - sinjohCumulative;
    }
}
