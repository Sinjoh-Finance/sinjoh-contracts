// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

contract MockControlledModule {
    address public immutable controller;
    uint256 public value;
    uint256 public calls;
    uint256 public nativeReceived;

    error OnlyController(address caller);

    constructor(address controller_) {
        controller = controller_;
    }

    modifier onlyController() {
        if (msg.sender != controller) revert OnlyController(msg.sender);
        _;
    }

    function setValue(uint256 newValue) external onlyController {
        value = newValue;
        calls += 1;
    }

    function setValuePayable(uint256 newValue) external payable onlyController {
        value = newValue;
        calls += 1;
        nativeReceived += msg.value;
    }

    function increment(uint256 amount) external onlyController returns (uint256 current) {
        value += amount;
        calls += 1;
        return value;
    }
}

contract MockBatchTarget {
    bool public shouldRevert = true;
    uint256 public calls;

    error ForcedFailure();

    function setShouldRevert(bool value) external {
        shouldRevert = value;
    }

    function run() external {
        if (shouldRevert) revert ForcedFailure();
        calls += 1;
    }
}
