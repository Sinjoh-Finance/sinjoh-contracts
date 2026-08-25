// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import {
    ProjectWethUnwrapPriceGuard
} from "../../src/integrations/ProjectWethUnwrapPriceGuard.sol";
import { MockERC20 } from "../mocks/liquidity/MockERC20.sol";

contract ProjectWethUnwrapPriceGuardTest is Test {
    MockERC20 private weth;
    ProjectWethUnwrapPriceGuard private guard;

    function setUp() public {
        weth = new MockERC20("Wrapped Ether", "WETH");
        guard = new ProjectWethUnwrapPriceGuard(address(weth));
        vm.warp(1_000_000);
    }

    function testReturnsAnExactOneToOneUnwrapFloor() public view {
        (uint256 minimum, uint48 validUntil) = guard.minimumOutput(
            address(0xBEEF), address(weth), address(0), 3 ether, keccak256(""), ""
        );
        assertEq(minimum, 3 ether);
        assertEq(validUntil, block.timestamp + 5 minutes);
    }

    function testRejectsAnyNonUnwrapRoute() public {
        vm.expectRevert(ProjectWethUnwrapPriceGuard.InvalidRoute.selector);
        guard.minimumOutput(
            address(0xBEEF), address(weth), address(0xCAFE), 3 ether, keccak256(""), ""
        );
    }
}
