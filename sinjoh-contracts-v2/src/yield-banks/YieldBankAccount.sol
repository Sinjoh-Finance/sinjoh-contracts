// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IYieldBankCollection } from "./interfaces/IYieldBankCollection.sol";
import { IYieldBankRestrictedShare } from "./interfaces/IYieldBankRestrictedShare.sol";

/// @notice Deterministic custody account permanently bound to one Yield Bank token ID.
/// @dev The implementation is locked in its constructor; only clones may be initialized.
contract YieldBankAccount {
    using SafeERC20 for IERC20;

    uint256 public constant MAX_TRACKED_ASSETS = 8;

    address public collection;
    address public nft;
    address public distributor;
    uint256 public tokenId;
    bool public initialized;
    bool public closed;

    address[] private _trackedAssets;
    mapping(address asset => bool tracked) private _isTracked;

    error AlreadyInitialized();
    error OnlyCollection(address caller);
    error OnlyAssetController(address caller);
    error OnlyPortfolioAllocator(address caller);
    error InvalidConfiguration();
    error InvalidAsset(address asset);
    error TooManyTrackedAssets(uint256 supplied);
    error AccountIsClosed();
    error AccountNotEmpty(address asset, uint256 balance);

    event AccountInitialized(
        address indexed collection,
        address indexed nft,
        uint256 indexed tokenId,
        address distributor
    );
    event AssetTracked(address indexed asset);
    event AssetUntracked(address indexed asset);
    event AssetReleased(
        address indexed asset,
        address indexed beneficiary,
        uint256 beneficiaryAmount,
        uint256 taxAmount
    );
    event AccountClosed(uint256 indexed tokenId);

    modifier onlyCollection() {
        if (msg.sender != collection) revert OnlyCollection(msg.sender);
        _;
    }

    modifier onlyAssetController() {
        if (
            msg.sender != collection && msg.sender != distributor
                && msg.sender != IYieldBankCollection(collection).portfolioAllocator()
        ) {
            revert OnlyAssetController(msg.sender);
        }
        _;
    }

    modifier onlyPortfolioAllocator() {
        if (msg.sender != IYieldBankCollection(collection).portfolioAllocator()) {
            revert OnlyPortfolioAllocator(msg.sender);
        }
        _;
    }

    constructor() {
        initialized = true;
    }

    function initialize(address collection_, address nft_, uint256 tokenId_, address distributor_)
        external
    {
        if (initialized) revert AlreadyInitialized();
        if (
            collection_ == address(0) || nft_ == address(0) || distributor_ == address(0)
                || tokenId_ == 0
        ) revert InvalidConfiguration();
        initialized = true;
        collection = collection_;
        nft = nft_;
        distributor = distributor_;
        tokenId = tokenId_;
        emit AccountInitialized(collection_, nft_, tokenId_, distributor_);
    }

    function trackAsset(address asset) external onlyAssetController {
        if (closed) revert AccountIsClosed();
        if (asset == address(0) || asset.code.length == 0) revert InvalidAsset(asset);
        if (_isTracked[asset]) return;
        uint256 nextLength = _trackedAssets.length + 1;
        if (nextLength > MAX_TRACKED_ASSETS) revert TooManyTrackedAssets(nextLength);
        _isTracked[asset] = true;
        _trackedAssets.push(asset);
        emit AssetTracked(asset);
    }

    function untrackEmptyAsset(address asset) external onlyPortfolioAllocator {
        if (closed) revert AccountIsClosed();
        if (!_isTracked[asset] || IERC20(asset).balanceOf(address(this)) != 0) {
            revert InvalidAsset(asset);
        }
        uint256 length = _trackedAssets.length;
        for (uint256 i; i < length; ++i) {
            if (_trackedAssets[i] != asset) continue;
            _trackedAssets[i] = _trackedAssets[length - 1];
            _trackedAssets.pop();
            _isTracked[asset] = false;
            emit AssetUntracked(asset);
            return;
        }
        revert InvalidAsset(asset);
    }

    function approveDistribution(address asset, uint256 amount) external onlyCollection {
        if (closed) revert AccountIsClosed();
        if (!_isTracked[asset] || amount == 0) revert InvalidAsset(asset);
        IERC20(asset).forceApprove(distributor, amount);
    }

    function clearDistributionApproval(address asset) external onlyCollection {
        if (closed) revert AccountIsClosed();
        if (!_isTracked[asset]) revert InvalidAsset(asset);
        IERC20(asset).forceApprove(distributor, 0);
    }

    function approveRebalance(address asset, uint256 amount) external onlyPortfolioAllocator {
        if (closed) revert AccountIsClosed();
        if (!_isTracked[asset] || amount == 0) revert InvalidAsset(asset);
        IERC20(asset).forceApprove(msg.sender, amount);
    }

    function clearRebalanceApproval(address asset) external onlyPortfolioAllocator {
        if (closed) revert AccountIsClosed();
        if (!_isTracked[asset]) revert InvalidAsset(asset);
        IERC20(asset).forceApprove(msg.sender, 0);
    }

    function releaseRemainder(address asset, address beneficiary, uint256 distributedTaxAmount)
        external
        onlyCollection
        returns (uint256 beneficiaryAmount)
    {
        if (closed) revert AccountIsClosed();
        if (!_isTracked[asset] || beneficiary == address(0)) revert InvalidAsset(asset);
        IERC20 token = IERC20(asset);
        beneficiaryAmount = token.balanceOf(address(this));
        if (beneficiaryAmount != 0) token.safeTransfer(beneficiary, beneficiaryAmount);
        uint256 remaining = token.balanceOf(address(this));
        if (remaining != 0) revert AccountNotEmpty(asset, remaining);
        emit AssetReleased(asset, beneficiary, beneficiaryAmount, distributedTaxAmount);
    }

    function releaseRestrictedRemainder(
        address asset,
        address beneficiary,
        uint256 distributedTaxAmount,
        bytes calldata proof
    ) external onlyCollection returns (uint256 beneficiaryAmount) {
        if (closed) revert AccountIsClosed();
        if (!_isTracked[asset] || beneficiary == address(0)) revert InvalidAsset(asset);
        beneficiaryAmount = IERC20(asset).balanceOf(address(this));
        if (beneficiaryAmount != 0) {
            bool transferred = IYieldBankRestrictedShare(asset)
                .transferWithProof(beneficiary, beneficiaryAmount, proof);
            if (!transferred) revert InvalidAsset(asset);
        }
        uint256 remaining = IERC20(asset).balanceOf(address(this));
        if (remaining != 0) revert AccountNotEmpty(asset, remaining);
        emit AssetReleased(asset, beneficiary, beneficiaryAmount, distributedTaxAmount);
    }

    function close() external onlyCollection {
        if (closed) revert AccountIsClosed();
        uint256 length = _trackedAssets.length;
        for (uint256 i; i < length; ++i) {
            address asset = _trackedAssets[i];
            uint256 balance = IERC20(asset).balanceOf(address(this));
            if (balance != 0) revert AccountNotEmpty(asset, balance);
        }
        closed = true;
        emit AccountClosed(tokenId);
    }

    function trackedAssets() external view returns (address[] memory) {
        return _trackedAssets;
    }

    function isTrackedAsset(address asset) external view returns (bool) {
        return _isTracked[asset];
    }
}
