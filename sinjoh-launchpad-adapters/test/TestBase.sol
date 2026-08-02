// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @dev The repo vendors no test dependencies. This mirrors
/// `sinjoh-pons-v1-adapter/test/TestBase.sol`, adding only the cheatcodes the
/// v2 adapter suite needs: chain-id control, funding, and revert matching on
/// encoded error arguments.
interface Vm {
    function expectRevert() external;
    function expectRevert(bytes4 selector) external;
    function expectRevert(bytes calldata revertData) external;
    function expectPartialRevert(bytes4 selector) external;
    function prank(address sender) external;
    function startPrank(address sender) external;
    function stopPrank() external;
    function chainId(uint256 newChainId) external;
    function roll(uint256 newHeight) external;
    function deal(address account, uint256 balance) external;
    function load(address target, bytes32 slot) external view returns (bytes32);
    function store(address target, bytes32 slot, bytes32 value) external;
    function createSelectFork(string calldata urlOrAlias) external returns (uint256);
    function createSelectFork(string calldata urlOrAlias, uint256 blockNumber)
        external
        returns (uint256);
    function envOr(string calldata name, string calldata defaultValue)
        external
        view
        returns (string memory);
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
