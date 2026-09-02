// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

interface IYieldBankAllocationReceiver {
    function allocate(address asset, uint256 amount, bytes calldata data)
        external
        returns (address[] memory distributionAssets, uint256[] memory distributionAmounts);
}
