// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { StockBankReceipt } from "../../src/yield-banks/stock/StockBankReceipt.sol";
import { RebalanceValueGuard } from "../../src/yield-banks/RebalanceValueGuard.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract StockReceiptHarness is StockBankReceipt {
    mapping(address => uint256[3]) public units;
    uint256[3] public totalUnits;
    uint256[3] public prices;
    constructor() StockBankReceipt("Isolated bank positions", "BANK-POSITION") {}
    function setPrices(uint256[3] memory values) external { prices = values; }
    function deposit(address bank, uint8 asset, uint256 amount) external {
        units[bank][asset] += amount;
        totalUnits[asset] += amount;
    }
    function totalAssetsUsd18() external view returns (uint256, uint48) {
        return (_totalValue36() / 1 ether, uint48(block.timestamp));
    }
    function _accountValue36(address bank) internal view override returns (uint256 value) {
        for (uint8 i; i < 3; ++i) value += units[bank][i] * prices[i];
    }
    function _totalValue36() internal view override returns (uint256 value) {
        for (uint8 i; i < 3; ++i) value += totalUnits[i] * prices[i];
    }
}

contract ReceiptWethMock is ERC20 {
    constructor() ERC20("WETH", "WETH") {}
}

contract StockBankReceiptTest is Test {
    StockReceiptHarness receipt = new StockReceiptHarness();
    RebalanceValueGuard guard = new RebalanceValueGuard();
    ReceiptWethMock weth = new ReceiptWethMock();
    address constant ALICE_BANK = address(101);
    address constant BOB_BANK = address(102);

    function _value(address bank) private view returns (uint256) {
        // Empty base destinations and the candidate dynamic destination use the unchanged
        // production valuation contract. WETH has no balance, so no loose-WETH quote is needed.
        address[3] memory empty = [address(weth), address(weth), address(weth)];
        return guard.accountValueUsd18(bank, address(weth), empty, address(receipt));
    }

    function testExistingGuardValuesEachBanksOwnBasketAsPricesDiverge() public {
        receipt.setPrices([uint256(100 ether), 200 ether, 300 ether]);
        receipt.deposit(ALICE_BANK, 0, 2 ether);
        receipt.deposit(BOB_BANK, 1, 1 ether);
        assertEq(_value(ALICE_BANK), 200 ether);
        assertEq(_value(BOB_BANK), 200 ether);
        receipt.setPrices([uint256(150 ether), 50 ether, 300 ether]);
        assertEq(_value(ALICE_BANK), 300 ether);
        assertEq(_value(BOB_BANK), 50 ether);
        assertEq(receipt.totalSupply(), receipt.balanceOf(ALICE_BANK) + receipt.balanceOf(BOB_BANK));
        assertEq(receipt.decimals(), 36);
    }

    function testMixedPortfolioAndNewDepositsDoNotDiluteAnotherBank() public {
        receipt.setPrices([uint256(100 ether), 200 ether, 300 ether]);
        receipt.deposit(ALICE_BANK, 0, 2 ether);
        receipt.deposit(ALICE_BANK, 1, 3 ether);
        receipt.deposit(BOB_BANK, 2, 1 ether);
        assertEq(_value(ALICE_BANK), 800 ether);
        assertEq(_value(BOB_BANK), 300 ether);
        receipt.deposit(BOB_BANK, 0, 500 ether);
        assertEq(_value(ALICE_BANK), 800 ether);
        assertEq(_value(BOB_BANK), 50300 ether);
    }

    function testReceiptCannotBeTransferredOutOfTreasury() public {
        receipt.setPrices([uint256(100 ether), 200 ether, 300 ether]);
        receipt.deposit(ALICE_BANK, 0, 1 ether);
        vm.prank(ALICE_BANK);
        vm.expectRevert(StockBankReceipt.ReceiptTransferDisabled.selector);
        receipt.transfer(BOB_BANK, 1);
    }

    function testFuzzSupplyConservationAndGuardRounding(uint96 a, uint96 b, uint96 priceA, uint96 priceB) public {
        uint256 qA = uint256(a) + 1 ether;
        uint256 qB = uint256(b) + 1 ether;
        uint256 pA = uint256(priceA) + 1 ether;
        uint256 pB = uint256(priceB) + 1 ether;
        receipt.setPrices([pA, pB, uint256(1 ether)]);
        receipt.deposit(ALICE_BANK, 0, qA);
        receipt.deposit(BOB_BANK, 1, qB);
        assertEq(receipt.totalSupply(), receipt.balanceOf(ALICE_BANK) + receipt.balanceOf(BOB_BANK));
        uint256 exactA = qA * pA / 1 ether;
        uint256 exactB = qB * pB / 1 ether;
        assertLe(_value(ALICE_BANK), exactA);
        assertLe(_value(BOB_BANK), exactB);
        assertLe(exactA - _value(ALICE_BANK), 1);
        assertLe(exactB - _value(BOB_BANK), 1);
    }
}
