// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { StockDividendVault } from "../stock/StockDividendVault.sol";
import { AirdropVault } from "./AirdropVault.sol";
import { IPriceHub } from "../interfaces/IPriceHub.sol";
import { IYieldBankAllocationRoute } from "../interfaces/IYieldBankAllocationRoute.sol";
import { IntegrationBinding } from "../libraries/IntegrationBinding.sol";

interface IAirdropLPLossLimit {
    function maximumOperatorLossBps() external view returns(uint16);
}

interface IAirdropLPExecution {
    function lpReceiptToken() external view returns (address);
    function purchaseLP(uint256, uint256, bytes calldata) external returns (uint256);
    function redeemLP(uint256, uint256, uint16, bytes calldata) external returns (uint256);
}

/// @notice Statically linked execution library. It has no storage, arbitrary target selection
/// or independent authority; all route/vault bindings originate in the authenticated sleeve.
library AirdropExecution {
    using SafeERC20 for IERC20;

    struct Route {
        address route;
        bytes32 codeHash;
    }

    struct Leg {
        address asset;
        uint256 amount;
        uint256 minimum;
        Route route;
        bytes data;
    }

    struct Context {
        address weth;
        address priceHub;
        address vault;
        uint256 bank;
        uint16 loss;
        bool stock;
    }
    error InexactTransfer();
    error InvalidConfiguration();
    error OracleUnavailable();

    function enter(Context memory c, Leg[] memory legs) public {
        for (uint256 i; i < legs.length; ++i) {
            Leg memory leg = legs[i];
            if (c.stock) StockDividendVault(c.vault).registry().requireCurrent(leg.asset, true);
            else AirdropVault(c.vault).registry().requireCurrent(leg.asset, true);
            uint256 units = convert(
                c.weth, leg.asset, leg.amount, leg.minimum, leg.route, leg.data, c.loss, c.priceHub
            );
            IERC20(leg.asset).forceApprove(c.vault, units);
            if (c.stock) StockDividendVault(c.vault).deposit(c.bank, leg.asset, units);
            else AirdropVault(c.vault).deposit(c.bank, leg.asset, units);
            IERC20(leg.asset).forceApprove(c.vault, 0);
        }
    }

    function exit(Context memory c, Leg[] memory legs) public {
        for (uint256 i; i < legs.length; ++i) {
            Leg memory leg = legs[i];
            uint256 units;
            if (c.stock) {
                StockDividendVault vault = StockDividendVault(c.vault);
                vault.checkpoint(c.bank, leg.asset, 32);
                uint256 reserved;
                (units, reserved,,) = vault.positions(c.bank, leg.asset);
                if (reserved != 0) {
                    vault.retainDividendDust(c.bank, leg.asset);
                    (units,,,) = vault.positions(c.bank, leg.asset);
                }
                if (units == 0) revert InvalidConfiguration();
                vault.withdrawPrincipal(c.bank, leg.asset, units);
            } else {
                units = AirdropVault(c.vault).principalOf(c.bank, leg.asset);
                AirdropVault(c.vault).withdraw(c.bank, leg.asset, units);
            }
            convert(leg.asset, c.weth, units, leg.minimum, leg.route, leg.data, c.loss, c.priceHub);
        }
    }

    function purchaseLP(
        address adapter,
        address weth,
        uint256 amount,
        uint256 minimum,
        bytes memory data
    ) public returns (uint256 units) {
        IERC20(weth).forceApprove(adapter, amount);
        IERC20 token = IERC20(IAirdropLPExecution(adapter).lpReceiptToken());
        uint256 beforeLP = token.balanceOf(address(this));
        units = IAirdropLPExecution(adapter).purchaseLP(amount, minimum, data);
        IERC20(weth).forceApprove(adapter, 0);
        if (units == 0 || token.balanceOf(address(this)) != beforeLP + units) {
            revert InexactTransfer();
        }
    }

    function redeemLP(
        address adapter,
        address weth,
        uint256 units,
        uint256 minimum,
        uint16 loss,
        bytes memory data
    ) public {
        IERC20 token = IERC20(IAirdropLPExecution(adapter).lpReceiptToken());
        uint256 beforeLP = token.balanceOf(address(this));
        uint256 beforeWeth = IERC20(weth).balanceOf(address(this));
        token.forceApprove(adapter, units);
        // A broader owner limit for Airdrop trading must not weaken the separate LP vault's cap.
        uint16 lpLimit=IAirdropLPLossLimit(address(token)).maximumOperatorLossBps();
        IAirdropLPExecution(adapter).redeemLP(units, minimum, loss < lpLimit ? loss : lpLimit, data);
        token.forceApprove(adapter, 0);
        if (
            token.balanceOf(address(this)) != beforeLP - units
                || IERC20(weth).balanceOf(address(this)) < beforeWeth + minimum
        ) revert InexactTransfer();
    }

    function convert(
        address input,
        address output,
        uint256 amount,
        uint256 minimum,
        Route memory route,
        bytes memory data,
        uint16 lossBps,
        address priceHub
    ) private returns (uint256 received) {
        IntegrationBinding.requireBound(route.route, route.codeHash);
        (uint256 inputPrice,) = price(input, priceHub);
        (uint256 outputPrice,) = price(output, priceHub);
        uint256 inputScale = 10 ** IERC20Metadata(input).decimals();
        uint256 outputScale = 10 ** IERC20Metadata(output).decimals();
        uint256 value = Math.mulDiv(amount, inputPrice, inputScale);
        uint256 quote = Math.mulDiv(value, outputScale, outputPrice);
        uint256 floor = Math.mulDiv(quote, 10000 - lossBps, 10000, Math.Rounding.Ceil);
        if (minimum == 0) revert InvalidConfiguration();
        minimum = Math.max(minimum, floor);
        uint256 beforeInput = IERC20(input).balanceOf(address(this));
        uint256 beforeOutput = IERC20(output).balanceOf(address(this));
        IERC20(input).forceApprove(route.route, amount);
        IYieldBankAllocationRoute(route.route).convert(amount, minimum, address(this), data);
        IERC20(input).forceApprove(route.route, 0);
        if (IERC20(input).balanceOf(address(this)) != beforeInput - amount) {
            revert InexactTransfer();
        }
        received = IERC20(output).balanceOf(address(this)) - beforeOutput;
        if (received < minimum) revert InexactTransfer();
    }

    function price(address asset, address hub) private view returns (uint256 value, uint48 at) {
        IPriceHub.FailureReason failure;
        (value, at, failure) = IPriceHub(hub).quoteUsd18(asset);
        if (value == 0 || failure != IPriceHub.FailureReason.NONE) revert OracleUnavailable();
    }
}
