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

/// @notice Permissionless revenue ingress with immutable per-collection allocation weights.
contract CollectionRevenueRouter is IYieldBankFundable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint16 private constant BPS = 10_000;
    IYieldBankCollection public immutable collection;
    IYieldBankAllocationReceiver public immutable allocator;
    address public immutable timelock;
    uint16 public immutable primaryBackingBps;
    uint16 public immutable primaryCreatorBps;
    uint16 public immutable primarySinjohBps;
    uint16 public immutable royaltyBackingBps;
    uint16 public immutable royaltyCreatorBps;
    uint16 public immutable royaltySinjohBps;

    address public creatorRecipient;
    address public sinjohRecipient;
    address public proposedCreatorRecipient;
    address public proposedSinjohRecipient;
    mapping(address asset => mapping(address recipient => uint256 amount)) public failedTransfer;
    mapping(address asset => mapping(bytes32 routeHash => uint256 amount)) public
        failedNftAllocation;
    mapping(address asset => uint256 amount) public accountedEscrow;

    error OnlyTimelock(address caller);
    error InvalidConfiguration();
    error InexactReceipt(uint256 expected, uint256 received);
    error NothingToRetry();
    error OnlyProposedRecipient(address caller);
    error OnlySelf(address caller);
    error OnlyAllocationOperator(address caller);

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
    event TreasuryBatchDelivered(address indexed caller, uint256 count);
    event NativeRoyaltyReceived(address indexed sender, uint256 amount);
    event FailedLegRetried(address indexed asset, address indexed recipient, uint256 amount);
    event CreatorRecipientProposed(
        address indexed currentRecipient, address indexed proposedRecipient
    );
    event CreatorRecipientAccepted(address indexed previousRecipient, address indexed newRecipient);
    event SinjohRecipientProposed(
        address indexed currentRecipient, address indexed proposedRecipient
    );
    event SinjohRecipientAccepted(address indexed previousRecipient, address indexed newRecipient);

    constructor(
        address collection_,
        address allocator_,
        address timelock_,
        address creator_,
        address sinjoh_,
        uint16 primaryBackingBps_,
        uint16 primaryCreatorBps_,
        uint16 primarySinjohBps_,
        uint16 royaltyBackingBps_,
        uint16 royaltyCreatorBps_,
        uint16 royaltySinjohBps_
    ) {
        if (
            collection_ == address(0) || allocator_.code.length == 0 || timelock_ == address(0)
                || creator_ == address(0) || sinjoh_ == address(0) || primaryBackingBps_ == 0
                || uint256(primaryBackingBps_) + primaryCreatorBps_ + primarySinjohBps_ != BPS
                || royaltyBackingBps_ == 0
                || uint256(royaltyBackingBps_) + royaltyCreatorBps_ + royaltySinjohBps_ != BPS
        ) revert InvalidConfiguration();
        collection = IYieldBankCollection(collection_);
        allocator = IYieldBankAllocationReceiver(allocator_);
        timelock = timelock_;
        primaryBackingBps = primaryBackingBps_;
        primaryCreatorBps = primaryCreatorBps_;
        primarySinjohBps = primarySinjohBps_;
        royaltyBackingBps = royaltyBackingBps_;
        royaltyCreatorBps = royaltyCreatorBps_;
        royaltySinjohBps = royaltySinjohBps_;
        creatorRecipient = creator_;
        sinjohRecipient = sinjoh_;
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

    function fund(
        bytes32 collectionId,
        address sourceAsset,
        uint256 amount,
        bytes32 sourceType,
        bytes calldata sourceData
    ) external nonReentrant returns (uint256 received) {
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
        (uint256 nftAmount, uint256 creatorAmount, uint256 sinjohAmount) =
            _splitAmounts(amount, YieldBankIds.ROYALTY_REVENUE);
        _tryLeg(address(0), creatorRecipient, creatorAmount);
        _tryLeg(address(0), sinjohRecipient, sinjohAmount);
        IYieldBankRoyaltyWETH(weth).deposit{ value: nftAmount }();
        _tryNftAllocation(weth, nftAmount, sourceData);
        emit RoyaltySynced(msg.sender, address(0), amount);
    }

    /// @notice Pushes already-accounted collection fees into their NFT treasury accounts.
    /// @dev Permissionless: callers cannot redirect assets or change any token's fee weight.
    function deliverToTreasuries(uint256[] calldata tokenIds) external nonReentrant {
        collection.deliverRevenueBatch(tokenIds);
        emit TreasuryBatchDelivered(msg.sender, tokenIds.length);
    }

    function _routeReceived(
        address sourceAsset,
        uint256 received,
        bytes32 sourceType,
        bytes memory sourceData
    ) private returns (uint256 nftAmount) {
        uint256 creatorAmount;
        uint256 sinjohAmount;
        (nftAmount, creatorAmount, sinjohAmount) = _splitAmounts(received, sourceType);
        _tryLeg(sourceAsset, creatorRecipient, creatorAmount);
        _tryLeg(sourceAsset, sinjohRecipient, sinjohAmount);
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
            if (distributionAsset.code.length == 0) {
                revert InvalidConfiguration();
            }
            if (distributionAmount == 0) continue;
            address distributor = collection.distributor();
            IERC20(distributionAsset).forceApprove(distributor, distributionAmount);
            collection.accrueDistribution(distributionAsset, distributionAmount);
            IERC20(distributionAsset).forceApprove(distributor, 0);
        }
    }

    function proposeCreatorRecipient(address nextRecipient) external onlyTimelock {
        if (nextRecipient == address(0)) revert InvalidConfiguration();
        proposedCreatorRecipient = nextRecipient;
        emit CreatorRecipientProposed(creatorRecipient, nextRecipient);
    }

    function acceptCreatorRecipient() external {
        if (msg.sender != proposedCreatorRecipient) revert OnlyProposedRecipient(msg.sender);
        address previous = creatorRecipient;
        creatorRecipient = msg.sender;
        delete proposedCreatorRecipient;
        emit CreatorRecipientAccepted(previous, msg.sender);
    }

    function proposeSinjohRecipient(address nextRecipient) external onlyTimelock {
        if (nextRecipient == address(0)) revert InvalidConfiguration();
        proposedSinjohRecipient = nextRecipient;
        emit SinjohRecipientProposed(sinjohRecipient, nextRecipient);
    }

    function acceptSinjohRecipient() external {
        if (msg.sender != proposedSinjohRecipient) revert OnlyProposedRecipient(msg.sender);
        address previous = sinjohRecipient;
        sinjohRecipient = msg.sender;
        delete proposedSinjohRecipient;
        emit SinjohRecipientAccepted(previous, msg.sender);
    }

    function _split(bytes32 sourceType)
        private
        view
        returns (uint16 nftBps, uint16 creatorBps, uint16 sinjohBps)
    {
        if (sourceType == YieldBankIds.PROJECT_REVENUE) {
            return (primaryBackingBps, primaryCreatorBps, primarySinjohBps);
        }
        if (sourceType == YieldBankIds.ROYALTY_REVENUE) {
            return (royaltyBackingBps, royaltyCreatorBps, royaltySinjohBps);
        }
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

    function _splitAmounts(uint256 received, bytes32 sourceType)
        private
        view
        returns (uint256 nftAmount, uint256 creatorAmount, uint256 sinjohAmount)
    {
        (uint16 nftBps, uint16 creatorBps, uint16 sinjohBps) = _split(sourceType);
        if (nftBps == 0 || uint256(nftBps) + creatorBps + sinjohBps != BPS) {
            revert InvalidConfiguration();
        }
        nftAmount = Math.mulDiv(received, nftBps, BPS);
        uint256 creatorCumulative = Math.mulDiv(received, uint256(nftBps) + creatorBps, BPS);
        creatorAmount = creatorCumulative - nftAmount;
        sinjohAmount = received - creatorCumulative;
    }
}
