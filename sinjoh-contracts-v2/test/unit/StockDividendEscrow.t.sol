// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { StockDividendEscrow } from "../../src/yield-banks/stock/StockDividendEscrow.sol";

contract DividendNftMock is ERC721 {
    constructor() ERC721("Bank", "BANK") { }

    function mint(address to, uint256 id) external {
        _mint(to, id);
    }

    function burn(uint256 id) external {
        _burn(id);
    }
}

contract DividendTokenMock is ERC20 {
    mapping(address => bool) public blocked;
    bool public tax;
    constructor() ERC20("USDG", "USDG") { }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function blockWallet(address wallet, bool value) external {
        blocked[wallet] = value;
    }

    function setTax(bool value) external {
        tax = value;
    }

    function _update(address from, address to, uint256 amount) internal override {
        require(!blocked[to], "blocked");
        if (tax && from != address(0) && to != address(0) && amount > 0) {
            super._update(from, address(0), 1);
            amount -= 1;
        }
        super._update(from, to, amount);
    }
}

contract StockDividendEscrowTest is Test {
    StockDividendEscrow escrow;
    DividendNftMock nft;
    DividendTokenMock cash;
    address constant ALICE = address(0xA11CE);
    address constant BOB = address(0xB0B);

    function setUp() public {
        nft = new DividendNftMock();
        cash = new DividendTokenMock();
        escrow = new StockDividendEscrow(address(nft), address(cash), address(this));
        nft.mint(ALICE, 1);
        cash.mint(address(this), 10000);
        cash.approve(address(escrow), type(uint256).max);
    }

    function testPaysCurrentOwnerAndRejectsReplayAndUnauthorizedFunding() public {
        vm.prank(ALICE);
        nft.transferFrom(ALICE, BOB, 1);
        escrow.settleAndPay(1, bytes32(uint256(1)), 500);
        assertEq(cash.balanceOf(BOB), 500);
        assertEq(cash.balanceOf(ALICE), 0);
        assertEq(escrow.totalCredits(), 0);
        vm.expectRevert(StockDividendEscrow.InvalidSettlement.selector);
        escrow.settle(1, bytes32(uint256(1)), 500);
        vm.prank(BOB);
        vm.expectRevert(StockDividendEscrow.UnauthorizedSettler.selector);
        escrow.settle(1, bytes32(uint256(2)), 500);
    }

    function testBlockedPayoutSurvivesNftTransferAndBurn() public {
        cash.blockWallet(ALICE, true);
        escrow.settleAndPay(1, bytes32(uint256(1)), 500);
        assertEq(escrow.creditOf(ALICE), 500);
        assertEq(escrow.totalCredits(), 500);
        assertEq(cash.balanceOf(address(escrow)), 500);
        vm.prank(ALICE);
        nft.transferFrom(ALICE, BOB, 1);
        nft.burn(1);
        cash.blockWallet(ALICE, false);
        vm.prank(BOB);
        escrow.pay(ALICE);
        assertEq(cash.balanceOf(ALICE), 500);
        assertEq(cash.balanceOf(BOB), 0);
        assertEq(escrow.totalCredits(), 0);
    }

    function testRejectsUnfundedAndFeeOnTransferCreditsAtomically() public {
        cash.approve(address(escrow), 0);
        vm.expectRevert();
        escrow.settle(1, bytes32(uint256(1)), 500);
        assertFalse(escrow.settled(bytes32(uint256(1))));
        assertEq(escrow.totalCredits(), 0);
        cash.approve(address(escrow), 1000);
        cash.setTax(true);
        vm.expectRevert(StockDividendEscrow.UnsupportedTransfer.selector);
        escrow.settle(1, bytes32(uint256(1)), 500);
        assertEq(cash.balanceOf(address(escrow)), 0);
        assertFalse(escrow.settled(bytes32(uint256(1))));
    }

    function testRevertedOutgoingTransferDoesNotConsumeCredit() public {
        escrow.settle(1, bytes32(uint256(1)), 500);
        cash.setTax(true);
        vm.expectRevert(StockDividendEscrow.UnsupportedTransfer.selector);
        escrow.pay(ALICE);
        assertEq(escrow.creditOf(ALICE), 500);
        assertEq(cash.balanceOf(address(escrow)), 500);
        assertEq(cash.balanceOf(ALICE), 0);
    }

    function testDirectDonationCreatesNoEntitlement() public {
        cash.transfer(address(escrow), 100);
        assertEq(escrow.totalCredits(), 0);
        vm.expectRevert(StockDividendEscrow.NothingToPay.selector);
        escrow.pay(ALICE);
        escrow.settleAndPay(1, bytes32(uint256(1)), 500);
        assertEq(cash.balanceOf(ALICE), 500);
        assertEq(cash.balanceOf(address(escrow)), 100);
    }

    function testFuzzPartialSettlementsConserveFundedCash(uint16 first, uint16 second) public {
        uint256 a = uint256(first) % 4000 + 1;
        uint256 b = uint256(second) % 4000 + 1;
        escrow.settle(1, bytes32(uint256(1)), a);
        vm.prank(ALICE);
        nft.transferFrom(ALICE, BOB, 1);
        escrow.settle(1, bytes32(uint256(2)), b);
        assertEq(escrow.totalCredits(), a + b);
        assertEq(cash.balanceOf(address(escrow)), a + b);
        escrow.pay(BOB);
        assertEq(escrow.totalCredits(), a);
        escrow.pay(ALICE);
        assertEq(cash.balanceOf(ALICE), a);
        assertEq(cash.balanceOf(BOB), b);
        assertEq(escrow.totalCredits(), 0);
        assertEq(cash.balanceOf(address(escrow)), 0);
    }
}
