// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { ProjectTreasuryVaultV2 } from "../../src/treasury/ProjectTreasuryVaultV2.sol";

contract SDKFixtureV2Test is Test {
    function testTreasurySendFixtureMatchesCanonicalSolidityEncoding() public view {
        string memory json = vm.readFile("sdk/fixtures/treasury-send.json");
        address asset = vm.parseJsonAddress(json, ".asset");
        uint256 amount = vm.parseUint(vm.parseJsonString(json, ".amount"));
        address recipient = vm.parseJsonAddress(json, ".recipient");
        bytes memory expected = vm.parseJsonBytes(json, ".calldata");

        assertEq(abi.encodeCall(ProjectTreasuryVaultV2.send, (asset, amount, recipient)), expected);
    }
}
