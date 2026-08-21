// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IYieldAdapter } from "../interfaces/IYieldAdapter.sol";

/// @notice Basket-bound adapter for a reviewed ERC-4626 vault.
/// @dev ERC-4626 yield compounds into the share price. It is realized as deposit asset when shares
/// are redeemed; this adapter intentionally has no separate reward-token harvest path.
contract ERC4626YieldAdapter is IYieldAdapter, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public immutable basket;
    IERC4626 public immutable vault;
    IERC20 private immutable _asset;

    error Unauthorized();
    error InvalidAddress();
    error InvalidAmount();
    error InexactTransfer(uint256 expected, uint256 actual);
    error NonCompliantPreview(uint256 previewed, uint256 actual);
    error HarvestUnsupported();

    constructor(address basket_, IERC4626 vault_) {
        if (basket_ == address(0) || address(vault_).code.length == 0) revert InvalidAddress();
        address asset_ = vault_.asset();
        if (asset_.code.length == 0) revert InvalidAddress();
        basket = basket_;
        vault = vault_;
        _asset = IERC20(asset_);
    }

    modifier onlyBasket() {
        if (msg.sender != basket) revert Unauthorized();
        _;
    }

    function asset() external view returns (address) {
        return address(_asset);
    }

    function deposit(uint256 amount) external onlyBasket nonReentrant returns (uint256 shares) {
        if (amount == 0) revert InvalidAmount();
        uint256 previewedShares = vault.previewDeposit(amount);
        if (previewedShares == 0) revert InvalidAmount();

        uint256 assetBalanceBefore = _asset.balanceOf(address(this));
        _asset.safeTransferFrom(basket, address(this), amount);
        uint256 assetBalanceAfterPull = _asset.balanceOf(address(this));
        uint256 received = assetBalanceAfterPull >= assetBalanceBefore
            ? assetBalanceAfterPull - assetBalanceBefore
            : 0;
        if (received != amount) revert InexactTransfer(amount, received);

        uint256 shareBalanceBefore = vault.balanceOf(address(this));
        _asset.forceApprove(address(vault), amount);
        shares = vault.deposit(amount, address(this));
        _asset.forceApprove(address(vault), 0);
        uint256 shareBalanceAfter = vault.balanceOf(address(this));
        uint256 minted =
            shareBalanceAfter >= shareBalanceBefore ? shareBalanceAfter - shareBalanceBefore : 0;
        if (minted != shares) revert InexactTransfer(shares, minted);
        if (shares < previewedShares) revert NonCompliantPreview(previewedShares, shares);

        uint256 assetBalanceAfter = _asset.balanceOf(address(this));
        uint256 spent = assetBalanceAfterPull >= assetBalanceAfter
            ? assetBalanceAfterPull - assetBalanceAfter
            : 0;
        if (spent != amount) revert InexactTransfer(amount, spent);
    }

    function withdraw(uint256 shares) external onlyBasket nonReentrant returns (uint256 assets) {
        uint256 shareBalanceBefore = vault.balanceOf(address(this));
        if (shares == 0 || shares > shareBalanceBefore) revert InvalidAmount();
        uint256 previewedAssets = vault.previewRedeem(shares);
        uint256 basketBalanceBefore = _asset.balanceOf(basket);
        assets = vault.redeem(shares, basket, address(this));
        uint256 shareBalanceAfter = vault.balanceOf(address(this));
        uint256 spentShares =
            shareBalanceBefore >= shareBalanceAfter ? shareBalanceBefore - shareBalanceAfter : 0;
        if (spentShares != shares) revert InexactTransfer(shares, spentShares);
        if (assets < previewedAssets) revert NonCompliantPreview(previewedAssets, assets);
        uint256 basketBalanceAfter = _asset.balanceOf(basket);
        uint256 received = basketBalanceAfter >= basketBalanceBefore
            ? basketBalanceAfter - basketBalanceBefore
            : 0;
        if (received != assets) revert InexactTransfer(assets, received);
    }

    function harvest() external view onlyBasket returns (address[] memory, uint256[] memory) {
        revert HarvestUnsupported();
    }

    function totalAssets() external view returns (uint256) {
        return vault.previewRedeem(vault.balanceOf(address(this)));
    }
}
