// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IYieldBankCollection } from "../interfaces/IYieldBankCollection.sol";
import { IYieldBankAllocationRoute } from "../interfaces/IYieldBankAllocationRoute.sol";
import { IPriceHub } from "../interfaces/IPriceHub.sol";
import { IntegrationBinding } from "../libraries/IntegrationBinding.sol";
import { StockCorporateActionRegistry as Registry } from "./StockCorporateActionRegistry.sol";
import { StockDividendAccounting as Accounting } from "./StockDividendAccounting.sol";
import { StockDividendEscrow } from "./StockDividendEscrow.sol";

/// @notice Isolated Stock custody and dividend-only conversion for an integrating sleeve.
/// @dev NOT itself an allocator-compatible sleeve. The immutable controller must implement
/// bank-bound allocation, basket selection, receipt valuation and the existing redemption path.
/// Deploying this vault does not grant access to an existing Piggy Bank's funds.
contract StockDividendVault is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Accounting for Accounting.Position;

    error InvalidConfiguration();
    error UnauthorizedController();
    error InvalidBank();
    error InexactTransfer();
    error UnpaidDividend();
    error InvalidQuote();
    error DividendDustRemainder();
    uint256 public constant MAX_DIVIDEND_DUST_UNITS = 100;

    struct RouteBinding {
        address route;
        bytes32 codeHash;
    }
    IYieldBankCollection public immutable collection;
    IERC721 public immutable nft;
    address public immutable controller;
    IERC20 public immutable payoutAsset;
    Registry public immutable registry;
    IPriceHub public immutable priceHub;
    StockDividendEscrow public immutable escrow;
    uint16 public immutable maximumLossBps;
    uint8 public immutable payoutDecimals;
    uint256 public settlementNonce;
    mapping(uint256 bank => mapping(address asset => Accounting.Position)) public positions;
    mapping(address asset => uint256) public accountedUnits;
    mapping(address asset => RouteBinding) public dividendRoutes;

    event PrincipalDeposited(uint256 indexed bank, address indexed asset, uint256 units);
    event PrincipalWithdrawn(uint256 indexed bank, address indexed asset, uint256 units);
    event ActionApplied(
        uint256 indexed bank, address indexed asset, uint64 sequence, uint256 reserved
    );
    event DividendConverted(
        uint256 indexed bank,
        address indexed asset,
        bytes32 indexed settlementId,
        uint256 units,
        uint256 proceeds
    );
    event DividendDustRetained(uint256 indexed bank, address indexed asset, uint256 units);
    event DividendRouteSet(address indexed asset, address indexed route, bytes32 codeHash);

    constructor(
        address collection_,
        address controller_,
        address governance_,
        address payoutAsset_,
        address registry_,
        address priceHub_,
        uint16 maximumLossBps_
    ) Ownable(governance_) {
        if (
            collection_.code.length == 0 || controller_ == address(0)
                || payoutAsset_.code.length == 0 || registry_.code.length == 0
                || priceHub_.code.length == 0 || maximumLossBps_ > 500
        ) revert InvalidConfiguration();
        collection = IYieldBankCollection(collection_);
        address nft_ = collection.nft();
        if (nft_.code.length == 0) revert InvalidConfiguration();
        nft = IERC721(nft_);
        controller = controller_;
        payoutAsset = IERC20(payoutAsset_);
        registry = Registry(registry_);
        priceHub = IPriceHub(priceHub_);
        maximumLossBps = maximumLossBps_;
        uint8 decimals_ = IERC20Metadata(payoutAsset_).decimals();
        if (decimals_ > 18) revert InvalidConfiguration();
        payoutDecimals = decimals_;
        escrow = new StockDividendEscrow(nft_, payoutAsset_, address(this));
    }

    modifier onlyController() {
        if (msg.sender != controller) revert UnauthorizedController();
        _;
    }

    function setDividendRoute(address asset, address route) external onlyOwner {
        if (
            asset == address(payoutAsset) || asset.code.length == 0
                || IERC20Metadata(asset).decimals() > 18 || route.code.length == 0
                || IYieldBankAllocationRoute(route).inputAsset() != asset
                || IYieldBankAllocationRoute(route).outputAsset() != address(payoutAsset)
        ) revert InvalidConfiguration();
        dividendRoutes[asset] = RouteBinding(route, route.codehash);
        emit DividendRouteSet(asset, route, route.codehash);
    }

    function deposit(uint256 bank, address asset, uint256 units)
        external
        onlyController
        nonReentrant
    {
        _requireBank(bank);
        (uint64 sequence, uint256 multiplier) = registry.requireCurrent(asset, true);
        _checkpoint(bank, asset, sequence, 32);
        Accounting.Position storage position = positions[bank][asset];
        uint256 beforeBalance = IERC20(asset).balanceOf(address(this));
        position.deposit(units, sequence, multiplier);
        accountedUnits[asset] += units;
        IERC20(asset).safeTransferFrom(msg.sender, address(this), units);
        if (IERC20(asset).balanceOf(address(this)) != beforeBalance + units) {
            revert InexactTransfer();
        }
        registry.requireCurrent(asset, true);
        emit PrincipalDeposited(bank, asset, units);
    }

    /// @dev Return principal only to the immutable sleeve. Its redemption must route the
    /// assets through the existing allocator, and must not burn its last receipt with debt.
    function withdrawPrincipal(uint256 bank, address asset, uint256 units)
        external
        onlyController
        nonReentrant
    {
        _requireBank(bank);
        (uint64 sequence, uint256 multiplier) = registry.requireCurrent(asset, false);
        _checkpoint(bank, asset, sequence, 32);
        Accounting.Position storage position = positions[bank][asset];
        if (units == position.principalUnits && position.reservedUnits != 0) {
            revert UnpaidDividend();
        }
        position.withdrawPrincipal(units, sequence, multiplier);
        accountedUnits[asset] -= units;
        uint256 beforeBalance = IERC20(asset).balanceOf(address(this));
        uint256 beforeReceiver = IERC20(asset).balanceOf(controller);
        IERC20(asset).safeTransfer(controller, units);
        if (
            IERC20(asset).balanceOf(address(this)) != beforeBalance - units
                || IERC20(asset).balanceOf(controller) != beforeReceiver + units
        ) revert InexactTransfer();
        emit PrincipalWithdrawn(bank, asset, units);
    }

    /// @notice Permissionless, bounded processing of already-authenticated actions.
    function checkpoint(uint256 bank, address asset, uint8 limit) external nonReentrant {
        if (limit == 0 || limit > 32) revert InvalidConfiguration();
        (, uint64 sequence,,,) = registry.assets(asset);
        _checkpoint(bank, asset, sequence, limit);
    }

    /// @notice Convert only this bank's reserved dividend units using a bound route.
    /// @dev Caller may strengthen the oracle-derived minimum but cannot weaken it, pick a
    /// beneficiary, spend principal or spend another bank's reserve. Price gains reserve zero.
    function settleDividend(
        uint256 bank,
        address asset,
        uint256 units,
        uint256 minimumOutput,
        bytes calldata data
    ) external nonReentrant returns (uint256 proceeds) {
        _requireBank(bank);
        (uint64 sequence, uint256 multiplier) = registry.requireCurrent(asset, false);
        _checkpoint(bank, asset, sequence, 32);
        positions[bank][asset].requireCurrent(sequence, multiplier);
        RouteBinding memory binding = dividendRoutes[asset];
        IntegrationBinding.requireBound(binding.route, binding.codeHash);
        uint256 reserved = positions[bank][asset].reservedUnits;
        if (units < reserved && _cashQuote(asset, reserved - units) <= MAX_DIVIDEND_DUST_UNITS) {
            revert DividendDustRemainder();
        }
        uint256 required = _minimumProceeds(asset, units);
        if (minimumOutput == 0) revert InvalidQuote();
        minimumOutput = Math.max(minimumOutput, required);
        positions[bank][asset].consumeDividend(units);
        accountedUnits[asset] -= units;
        uint256 beforeInput = IERC20(asset).balanceOf(address(this));
        uint256 beforeOutput = payoutAsset.balanceOf(address(this));
        IERC20(asset).forceApprove(binding.route, units);
        IYieldBankAllocationRoute(binding.route).convert(units, minimumOutput, address(this), data);
        IERC20(asset).forceApprove(binding.route, 0);
        if (IERC20(asset).balanceOf(address(this)) != beforeInput - units) {
            revert InexactTransfer();
        }
        proceeds = payoutAsset.balanceOf(address(this)) - beforeOutput;
        if (proceeds < minimumOutput) revert InvalidQuote();
        registry.requireCurrent(asset, false);
        bytes32 id =
            keccak256(abi.encode(block.chainid, address(this), ++settlementNonce, bank, asset));
        payoutAsset.forceApprove(address(escrow), proceeds);
        escrow.settleAndPay(bank, id, proceeds);
        payoutAsset.forceApprove(address(escrow), 0);
        if (payoutAsset.balanceOf(address(this)) != beforeOutput) revert InexactTransfer();
        emit DividendConverted(bank, asset, id, units, proceeds);
    }

    /// @notice Preserve sub-payment-precision dividend dust in backing during a full exit.
    /// @dev Only the custody controller may do this. No units are lost, sent to governance,
    /// or counted as paid income. The cap is 100 payout base units (0.0001 USDG at 6 decimals).
    function retainDividendDust(uint256 bank, address asset) external onlyController nonReentrant {
        _requireBank(bank);
        (uint64 sequence, uint256 multiplier) = registry.requireCurrent(asset, false);
        _checkpoint(bank, asset, sequence, 32);
        Accounting.Position storage position = positions[bank][asset];
        position.requireCurrent(sequence, multiplier);
        uint256 units = position.reservedUnits;
        if (units == 0 || _cashQuote(asset, units) > MAX_DIVIDEND_DUST_UNITS) {
            revert UnpaidDividend();
        }
        position.reservedUnits = 0;
        position.principalUnits += units;
        emit DividendDustRetained(bank, asset, units);
    }

    function _checkpoint(uint256 bank, address asset, uint64 latest, uint8 limit) private {
        Accounting.Position storage position = positions[bank][asset];
        if (position.multiplier == 0) return;
        uint256 count;
        while (position.sequence < latest && count < limit) {
            uint64 next = position.sequence + 1;
            Registry.Action memory action = registry.actionAt(asset, next);
            uint256 reserved = position.applyAction(
                next, action.beforeMultiplier, action.afterMultiplier, action.kind
            );
            emit ActionApplied(bank, asset, next, reserved);
            ++count;
        }
        // Public checkpoint calls can advance in batches; mutations subsequently require
        // equality through deposit/withdraw or the explicit check in settlement below.
    }

    function _minimumProceeds(address asset, uint256 units) private view returns (uint256) {
        uint256 cashUnits = _cashQuote(asset, units);
        return
            Math.max(1, Math.mulDiv(cashUnits, 10_000 - maximumLossBps, 10_000, Math.Rounding.Ceil));
    }

    function _cashQuote(address asset, uint256 units) private view returns (uint256) {
        (uint256 stockPrice,, IPriceHub.FailureReason stockFailure) = priceHub.quoteUsd18(asset);
        (uint256 cashPrice,, IPriceHub.FailureReason cashFailure) =
            priceHub.quoteUsd18(address(payoutAsset));
        if (
            stockPrice == 0 || cashPrice == 0 || stockFailure != IPriceHub.FailureReason.NONE
                || cashFailure != IPriceHub.FailureReason.NONE
        ) revert InvalidQuote();
        uint8 decimals_ = IERC20Metadata(asset).decimals();
        if (decimals_ > 18) revert InvalidConfiguration();
        uint256 value = Math.mulDiv(units, stockPrice, 10 ** decimals_);
        return Math.mulDiv(value, 10 ** payoutDecimals, cashPrice);
    }

    function _requireBank(uint256 bank) private view {
        if (collection.accountOf(bank) == address(0) || nft.ownerOf(bank) == address(0)) {
            revert InvalidBank();
        }
    }
}
