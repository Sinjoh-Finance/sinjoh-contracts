// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

/// @notice Price-safety boundary for one project swap.
interface IProjectPriceGuard {
    function minimumOutput(
        address assetIn,
        address assetOut,
        uint256 amountIn,
        bytes32 routeHash,
        bytes calldata guardData
    ) external view returns (uint256 minimumOut, uint48 validUntil);
}
