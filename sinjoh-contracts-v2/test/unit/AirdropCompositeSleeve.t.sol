// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { AirdropBankCustody } from "../../src/yield-banks/airdrop/AirdropBankCustody.sol";
import { AirdropTargetBook as Book } from "../../src/yield-banks/airdrop/AirdropTargetBook.sol";
import { AirdropVault } from "../../src/yield-banks/airdrop/AirdropVault.sol";
import { AirdropAssetRegistry } from "../../src/yield-banks/airdrop/AirdropAssetRegistry.sol";
import { PonsAirdropClaimAdapter } from "../../src/yield-banks/airdrop/PonsAirdropClaimAdapter.sol";
import {
    AirdropTokenMock,
    AirdropBeaconMock,
    AirdropDistributorMock
} from "./AirdropCustody.t.sol";
import { Test } from "forge-std/Test.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import {
    AirdropCompositeSleeve as Composite
} from "../../src/yield-banks/airdrop/AirdropCompositeSleeve.sol";
import { StockDividendVault } from "../../src/yield-banks/stock/StockDividendVault.sol";
import {
    StockCorporateActionRegistry as Registry
} from "../../src/yield-banks/stock/StockCorporateActionRegistry.sol";
import {
    StockDividendAccounting as Accounting
} from "../../src/yield-banks/stock/StockDividendAccounting.sol";
import {
    CollectionPortfolioAllocator as Allocator
} from "../../src/yield-banks/CollectionPortfolioAllocator.sol";
import { YieldBankAccount } from "../../src/yield-banks/YieldBankAccount.sol";
import {
    YieldBankAdapterRedemptionCall
} from "../../src/yield-banks/interfaces/IYieldBankManagedSleeve.sol";
import { IPriceHub } from "../../src/yield-banks/interfaces/IPriceHub.sol";
import { DividendStockMock, DividendRouteMock } from "./StockDividendVault.t.sol";
import { DividendTokenMock } from "./StockDividendEscrow.t.sol";
import {
    MockOwnerAllocationNFT,
    MockOwnerAllocationVault,
    MockOwnerAllocationCollection,
    MockOwnerAllocationSleeve,
    MockOwnerDeltaPoolController,
    MockSelfServicePool
} from "./YieldBankOwnerAllocation.t.sol";
import {
    MockYieldBankAsset,
    MockYieldBankAllocationRoute
} from "../mocks/MockYieldBankIntegrations.sol";

contract AirdropPriceMock is IPriceHub {
    mapping(address => uint256) public price;

    function set(address asset, uint256 value) external {
        price[asset] = value;
    }

    function quoteUsd18(address asset) external view returns (uint256, uint48, FailureReason) {
        return (
            price[asset],
            uint48(block.timestamp),
            price[asset] == 0 ? FailureReason.UNSUPPORTED_ASSET : FailureReason.NONE
        );
    }
}

/// @dev The LP leg is backed by WETH in this unit fixture. Real Delta deployment and routes
/// are a separate fork test; this fixture does not pretend to earn actual LP fees.
contract AirdropLPMock is ERC20 {
    uint16 public constant maximumOperatorLossBps = 200;
    address public immutable sleeve;
    address public immutable pool;
    IERC20 public immutable weth;

    constructor(address sleeve_, address pool_, address weth_) ERC20("LP fixture", "LP") {
        sleeve = sleeve_;
        pool = pool_;
        weth = IERC20(weth_);
    }

    function lpReceiptToken() external view returns (address) {
        return address(this);
    }

    function lpUnitPriceUsd18() external view returns (uint256, uint48) {
        return (1 ether, uint48(block.timestamp));
    }

    function purchaseLP(uint256 assets, uint256 minimumShares, bytes calldata)
        external
        returns (uint256)
    {
        require(msg.sender == sleeve && assets >= minimumShares);
        weth.transferFrom(sleeve, address(this), assets);
        _mint(sleeve, assets);
        return assets;
    }

    function redeemLP(uint256 shares, uint256 minimumWeth, uint16 loss, bytes calldata)
        external
        returns (uint256)
    {
        require(msg.sender == sleeve && shares >= minimumWeth && loss <= maximumOperatorLossBps);
        _spendAllowance(sleeve, address(this), shares);
        _burn(sleeve, shares);
        weth.transfer(sleeve, shares);
        return shares;
    }
}

contract AirdropCompositeSleeveTest is Test {
    address constant ALICE = address(0xA11CE);
    address constant BOB = address(0xB0B);
    MockYieldBankAsset weth;
    DividendTokenMock cash;
    DividendStockMock stockA;
    DividendStockMock stockB;
    AirdropPriceMock prices;
    MockOwnerAllocationNFT nft;
    MockOwnerAllocationCollection collection;
    MockOwnerAllocationSleeve usdg;
    MockOwnerAllocationSleeve core;
    MockOwnerAllocationSleeve market;
    MockOwnerDeltaPoolController controller;
    MockSelfServicePool pool;
    Allocator allocator;
    Composite composite;
    AirdropLPMock lp;
    Registry registry;
    StockDividendVault custody;
    YieldBankAccount accountA;
    YieldBankAccount accountB;
    DividendRouteMock exitA;

    AirdropVault airVault;
    Book book;
    AirdropAssetRegistry airRegistry;
    address[3] airTokens;

    function setUp() public {
        vm.warp(1000);
        weth = new MockYieldBankAsset("WETH", "WETH");
        cash = new DividendTokenMock();
        stockA = new DividendStockMock();
        stockB = new DividendStockMock();
        prices = new AirdropPriceMock();
        prices.set(address(weth), 1 ether);
        prices.set(address(cash), 1 ether);
        prices.set(address(stockA), 1 ether);
        prices.set(address(stockB), 1 ether);
        nft = new MockOwnerAllocationNFT();
        MockOwnerAllocationVault proceeds = new MockOwnerAllocationVault(address(this));
        collection =
            new MockOwnerAllocationCollection(address(nft), address(weth), address(proceeds));
        core = new MockOwnerAllocationSleeve(address(weth), "CORE");
        market = new MockOwnerAllocationSleeve(address(weth), "LP");
        usdg = new MockOwnerAllocationSleeve(address(weth), "USDG");
        controller = new MockOwnerDeltaPoolController();
        pool = new MockSelfServicePool();
        allocator = new Allocator(
            address(collection),
            address(this),
            address(this),
            address(this),
            address(controller),
            address(core),
            address(market),
            address(usdg),
            0,
            0,
            10000
        );
        YieldBankAccount implementation = new YieldBankAccount();
        accountA = YieldBankAccount(Clones.clone(address(implementation)));
        accountB = YieldBankAccount(Clones.clone(address(implementation)));
        accountA.initialize(address(collection), address(nft), 1, address(this));
        accountB.initialize(address(collection), address(nft), 2, address(this));
        collection.configure(address(allocator), 1, address(accountA));
        collection.configure(address(allocator), 2, address(accountB));
        nft.mint(ALICE, 1);
        nft.mint(BOB, 2);
        composite = new Composite(
            "Bank stock portfolio",
            "STOCK-LP",
            address(weth),
            address(allocator),
            address(this),
            address(this),
            address(prices),
            address(prices),
            address(prices),
            1,
            10000,
            100
        );
        lp = new AirdropLPMock(address(composite), address(pool), address(weth));
        composite.addAdapter(address(lp), 10000);
        controller.materialize(address(pool), address(composite), address(lp));
        collection.registerSleeve(address(composite));
        registry = new Registry(address(this));
        registry.register(address(stockA), keccak256("stock A"));
        registry.register(address(stockB), keccak256("stock B"));
        custody = new StockDividendVault(
            address(collection),
            address(composite),
            address(this),
            address(cash),
            address(registry),
            address(prices),
            100
        );
        composite.configureVault(address(custody));
        MockYieldBankAllocationRoute entryA =
            new MockYieldBankAllocationRoute(address(weth), address(stockA));
        exitA = new DividendRouteMock(address(stockA), address(weth));
        weth.mint(address(exitA), 10000 ether);
        MockYieldBankAllocationRoute entryB =
            new MockYieldBankAllocationRoute(address(weth), address(stockB));
        MockYieldBankAllocationRoute exitB =
            new MockYieldBankAllocationRoute(address(stockB), address(weth));
        composite.bindStockRoutes(address(stockA), address(entryA), address(exitA));
        composite.bindStockRoutes(address(stockB), address(entryB), address(exitB));
        airRegistry = new AirdropAssetRegistry(address(this), keccak256("approved"));
        airVault = new AirdropVault(address(composite), address(collection), address(airRegistry));
        composite.configureAirdropVault(address(airVault));
        book = new Book(address(composite));
        composite.configureTargetBook(address(book));
        for (uint256 i; i < 3; ++i) {
            AirdropTokenMock token = new AirdropTokenMock();
            airTokens[i] = address(token);
            prices.set(address(token), 1 ether);
            airRegistry.register(address(token), keccak256(abi.encode(i)));
            AirdropDistributorMock dist = new AirdropDistributorMock(address(token), address(cash));
            airRegistry.addClaimRoute(
                address(token),
                address(
                    new PonsAirdropClaimAdapter(address(dist), address(new AirdropBeaconMock()))
                )
            );
            airRegistry.setEnabled(address(token), true);
            composite.bindAirdropRoutes(
                address(token),
                address(new MockYieldBankAllocationRoute(address(weth), address(token))),
                address(new MockYieldBankAllocationRoute(address(token), address(weth)))
            );
        }
        composite.setDepositsPaused(false);
        weth.mint(address(this), 200 ether);
        weth.approve(address(usdg), 200 ether);
        usdg.deposit(100 ether, address(accountA), 100 ether, "");
        usdg.deposit(100 ether, address(accountB), 100 ether, "");
        collection.track(address(accountA), address(usdg));
        collection.track(address(accountB), address(usdg));
    }

    function _airTarget(uint256 n) private view returns (Book.TargetInput memory t) {
        address[] memory assets = new address[](n);
        uint16[] memory weights = new uint16[](n);
        for (uint256 i; i < n; ++i) {
            assets[i] = airTokens[i % 3];
            weights[i] = uint16(10000 / n + (i == 0 ? 10000 % n : 0));
        }
        return Book.TargetInput(
            0,
            0,
            5000,
            Book.Basket(new address[](0), new uint16[](0)),
            Book.Basket(assets, weights),
            uint48(block.timestamp + 1 hours)
        );
    }

    function testMalformedBasketsAndUnauthorizedTargetsNeverChangePreferences() public {
        Book.TargetInput memory t = _airTarget(2);
        vm.prank(BOB);
        vm.expectRevert();
        book.setTarget(1, t);
        t.airdrops.weights[1] = 4999;
        vm.prank(ALICE);
        vm.expectRevert();
        book.setTarget(1, t);
        t.airdrops.weights[0] = 10000;
        t.airdrops.weights[1] = 0;
        vm.prank(ALICE);
        vm.expectRevert();
        book.setTarget(1, t);
        t = _airTarget(2);
        t.airdrops.assets[1] = t.airdrops.assets[0];
        vm.prank(ALICE);
        vm.expectRevert();
        book.setTarget(1, t);
        t = _airTarget(4);
        vm.prank(ALICE);
        vm.expectRevert();
        book.setTarget(1, t);
        t = _airTarget(1);
        t.airdrop = 0;
        t.lp = 1000;
        vm.prank(ALICE);
        vm.expectRevert();
        book.setTarget(1, t);
        t = _airTarget(1);
        t.validUntil = uint48(block.timestamp);
        vm.prank(ALICE);
        vm.expectRevert();
        book.setTarget(1, t);
        t = _airTarget(1);
        t.validUntil = uint48(block.timestamp + 1 days + 1);
        vm.prank(ALICE);
        vm.expectRevert();
        book.setTarget(1, t);
        assertEq(book.targetOf(1).nonce, 0);
        assertEq(usdg.balanceOf(address(accountA)), 100 ether);
    }

    function testFuzzValidBasketWeightsPreserveExactOwnerPreference(uint16 first, uint16 second)
        public
    {
        uint16 a = uint16(bound(first, 1, 9998));
        uint16 b = uint16(bound(second, 1, 9999 - a));
        Book.TargetInput memory t = _airTarget(3);
        t.airdrops.weights[0] = a;
        t.airdrops.weights[1] = b;
        t.airdrops.weights[2] = 10000 - a - b;
        vm.prank(ALICE);
        book.setTarget(1, t);
        Book.Target memory saved = book.targetOf(1);
        assertEq(saved.airdropWeights[0], a);
        assertEq(saved.airdropWeights[1], b);
        assertEq(saved.airdropWeights[2], 10000 - a - b);
        assertEq(saved.owner, ALICE);
        assertEq(saved.nonce, 1);
    }

    function _target(uint256 bank, address stock) private {
        address[] memory assets = new address[](1);
        assets[0] = stock;
        uint16[] memory weights = new uint16[](1);
        weights[0] = 10000;
        vm.prank(nft.ownerOf(bank));
        book.setTarget(
            bank,
            Book.TargetInput(
                2000,
                3000,
                0,
                Book.Basket(assets, weights),
                Book.Basket(new address[](0), new uint16[](0)),
                uint48(block.timestamp + 1 hours)
            )
        );
    }

    function _request(uint256 bank, bool enter) private returns (uint64) {
        vm.prank(nft.ownerOf(bank));
        return allocator.setTargetAllocation(
            bank,
            [uint16(0), enter ? uint16(5000) : uint16(0), enter ? uint16(5000) : uint16(10000)],
            enter ? address(pool) : address(0),
            100,
            uint48(block.timestamp + 1 hours)
        );
    }

    function _entry(uint256 bank)
        private
        view
        returns (Allocator.RebalanceExecution memory execution)
    {
        execution.redemptions[2].minimumOutputs = new uint256[](1);
        execution.redemptions[2].minimumOutputs[0] = 100 ether;
        execution.allocations[2].minimumOutput = 50 ether;
        execution.allocations[2].minimumShares = 50 ether;
        execution.allocations[1].minimumOutput = 50 ether;
        execution.allocations[1].minimumShares = 50 * 1e36;
        Composite.DepositExecution memory deposit;
        deposit.bank = bank;
        deposit.targetNonce = book.targetOf(bank).nonce;
        deposit.minimumStockUnits = new uint256[](1);
        deposit.minimumStockUnits[0] = 30 ether;
        deposit.stockRouteData = new bytes[](1);
        deposit.minimumLPUnits = 20 ether;
        execution.allocations[1].sleeveData = abi.encode(deposit);
        execution.minimumWethRecovered = 100 ether;
        execution.deadline = block.timestamp + 1 hours;
    }

    function _exit() private view returns (Allocator.RebalanceExecution memory execution) {
        execution.redemptions[2].minimumOutputs = new uint256[](1);
        execution.redemptions[2].minimumOutputs[0] = 50 ether;
        execution.deltaPoolRedemption.minimumOutputs = new uint256[](1);
        execution.deltaPoolRedemption.minimumOutputs[0] = 49 ether;
        execution.deltaPoolRedemption.adapterCalls = new YieldBankAdapterRedemptionCall[](1);
        Composite.RedemptionExecution memory redemption;
        redemption.minimumStockWeth = new uint256[](1);
        redemption.minimumStockWeth[0] = 29.7 ether;
        redemption.stockRouteData = new bytes[](1);
        redemption.minimumLPWeth = 20 ether;
        execution.deltaPoolRedemption.adapterCalls[0] =
            YieldBankAdapterRedemptionCall(address(lp), 100, abi.encode(redemption));
        execution.allocations[2].minimumOutput = 99 ether;
        execution.allocations[2].minimumShares = 99 ether;
        execution.minimumWethRecovered = 99 ether;
        execution.deadline = block.timestamp + 1 hours;
    }

    function testExistingAllocatorRebalancesUSDGIntoLPAndOwnStocksAndBack() public {
        _target(1, address(stockA));
        _target(2, address(stockB));
        uint64 a = _request(1, true);
        uint64 b = _request(2, true);
        allocator.executeTargetAllocation(1, a, _entry(1));
        allocator.executeTargetAllocation(2, b, _entry(2));
        assertEq(usdg.balanceOf(address(accountA)), 50 ether);
        assertEq(composite.lpUnitsOf(1), 20 ether);
        (uint256 unitsA,,,) = custody.positions(1, address(stockA));
        (uint256 unitsB,,,) = custody.positions(2, address(stockB));
        assertEq(unitsA, 30 ether);
        assertEq(unitsB, 30 ether);
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
        _target(1, address(stockA));
        _target(2, address(stockB));
        allocator.executeTargetAllocation(1, _request(1, true), _entry(1));
        allocator.executeTargetAllocation(2, _request(2, true), _entry(2));
        prices.set(address(stockA), 2 ether);
        prices.set(address(stockB), 0.5 ether);
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
        registry.publish(
            address(stockA),
            Registry.Action(
                100,
                102,
                uint48(block.timestamp),
                Accounting.ActionKind.CashDividend,
                keccak256("issuer"),
                keccak256("action")
            )
        );
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

    function testSingleAirdropWithStockLPAndUSDGRoundTrip() public {
        _airdropRoundTrip(1);
    }

    function testTwoTokenAirdropBasketWithStockLPAndUSDGRoundTrip() public {
        _airdropRoundTrip(2);
    }

    function testThreeTokenAirdropBasketWithStockLPAndUSDGRoundTrip() public {
        _airdropRoundTrip(3);
    }

    function _airdropRoundTrip(uint256 count) private {
        address[] memory a = new address[](count);
        uint16[] memory w = new uint16[](count);
        uint256[] memory minima = new uint256[](count);
        uint256 used;
        for (uint256 i; i < count; ++i) {
            a[i] = airTokens[i];
            w[i] = uint16(10000 / count + (i == 0 ? 10000 % count : 0));
            minima[i] = i == count - 1 ? 30 ether - used : uint256(30 ether) * uint256(w[i]) / 10000;
            used += minima[i];
        }
        address[] memory stocks = new address[](1);
        stocks[0] = address(stockA);
        uint16[] memory stockWeights = new uint16[](1);
        stockWeights[0] = 10000;
        vm.prank(ALICE);
        book.setTarget(
            1,
            Book.TargetInput(
                1000,
                2000,
                3000,
                Book.Basket(stocks, stockWeights),
                Book.Basket(a, w),
                uint48(block.timestamp + 1 hours)
            )
        );
        vm.prank(ALICE);
        uint64 rev = allocator.setTargetAllocation(
            1,
            [uint16(0), uint16(6000), uint16(4000)],
            address(pool),
            100,
            uint48(block.timestamp + 1 hours)
        );
        Allocator.RebalanceExecution memory execution = _entry(1);
        execution.allocations[2].minimumOutput = 40 ether;
        execution.allocations[2].minimumShares = 40 ether;
        execution.allocations[1].minimumOutput = 60 ether;
        execution.allocations[1].minimumShares = 60 * 1e36;
        Composite.DepositExecution memory d =
            abi.decode(execution.allocations[1].sleeveData, (Composite.DepositExecution));
        d.minimumStockUnits[0] = 20 ether;
        d.minimumLPUnits = 10 ether;
        d.minimumAirdropUnits = minima;
        d.airdropRouteData = new bytes[](count);
        execution.allocations[1].sleeveData = abi.encode(d);
        allocator.executeTargetAllocation(1, rev, execution);
        assertEq(composite.balanceOf(address(accountA)), 60 * 1e36);
        assertEq(usdg.balanceOf(address(accountA)), 40 ether);
        for (uint256 i; i < count; ++i) {
            assertEq(airVault.principalOf(1, a[i]), minima[i]);
            cash.mint(address(airVault.custodyOf(1, a[i])), (i + 1) * 1 ether);
        }
        // Reward transfers do not inflate portfolio principal/NAV.
        assertEq(composite.balanceOf(address(accountA)), 60 * 1e36);
        uint64 exitRev = _request(1, false);
        execution = _exit();
        execution.redemptions[2].minimumOutputs[0] = 40 ether;
        execution.deltaPoolRedemption.minimumOutputs[0] = 60 ether;
        Composite.RedemptionExecution memory r = abi.decode(
            execution.deltaPoolRedemption.adapterCalls[0].data, (Composite.RedemptionExecution)
        );
        r.minimumStockWeth[0] = 20 ether;
        r.minimumLPWeth = 10 ether;
        r.minimumAirdropWeth = minima;
        r.airdropRouteData = new bytes[](count);
        execution.deltaPoolRedemption.adapterCalls[0].data = abi.encode(r);
        allocator.executeTargetAllocation(1, exitRev, execution);
        assertEq(usdg.balanceOf(address(accountA)), 100 ether);
        assertEq(composite.balanceOf(address(accountA)), 0);
        for (uint256 i; i < count; ++i) {
            assertEq(airVault.principalOf(1, a[i]), 0);
            address holder = address(airVault.custodyOf(1, a[i]));
            vm.prank(ALICE);
            AirdropBankCustody(payable(holder)).claim(address(cash));
        }
        assertEq(cash.balanceOf(ALICE), count * (count + 1) / 2 * 1 ether);
    }
}
