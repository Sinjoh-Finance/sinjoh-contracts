// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { YieldBankAccount } from "./YieldBankAccount.sol";

/// @notice O(1) per-live-token distribution accounting with bounded settlement.
contract YieldBankDistributor is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant RAY = 1e27;
    uint256 public constant MAX_DISTRIBUTION_ASSETS = 8;

    address public immutable collection;
    address[] private _assets;
    mapping(address asset => bool registered) public isDistributionAsset;
    mapping(address asset => uint256 index) public accPerLiveNftRay;
    mapping(uint256 tokenId => mapping(address asset => uint256 debt)) public debtRay;
    mapping(address asset => uint256 amount) public totalReceived;
    mapping(address asset => uint256 amount) public totalSettled;
    mapping(uint256 tokenId => mapping(address asset => uint256 amount)) public cumulativeSettled;
    mapping(address asset => uint256 amount) public accountedBalance;

    error OnlyCollection(address caller);
    error InvalidAsset(address asset);
    error TooManyAssets(uint256 supplied);
    error InvalidSupply(uint256 supplied);
    error InvalidAmount(uint256 supplied);
    error InexactReceipt(address asset, uint256 expected, uint256 measured);

    event DistributionAssetRegistered(address indexed asset);
    event DistributionAccrued(
        address indexed asset, uint256 amount, uint256 liveSupply, uint256 indexIncrease
    );
    event TokenSettled(uint256 indexed tokenId, address indexed account, bool terminal);
    event AssetSettled(
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

    function initializeTokenDebt(uint256 tokenId) external onlyCollection {
        uint256 length = _assets.length;
        for (uint256 i; i < length; ++i) {
            address asset = _assets[i];
            debtRay[tokenId][asset] = accPerLiveNftRay[asset];
        }
    }

    function accrueFrom(address asset, address source, uint256 amount, uint256 liveSupply)
        external
        onlyCollection
        nonReentrant
    {
        if (!isDistributionAsset[asset]) revert InvalidAsset(asset);
        if (amount == 0) revert InvalidAmount(amount);
        if (liveSupply == 0) revert InvalidSupply(liveSupply);
        IERC20 token = IERC20(asset);
        uint256 beforeBalance = token.balanceOf(address(this));
        token.safeTransferFrom(source, address(this), amount);
        uint256 measured = token.balanceOf(address(this)) - beforeBalance;
        if (measured != amount) revert InexactReceipt(asset, amount, measured);
        _accrue(asset, amount, liveSupply);
    }

    function settle(uint256 tokenId, address account, bool terminal)
        external
        onlyCollection
        nonReentrant
    {
        uint256 length = _assets.length;
        for (uint256 i; i < length; ++i) {
            address asset = _assets[i];
            YieldBankAccount(account).trackAsset(asset);
            uint256 amount;
            if (terminal) {
                amount = accountedBalance[asset];
                debtRay[tokenId][asset] = accPerLiveNftRay[asset];
            } else {
                uint256 pendingRay = accPerLiveNftRay[asset] - debtRay[tokenId][asset];
                amount = pendingRay / RAY;
                debtRay[tokenId][asset] += amount * RAY;
            }
            if (amount == 0) continue;
            accountedBalance[asset] -= amount;
            totalSettled[asset] += amount;
            cumulativeSettled[tokenId][asset] += amount;
            IERC20(asset).safeTransfer(account, amount);
            emit AssetSettled(tokenId, asset, amount, terminal);
        }
        emit TokenSettled(tokenId, account, terminal);
    }

    function retireToken(uint256 tokenId) external onlyCollection {
        uint256 length = _assets.length;
        for (uint256 i; i < length; ++i) {
            address asset = _assets[i];
            debtRay[tokenId][asset] = accPerLiveNftRay[asset];
        }
        emit TokenRetired(tokenId);
    }

    function pending(uint256 tokenId, address asset) external view returns (uint256) {
        if (!isDistributionAsset[asset]) return 0;
        return (accPerLiveNftRay[asset] - debtRay[tokenId][asset]) / RAY;
    }

    function distributionAssets() external view returns (address[] memory) {
        return _assets;
    }

    function solvent(address asset) external view returns (bool) {
        return IERC20(asset).balanceOf(address(this)) >= accountedBalance[asset];
    }

    function _accrue(address asset, uint256 amount, uint256 liveSupply) private {
        uint256 indexIncrease = Math.mulDiv(amount, RAY, liveSupply);
        accPerLiveNftRay[asset] += indexIncrease;
        accountedBalance[asset] += amount;
        totalReceived[asset] += amount;
        emit DistributionAccrued(asset, amount, liveSupply, indexIncrease);
    }
}
