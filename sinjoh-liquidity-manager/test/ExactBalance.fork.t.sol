// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;
import { Test } from "forge-std/Test.sol";
import { DeployRafflePriceGuardsMainnet } from "../script/DeployRafflePriceGuardsMainnet.s.sol";

contract ExactBalanceForkTest is Test {
    function testExactBalanceSuffices() public {
        string memory url = vm.envOr("RH_RPC_URL", string(""));
        if (bytes(url).length == 0) return;
        vm.createSelectFork(url);
        vm.warp(block.timestamp + 1);
        DeployRafflePriceGuardsMainnet s = new DeployRafflePriceGuardsMainnet();
        vm.deal(address(s), 0.00786723 ether);
        s.execute(1_500, 0.0005 ether);
        emit log_named_decimal_uint("consumed", 0.00786723 ether - address(s).balance, 18);
    }
}
