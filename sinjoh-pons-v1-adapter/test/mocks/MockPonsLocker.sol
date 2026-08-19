// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { MockERC20 } from "./MockERC20.sol";

contract MockPonsLocker {
    MockERC20 public immutable weth;
    address public lastSubject;
    mapping(address subject => address recipient) public feeRedirects;
    mapping(address subject => uint256 amount) public subjectFees;
    mapping(address subject => uint256 amount) public wethFees;

    constructor(MockERC20 weth_) {
        weth = weth_;
    }

    function setFeeRedirect(address subject, address recipient) external {
        feeRedirects[subject] = recipient;
    }

    function seedFees(address subject, uint256 subjectAmount, uint256 wethAmount) external {
        subjectFees[subject] += subjectAmount;
        wethFees[subject] += wethAmount;
        MockERC20(subject).mint(address(this), subjectAmount);
        weth.mint(address(this), wethAmount);
    }

    function collectFees(address subject) external {
        if (feeRedirects[subject] != msg.sender) revert("UNAUTHORIZED_RECIPIENT");
        lastSubject = subject;
        _send(subject, msg.sender);
    }

    function automate(address subject) external {
        address recipient = feeRedirects[subject];
        if (recipient == address(0)) revert("NO_RECIPIENT");
        _send(subject, recipient);
    }

    function _send(address subject, address recipient) private {
        uint256 subjectAmount = subjectFees[subject];
        uint256 wethAmount = wethFees[subject];
        subjectFees[subject] = 0;
        wethFees[subject] = 0;
        require(MockERC20(subject).transfer(recipient, subjectAmount));
        require(weth.transfer(recipient, wethAmount));
    }
}
