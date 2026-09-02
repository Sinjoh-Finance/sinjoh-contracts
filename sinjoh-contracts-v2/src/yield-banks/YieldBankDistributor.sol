// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { YieldBankAccount } from "./YieldBankAccount.sol";

/// @notice O(1) weighted per-live-token fee accounting with bounded treasury delivery.
contract YieldBankDistributor is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant RAY = 1e27;
    uint256 public constant MAX_DISTRIBUTION_ASSETS = 64;

    address public immutable collection;
    address[] private _assets;
    mapping(address asset => bool registered) public isDistributionAsset;
    mapping(address asset => uint256 index) public accPerFeeWeightRay;
    mapping(uint256 tokenId => uint96 weight) public feeWeightOf;
    mapping(uint256 tokenId => mapping(address asset => uint256 debt)) public debtRay;
    mapping(uint256 tokenId => mapping(address asset => uint256 remainder)) public remainderRay;
    mapping(address asset => uint256 amount) public totalReceived;
    mapping(address asset => uint256 amount) public totalDelivered;
    mapping(uint256 tokenId => mapping(address asset => uint256 amount)) public cumulativeDelivered;
    mapping(address asset => uint256 amount) public accountedBalance;

    error OnlyCollection(address caller);
    error InvalidAsset(address asset);
    error TooManyAssets(uint256 supplied);
    error InvalidSupply(uint256 supplied);
    error InvalidAmount(uint256 supplied);
    error InvalidFeeWeight(uint256 supplied);
    error TokenAlreadyInitialized(uint256 tokenId);
    error InexactReceipt(address asset, uint256 expected, uint256 measured);

    event DistributionAssetRegistered(address indexed asset);
    event DistributionAccrued(
        address indexed asset, uint256 amount, uint256 totalLiveFeeWeight, uint256 indexIncrease
    );
    event TokenDelivered(uint256 indexed tokenId, address indexed account, bool terminal);
    event AssetDelivered(
        uint256 indexed tokenId, address indexed asset, uint256 amount, bool terminal
    );
    event TokenRetired(uint256 indexed tokenId);

    modifier onlyCollection() {
        if (msg.sender != collection) revert OnlyCollection(msg.sender);
        _;
    }

    constructor(address collection_) {
        if (collection_ == address(0)) revert OnlyCollection(address(0));
        collection = collection_;
    }

    function registerAsset(address asset) external onlyCollection {
        if (asset == address(0) || asset.code.length == 0) revert InvalidAsset(asset);
        if (isDistributionAsset[asset]) return;
        uint256 nextLength = _assets.length + 1;
        if (nextLength > MAX_DISTRIBUTION_ASSETS) revert TooManyAssets(nextLength);
        isDistributionAsset[asset] = true;
        _assets.push(asset);
        emit DistributionAssetRegistered(asset);
    }

    function initializeTokenDebt(uint256 tokenId, uint96 feeWeight) external onlyCollection {
        if (feeWeight == 0) revert InvalidFeeWeight(feeWeight);
        if (feeWeightOf[tokenId] != 0) revert TokenAlreadyInitialized(tokenId);
        feeWeightOf[tokenId] = feeWeight;
        uint256 length = _assets.length;
        for (uint256 i; i < length; ++i) {
            address asset = _assets[i];
            debtRay[tokenId][asset] = accPerFeeWeightRay[asset];
        }
    }

    function accrueFrom(address asset, address source, uint256 amount, uint256 totalLiveFeeWeight)
        external
        onlyCollection
        nonReentrant
    {
        if (!isDistributionAsset[asset]) revert InvalidAsset(asset);
        if (amount == 0) revert InvalidAmount(amount);
        if (totalLiveFeeWeight == 0) revert InvalidSupply(totalLiveFeeWeight);
        IERC20 token = IERC20(asset);
        uint256 beforeBalance = token.balanceOf(address(this));
        token.safeTransferFrom(source, address(this), amount);
        uint256 measured = token.balanceOf(address(this)) - beforeBalance;
        if (measured != amount) revert InexactReceipt(asset, amount, measured);
        _accrue(asset, amount, totalLiveFeeWeight);
    }

    function deliver(uint256 tokenId, address account, bool terminal)
        external
        onlyCollection
        nonReentrant
    {
        uint96 feeWeight = feeWeightOf[tokenId];
        if (feeWeight == 0) revert InvalidFeeWeight(feeWeight);
        uint256 length = _assets.length;
        for (uint256 i; i < length; ++i) {
            address asset = _assets[i];
            uint256 amount;
            if (terminal) {
                amount = accountedBalance[asset];
                debtRay[tokenId][asset] = accPerFeeWeightRay[asset];
                remainderRay[tokenId][asset] = 0;
            } else {
                uint256 indexDelta = accPerFeeWeightRay[asset] - debtRay[tokenId][asset];
                amount = Math.mulDiv(indexDelta, feeWeight, RAY);
                uint256 remainder =
                    remainderRay[tokenId][asset] + mulmod(indexDelta, feeWeight, RAY);
                if (remainder >= RAY) {
                    amount += 1;
                    remainder -= RAY;
                }
                debtRay[tokenId][asset] = accPerFeeWeightRay[asset];
                remainderRay[tokenId][asset] = remainder;
            }
            if (amount == 0) continue;
            YieldBankAccount(account).trackAsset(asset);
            accountedBalance[asset] -= amount;
            totalDelivered[asset] += amount;
            cumulativeDelivered[tokenId][asset] += amount;
            IERC20(asset).safeTransfer(account, amount);
            emit AssetDelivered(tokenId, asset, amount, terminal);
        }
        emit TokenDelivered(tokenId, account, terminal);
    }

    function retireToken(uint256 tokenId) external onlyCollection {
        uint256 length = _assets.length;
        for (uint256 i; i < length; ++i) {
            address asset = _assets[i];
            debtRay[tokenId][asset] = accPerFeeWeightRay[asset];
            remainderRay[tokenId][asset] = 0;
        }
        delete feeWeightOf[tokenId];
        emit TokenRetired(tokenId);
    }

    function pending(uint256 tokenId, address asset) external view returns (uint256) {
        if (!isDistributionAsset[asset]) return 0;
        uint96 feeWeight = feeWeightOf[tokenId];
        if (feeWeight == 0) return 0;
        uint256 indexDelta = accPerFeeWeightRay[asset] - debtRay[tokenId][asset];
        uint256 amount = Math.mulDiv(indexDelta, feeWeight, RAY);
        uint256 remainder = remainderRay[tokenId][asset] + mulmod(indexDelta, feeWeight, RAY);
        return amount + remainder / RAY;
    }

    function distributionAssets() external view returns (address[] memory) {
        return _assets;
    }

    function distributionAssetCount() external view returns (uint256) {
        return _assets.length;
    }

    function solvent(address asset) external view returns (bool) {
        return IERC20(asset).balanceOf(address(this)) >= accountedBalance[asset];
    }

    function _accrue(address asset, uint256 amount, uint256 totalLiveFeeWeight) private {
        uint256 indexIncrease = Math.mulDiv(amount, RAY, totalLiveFeeWeight);
        accPerFeeWeightRay[asset] += indexIncrease;
        accountedBalance[asset] += amount;
        totalReceived[asset] += amount;
        emit DistributionAccrued(asset, amount, totalLiveFeeWeight, indexIncrease);
    }
}
