// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { StockCompositeSleeve as Composite } from "../../src/yield-banks/stock/StockCompositeSleeve.sol";
import { StockDividendVault } from "../../src/yield-banks/stock/StockDividendVault.sol";
import { StockCorporateActionRegistry as Registry } from "../../src/yield-banks/stock/StockCorporateActionRegistry.sol";
import { StockDividendAccounting as Accounting } from "../../src/yield-banks/stock/StockDividendAccounting.sol";
import { CollectionPortfolioAllocator as Allocator } from "../../src/yield-banks/CollectionPortfolioAllocator.sol";
import { YieldBankAccount } from "../../src/yield-banks/YieldBankAccount.sol";
import { YieldBankAdapterRedemptionCall } from "../../src/yield-banks/interfaces/IYieldBankManagedSleeve.sol";
import { IPriceHub } from "../../src/yield-banks/interfaces/IPriceHub.sol";
import { DividendStockMock, DividendRouteMock } from "./StockDividendVault.t.sol";
import { DividendTokenMock } from "./StockDividendEscrow.t.sol";
import {
    MockOwnerAllocationNFT, MockOwnerAllocationVault, MockOwnerAllocationCollection,
    MockOwnerAllocationSleeve, MockOwnerDeltaPoolController, MockSelfServicePool
} from "./YieldBankOwnerAllocation.t.sol";
import { MockYieldBankAsset, MockYieldBankAllocationRoute } from "../mocks/MockYieldBankIntegrations.sol";

contract CompositePriceMock is IPriceHub {
    mapping(address => uint256) public price;
    function set(address asset, uint256 value) external { price[asset] = value; }
    function quoteUsd18(address asset) external view returns (uint256, uint48, FailureReason) {
        return (price[asset], uint48(block.timestamp), price[asset] == 0 ? FailureReason.UNSUPPORTED_ASSET : FailureReason.NONE);
    }
}

/// @dev The LP leg is backed by WETH in this unit fixture. Real Delta deployment and routes
/// are a separate fork test; this fixture does not pretend to earn actual LP fees.
contract CompositeLPMock is ERC20 {
    address public immutable sleeve;
    address public immutable pool;
    IERC20 public immutable weth;
    constructor(address sleeve_, address pool_, address weth_) ERC20("LP fixture", "LP") {
        sleeve = sleeve_; pool = pool_; weth = IERC20(weth_);
    }
    function lpReceiptToken() external view returns (address) { return address(this); }
    function lpUnitPriceUsd18() external view returns (uint256, uint48) { return (1 ether, uint48(block.timestamp)); }
    function purchaseLP(uint256 assets, uint256 minimumShares, bytes calldata) external returns (uint256) {
        require(msg.sender == sleeve && assets >= minimumShares);
        weth.transferFrom(sleeve, address(this), assets);
        _mint(sleeve, assets);
        return assets;
    }
    function redeemLP(uint256 shares, uint256 minimumWeth, uint16, bytes calldata) external returns (uint256) {
        require(msg.sender == sleeve && shares >= minimumWeth);
        _spendAllowance(sleeve, address(this), shares);
        _burn(sleeve, shares);
        weth.transfer(sleeve, shares);
        return shares;
    }
}

contract StockCompositeSleeveTest is Test {
    address constant ALICE = address(0xA11CE);
    address constant BOB = address(0xB0B);
    MockYieldBankAsset weth;
    DividendTokenMock cash;
    DividendStockMock stockA;
    DividendStockMock stockB;
    CompositePriceMock prices;
    MockOwnerAllocationNFT nft;
    MockOwnerAllocationCollection collection;
    MockOwnerAllocationSleeve usdg;
    MockOwnerAllocationSleeve core;
    MockOwnerAllocationSleeve market;
    MockOwnerDeltaPoolController controller;
    MockSelfServicePool pool;
    Allocator allocator;
    Composite composite;
    CompositeLPMock lp;
    Registry registry;
    StockDividendVault custody;
    YieldBankAccount accountA;
    YieldBankAccount accountB;
    DividendRouteMock exitA;

    function setUp() public {
        vm.warp(1000);
        weth = new MockYieldBankAsset("WETH", "WETH");
        cash = new DividendTokenMock();
        stockA = new DividendStockMock(); stockB = new DividendStockMock();
        prices = new CompositePriceMock();
        prices.set(address(weth), 1 ether); prices.set(address(cash), 1 ether);
        prices.set(address(stockA), 1 ether); prices.set(address(stockB), 1 ether);
        nft = new MockOwnerAllocationNFT();
        MockOwnerAllocationVault proceeds = new MockOwnerAllocationVault(address(this));
        collection = new MockOwnerAllocationCollection(address(nft), address(weth), address(proceeds));
        core = new MockOwnerAllocationSleeve(address(weth), "CORE");
        market = new MockOwnerAllocationSleeve(address(weth), "LP");
        usdg = new MockOwnerAllocationSleeve(address(weth), "USDG");
        controller = new MockOwnerDeltaPoolController();
        pool = new MockSelfServicePool();
        allocator = new Allocator(address(collection), address(this), address(this), address(this), address(controller), address(core), address(market), address(usdg), 0, 0, 10000);
        YieldBankAccount implementation = new YieldBankAccount();
        accountA = YieldBankAccount(Clones.clone(address(implementation)));
        accountB = YieldBankAccount(Clones.clone(address(implementation)));
        accountA.initialize(address(collection), address(nft), 1, address(this));
        accountB.initialize(address(collection), address(nft), 2, address(this));
        collection.configure(address(allocator), 1, address(accountA));
        collection.configure(address(allocator), 2, address(accountB));
        nft.mint(ALICE, 1); nft.mint(BOB, 2);
        composite = new Composite("Bank stock portfolio", "STOCK-LP", address(weth), address(allocator), address(this), address(this), address(prices), address(prices), address(prices), 1, 10000, 100);
        lp = new CompositeLPMock(address(composite), address(pool), address(weth));
        composite.addAdapter(address(lp), 10000);
        controller.materialize(address(pool), address(composite), address(lp));
        collection.registerSleeve(address(composite));
        registry = new Registry(address(this));
        registry.register(address(stockA), keccak256("stock A"));
        registry.register(address(stockB), keccak256("stock B"));
        custody = new StockDividendVault(address(collection), address(composite), address(this), address(cash), address(registry), address(prices), 100);
        composite.configureVault(address(custody));
        MockYieldBankAllocationRoute entryA = new MockYieldBankAllocationRoute(address(weth), address(stockA));
        exitA = new DividendRouteMock(address(stockA), address(weth));
        weth.mint(address(exitA), 10000 ether);
        MockYieldBankAllocationRoute entryB = new MockYieldBankAllocationRoute(address(weth), address(stockB));
        MockYieldBankAllocationRoute exitB = new MockYieldBankAllocationRoute(address(stockB), address(weth));
        composite.bindStockRoutes(address(stockA), address(entryA), address(exitA));
        composite.bindStockRoutes(address(stockB), address(entryB), address(exitB));
        composite.setDepositsPaused(false);
        weth.mint(address(this), 200 ether);
        weth.approve(address(usdg), 200 ether);
        usdg.deposit(100 ether, address(accountA), 100 ether, "");
        usdg.deposit(100 ether, address(accountB), 100 ether, "");
        collection.track(address(accountA), address(usdg));
        collection.track(address(accountB), address(usdg));
    }

    function _target(uint256 bank, address stock) private {
        address[] memory assets = new address[](1); assets[0] = stock;
        uint16[] memory weights = new uint16[](1); weights[0] = 10000;
        vm.prank(nft.ownerOf(bank));
        composite.setTarget(bank, 2000, 3000, false, assets, weights, uint48(block.timestamp + 1 hours));
    }
    function _request(uint256 bank, bool enter) private returns (uint64) {
        vm.prank(nft.ownerOf(bank));
        return allocator.setTargetAllocation(bank, [uint16(0), enter ? uint16(5000) : uint16(0), enter ? uint16(5000) : uint16(10000)], enter ? address(pool) : address(0), 100, uint48(block.timestamp + 1 hours));
    }
    function _entry(uint256 bank) private view returns (Allocator.RebalanceExecution memory execution) {
        execution.redemptions[2].minimumOutputs = new uint256[](1);
        execution.redemptions[2].minimumOutputs[0] = 100 ether;
        execution.allocations[2].minimumOutput = 50 ether;
        execution.allocations[2].minimumShares = 50 ether;
        execution.allocations[1].minimumOutput = 50 ether;
        execution.allocations[1].minimumShares = 50 * 1e36;
        Composite.DepositExecution memory deposit;
        deposit.bank = bank;
        deposit.targetNonce = composite.targetOf(bank).nonce;
        deposit.minimumStockUnits = new uint256[](1); deposit.minimumStockUnits[0] = 30 ether;
        deposit.stockRouteData = new bytes[](1);
        deposit.minimumLPUnits = 20 ether;
        execution.allocations[1].sleeveData = abi.encode(deposit);
        execution.minimumWethRecovered = 100 ether;
        execution.deadline = block.timestamp + 1 hours;
    }
    function _exit() private view returns (Allocator.RebalanceExecution memory execution) {
        execution.redemptions[2].minimumOutputs = new uint256[](1); execution.redemptions[2].minimumOutputs[0] = 50 ether;
        execution.deltaPoolRedemption.minimumOutputs = new uint256[](1); execution.deltaPoolRedemption.minimumOutputs[0] = 49 ether;
        execution.deltaPoolRedemption.adapterCalls = new YieldBankAdapterRedemptionCall[](1);
        Composite.RedemptionExecution memory redemption;
        redemption.minimumStockWeth = new uint256[](1); redemption.minimumStockWeth[0] = 29.7 ether;
        redemption.stockRouteData = new bytes[](1);
        redemption.minimumLPWeth = 20 ether;
        execution.deltaPoolRedemption.adapterCalls[0] = YieldBankAdapterRedemptionCall(address(lp), 100, abi.encode(redemption));
        execution.allocations[2].minimumOutput = 99 ether;
        execution.allocations[2].minimumShares = 99 ether;
        execution.minimumWethRecovered = 99 ether;
        execution.deadline = block.timestamp + 1 hours;
    }

    function testExistingAllocatorRebalancesUSDGIntoLPAndOwnStocksAndBack() public {
        _target(1, address(stockA)); _target(2, address(stockB));
        uint64 a = _request(1, true); uint64 b = _request(2, true);
        allocator.executeTargetAllocation(1, a, _entry(1));
        allocator.executeTargetAllocation(2, b, _entry(2));
        assertEq(usdg.balanceOf(address(accountA)), 50 ether);
        assertEq(composite.lpUnitsOf(1), 20 ether);
        (uint256 unitsA,,,) = custody.positions(1, address(stockA));
        (uint256 unitsB,,,) = custody.positions(2, address(stockB));
        assertEq(unitsA, 30 ether); assertEq(unitsB, 30 ether);
        assertEq(composite.balanceOf(address(accountA)), 50 * 1e36);
        assertEq(composite.totalSupply(), 100 * 1e36);
        uint64 exitRevision = _request(1, false);
        allocator.executeTargetAllocation(1, exitRevision, _exit());
        assertEq(usdg.balanceOf(address(accountA)), 100 ether);
        assertEq(composite.balanceOf(address(accountA)), 0);
        assertEq(composite.balanceOf(address(accountB)), 50 * 1e36);
        assertEq(composite.totalSupply(), composite.balanceOf(address(accountB)));
        assertEq(allocator.activeDeltaPoolOf(1), address(0));
        assertEq(collection.accountOf(1), address(accountA));
        assertEq(nft.ownerOf(1), ALICE);
    }

    function testDifferentStockGainsStayWithTheCorrectBank() public {
        _target(1, address(stockA)); _target(2, address(stockB));
        allocator.executeTargetAllocation(1, _request(1, true), _entry(1));
        allocator.executeTargetAllocation(2, _request(2, true), _entry(2));
        prices.set(address(stockA), 2 ether); prices.set(address(stockB), 0.5 ether);
        assertEq(composite.balanceOf(address(accountA)), 80 * 1e36);
        assertEq(composite.balanceOf(address(accountB)), 35 * 1e36);
        assertEq(composite.totalSupply(), 115 * 1e36);
        (uint256 value,) = composite.totalAssetsUsd18();
        assertEq(value, 115 ether);
        assertEq(value * composite.balanceOf(address(accountA)) / composite.totalSupply(), 80 ether);
    }

    function testTransferredNftRejectsPreviousOwnersStockTarget() public {
        _target(1, address(stockA));
        nft.transfer(1, BOB);
        uint64 revision = _request(1, true);
        Allocator.RebalanceExecution memory staleExecution = _entry(1);
        vm.expectRevert(Composite.InvalidTarget.selector);
        allocator.executeTargetAllocation(1, revision, staleExecution);
        assertEq(usdg.balanceOf(address(accountA)), 100 ether);
        _target(1, address(stockB));
        allocator.executeTargetAllocation(1, revision, _entry(1));
        (uint256 units,,,) = custody.positions(1, address(stockB));
        assertEq(units, 30 ether);
    }

    function testUnconvertedDividendBlocksExitThenPaysOwnerBeforeRebalance() public {
        _target(1, address(stockA));
        allocator.executeTargetAllocation(1, _request(1, true), _entry(1));
        stockA.setMultiplier(102);
        prices.set(address(stockA), 1.02 ether);
        registry.publish(address(stockA), Registry.Action(100, 102, uint48(block.timestamp), Accounting.ActionKind.CashDividend, keccak256("issuer"), keccak256("action")));
        uint64 revision = _request(1, false);
        vm.expectRevert(StockDividendVault.UnpaidDividend.selector);
        allocator.executeTargetAllocation(1, revision, _exit());
        assertEq(usdg.balanceOf(address(accountA)), 50 ether);
        custody.checkpoint(1, address(stockA), 32);
        (, uint256 reserved,,) = custody.positions(1, address(stockA));
        DividendRouteMock dividendRoute = new DividendRouteMock(address(stockA), address(cash));
        cash.mint(address(dividendRoute), 1000 ether);
        dividendRoute.setOutputBps(10200);
        custody.setDividendRoute(address(stockA), address(dividendRoute));
        custody.settleDividend(1, address(stockA), reserved, reserved * 102 / 100, "");
        assertApproxEqAbs(cash.balanceOf(ALICE), 0.6 ether, 1);
        exitA.setOutputBps(10200);
        allocator.executeTargetAllocation(1, revision, _exit());
        assertApproxEqAbs(usdg.balanceOf(address(accountA)), 100 ether, 1);
        assertEq(composite.balanceOf(address(accountA)), 0);
    }
}
