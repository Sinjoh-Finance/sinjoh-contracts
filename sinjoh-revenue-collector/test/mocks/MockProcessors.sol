// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface ICollector {
    function forward(address asset, uint256 amount) external;
}

contract RejectingProcessor {
    receive() external payable {
        revert();
    }
}

contract ReentrantProcessor {
    ICollector public immutable collector;

    constructor(address collector_) {
        collector = ICollector(collector_);
    }

    receive() external payable {
        collector.forward(address(0), 1);
    }
}
