// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IBasketYieldAdapter } from "../interfaces/IBasketYieldAdapter.sol";
import { SinjohV2Constants } from "../libraries/SinjohV2Constants.sol";

/// @notice Basket-bound adapter for one reviewed ERC-4626 vault.
/// @dev Constructor bindings are ordinary frozen storage so every instance has the same runtime
/// hash for release-root approval. There is no owner, initializer, rescue, or mutable route.
contract ERC4626BasketYieldAdapter is IBasketYieldAdapter, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public override basketVault;
    address public override depositAsset;
    IERC4626 public vault;
    uint256 public managedPrincipal;

    error OnlyBasketVault(address caller);
    error InvalidAddress(address candidate);
    error InvalidRecipient(address supplied);
    error InvalidAmount(uint256 supplied);
    error InexactAssetMovement(uint256 expected, uint256 actual);
    error InexactShareMovement(uint256 expected, uint256 actual);
    error PrincipalImpaired(uint256 principal, uint256 positionValue);

    event Deposited(uint256 assets, uint256 shares, uint256 managedPrincipal);
    event Harvested(uint256 assets, uint256 remainingPositionValue);
    event Exited(uint256 assets);

    constructor(address basketVault_, address vault_) {
        if (basketVault_ == address(0) || basketVault_ == SinjohV2Constants.BURN_ADDRESS) {
            revert InvalidAddress(basketVault_);
        }
        if (vault_.code.length == 0) revert InvalidAddress(vault_);
        address asset = IERC4626(vault_).asset();
        if (asset.code.length == 0) revert InvalidAddress(asset);
        basketVault = basketVault_;
        vault = IERC4626(vault_);
        depositAsset = asset;
    }

    modifier onlyBasket() {
        if (msg.sender != basketVault) revert OnlyBasketVault(msg.sender);
        _;
    }

    function yieldSource() external view override returns (address) {
        return address(vault);
    }

    function deposit(uint256 assets)
        external
        onlyBasket
        nonReentrant
        returns (uint256 positionUnits)
    {
        if (assets == 0) revert InvalidAmount(assets);
        IERC20 asset = IERC20(depositAsset);
        uint256 positionBefore = totalAssets();
        uint256 idleBefore = asset.balanceOf(address(this));
        asset.safeTransferFrom(msg.sender, address(this), assets);
        uint256 idleAfterPull = asset.balanceOf(address(this));
        uint256 received = idleAfterPull >= idleBefore ? idleAfterPull - idleBefore : 0;
        if (received != assets) revert InexactAssetMovement(assets, received);

        uint256 sharesBefore = vault.balanceOf(address(this));
        asset.forceApprove(address(vault), assets);
        positionUnits = vault.deposit(assets, address(this));
        asset.forceApprove(address(vault), 0);
        uint256 sharesAfter = vault.balanceOf(address(this));
        uint256 minted = sharesAfter >= sharesBefore ? sharesAfter - sharesBefore : 0;
        if (positionUnits == 0 || minted != positionUnits) {
            revert InexactShareMovement(positionUnits, minted);
        }
        uint256 idleAfter = asset.balanceOf(address(this));
        uint256 spent = idleAfterPull >= idleAfter ? idleAfterPull - idleAfter : 0;
        if (spent != assets) revert InexactAssetMovement(assets, spent);

        uint256 positionAfter = totalAssets();
        if (positionAfter < positionBefore + assets) {
            revert InexactAssetMovement(positionBefore + assets, positionAfter);
        }
        managedPrincipal += assets;
        emit Deposited(assets, positionUnits, managedPrincipal);
    }

    function totalAssets() public view returns (uint256 assets) {
        return IERC20(depositAsset).balanceOf(address(this))
            + vault.previewRedeem(vault.balanceOf(address(this)));
    }

    function harvest(address recipient)
        external
        onlyBasket
        nonReentrant
        returns (address[] memory assets, uint256[] memory amounts)
    {
        _requireRecipient(recipient);
        assets = _singleAsset();
        amounts = new uint256[](1);
        uint256 positionBefore = totalAssets();
        if (positionBefore <= managedPrincipal) return (assets, amounts);

        IERC20 asset = IERC20(depositAsset);
        uint256 recipientBefore = asset.balanceOf(recipient);
        uint256 expected;
        uint256 distributable = positionBefore - managedPrincipal;
        uint256 idle = asset.balanceOf(address(this));
        uint256 idleYield = idle < distributable ? idle : distributable;
        if (idleYield != 0) {
            asset.safeTransfer(recipient, idleYield);
            expected = idleYield;
        }

        uint256 idleRemaining = asset.balanceOf(address(this));
        uint256 requiredVaultAssets =
            managedPrincipal > idleRemaining ? managedPrincipal - idleRemaining : 0;
        uint256 shares = vault.balanceOf(address(this));
        uint256 sharesToKeep =
            requiredVaultAssets == 0 ? 0 : vault.previewWithdraw(requiredVaultAssets);
        if (sharesToKeep < shares) {
            uint256 sharesToRedeem = shares - sharesToKeep;
            uint256 sharesBefore = shares;
            uint256 redeemed = vault.redeem(sharesToRedeem, recipient, address(this));
            uint256 sharesAfter = vault.balanceOf(address(this));
            uint256 spentShares = sharesBefore >= sharesAfter ? sharesBefore - sharesAfter : 0;
            if (spentShares != sharesToRedeem) {
                revert InexactShareMovement(sharesToRedeem, spentShares);
            }
            expected += redeemed;
        }

        uint256 received = asset.balanceOf(recipient) - recipientBefore;
        if (received != expected) revert InexactAssetMovement(expected, received);
        uint256 positionAfter = totalAssets();
        if (positionAfter < managedPrincipal) {
            revert PrincipalImpaired(managedPrincipal, positionAfter);
        }
        amounts[0] = received;
        emit Harvested(received, positionAfter);
    }

    function exitAll(address recipient)
        external
        onlyBasket
        nonReentrant
        returns (address[] memory assets, uint256[] memory amounts)
    {
        _requireRecipient(recipient);
        assets = _singleAsset();
        amounts = new uint256[](1);
        IERC20 asset = IERC20(depositAsset);
        uint256 recipientBefore = asset.balanceOf(recipient);
        uint256 expected;

        uint256 idle = asset.balanceOf(address(this));
        if (idle != 0) {
            asset.safeTransfer(recipient, idle);
            expected = idle;
        }
        uint256 shares = vault.balanceOf(address(this));
        if (shares != 0) {
            uint256 redeemed = vault.redeem(shares, recipient, address(this));
            uint256 remainingShares = vault.balanceOf(address(this));
            if (remainingShares != 0) {
                revert InexactShareMovement(shares, shares - remainingShares);
            }
            expected += redeemed;
        }

        uint256 received = asset.balanceOf(recipient) - recipientBefore;
        if (received != expected) revert InexactAssetMovement(expected, received);
        managedPrincipal = 0;
        if (totalAssets() != 0) revert InexactAssetMovement(0, totalAssets());
        amounts[0] = received;
        emit Exited(received);
    }

    function _requireRecipient(address recipient) private view {
        if (recipient != basketVault) revert InvalidRecipient(recipient);
    }

    function _singleAsset() private view returns (address[] memory assets) {
        assets = new address[](1);
        assets[0] = depositAsset;
    }
}
