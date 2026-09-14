// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    StockCorporateActionRegistry as Registry
} from "../../src/yield-banks/stock/StockCorporateActionRegistry.sol";
import {
    StockDividendAccounting as Accounting
} from "../../src/yield-banks/stock/StockDividendAccounting.sol";
import { StockDividendVault } from "../../src/yield-banks/stock/StockDividendVault.sol";
import { IPriceHub } from "../../src/yield-banks/interfaces/IPriceHub.sol";
import { DividendNftMock, DividendTokenMock } from "./StockDividendEscrow.t.sol";

contract DividendStockMock is DividendTokenMock {
    uint256 public uiMultiplier = 100;
    bool public oraclePaused;

    function setMultiplier(uint256 value) external {
        uiMultiplier = value;
    }
}

contract DividendCollectionMock {
    address public nft;

    constructor(address nft_) {
        nft = nft_;
    }

    function accountOf(uint256 id) external pure returns (address) {
        return id == 1 || id == 2 ? address(uint160(100 + id)) : address(0);
    }
}

contract DividendPriceMock is IPriceHub {
    FailureReason public failure;
    uint256 public price = 1 ether;

    function setPrice(uint256 value) external {
        price = value;
    }

    function setFailure(FailureReason value) external {
        failure = value;
    }

    function quoteUsd18(address) external view returns (uint256, uint48, FailureReason) {
        return (price, uint48(block.timestamp), failure);
    }
}

contract DividendRouteMock {
    address public inputAsset;
    address public outputAsset;
    uint16 public outputBps = 10000;

    constructor(address input, address output) {
        inputAsset = input;
        outputAsset = output;
    }

    function setOutputBps(uint16 value) external {
        outputBps = value;
    }

    function convert(uint256 amount, uint256, address receiver, bytes calldata)
        external
        returns (uint256)
    {
        IERC20(inputAsset).transferFrom(msg.sender, address(this), amount);
        uint256 output = amount * outputBps / 10000;
        IERC20(outputAsset).transfer(receiver, output);
        return output;
    }
}

contract StockDividendVaultTest is Test {
    StockDividendVault vault;
    Registry registry;
    DividendStockMock stock;
    DividendTokenMock cash;
    DividendNftMock nft;
    DividendPriceMock prices;
    DividendRouteMock route;
    address constant ALICE = address(0xA11CE);
    address constant BOB = address(0xB0B);

    function setUp() public {
        vm.warp(1000);
        stock = new DividendStockMock();
        cash = new DividendTokenMock();
        nft = new DividendNftMock();
        nft.mint(ALICE, 1);
        nft.mint(BOB, 2);
        registry = new Registry(address(this));
        registry.register(address(stock), keccak256("manifest"));
        prices = new DividendPriceMock();
        DividendCollectionMock collection = new DividendCollectionMock(address(nft));
        vault = new StockDividendVault(
            address(collection),
            address(this),
            address(this),
            address(cash),
            address(registry),
            address(prices),
            100
        );
        route = new DividendRouteMock(address(stock), address(cash));
        vault.setDividendRoute(address(stock), address(route));
        stock.mint(address(this), 10000 ether);
        cash.mint(address(route), 10000 ether);
        stock.approve(address(vault), type(uint256).max);
    }

    function _action(uint256 m0, uint256 m1, Accounting.ActionKind kind) private {
        stock.setMultiplier(m1);
        registry.publish(
            address(stock),
            Registry.Action(
                m0,
                m1,
                uint48(block.timestamp),
                kind,
                keccak256("issuer evidence"),
                keccak256(abi.encode(m0, m1))
            )
        );
    }

    function testDividendFlowPreservesPrincipalAndOtherBanks() public {
        vault.deposit(1, address(stock), 1020 ether);
        vault.deposit(2, address(stock), 510 ether);
        _action(100, 102, Accounting.ActionKind.CashDividend);
        vm.prank(address(0xCA11));
        assertEq(vault.settleDividend(1, address(stock), 20 ether, 20 ether, ""), 20 ether);
        assertEq(cash.balanceOf(ALICE), 20 ether);
        assertEq(cash.balanceOf(BOB), 0);
        (uint256 principal, uint256 reserved,,) = vault.positions(1, address(stock));
        assertEq(principal, 1000 ether);
        assertEq(reserved, 0);
        assertEq(stock.balanceOf(address(vault)), 1510 ether);
        assertEq(vault.accountedUnits(address(stock)), 1510 ether);
        vault.withdrawPrincipal(1, address(stock), 1000 ether);
        vault.settleDividend(2, address(stock), 10 ether, 10 ether, "");
        assertEq(cash.balanceOf(BOB), 10 ether);
        assertEq(stock.allowance(address(vault), address(route)), 0);
        assertEq(cash.allowance(address(vault), address(vault.escrow())), 0);
    }

    function testPriceGainAndSplitCannotCreatePayout() public {
        vault.deposit(1, address(stock), 1000 ether);
        prices.setPrice(2 ether);
        vm.expectRevert(Accounting.InsufficientDividend.selector);
        vault.settleDividend(1, address(stock), 1 ether, 1 ether, "");
        _action(100, 1000, Accounting.ActionKind.NonDividend);
        vm.expectRevert(Accounting.InsufficientDividend.selector);
        vault.settleDividend(1, address(stock), 1 ether, 1 ether, "");
        assertEq(stock.balanceOf(address(vault)), 1000 ether);
    }

    function testUnknownChangeAndStalePriceBlockConversion() public {
        vault.deposit(1, address(stock), 1020 ether);
        stock.setMultiplier(102);
        vm.expectRevert(Registry.AssetNotCurrent.selector);
        vault.deposit(2, address(stock), 10 ether);
        vm.expectRevert(Registry.AssetNotCurrent.selector);
        vault.settleDividend(1, address(stock), 20 ether, 20 ether, "");
        _action(100, 102, Accounting.ActionKind.CashDividend);
        prices.setFailure(IPriceHub.FailureReason.STALE_FEED);
        vm.expectRevert(StockDividendVault.InvalidQuote.selector);
        vault.settleDividend(1, address(stock), 20 ether, 20 ether, "");
        assertEq(stock.balanceOf(address(vault)), 1020 ether);
    }

    function testBadRouteOutputRollsBackReserveAndAllowance() public {
        vault.deposit(1, address(stock), 1020 ether);
        _action(100, 102, Accounting.ActionKind.CashDividend);
        vault.checkpoint(1, address(stock), 32);
        route.setOutputBps(9000);
        vm.expectRevert(StockDividendVault.InvalidQuote.selector);
        vault.settleDividend(1, address(stock), 20 ether, 20 ether, "");
        (uint256 principal, uint256 reserved,,) = vault.positions(1, address(stock));
        assertEq(principal, 1000 ether);
        assertEq(reserved, 20 ether);
        assertEq(stock.balanceOf(address(vault)), 1020 ether);
        assertEq(stock.allowance(address(vault), address(route)), 0);
        assertEq(vault.settlementNonce(), 0);
    }

    function testCannotWeakenOracleMinimumOrExitWithUnpaidReserve() public {
        vault.deposit(1, address(stock), 1020 ether);
        _action(100, 102, Accounting.ActionKind.CashDividend);
        route.setOutputBps(9000);
        vm.expectRevert(StockDividendVault.InvalidQuote.selector);
        vault.settleDividend(1, address(stock), 20 ether, 1, "");
        route.setOutputBps(10000);
        vm.expectRevert(StockDividendVault.UnpaidDividend.selector);
        vault.withdrawPrincipal(1, address(stock), 1000 ether);
        vault.settleDividend(1, address(stock), 20 ether, 20 ether, "");
        vault.withdrawPrincipal(1, address(stock), 1000 ether);
    }

    function testBlockedOwnerRetainsFundedCreditAndPrincipalCanExit() public {
        vault.deposit(1, address(stock), 1020 ether);
        _action(100, 102, Accounting.ActionKind.CashDividend);
        cash.blockWallet(ALICE, true);
        vault.settleDividend(1, address(stock), 20 ether, 20 ether, "");
        assertEq(vault.escrow().creditOf(ALICE), 20 ether);
        vault.withdrawPrincipal(1, address(stock), 1000 ether);
        nft.burn(1);
        cash.blockWallet(ALICE, false);
        vault.escrow().pay(ALICE);
        assertEq(cash.balanceOf(ALICE), 20 ether);
    }

    function testOnlyControllerCanChangePrincipalAndDonationsStayUnallocated() public {
        vm.prank(ALICE);
        vm.expectRevert(StockDividendVault.UnauthorizedController.selector);
        vault.deposit(1, address(stock), 1 ether);
        vault.deposit(1, address(stock), 100 ether);
        stock.transfer(address(vault), 10 ether);
        vm.prank(ALICE);
        vm.expectRevert(StockDividendVault.UnauthorizedController.selector);
        vault.withdrawPrincipal(1, address(stock), 100 ether);
        assertEq(vault.accountedUnits(address(stock)), 100 ether);
        vault.withdrawPrincipal(1, address(stock), 100 ether);
        assertEq(stock.balanceOf(address(vault)), 10 ether);
        assertEq(vault.accountedUnits(address(stock)), 0);
    }

    function testLongActionHistoryProcessesInBoundedBatchesBeforeNewFunds() public {
        vault.deposit(1, address(stock), 100 ether);
        for (uint256 i; i < 35; ++i) {
            _action(100 + i, 101 + i, Accounting.ActionKind.NonDividend);
        }
        vm.expectRevert(Accounting.UnsettledCorporateAction.selector);
        vault.deposit(1, address(stock), 1 ether);
        (,,, uint64 sequence) = vault.positions(1, address(stock));
        assertEq(sequence, 0);
        vault.checkpoint(1, address(stock), 32);
        (,,, sequence) = vault.positions(1, address(stock));
        assertEq(sequence, 32);
        vault.deposit(1, address(stock), 1 ether);
        (uint256 principal, uint256 reserved,, uint64 finalSequence) =
            vault.positions(1, address(stock));
        assertEq(principal, 101 ether);
        assertEq(reserved, 0);
        assertEq(finalSequence, 35);
    }

    function testPermissionlessPartialSettlementCannotStrandUnconvertibleDust() public {
        vault.deposit(1, address(stock), 1020 ether);
        _action(100, 102, Accounting.ActionKind.CashDividend);
        vm.expectRevert(StockDividendVault.DividendDustRemainder.selector);
        vault.settleDividend(1, address(stock), 20 ether - 1, 20 ether - 1, "");
        vault.checkpoint(1, address(stock), 32);
        (, uint256 reserved,,) = vault.positions(1, address(stock));
        assertEq(reserved, 20 ether);
        vault.settleDividend(1, address(stock), 10 ether, 10 ether, "");
        vault.settleDividend(1, address(stock), 10 ether, 10 ether, "");
        vault.withdrawPrincipal(1, address(stock), 1000 ether);
    }

    function testDividendDustIsRetainedInBackingWithoutBeingReportedAsPaid() public {
        vault.deposit(1, address(stock), 102);
        _action(100, 102, Accounting.ActionKind.CashDividend);
        vm.prank(address(0xBAD));
        vm.expectRevert(StockDividendVault.UnauthorizedController.selector);
        vault.retainDividendDust(1, address(stock));
        vault.retainDividendDust(1, address(stock));
        (uint256 principal, uint256 reserved,,) = vault.positions(1, address(stock));
        assertEq(principal, 102);
        assertEq(reserved, 0);
        assertEq(vault.accountedUnits(address(stock)), 102);
        assertEq(cash.balanceOf(ALICE), 0);
        assertEq(vault.settlementNonce(), 0);
        vault.withdrawPrincipal(1, address(stock), 102);
    }
}
