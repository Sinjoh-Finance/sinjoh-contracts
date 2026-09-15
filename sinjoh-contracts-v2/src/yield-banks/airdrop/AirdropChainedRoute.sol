// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IYieldBankAllocationRoute } from "../interfaces/IYieldBankAllocationRoute.sol";
import { IntegrationBinding } from "../libraries/IntegrationBinding.sol";

/// @notice An immutable, acyclic path of two or three reviewed routes.
/// @dev The final receiver's measured output enforces the whole-path minimum.
contract AirdropChainedRoute is IYieldBankAllocationRoute, ReentrancyGuard {
    using SafeERC20 for IERC20;
    address public immutable inputAsset;
    address public immutable outputAsset;
    address[] public routes;
    bytes32[] public routeCodeHashes;
    address[] public assets;
    bytes32[] public assetCodeHashes;
    error InvalidRoute();
    error InexactTransfer();
    error InsufficientOutput(uint256 minimum, uint256 actual);

    constructor(address[] memory routes_) {
        if (routes_.length < 2 || routes_.length > 3) revert InvalidRoute();
        for (uint256 i; i < routes_.length; ++i) {
            if (routes_[i].code.length == 0) revert InvalidRoute();
            IYieldBankAllocationRoute route = IYieldBankAllocationRoute(routes_[i]);
            address input = route.inputAsset();
            address output = route.outputAsset();
            if (input.code.length == 0 || output.code.length == 0 || input == output) {
                revert InvalidRoute();
            }
            if (i == 0) assets.push(input);
            else if (input != assets[i]) revert InvalidRoute();
            for (uint256 j; j < assets.length; ++j) {
                if (assets[j] == output) revert InvalidRoute();
            }
            assets.push(output);
            routes.push(routes_[i]);
            routeCodeHashes.push(routes_[i].codehash);
        }
        for (uint256 i; i < assets.length; ++i) {
            assetCodeHashes.push(assets[i].codehash);
        }
        inputAsset = assets[0];
        outputAsset = assets[assets.length - 1];
    }

    function convert(uint256 amountIn, uint256 minimumOutput, address receiver, bytes calldata data)
        external
        nonReentrant
        returns (uint256 amountOut)
    {
        if (
            amountIn == 0 || minimumOutput == 0 || data.length != 0 || receiver == address(0)
                || receiver == address(this)
        ) revert InvalidRoute();
        uint256[] memory beforeBalances = new uint256[](assets.length);
        for (uint256 i; i < assets.length; ++i) {
            IntegrationBinding.requireBound(assets[i], assetCodeHashes[i]);
            beforeBalances[i] = IERC20(assets[i]).balanceOf(address(this));
        }
        uint256 receiverBefore = IERC20(outputAsset).balanceOf(receiver);
        IERC20(inputAsset).safeTransferFrom(msg.sender, address(this), amountIn);
        if (IERC20(inputAsset).balanceOf(address(this)) != beforeBalances[0] + amountIn) {
            revert InexactTransfer();
        }
        amountOut = amountIn;
        for (uint256 i; i < routes.length; ++i) {
            IntegrationBinding.requireBound(routes[i], routeCodeHashes[i]);
            IERC20(assets[i]).forceApprove(routes[i], amountOut);
            IYieldBankAllocationRoute(routes[i])
                .convert(amountOut, i + 1 == routes.length ? minimumOutput : 1, address(this), "");
            IERC20(assets[i]).forceApprove(routes[i], 0);
            if (IERC20(assets[i]).balanceOf(address(this)) != beforeBalances[i]) {
                revert InexactTransfer();
            }
            amountOut = IERC20(assets[i + 1]).balanceOf(address(this)) - beforeBalances[i + 1];
            if (amountOut == 0) revert InexactTransfer();
        }
        if (amountOut < minimumOutput) revert InsufficientOutput(minimumOutput, amountOut);
        IERC20(outputAsset).safeTransfer(receiver, amountOut);
        if (IERC20(outputAsset).balanceOf(receiver) != receiverBefore + amountOut) {
            revert InexactTransfer();
        }
        for (uint256 i; i < assets.length; ++i) {
            if (IERC20(assets[i]).balanceOf(address(this)) != beforeBalances[i]) {
                revert InexactTransfer();
            }
        }
    }
}
