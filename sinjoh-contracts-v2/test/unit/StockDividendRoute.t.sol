// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;
import { Test } from "forge-std/Test.sol";
import { StockDividendRoute } from "../../src/yield-banks/stock/StockDividendRoute.sol";
import { DividendRouteMock } from "./StockDividendVault.t.sol";
import { DividendTokenMock } from "./StockDividendEscrow.t.sol";

contract StockDividendRouteTest is Test {
    DividendTokenMock stock;
    DividendTokenMock weth;
    DividendTokenMock usdg;
    DividendRouteMock first;
    DividendRouteMock second;
    StockDividendRoute route;
    address owner = address(0xA11CE);

    function setUp() public {
        stock = new DividendTokenMock();
        weth = new DividendTokenMock();
        usdg = new DividendTokenMock();
        first = new DividendRouteMock(address(stock), address(weth));
        second = new DividendRouteMock(address(weth), address(usdg));
        route = new StockDividendRoute(address(first), address(second));
        stock.mint(address(this), 100 ether);
        weth.mint(address(first), 100 ether);
        usdg.mint(address(second), 100 ether);
        stock.approve(address(route), 100 ether);
    }

    function testOnlySuppliedDividendUnitsAreConvertedAndDonationsPreserved() public {
        stock.mint(address(route), 3 ether);
        weth.mint(address(route), 4 ether);
        usdg.mint(address(route), 5 ether);
        uint256 cash = route.convert(
            1 ether, 1 ether, owner, abi.encode(StockDividendRoute.Conversion(1 ether, "", ""))
        );
        assertEq(cash, 1 ether);
        assertEq(usdg.balanceOf(owner), cash);
        assertEq(stock.balanceOf(address(this)), 99 ether);
        assertEq(stock.balanceOf(address(route)), 3 ether);
        assertEq(weth.balanceOf(address(route)), 4 ether);
        assertEq(usdg.balanceOf(address(route)), 5 ether);
        assertEq(stock.allowance(address(route), address(first)), 0);
        assertEq(weth.allowance(address(route), address(second)), 0);
    }

    function testUnderpaymentAtEitherLegRollsBackAllFunds() public {
        bytes memory data = abi.encode(StockDividendRoute.Conversion(1 ether, "", ""));
        first.setOutputBps(9900);
        vm.expectRevert(StockDividendRoute.InexactTransfer.selector);
        route.convert(1 ether, 1 ether, owner, data);
        assertEq(stock.balanceOf(address(this)), 100 ether);
        first.setOutputBps(10000);
        second.setOutputBps(9900);
        vm.expectRevert(StockDividendRoute.InexactTransfer.selector);
        route.convert(1 ether, 1 ether, owner, data);
        assertEq(stock.balanceOf(address(this)), 100 ether);
        assertEq(usdg.balanceOf(owner), 0);
    }

    function testWrongIntermediateAssetCannotBeBound() public {
        DividendRouteMock wrong = new DividendRouteMock(address(stock), address(usdg));
        vm.expectRevert(StockDividendRoute.InvalidConfiguration.selector);
        new StockDividendRoute(address(first), address(wrong));
    }

    function testChangedRuntimeCannotConsumeCustody() public {
        bytes memory data = abi.encode(StockDividendRoute.Conversion(1 ether, "", ""));
        vm.etch(address(second), hex"60006000fd");
        vm.expectRevert();
        route.convert(1 ether, 1 ether, owner, data);
        assertEq(stock.balanceOf(address(this)), 100 ether);
    }
}
