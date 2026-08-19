// SPDX-License-Identifier: Apache-2.0
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

abstract contract InvariantTestBase is TestBase {
    struct FuzzSelector {
        address addr;
        bytes4[] selectors;
    }

    struct FuzzArtifactSelector {
        string artifact;
        bytes4[] selectors;
    }

    struct FuzzInterface {
        address addr;
        string[] artifacts;
    }

    address[] internal _targetedContracts;

    function excludeArtifacts() public pure returns (string[] memory values) {
        values = new string[](0);
    }

    function excludeContracts() public pure returns (address[] memory values) {
        values = new address[](0);
    }

    function excludeSelectors() public pure returns (FuzzSelector[] memory values) {
        values = new FuzzSelector[](0);
    }

    function excludeSenders() public pure returns (address[] memory values) {
        values = new address[](0);
    }

    function targetArtifacts() public pure returns (string[] memory values) {
        values = new string[](0);
    }

    function targetArtifactSelectors() public pure returns (FuzzArtifactSelector[] memory values) {
        values = new FuzzArtifactSelector[](0);
    }

    function targetContracts() public view returns (address[] memory) {
        return _targetedContracts;
    }

    function targetSelectors() public pure returns (FuzzSelector[] memory values) {
        values = new FuzzSelector[](0);
    }

    function targetSenders() public pure returns (address[] memory values) {
        values = new address[](0);
    }

    function targetInterfaces() public pure returns (FuzzInterface[] memory values) {
        values = new FuzzInterface[](0);
    }
}
