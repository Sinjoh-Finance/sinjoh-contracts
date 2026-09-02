// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

/// @notice Verified DeltaPositionBuilder surface used by Yield Banks.
interface IDeltaPositionBuilder {
    struct Rung {
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0;
        uint256 amount1;
        uint256 amount0Min;
        uint256 amount1Min;
    }

    function mintLadder(
        address pool,
        Rung[] calldata rungs,
        int24 minTick,
        int24 maxTick,
        uint256 deadline
    ) external payable returns (uint256[] memory tokenIds);

    function positionManager() external view returns (address);
    function uniFactory() external view returns (address);
    function weth() external view returns (address);
}
