// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface Vm {
    function deal(address account, uint256 newBalance) external;
    function expectRevert() external;
    function expectRevert(bytes4 selector) external;
    function expectPartialRevert(bytes4 selector) external;
    function prank(address sender) external;
    function warp(uint256 newTimestamp) external;
}

abstract contract TestBase {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    error AssertionEqFailed(uint256 left, uint256 right);
    error AssertionAddressEqFailed(address left, address right);
    error AssertionTrueFailed();

    function assertEq(uint256 left, uint256 right) internal pure {
        if (left != right) revert AssertionEqFailed(left, right);
    }

    function assertEq(address left, address right) internal pure {
        if (left != right) revert AssertionAddressEqFailed(left, right);
    }

    function assertTrue(bool condition) internal pure {
        if (!condition) revert AssertionTrueFailed();
    }
}
