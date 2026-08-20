// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

interface ISinjohFundable {
    function fund(address asset, uint256 amount, bytes calldata config)
        external
        returns (uint256 received);
}
