// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

interface Vm {
    function expectRevert() external;
    function expectRevert(bytes4 selector) external;
    function expectRevert(bytes calldata revertData) external;
    function expectPartialRevert(bytes4 selector) external;
    function prank(address sender) external;
    function startPrank(address sender) external;
    function stopPrank() external;
    function warp(uint256 timestamp) external;
    function roll(uint256 blockNumber) external;
    function chainId(uint256 newChainId) external;
    function computeCreateAddress(address deployer, uint256 nonce) external pure returns (address);
    function createSelectFork(string calldata urlOrAlias) external returns (uint256 forkId);
    function envOr(string calldata name, string calldata defaultValue)
        external
        returns (string memory value);
    function envOr(string calldata name, address defaultValue) external returns (address value);
    function envOr(string calldata name, uint256 defaultValue) external returns (uint256 value);
}

abstract contract TestBase {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    error AssertEq(uint256 left, uint256 right);
    error AssertAddressEq(address left, address right);
    error AssertTrue();

    function assertEq(uint256 left, uint256 right) internal pure {
        if (left != right) revert AssertEq(left, right);
    }

    function assertEq(address left, address right) internal pure {
        if (left != right) revert AssertAddressEq(left, right);
    }

    function assertTrue(bool value) internal pure {
        if (!value) revert AssertTrue();
    }
}

abstract contract InvariantTestBase is TestBase {
    address[] internal _targetedContracts;

    function targetContracts() public view returns (address[] memory) {
        return _targetedContracts;
    }
}
