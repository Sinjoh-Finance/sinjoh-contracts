// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface ISinjohSink {
    function fund(address subject, address asset, uint256 amount, bytes calldata config)
        external
        payable
        returns (uint256 received);
}
