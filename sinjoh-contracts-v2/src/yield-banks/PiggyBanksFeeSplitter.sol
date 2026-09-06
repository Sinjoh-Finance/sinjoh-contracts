// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IPriceHub } from "./interfaces/IPriceHub.sol";

interface IPiggyBanksSplitterCollection {
    function collectionId() external view returns (bytes32);
    function revenueRouter() external view returns (address);
    function weth() external view returns (address);
}

interface IPiggyBanksSplitterRevenueRouter {
    function collection() external view returns (address);
    function allocator() external view returns (address);
    function royaltyBackingBps() external view returns (uint16);
    function royaltyCreatorBps() external view returns (uint16);
    function royaltySinjohBps() external view returns (uint16);
    function failedNftAllocation(address asset, bytes32 routeHash) external view returns (uint256);
    function fund(
        bytes32 collectionId,
        address sourceAsset,
        uint256 amount,
        bytes32 sourceType,
        bytes calldata sourceData
    ) external returns (uint256 received);
}

interface IPiggyBanksSplitterAllocator {
    function sleeves(uint256 index) external view returns (address);
}

interface IPiggyBanksSplitterSleeve is IERC20 {
    function accountingAsset() external view returns (address);
    function priceHub() external view returns (address);
    function totalAssetsUsd18() external view returns (uint256 value, uint48 pricedAt);
}

interface IPiggyBanksSourceFeeRouter {
    function creator() external view returns (address);
    function subject() external view returns (address);
    function weth() external view returns (address);
    function allocationInfo(uint8 bucketId, uint8 allocationId)
        external
        view
        returns (
            address destination,
            uint16 bps,
            bool isSink,
            bool creatorMayRepoint,
            bytes memory sinkConfig
        );
}

/// @notice Immutable 50/50 routing of the INJOH creator WETH leg to its creator and Piggy Banks.
/// @dev WETH arrives through ordinary ERC-20 transfers. Settlement is explicit because ERC-20 has
///      no receiver hook. An unmatched odd wei remains until the next receipt, so both cumulative
///      released totals are always exactly equal.
contract PiggyBanksFeeSplitter is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint8 public constant SOURCE_BUCKET_ID = 0;
    uint8 public constant SOURCE_ALLOCATION_ID = 0;
    uint16 public constant SOURCE_ALLOCATION_BPS = 8_000;
    uint16 public constant BPS = 10_000;
    uint16 public constant CREATOR_BPS = 5_000;
    uint16 public constant PIGGY_BANKS_BPS = 5_000;
    uint16 public constant MAXIMUM_SLIPPAGE_BPS = 200;
    uint256 public constant WAD = 1e18;
    bytes32 public constant PIGGY_BANKS_REVENUE_TYPE = keccak256("YIELD_BANK_ROYALTY_REVENUE");

    struct AllocationCall {
        uint256 minimumOutput;
        uint256 minimumShares;
        bytes routeData;
        bytes sleeveData;
    }

    IERC20 public immutable weth;
    address public immutable creatorRecipient;
    address public immutable sourceFeeRouter;
    address public immutable sourceToken;
    address public immutable collection;
    bytes32 public immutable collectionId;
    IPiggyBanksSplitterRevenueRouter public immutable revenueRouter;
    IPiggyBanksSplitterAllocator public immutable allocator;
    IPiggyBanksSplitterSleeve public immutable usdgSleeve;
    IERC20Metadata public immutable usdg;
    IPriceHub public immutable priceHub;
    uint256 public immutable usdgScale;

    uint256 public totalCreatorReleased;
    uint256 public totalPiggyBanksFunded;

    error InvalidConfiguration();
    error NothingToSettle();
    error PriceUnavailable(address asset, IPriceHub.FailureReason failure);
    error InexactTransfer(uint256 expected, uint256 measured);
    error InexactFunding(uint256 expected, uint256 reported, uint256 measured);
    error PiggyBanksAllocationEscrowed(bytes32 routeHash, uint256 previous, uint256 current);

    event CreatorWethReleased(address indexed recipient, uint256 amount, uint256 cumulative);
    event PiggyBanksFunded(
        address indexed revenueRouter,
        bytes32 indexed collectionId,
        bytes32 indexed routeHash,
        uint256 amount,
        uint256 cumulative
    );

    constructor(
        address weth_,
        address creatorRecipient_,
        address sourceFeeRouter_,
        address sourceToken_,
        address collection_,
        bytes32 collectionId_,
        address revenueRouter_
    ) {
        if (
            weth_.code.length == 0 || creatorRecipient_ == address(0)
                || sourceFeeRouter_.code.length == 0 || sourceToken_.code.length == 0
                || collection_.code.length == 0 || collectionId_ == bytes32(0)
                || revenueRouter_.code.length == 0
        ) revert InvalidConfiguration();

        IPiggyBanksSourceFeeRouter source = IPiggyBanksSourceFeeRouter(sourceFeeRouter_);
        (address destination, uint16 allocationBps, bool isSink, bool creatorMayRepoint,) =
            source.allocationInfo(SOURCE_BUCKET_ID, SOURCE_ALLOCATION_ID);
        if (
            source.creator() != creatorRecipient_ || source.subject() != sourceToken_
                || source.weth() != weth_ || destination != creatorRecipient_
                || allocationBps != SOURCE_ALLOCATION_BPS || isSink || !creatorMayRepoint
        ) revert InvalidConfiguration();

        IPiggyBanksSplitterCollection collectionContract =
            IPiggyBanksSplitterCollection(collection_);
        IPiggyBanksSplitterRevenueRouter router = IPiggyBanksSplitterRevenueRouter(revenueRouter_);
        address allocator_ = router.allocator();
        if (allocator_.code.length == 0) revert InvalidConfiguration();
        IPiggyBanksSplitterAllocator allocatorContract = IPiggyBanksSplitterAllocator(allocator_);
        address usdgSleeve_ = allocatorContract.sleeves(2);
        if (usdgSleeve_.code.length == 0) revert InvalidConfiguration();
        IPiggyBanksSplitterSleeve sleeve = IPiggyBanksSplitterSleeve(usdgSleeve_);
        address usdg_ = sleeve.accountingAsset();
        address priceHub_ = sleeve.priceHub();
        if (usdg_.code.length == 0 || priceHub_.code.length == 0) revert InvalidConfiguration();
        uint8 usdgDecimals = IERC20Metadata(usdg_).decimals();
        if (
            collectionContract.collectionId() != collectionId_
                || collectionContract.revenueRouter() != revenueRouter_
                || collectionContract.weth() != weth_ || router.collection() != collection_
                || router.royaltyBackingBps() != BPS || router.royaltyCreatorBps() != 0
                || router.royaltySinjohBps() != 0 || usdgDecimals > 18
        ) revert InvalidConfiguration();

        weth = IERC20(weth_);
        creatorRecipient = creatorRecipient_;
        sourceFeeRouter = sourceFeeRouter_;
        sourceToken = sourceToken_;
        collection = collection_;
        collectionId = collectionId_;
        revenueRouter = router;
        allocator = allocatorContract;
        usdgSleeve = sleeve;
        usdg = IERC20Metadata(usdg_);
        priceHub = IPriceHub(priceHub_);
        usdgScale = 10 ** usdgDecimals;
    }

    /// @notice Total WETH ever observed by the splitter, including amounts already released.
    function cumulativeReceived() public view returns (uint256) {
        return weth.balanceOf(address(this)) + totalCreatorReleased + totalPiggyBanksFunded;
    }

    /// @notice Each side's equal entitlement. At most one unmatched wei is deliberately excluded.
    function cumulativeEntitlementPerSide() public view returns (uint256) {
        return cumulativeReceived() / 2;
    }

    function pendingCreator() public view returns (uint256) {
        return cumulativeEntitlementPerSide() - totalCreatorReleased;
    }

    function pendingPiggyBanks() public view returns (uint256) {
        return cumulativeEntitlementPerSide() - totalPiggyBanksFunded;
    }

    /// @notice Permissionlessly releases the creator's currently accrued half.
    function releaseCreator() external nonReentrant returns (uint256 amount) {
        return _releaseCreator();
    }

    /// @notice Funds Piggy Banks using fresh oracle-derived minimum outputs for the live route.
    function fundPiggyBanks() external nonReentrant returns (uint256 amount) {
        return _fundPiggyBanks();
    }

    /// @notice Permissionlessly releases and funds every currently pending half.
    function settle()
        external
        nonReentrant
        returns (uint256 creatorAmount, uint256 piggyBanksAmount)
    {
        creatorAmount = pendingCreator();
        piggyBanksAmount = pendingPiggyBanks();
        if (creatorAmount == 0 && piggyBanksAmount == 0) revert NothingToSettle();
        if (creatorAmount != 0) _releaseCreator();
        if (piggyBanksAmount != 0) _fundPiggyBanks();
    }

    /// @notice Returns the exact guarded allocation payload used for a Piggy Banks deposit.
    function previewFundingData(uint256 amount)
        public
        view
        returns (bytes memory sourceData, uint256 minimumOutput, uint256 minimumShares)
    {
        if (amount == 0) revert NothingToSettle();
        (uint256 wethPrice,, IPriceHub.FailureReason wethFailure) =
            priceHub.quoteUsd18(address(weth));
        if (wethFailure != IPriceHub.FailureReason.NONE || wethPrice == 0) {
            revert PriceUnavailable(address(weth), wethFailure);
        }
        (uint256 usdgPrice,, IPriceHub.FailureReason usdgFailure) =
            priceHub.quoteUsd18(address(usdg));
        if (usdgFailure != IPriceHub.FailureReason.NONE || usdgPrice == 0) {
            revert PriceUnavailable(address(usdg), usdgFailure);
        }

        uint256 inputValue = Math.mulDiv(amount, wethPrice, WAD);
        uint256 expectedOutput = Math.mulDiv(inputValue, usdgScale, usdgPrice);
        minimumOutput = Math.mulDiv(expectedOutput, BPS - MAXIMUM_SLIPPAGE_BPS, BPS);

        (uint256 sleeveNav,) = usdgSleeve.totalAssetsUsd18();
        uint256 minimumAssetValue = Math.mulDiv(minimumOutput, usdgPrice, usdgScale);
        minimumShares =
            Math.mulDiv(minimumAssetValue, usdgSleeve.totalSupply() + WAD, sleeveNav + WAD);
        if (minimumOutput == 0 || minimumShares == 0) revert InvalidConfiguration();

        AllocationCall[3] memory calls;
        calls[2].minimumOutput = minimumOutput;
        calls[2].minimumShares = minimumShares;
        sourceData = abi.encode(calls);
    }

    function _releaseCreator() private returns (uint256 amount) {
        amount = pendingCreator();
        if (amount == 0) revert NothingToSettle();

        uint256 splitterBefore = weth.balanceOf(address(this));
        uint256 recipientBefore = weth.balanceOf(creatorRecipient);
        totalCreatorReleased += amount;
        weth.safeTransfer(creatorRecipient, amount);
        uint256 spent = splitterBefore - weth.balanceOf(address(this));
        uint256 received = weth.balanceOf(creatorRecipient) - recipientBefore;
        if (spent != amount || received != amount) revert InexactTransfer(amount, received);

        emit CreatorWethReleased(creatorRecipient, amount, totalCreatorReleased);
    }

    function _fundPiggyBanks() private returns (uint256 amount) {
        amount = pendingPiggyBanks();
        if (amount == 0) revert NothingToSettle();

        (bytes memory sourceData,,) = previewFundingData(amount);
        bytes32 routeHash = keccak256(sourceData);
        uint256 escrowBefore = revenueRouter.failedNftAllocation(address(weth), routeHash);
        uint256 splitterBefore = weth.balanceOf(address(this));
        totalPiggyBanksFunded += amount;
        weth.forceApprove(address(revenueRouter), amount);
        uint256 reported = revenueRouter.fund(
            collectionId, address(weth), amount, PIGGY_BANKS_REVENUE_TYPE, sourceData
        );
        weth.forceApprove(address(revenueRouter), 0);
        uint256 measured = splitterBefore - weth.balanceOf(address(this));
        if (reported != amount || measured != amount) {
            revert InexactFunding(amount, reported, measured);
        }

        uint256 escrowAfter = revenueRouter.failedNftAllocation(address(weth), routeHash);
        if (escrowAfter != escrowBefore) {
            revert PiggyBanksAllocationEscrowed(routeHash, escrowBefore, escrowAfter);
        }

        emit PiggyBanksFunded(
            address(revenueRouter), collectionId, routeHash, amount, totalPiggyBanksFunded
        );
    }
}
