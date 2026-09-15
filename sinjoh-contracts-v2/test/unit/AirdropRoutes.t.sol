// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;
import { Test } from "forge-std/Test.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AirdropChainedRoute } from "../../src/yield-banks/airdrop/AirdropChainedRoute.sol";
import {
    IYieldBankAllocationRoute
} from "../../src/yield-banks/interfaces/IYieldBankAllocationRoute.sol";

contract AirRouteToken is ERC20 {
    constructor() ERC20("fixture", "FIX") { }

    function mint(address to, uint256 n) external {
        _mint(to, n);
    }
}

contract AirRouteMock is IYieldBankAllocationRoute {
    address public inputAsset;
    address public outputAsset;
    uint256 public numerator = 1;
    uint256 public denominator = 1;
    bool public partialFill;

    constructor(address a, address b) {
        inputAsset = a;
        outputAsset = b;
    }

    function set(uint256 n, uint256 d, bool p) external {
        numerator = n;
        denominator = d;
        partialFill = p;
    }

    function convert(uint256 amount, uint256 minimum, address receiver, bytes calldata)
        external
        returns (uint256 out)
    {
        IERC20(inputAsset)
            .transferFrom(msg.sender, address(this), partialFill ? amount / 2 : amount);
        out = amount * numerator / denominator;
        require(out >= minimum, "slippage");
        AirRouteToken(outputAsset).mint(receiver, out);
    }
}

contract AirdropRoutesTest is Test {
    AirRouteToken a;
    AirRouteToken b;
    AirRouteToken c;
    AirRouteToken d;
    AirRouteMock first;
    AirRouteMock second;
    AirdropChainedRoute route;

    function setUp() public {
        a = new AirRouteToken();
        b = new AirRouteToken();
        c = new AirRouteToken();
        d = new AirRouteToken();
        first = new AirRouteMock(address(a), address(b));
        second = new AirRouteMock(address(b), address(c));
        address[] memory rs = new address[](2);
        rs[0] = address(first);
        rs[1] = address(second);
        route = new AirdropChainedRoute(rs);
        a.mint(address(this), 1e18);
        a.approve(address(route), 1e18);
    }

    function testFullPathChecksOutputAndClearsEveryApproval() public {
        assertEq(route.convert(1e18, 1e18, address(this), ""), 1e18);
        assertEq(a.allowance(address(route), address(first)), 0);
        assertEq(b.allowance(address(route), address(second)), 0);
        assertEq(b.balanceOf(address(route)), 0);
        assertEq(c.balanceOf(address(route)), 0);
    }

    function testMinimumAppliesAcrossAllHops() public {
        first.set(99, 100, false);
        second.set(99, 100, false);
        vm.expectRevert();
        route.convert(1e18, 99e16, address(this), "");
        assertEq(a.balanceOf(address(this)), 1e18);
    }

    function testPartialInputRevertsAtomically() public {
        first.set(1, 1, true);
        vm.expectRevert(AirdropChainedRoute.InexactTransfer.selector);
        route.convert(1e18, 1, address(this), "");
        assertEq(a.balanceOf(address(this)), 1e18);
    }

    function testPreexistingDustCannotBeSpentOrReturned() public {
        a.mint(address(route), 100);
        b.mint(address(route), 200);
        c.mint(address(route), 300);
        route.convert(1e18, 1e18, address(this), "");
        assertEq(a.balanceOf(address(route)), 100);
        assertEq(b.balanceOf(address(route)), 200);
        assertEq(c.balanceOf(address(route)), 300);
        assertEq(c.balanceOf(address(this)), 1e18);
    }

    function testDependencyChangeRevertsBeforeFundsMove() public {
        vm.etch(address(first), hex"00");
        vm.expectRevert();
        route.convert(1e18, 1, address(this), "");
        assertEq(a.balanceOf(address(this)), 1e18);
    }

    function testRejectsCyclesAndBrokenPaths() public {
        AirRouteMock back = new AirRouteMock(address(b), address(a));
        address[] memory rs = new address[](2);
        rs[0] = address(first);
        rs[1] = address(back);
        vm.expectRevert(AirdropChainedRoute.InvalidRoute.selector);
        new AirdropChainedRoute(rs);
        rs[1] = address(first);
        vm.expectRevert(AirdropChainedRoute.InvalidRoute.selector);
        new AirdropChainedRoute(rs);
    }

    function testThreeHopsAndDistinctReceiver() public {
        AirRouteMock third = new AirRouteMock(address(c), address(d));
        address[] memory rs = new address[](3);
        rs[0] = address(first);
        rs[1] = address(second);
        rs[2] = address(third);
        AirdropChainedRoute r = new AirdropChainedRoute(rs);
        a.approve(address(r), 1e18);
        r.convert(1e18, 1e18, address(0xB0B), "");
        assertEq(d.balanceOf(address(0xB0B)), 1e18);
        assertEq(c.allowance(address(r), address(third)), 0);
    }

    function testRejectsArbitraryCalldataAndZeroMinimum() public {
        vm.expectRevert(AirdropChainedRoute.InvalidRoute.selector);
        route.convert(1e18, 1, address(this), hex"1234");
        vm.expectRevert(AirdropChainedRoute.InvalidRoute.selector);
        route.convert(1e18, 0, address(this), "");
    }

    function testFuzzConservation(uint96 amount) public {
        vm.assume(amount > 0);
        a.mint(address(this), amount);
        a.approve(address(route), amount);
        uint256 before = a.balanceOf(address(this));
        uint256 out = route.convert(amount, amount, address(this), "");
        assertEq(out, amount);
        assertEq(a.balanceOf(address(this)), before - amount);
        assertEq(c.balanceOf(address(this)), amount);
    }
}
