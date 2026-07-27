// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { SinjohRevenueCollector } from "../src/SinjohRevenueCollector.sol";
import { TestBase } from "./TestBase.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";

contract RobinhoodTestnetForkTest is TestBase {
    uint256 internal constant ROBINHOOD_TESTNET_CHAIN_ID = 46_630;
    address internal constant GOVERNANCE = 0x39E2f5eFdFd808F26B98979a06BA11ea82E1C85f;
    address internal constant LIVE_COLLECTOR = 0x1e22b9B257c73b309F1fcDA3508A48755896619b;

    function testFreshCollectorDeploymentAndForwardingOnFork() public {
        SinjohRevenueCollector collector = new SinjohRevenueCollector(GOVERNANCE, GOVERNANCE);
        MockERC20 token = new MockERC20();
        token.mint(address(collector), 123 ether);

        collector.forwardAll(address(token));

        assertEq(collector.owner(), GOVERNANCE);
        assertEq(collector.processor(), GOVERNANCE);
        assertEq(token.balanceOf(GOVERNANCE), 123 ether);
        assertEq(token.balanceOf(address(collector)), 0);
    }

    function testLiveCollectorFinalStateOnFork() public view {
        if (block.chainid != ROBINHOOD_TESTNET_CHAIN_ID) return;

        SinjohRevenueCollector collector = SinjohRevenueCollector(payable(LIVE_COLLECTOR));
        assertTrue(LIVE_COLLECTOR.code.length != 0);
        assertEq(collector.owner(), GOVERNANCE);
        assertEq(collector.processor(), GOVERNANCE);
        assertEq(LIVE_COLLECTOR.balance, 0);
    }
}
