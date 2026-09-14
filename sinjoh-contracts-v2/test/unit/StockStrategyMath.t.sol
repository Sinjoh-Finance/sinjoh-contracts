// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;
import { Test } from "forge-std/Test.sol";
import { StockStrategyMath } from "../../src/yield-banks/stock/StockStrategyMath.sol";

contract StockMathHarness {
    function reserve(uint256 q, uint256 m0, uint256 m1) external pure returns (uint256) {
        return StockStrategyMath.reserveUnits(q, m0, m1);
    }

    function allocate(uint256 amount, bool basket, address[] memory assets, uint16[] memory weights)
        external
        pure
        returns (uint256[] memory)
    {
        return StockStrategyMath.allocate(amount, basket, assets, weights);
    }
}

contract StockStrategyMathTest is Test {
    StockMathHarness h = new StockMathHarness();

    function testDividendVector() public view {
        assertEq(h.reserve(10 ether, 100, 102), 196078431372549019);
        assertEq(h.reserve(10 ether, 100, 100), 0);
    }

    function testFuzzPrincipalPreserved(uint128 q, uint64 beforeM, uint64 change) public view {
        uint256 m0 = uint256(beforeM) + 1;
        uint256 m1 = m0 + change;
        uint256 income = h.reserve(q, m0, m1);
        assertLe(income, q);
        assertGe((uint256(q) - income) * m1, uint256(q) * m0);
        if (income < q) assertLt((uint256(q) - income - 1) * m1, uint256(q) * m0);
    }

    function testInvalidMultiplier() public {
        vm.expectRevert(StockStrategyMath.InvalidMultiplier.selector);
        h.reserve(100, 0, 2);
        vm.expectRevert(StockStrategyMath.InvalidMultiplier.selector);
        h.reserve(100, 2, 1);
    }

    function testBasketDustAndDuplicate() public {
        address[] memory assets = new address[](3);
        assets[0] = address(1);
        assets[1] = address(2);
        assets[2] = address(3);
        uint16[] memory weights = new uint16[](3);
        weights[0] = 3334;
        weights[1] = 3333;
        weights[2] = 3333;
        uint256[] memory amounts = h.allocate(2500010000, true, assets, weights);
        assertEq(amounts[0] + amounts[1] + amounts[2], 2500010000);
        vm.expectRevert(StockStrategyMath.AllocationTooSmall.selector);
        h.allocate(1, true, assets, weights);
        assets[1] = assets[0];
        vm.expectRevert(StockStrategyMath.InvalidSelection.selector);
        h.allocate(10000, true, assets, weights);
    }
}
