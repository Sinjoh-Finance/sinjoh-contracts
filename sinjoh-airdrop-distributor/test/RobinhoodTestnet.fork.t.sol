// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { SinjohAirdropDistributor } from "../src/SinjohAirdropDistributor.sol";

contract RobinhoodTestnetAirdropForkTest is TestBase {
    uint256 internal constant ROBINHOOD_TESTNET_CHAIN_ID = 46_630;
    address internal constant EXPECTED_ATTESTOR = 0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49;
    address internal constant PROTOCOL_FEE_RECIPIENT = 0x1e22b9B257c73b309F1fcDA3508A48755896619b;
    address internal constant LIVE_DISTRIBUTOR = 0x55b8b547D811FA9c356E7493b04A275CB2E21e54;
    address internal constant ARBSYS = address(0x64);
    bytes32 internal constant ARBSYS_MARKER_HASH =
        0xbcc90f2d6dada5b18e155c17a1c0a55920aae94f39857d39d0d8ed07ae8f228b;

    function testForkArbSysAndDeployment() public {
        if (block.chainid != ROBINHOOD_TESTNET_CHAIN_ID) return;

        // Foundry preserves Orbit's 0xfe precompile marker but does not emulate ArbSys calls.
        assertTrue(ARBSYS.codehash == ARBSYS_MARKER_HASH);

        SinjohAirdropDistributor distributor =
            new SinjohAirdropDistributor(EXPECTED_ATTESTOR, PROTOCOL_FEE_RECIPIENT);
        assertEq(distributor.attestor(), EXPECTED_ATTESTOR);
        assertEq(distributor.protocolFeeRecipient(), PROTOCOL_FEE_RECIPIENT);
        assertTrue(address(distributor).code.length != 0);
    }

    function testLiveDistributorFinalStateOnFork() public view {
        if (block.chainid != ROBINHOOD_TESTNET_CHAIN_ID) return;

        SinjohAirdropDistributor distributor = SinjohAirdropDistributor(payable(LIVE_DISTRIBUTOR));
        assertTrue(LIVE_DISTRIBUTOR.code.length != 0);
        assertEq(distributor.attestor(), EXPECTED_ATTESTOR);
        assertEq(distributor.protocolFeeRecipient(), PROTOCOL_FEE_RECIPIENT);
        assertEq(distributor.protocolOwed(0x37E402B8081eFcE1D82A09a066512278006e4691), 0);
    }
}
