// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { StockLPLossBounds } from "../../src/yield-banks/stock/StockLPLossBounds.sol";

contract StockLPLossBoundsTest is Test {
    function testActualBasketRebalanceAcceptsEnoughTotalProceeds() public pure {
        // Values from the failed sequential bank-334 fork transaction. The old
        // 2%-per-conversion assumption rejected output that satisfied total LP loss.
        uint256 recovered = 0x304b9cd8d644c;
        uint256 totalMinimum = 0x5b230665424e5;
        uint256 actualSwap = 0x2ad7c93d18477;
        uint256 oldMinimum = 0x2ae1ed4ffb622;
        uint256 quote = oldMinimum * 10000 / 9800;
        assertLt(actualSwap, oldMinimum);
        assertGe(recovered + actualSwap, totalMinimum);
        assertLe(StockLPLossBounds.conversionMinimum(quote, recovered, totalMinimum, 0), actualSwap);
    }

    function testAsymmetricPairedHeavyExitStillReservesFullPortfolioMinimum() public pure {
        // 90 paired / 10 WETH: a 2% swap haircut would breach a 1% total cap.
        assertEq(StockLPLossBounds.conversionMinimum(90 ether, 10 ether, 99 ether, 0), 89 ether);
    }

    function testOwnerCanStrengthenConversionFloor() public pure {
        assertEq(StockLPLossBounds.conversionMinimum(50 ether, 50 ether, 99 ether, 50 ether), 50 ether);
    }

    function testSurplusWethCannotRemovePerSwapOracleProtection() public pure {
        assertEq(StockLPLossBounds.conversionMinimum(100 ether, 200 ether, 99 ether, 0), 95 ether);
        assertEq(StockLPLossBounds.conversionMinimum(0, 200 ether, 99 ether, 0), 1);
    }

    function testFuzzAllLossAndOwnerBoundsRemainEnforced(uint128 quote, uint128 recovered, uint128 total, uint128 owner) public pure {
        uint256 minimum = StockLPLossBounds.conversionMinimum(quote, recovered, total, owner);
        assertGe(minimum + recovered, total);
        assertGe(minimum, Math.mulDiv(quote, 9500, 10000, Math.Rounding.Ceil));
        assertGe(minimum, owner);
        assertGt(minimum, 0);
    }
}
