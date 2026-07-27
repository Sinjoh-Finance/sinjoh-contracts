// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { MockERC20 } from "./MockERC20.sol";

contract MockFeeRouter {
    mapping(address asset => uint256 liability) public totalLiability;
    mapping(address asset => uint256 amount) public protocolOwed;

    function sync(address asset) external {
        uint256 balance = MockERC20(asset).balanceOf(address(this));
        uint256 gross = balance - totalLiability[asset];
        uint256 fee = gross / 100;
        totalLiability[asset] += gross;
        protocolOwed[asset] += fee;
    }
}
