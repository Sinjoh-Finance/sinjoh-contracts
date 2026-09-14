// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import {
    StockDividendAccounting as Accounting
} from "../../src/yield-banks/stock/StockDividendAccounting.sol";

contract StockAccountingHarness {
    using Accounting for Accounting.Position;
    mapping(uint256 bank => mapping(address asset => Accounting.Position)) public positions;

    function deposit(uint256 bank, address asset, uint256 amount, uint64 seq, uint256 multiplier)
        external
    {
        positions[bank][asset].deposit(amount, seq, multiplier);
    }

    function action(
        uint256 bank,
        address asset,
        uint64 seq,
        uint256 m0,
        uint256 m1,
        Accounting.ActionKind kind
    ) external returns (uint256) {
        return positions[bank][asset].applyAction(seq, m0, m1, kind);
    }

    function withdraw(uint256 bank, address asset, uint256 amount, uint64 seq, uint256 multiplier)
        external
    {
        positions[bank][asset].withdrawPrincipal(amount, seq, multiplier);
    }

    function consume(uint256 bank, address asset, uint256 amount) external {
        positions[bank][asset].consumeDividend(amount);
    }
}

contract StockDividendAccountingTest is Test {
    StockAccountingHarness h = new StockAccountingHarness();
    address constant A = address(0xA);
    address constant B = address(0xB);

    function testIsolatesBanksAssetsAndDepositsAfterDividend() public {
        h.deposit(1, A, 1020, 0, 100);
        h.deposit(1, B, 500, 0, 100);
        assertEq(h.action(1, A, 1, 100, 102, Accounting.ActionKind.CashDividend), 20);
        h.deposit(2, A, 1020, 1, 102);
        h.deposit(1, A, 102, 1, 102);
        (uint256 principal, uint256 reserved,,) = h.positions(1, A);
        assertEq(principal, 1102);
        assertEq(reserved, 20);
        (principal, reserved,,) = h.positions(2, A);
        assertEq(principal, 1020);
        assertEq(reserved, 0);
        (principal, reserved,,) = h.positions(1, B);
        assertEq(principal, 500);
        assertEq(reserved, 0);
    }

    function testSplitAndReverseSplitNeverReserveIncome() public {
        h.deposit(1, A, 1000, 0, 100);
        assertEq(h.action(1, A, 1, 100, 1000, Accounting.ActionKind.NonDividend), 0);
        assertEq(h.action(1, A, 2, 1000, 100, Accounting.ActionKind.NonDividend), 0);
        (uint256 principal, uint256 reserved,,) = h.positions(1, A);
        assertEq(principal, 1000);
        assertEq(reserved, 0);
    }

    function testRejectsReplaySkippedActionAndUnsettledDeposit() public {
        h.deposit(1, A, 1000, 3, 100);
        vm.expectRevert(Accounting.InvalidCorporateAction.selector);
        h.action(1, A, 5, 100, 102, Accounting.ActionKind.CashDividend);
        h.action(1, A, 4, 100, 102, Accounting.ActionKind.CashDividend);
        vm.expectRevert(Accounting.InvalidCorporateAction.selector);
        h.action(1, A, 4, 100, 102, Accounting.ActionKind.CashDividend);
        vm.expectRevert(Accounting.UnsettledCorporateAction.selector);
        h.deposit(1, A, 1, 5, 104);
        vm.expectRevert(Accounting.UnsettledCorporateAction.selector);
        h.withdraw(1, A, 1, 5, 104);
    }

    function testPrincipalExitRetainsReserveAndPartialConversionIsBounded() public {
        h.deposit(1, A, 1020, 0, 100);
        h.action(1, A, 1, 100, 102, Accounting.ActionKind.CashDividend);
        vm.expectRevert(Accounting.InsufficientPrincipal.selector);
        h.withdraw(1, A, 1001, 1, 102);
        h.withdraw(1, A, 1000, 1, 102);
        h.consume(1, A, 7);
        (uint256 principal, uint256 reserved,,) = h.positions(1, A);
        assertEq(principal, 0);
        assertEq(reserved, 13);
        vm.expectRevert(Accounting.InsufficientDividend.selector);
        h.consume(1, A, 14);
        h.consume(1, A, 13);
        h.action(1, A, 2, 102, 104, Accounting.ActionKind.CashDividend);
        (, reserved,,) = h.positions(1, A);
        assertEq(reserved, 0);
    }

    function testFuzzConservationAcrossTwoDividends(
        uint128 units,
        uint64 base,
        uint32 first,
        uint32 second
    ) public {
        uint256 q = uint256(units) + 1;
        uint256 m0 = uint256(base) + 1;
        uint256 m1 = m0 + uint256(first) + 1;
        uint256 m2 = m1 + uint256(second) + 1;
        h.deposit(1, A, q, 0, m0);
        h.action(1, A, 1, m0, m1, Accounting.ActionKind.CashDividend);
        h.action(1, A, 2, m1, m2, Accounting.ActionKind.CashDividend);
        (uint256 principal, uint256 reserved,,) = h.positions(1, A);
        assertEq(principal + reserved, q);
        assertGe(principal * m2, q * m0);
    }
}
