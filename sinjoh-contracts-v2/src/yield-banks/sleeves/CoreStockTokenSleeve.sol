// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { BaseSleeve } from "./BaseSleeve.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IYieldBankAllocationRoute } from "../interfaces/IYieldBankAllocationRoute.sol";
import { IPriceHub } from "../interfaces/IPriceHub.sol";
import { IntegrationBinding } from "../libraries/IntegrationBinding.sol";
import { YieldBankIds } from "../libraries/YieldBankIds.sol";

/// @notice Directly holds a collection-configured set of reviewed Robinhood Stock Tokens.
contract CoreStockTokenSleeve is BaseSleeve {
    using SafeERC20 for IERC20;

    struct Constituent {
        address asset;
        address route;
        bytes32 routeRuntimeCodeHash;
        uint16 weightBps;
    }

    struct ConstituentCall {
        uint256 minimumOutput;
        bytes routeData;
    }

    uint256 private constant MAX_CONSTITUENTS = MAX_INVENTORY_ASSETS - 1;
    Constituent[] private _constituents;
    mapping(address asset => bool constituent) private _isConstituent;
    uint16 public constituentWeightTotal;

    event ConstituentRouteUpdated(
        address indexed asset, address indexed route, bytes32 runtimeCodeHash
    );

    constructor(
        string memory name_,
        string memory symbol_,
        address accountingAsset_,
        address allocator_,
        address timelock_,
        address guardian_,
        address priceHub_,
        address strategyRegistry_,
        address eligibilityPolicy_,
        uint8 maximumStrategies_,
        uint16 maximumAdapterCapBps_,
        uint16 maximumOperatorLossBps_
    )
        BaseSleeve(
            name_,
            symbol_,
            YieldBankIds.CORE,
            accountingAsset_,
            allocator_,
            timelock_,
            guardian_,
            priceHub_,
            strategyRegistry_,
            eligibilityPolicy_,
            maximumStrategies_,
            maximumAdapterCapBps_,
            maximumOperatorLossBps_
        )
    { }

    function constituents() external view returns (Constituent[] memory) {
        return _constituents;
    }

    function addConstituent(
        address asset,
        address route,
        bytes32 routeRuntimeCodeHash,
        uint16 weightBps
    ) external onlyTimelock {
        if (
            totalSupply() != 0 || _isConstituent[asset] || _constituents.length >= MAX_CONSTITUENTS
                || weightBps == 0 || constituentWeightTotal + weightBps > BPS
        ) {
            revert InvalidConfiguration();
        }
        _validateRoute(asset, route, routeRuntimeCodeHash);
        _addInventoryAsset(asset);
        _isConstituent[asset] = true;
        constituentWeightTotal += weightBps;
        _constituents.push(Constituent(asset, route, routeRuntimeCodeHash, weightBps));
    }

    function replaceConstituent(
        uint256 index,
        address replacement,
        address route,
        bytes32 routeRuntimeCodeHash
    ) external onlyTimelock {
        if (
            index >= _constituents.length || _isConstituent[replacement]
                || activeStrategyCount() != 0
        ) {
            revert InvalidConfiguration();
        }
        Constituent storage current = _constituents[index];
        address previous = current.asset;
        if (IERC20(previous).balanceOf(address(this)) != 0) revert InvalidConfiguration();
        _validateRoute(replacement, route, routeRuntimeCodeHash);
        _replaceInventoryAsset(previous, replacement);
        _isConstituent[previous] = false;
        _isConstituent[replacement] = true;
        current.asset = replacement;
        current.route = route;
        current.routeRuntimeCodeHash = routeRuntimeCodeHash;
    }

    function updateConstituentRoute(uint256 index, address route, bytes32 routeRuntimeCodeHash)
        external
        onlyTimelock
    {
        if (index >= _constituents.length) revert InvalidConfiguration();
        Constituent storage current = _constituents[index];
        _validateRoute(current.asset, route, routeRuntimeCodeHash);
        current.route = route;
        current.routeRuntimeCodeHash = routeRuntimeCodeHash;
        emit ConstituentRouteUpdated(current.asset, route, routeRuntimeCodeHash);
    }

    function _afterDeposit(uint256 assets, bytes calldata data, uint256)
        internal
        override
        returns (uint256 creditedValue)
    {
        uint256 length = _constituents.length;
        if (length == 0 || constituentWeightTotal != BPS) revert InvalidConfiguration();
        ConstituentCall[] memory calls = abi.decode(data, (ConstituentCall[]));
        if (calls.length != length) revert InvalidConfiguration();
        uint256 allocated;
        for (uint256 i; i < length; ++i) {
            if (calls[i].minimumOutput == 0) revert InvalidConfiguration();
            Constituent memory constituent = _constituents[i];
            IntegrationBinding.requireBound(constituent.route, constituent.routeRuntimeCodeHash);
            uint256 amountIn = i + 1 == length
                ? assets - allocated
                : Math.mulDiv(assets, constituent.weightBps, BPS);
            allocated += amountIn;
            IERC20 outputToken = IERC20(constituent.asset);
            uint256 beforeBalance = outputToken.balanceOf(address(this));
            IERC20 inputToken = IERC20(accountingAsset);
            uint256 inputBefore = inputToken.balanceOf(address(this));
            inputToken.forceApprove(constituent.route, amountIn);
            IYieldBankAllocationRoute(constituent.route)
                .convert(amountIn, calls[i].minimumOutput, address(this), calls[i].routeData);
            inputToken.forceApprove(constituent.route, 0);
            uint256 consumed = inputBefore - inputToken.balanceOf(address(this));
            if (consumed != amountIn) revert InexactReceipt(amountIn, consumed);
            uint256 received = outputToken.balanceOf(address(this)) - beforeBalance;
            if (received < calls[i].minimumOutput || received == 0) {
                revert InexactReceipt(calls[i].minimumOutput, received);
            }
            (uint256 price,, IPriceHub.FailureReason failure) =
                priceHub.quoteUsd18(constituent.asset);
            if (failure != IPriceHub.FailureReason.NONE || price == 0) {
                revert InvalidConfiguration();
            }
            creditedValue += Math.mulDiv(
                received, price, 10 ** IERC20Metadata(constituent.asset).decimals()
            );
        }
    }

    function _validateRoute(address asset, address route, bytes32 codeHash) private view {
        IntegrationBinding.requireBound(route, codeHash);
        if (
            IYieldBankAllocationRoute(route).inputAsset() != accountingAsset
                || IYieldBankAllocationRoute(route).outputAsset() != asset
        ) revert InvalidConfiguration();
    }
}
