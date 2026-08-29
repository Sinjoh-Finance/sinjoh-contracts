// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

interface IYieldBankAllocationRoute {
    function inputAsset() external view returns (address);
    function outputAsset() external view returns (address);
    function convert(uint256 amountIn, uint256 minimumOutput, address receiver, bytes calldata data)
        external
        returns (uint256 amountOut);
}
