// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { SinjohPonsV1AdapterFactory } from "../src/SinjohPonsV1AdapterFactory.sol";

contract RobinhoodTestnetPonsForkTest is TestBase {
    uint256 internal constant ROBINHOOD_TESTNET_CHAIN_ID = 46_630;
    address internal constant PONS_V1_LOCKER = 0x9E18AFba6eADDC1A00Edd35FB7AB6C5CD1E1dEE0;
    address internal constant WETH = 0x37E402B8081eFcE1D82A09a066512278006e4691;
    address internal constant LIVE_SUBJECT = 0x09574C74D97EC78983F326Ed60C7E9fb2a2De62e;

    bytes32 internal constant PONS_V1_LOCKER_HASH =
        0xc98810d63174049c9debaab082a05f52ff16b6df65781dda07cc95d85a34730c;
    bytes32 internal constant WETH_HASH =
        0xa7f01c02394c333cc82f3236a0212384759ac2b0a4b982db822e3ff691e6567d;

    function testForkDependenciesAndDeployment() public {
        if (block.chainid != ROBINHOOD_TESTNET_CHAIN_ID) return;

        assertTrue(PONS_V1_LOCKER.codehash == PONS_V1_LOCKER_HASH);
        assertTrue(WETH.codehash == WETH_HASH);

        (bool redirectSuccess, bytes memory redirectData) = PONS_V1_LOCKER.staticcall(
            abi.encodeWithSignature("feeRedirects(address)", LIVE_SUBJECT)
        );
        assertTrue(redirectSuccess && redirectData.length >= 32);

        SinjohPonsV1AdapterFactory factory =
            new SinjohPonsV1AdapterFactory(PONS_V1_LOCKER, WETH, block.chainid);
        assertTrue(address(factory).code.length != 0);
        assertTrue(factory.implementation().code.length != 0);
        assertEq(factory.ponsLocker(), PONS_V1_LOCKER);
        assertEq(factory.weth(), WETH);
    }
}
