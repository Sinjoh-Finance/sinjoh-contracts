// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IPonsV1LaunchFactory } from "../../src/interfaces/IPonsV1.sol";
import { MockERC20 } from "./MockERC20.sol";

contract MockPonsV1Locker {
    error NotAuthorized();

    mapping(address subject => address deployer) public deployerOf;
    mapping(address subject => address feeWallet) public feeWalletOf;
    mapping(address subject => uint256 amount) public subjectFees;
    mapping(address subject => uint256 amount) public wethFees;

    MockERC20 public immutable weth;

    constructor(MockERC20 weth_) {
        weth = weth_;
    }

    function configure(address subject, address deployer, address feeWallet) external {
        deployerOf[subject] = deployer;
        feeWalletOf[subject] = feeWallet;
    }

    function setFees(address subject, uint256 subjectAmount, uint256 wethAmount) external {
        subjectFees[subject] = subjectAmount;
        wethFees[subject] = wethAmount;
    }

    function collectFees(address subject) external returns (uint256 amount0, uint256 amount1) {
        if (msg.sender != deployerOf[subject]) revert NotAuthorized();
        amount0 = subjectFees[subject];
        amount1 = wethFees[subject];
        subjectFees[subject] = 0;
        wethFees[subject] = 0;
        if (amount0 != 0) MockERC20(subject).mint(feeWalletOf[subject], amount0);
        if (amount1 != 0) weth.mint(feeWalletOf[subject], amount1);
    }
}

contract MockPonsV1LaunchFactory is IPonsV1LaunchFactory {
    address public immutable locker;
    address public lastDeployer;
    address public lastFeeWallet;
    address public lastToken;
    uint256 public launchBuyAmount;

    constructor(address locker_) {
        locker = locker_;
    }

    function setLaunchBuyAmount(uint256 amount) external {
        launchBuyAmount = amount;
    }

    function launchToken(LaunchParams calldata params, uint256, uint256, bytes32)
        external
        payable
        returns (address token)
    {
        MockERC20 launched = new MockERC20(params.name, params.symbol);
        token = address(launched);
        lastDeployer = msg.sender;
        lastFeeWallet = params.feeWallet;
        lastToken = token;
        MockPonsV1Locker(locker).configure(token, msg.sender, params.feeWallet);
        if (launchBuyAmount != 0) launched.mint(params.feeWallet, launchBuyAmount);
    }
}
