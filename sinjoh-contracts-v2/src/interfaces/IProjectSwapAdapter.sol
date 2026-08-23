// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

/// @notice Narrow swap boundary shared by project custody modules.
/// @dev The adapter pulls exact ERC-20 input from msg.sender or consumes exact msg.value for native
/// input, then sends all output back to msg.sender. Callers measure both deltas independently.
interface IProjectSwapAdapter {
    function swap(
        address assetIn,
        address assetOut,
        uint256 amountIn,
        uint256 minimumOut,
        bytes calldata routeData
    ) external payable returns (uint256 reportedAmountOut);
}
