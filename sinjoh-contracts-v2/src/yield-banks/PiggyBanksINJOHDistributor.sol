// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    ReentrancyGuardTransient
} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

interface IPiggyBanksDistributionCollection {
    function maxSupply() external view returns (uint256);
    function mintedSupply() external view returns (uint256);
    function liveSupply() external view returns (uint256);
    function maximumTotalFeeWeight() external view returns (uint256);
    function totalLiveFeeWeight() external view returns (uint256);
    function feeWeightRangeCount() external view returns (uint256);
    function feeWeightRange(uint256 index) external view returns (uint64 endTokenId, uint96 weight);
    function feeWeightOf(uint256 tokenId) external view returns (uint96);
    function accountOf(uint256 tokenId) external view returns (address);
    function nft() external view returns (address);
}

/// @notice One-purpose deposit address for the 6,000,000 INJOH Piggy Banks contribution.
/// @dev Once fully funded, anyone may advance bounded batches. Every token is sent directly to
///      the immutable treasury account belonging to the corresponding Piggy Bank NFT. Cumulative
///      division assigns every last wei while preserving the collection's exact fee-weight ratios.
contract PiggyBanksINJOHDistributor is ReentrancyGuardTransient {
    using SafeERC20 for IERC20;

    uint256 public constant CHAIN_ID = 4_663;
    uint256 public constant TOKEN_COUNT = 3_333;
    uint256 public constant TOTAL_WEIGHT = 8_130;
    uint256 public constant TARGET_AMOUNT = 6_000_000 ether;
    uint256 public constant MAX_BATCH_SIZE = 64;

    address public constant COLLECTION = 0xc275fa302Cd53DFa42D41b1C5b770661d923ba43;
    address public constant NFT = 0xF39D4C50a08E0FdafC51d37FC92Bd2c25191DA6a;
    address public constant INJOH = 0x2cC0FAC44B8252f6B10208B091aFf2c94B4da77D;
    address public constant OPERATOR = 0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49;

    bytes32 public constant COLLECTION_RUNTIME_CODE_HASH =
        0x4a019003aefe312456d9d3f0c1bcf18eacda2abd08e9a917e3db7e26345fbec0;
    bytes32 public constant INJOH_RUNTIME_CODE_HASH =
        0x7e6ca88b216c0b26c5f8497f3e7106648f4bcd8ed41eedfa1c80787fb407f4e2;

    uint256 public nextTokenId = 1;
    uint256 public cumulativeWeight;
    uint256 public totalDistributed;

    error DistributionAlreadyComplete();
    error FundingIncomplete(uint256 required, uint256 available);
    error InvalidBatchSize(uint256 requested);
    error InvalidChain(uint256 actual);
    error InvalidCollection();
    error InvalidRuntimeCodeHash(address target, bytes32 expected, bytes32 actual);
    error MissingBankAccount(uint256 tokenId);
    error NativeCurrencyNotAccepted();
    error Unauthorized(address caller);
    error UnexpectedFeeWeight(uint256 tokenId, uint256 expected, uint256 actual);

    event DistributionBatchCompleted(
        uint256 indexed firstTokenId,
        uint256 indexed lastTokenId,
        uint256 amount,
        uint256 totalDistributed
    );
    event DistributionCompleted(uint256 amount, uint256 totalWeight);
    event ExcessRecovered(address indexed recipient, uint256 amount);

    constructor() {
        if (block.chainid != CHAIN_ID) revert InvalidChain(block.chainid);
        _requireRuntimeCodeHash(COLLECTION, COLLECTION_RUNTIME_CODE_HASH);
        _requireRuntimeCodeHash(INJOH, INJOH_RUNTIME_CODE_HASH);

        IPiggyBanksDistributionCollection collection = IPiggyBanksDistributionCollection(COLLECTION);
        if (
            collection.nft() != NFT || collection.maxSupply() != TOKEN_COUNT
                || collection.mintedSupply() != TOKEN_COUNT
                || collection.liveSupply() != TOKEN_COUNT
                || collection.maximumTotalFeeWeight() != TOTAL_WEIGHT
                || collection.totalLiveFeeWeight() != TOTAL_WEIGHT
                || collection.feeWeightRangeCount() != 4
        ) revert InvalidCollection();

        _requireRange(collection, 0, 3, 60);
        _requireRange(collection, 1, 33, 15);
        _requireRange(collection, 2, 333, 5);
        _requireRange(collection, 3, 3_333, 2);
    }

    /// @notice Amount still needed before any distribution batch can run.
    function remainingFunding() external view returns (uint256) {
        uint256 available = IERC20(INJOH).balanceOf(address(this));
        uint256 outstanding = TARGET_AMOUNT - totalDistributed;
        return available >= outstanding ? 0 : outstanding - available;
    }

    /// @notice Advances at most `maximumTokenCount` banks after the full target is deposited.
    function distribute(uint256 maximumTokenCount) external nonReentrant {
        if (maximumTokenCount == 0 || maximumTokenCount > MAX_BATCH_SIZE) {
            revert InvalidBatchSize(maximumTokenCount);
        }

        uint256 firstTokenId = nextTokenId;
        if (firstTokenId > TOKEN_COUNT) revert DistributionAlreadyComplete();

        IERC20 token = IERC20(INJOH);
        uint256 available = token.balanceOf(address(this));
        uint256 outstanding = TARGET_AMOUNT - totalDistributed;
        if (available < outstanding) revert FundingIncomplete(outstanding, available);

        uint256 finalTokenId = firstTokenId + maximumTokenCount - 1;
        if (finalTokenId > TOKEN_COUNT) finalTokenId = TOKEN_COUNT;

        IPiggyBanksDistributionCollection collection = IPiggyBanksDistributionCollection(COLLECTION);
        uint256 runningWeight = cumulativeWeight;
        uint256 runningDistributed = totalDistributed;
        uint256 batchStartDistributed = runningDistributed;

        for (uint256 tokenId = firstTokenId; tokenId <= finalTokenId; ++tokenId) {
            uint256 expectedWeight = _expectedWeight(tokenId);
            uint256 actualWeight = collection.feeWeightOf(tokenId);
            if (actualWeight != expectedWeight) {
                revert UnexpectedFeeWeight(tokenId, expectedWeight, actualWeight);
            }
            address account = collection.accountOf(tokenId);
            if (account == address(0)) revert MissingBankAccount(tokenId);

            runningWeight += actualWeight;
            uint256 cumulativeEntitlement = TARGET_AMOUNT * runningWeight / TOTAL_WEIGHT;
            uint256 amount = cumulativeEntitlement - runningDistributed;
            runningDistributed = cumulativeEntitlement;
            token.safeTransfer(account, amount);
        }

        cumulativeWeight = runningWeight;
        totalDistributed = runningDistributed;
        nextTokenId = finalTokenId + 1;

        emit DistributionBatchCompleted(
            firstTokenId,
            finalTokenId,
            runningDistributed - batchStartDistributed,
            runningDistributed
        );

        if (finalTokenId == TOKEN_COUNT) {
            assert(runningWeight == TOTAL_WEIGHT);
            assert(runningDistributed == TARGET_AMOUNT);
            emit DistributionCompleted(runningDistributed, runningWeight);
        }
    }

    /// @notice Recovers only tokens above the undistributed contribution, never principal.
    function recoverExcess() external nonReentrant returns (uint256 amount) {
        if (msg.sender != OPERATOR) revert Unauthorized(msg.sender);
        uint256 outstanding = TARGET_AMOUNT - totalDistributed;
        uint256 available = IERC20(INJOH).balanceOf(address(this));
        if (available > outstanding) {
            amount = available - outstanding;
            IERC20(INJOH).safeTransfer(OPERATOR, amount);
        }
        emit ExcessRecovered(OPERATOR, amount);
    }

    receive() external payable {
        revert NativeCurrencyNotAccepted();
    }

    function _expectedWeight(uint256 tokenId) private pure returns (uint256) {
        if (tokenId <= 3) return 60;
        if (tokenId <= 33) return 15;
        if (tokenId <= 333) return 5;
        return 2;
    }

    function _requireRange(
        IPiggyBanksDistributionCollection collection,
        uint256 index,
        uint64 expectedEndTokenId,
        uint96 expectedWeight
    ) private view {
        (uint64 endTokenId, uint96 weight) = collection.feeWeightRange(index);
        if (endTokenId != expectedEndTokenId || weight != expectedWeight) {
            revert InvalidCollection();
        }
    }

    function _requireRuntimeCodeHash(address target, bytes32 expected) private view {
        bytes32 actual = target.codehash;
        if (actual != expected) revert InvalidRuntimeCodeHash(target, expected, actual);
    }
}
