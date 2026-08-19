// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

interface ISinjohSink {
    function fund(address subject, address asset, uint256 amount, bytes calldata config)
        external
        payable
        returns (uint256 received);
}
