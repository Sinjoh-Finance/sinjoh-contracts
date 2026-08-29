// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { YieldBankOnchainRenderer } from "../../src/yield-banks/YieldBankOnchainRenderer.sol";

contract YieldBankOnchainRendererTest is Test {
    function testMetadataIsOnchainAndBoundToProtocolAddresses() external {
        YieldBankOnchainRenderer renderer = new YieldBankOnchainRenderer();
        address collection = 0x1111111111111111111111111111111111111111;
        address account = 0x2222222222222222222222222222222222222222;
        string memory uri = renderer.tokenURI(collection, 42, account, 1);

        assertTrue(_startsWith(uri, "data:application/json;base64,"));
        assertEq(uri, renderer.tokenURI(collection, 42, account, 1));
        assertNotEq(uri, renderer.tokenURI(collection, 43, account, 1));
        assertNotEq(
            uri, renderer.tokenURI(collection, 42, 0x3333333333333333333333333333333333333333, 1)
        );
        assertNotEq(uri, renderer.tokenURI(collection, 42, account, 3));
    }

    function _startsWith(string memory value, string memory prefix) private pure returns (bool) {
        bytes memory source = bytes(value);
        bytes memory expected = bytes(prefix);
        if (source.length < expected.length) return false;
        for (uint256 i; i < expected.length; ++i) {
            if (source[i] != expected[i]) return false;
        }
        return true;
    }
}
