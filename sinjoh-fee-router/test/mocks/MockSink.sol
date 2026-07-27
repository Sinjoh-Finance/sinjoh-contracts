// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ISinjohSink } from "../../src/interfaces/ISinjohSink.sol";

interface IERC20Pull {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

contract MockSink is ISinjohSink {
    bool public shouldRevert;
    bool public lieAboutReceipt;
    uint256 public totalReceived;
    bytes32 public lastConfigHash;

    function setShouldRevert(bool value) external {
        shouldRevert = value;
    }

    function setLieAboutReceipt(bool value) external {
        lieAboutReceipt = value;
    }

    function fund(address, address asset, uint256 amount, bytes calldata config)
        external
        payable
        returns (uint256 received)
    {
        if (shouldRevert) revert("SINK_REVERT");
        if (asset == address(0)) {
            require(msg.value == amount);
        } else {
            require(msg.value == 0);
            require(IERC20Pull(asset).transferFrom(msg.sender, address(this), amount));
        }
        totalReceived += amount;
        lastConfigHash = keccak256(config);
        return lieAboutReceipt ? amount - 1 : amount;
    }
}
