// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

interface ISinjohPriceGuard {
    function minimumOutput(
        address subject,
        address assetIn,
        address assetOut,
        uint256 amountIn,
        bytes32 routeHash,
        bytes calldata guardData
    ) external view returns (uint256 minOut, uint48 validUntil);
}
