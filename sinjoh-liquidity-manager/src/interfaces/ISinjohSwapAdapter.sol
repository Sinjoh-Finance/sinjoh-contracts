// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface ISinjohSwapAdapter {
    function swap(
        address assetIn,
        address assetOut,
        uint256 amountIn,
        uint256 minimumAmountOut,
        bytes calldata routeData
    ) external payable;
}
