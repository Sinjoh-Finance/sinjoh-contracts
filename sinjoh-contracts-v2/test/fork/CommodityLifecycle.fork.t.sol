// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { PriceHub } from "../../src/yield-banks/PriceHub.sol";
import { IPriceHub } from "../../src/yield-banks/interfaces/IPriceHub.sol";
import { MarketMakingSleeve } from "../../src/yield-banks/sleeves/MarketMakingSleeve.sol";
import { DeltaV3LPAdapter } from "../../src/yield-banks/adapters/DeltaV3LPAdapter.sol";
import { IDeltaPositionBuilder } from "../../src/yield-banks/interfaces/IDeltaPositionBuilder.sol";
import {
    IYieldBankV3Pool,
    IYieldBankV3PositionManager
} from "../../src/yield-banks/interfaces/IYieldBankV3.sol";
import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { PreparePiggyBanksCommodity } from "../../script/PreparePiggyBanksCommodity.s.sol";
import { CommoditySleeve } from "../../src/yield-banks/commodity/CommoditySleeve.sol";
import { StockDividendRoute } from "../../src/yield-banks/stock/StockDividendRoute.sol";
import { StockCompositeLPAdapter } from "../../src/yield-banks/stock/StockCompositeLPAdapter.sol";
import { YieldBankCollection } from "../../src/yield-banks/YieldBankCollection.sol";
import {
    CollectionPortfolioAllocator
} from "../../src/yield-banks/CollectionPortfolioAllocator.sol";
import {
    YieldBankSelfServiceExecutionRouter
} from "../../src/yield-banks/YieldBankSelfServiceExecutionRouter.sol";
import {
    YieldBankAdapterRedemptionCall
} from "../../src/yield-banks/interfaces/IYieldBankManagedSleeve.sol";

/// @notice Real deployed treasury, real assets and pools; all writes occur on an isolated fork.
contract CommodityLifecycleForkTest is Test {
    YieldBankCollection constant collection =
        YieldBankCollection(0xc275fa302Cd53DFa42D41b1C5b770661d923ba43);
    CollectionPortfolioAllocator constant allocator =
        CollectionPortfolioAllocator(0x42e14eA9f926ad7b530ce49d433CB6f748f8D0a1);
    address constant USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;
    CommoditySleeve sleeve;
    address pool;
    address facade;
    StockCompositeLPAdapter adapter;
    YieldBankSelfServiceExecutionRouter router;
    IERC721 nft;
    PriceHub hub;
    MarketMakingSleeve lpVault;
    DeltaV3LPAdapter lpAdapter;
    address constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    address constant INJOH = 0x2cC0FAC44B8252f6B10208B091aFf2c94B4da77D;
    address constant OLD_MANAGER = 0x73991a25C818Bf1f1128dEAaB1492D45638DE0D3;
    address constant INJOH_POOL = 0xB09fa4f04032b9d9e690ac4a1d29523b5f9A72DC;

    function setUp() public {
        string memory rpc = vm.envOr("ROBINHOOD_MAINNET_RPC_URL", string(""));
        if (bytes(rpc).length == 0) vm.skip(true);
        vm.createSelectFork(rpc);
        // Only the infrastructure deployer's fork ETH is funded; bank balances are untouched.
        vm.deal(0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49, 1 ether);
        new PreparePiggyBanksCommodity().run();
        string memory plan = vm.readFile("deployments/piggy-banks-commodity-preparation.json");
        sleeve = CommoditySleeve(vm.parseJsonAddress(plan, ".composite"));
        pool = vm.parseJsonAddress(plan, ".registrationPool");
        facade = vm.parseJsonAddress(plan, ".facade");
        adapter = StockCompositeLPAdapter(facade);
        router = YieldBankSelfServiceExecutionRouter(allocator.allocationOperator());
        nft = IERC721(address(collection.nft()));
        hub = PriceHub(sleeve.priceHub());
        lpVault = MarketMakingSleeve(vm.parseJsonAddress(plan, ".lpVault"));
        lpAdapter = DeltaV3LPAdapter(vm.parseJsonAddress(plan, ".lpAdapter"));
    }

    function testSingleGoldRoundTrip() public {
        _roundTrip([uint16(10000), 0, 0, 0]);
    }

    function testTwoAssetRoundTrip() public {
        _roundTrip([uint16(7000), 3000, 0, 0]);
    }

    function testThreeAssetRoundTrip() public {
        _roundTrip([uint16(3334), 3333, 3333, 0]);
    }

    function testFourAssetRoundTripIncludingEightDecimalBitcoin() public {
        _roundTrip([uint16(2500), 2500, 2500, 2500]);
    }

    function _roundTrip(uint16[4] memory weights) private {
        address account = collection.accountOf(334);
        uint256 initialCashShares = IERC20(allocator.sleeves(2)).balanceOf(account);
        _rebalance(334, 4000, 0, weights);
        uint256[4] memory units = sleeve.unitsOf(334);
        CommoditySleeve.Asset[4] memory assets = sleeve.assets();
        for (uint256 i; i < 4; ++i) {
            if (weights[i] == 0) assertEq(units[i], 0);
            else assertGt(units[i], 0);
            assertEq(sleeve.totalUnits(i), units[i]);
            assertEq(IERC20(assets[i].token).balanceOf(address(sleeve)), units[i]);
            assertEq(IERC20(assets[i].token).allowance(address(sleeve), assets[i].exit), 0);
        }
        assertEq(assets[3].decimals, 8);
        assertGt(sleeve.balanceOf(account), 0);
        assertGt(IERC20(allocator.sleeves(2)).balanceOf(account), 0);
        _rebalance(334, 0, 0, [uint16(0), 0, 0, 0]);
        assertEq(sleeve.balanceOf(account), 0);
        assertEq(allocator.activeDeltaPoolOf(334), address(0));
        assertGt(IERC20(allocator.sleeves(2)).balanceOf(account), initialCashShares * 98 / 100);
        for (uint256 i; i < 4; ++i) {
            assertEq(sleeve.totalUnits(i), 0);
        }
    }

    function testAssetRemovalAndFullAllocation() public {
        _rebalance(334, 10000, 0, [uint16(2500), 2500, 2500, 2500]);
        assertEq(IERC20(allocator.sleeves(2)).balanceOf(collection.accountOf(334)), 0);
        _rebalance(334, 6000, 0, [uint16(0), 0, 0, 10000]);
        uint256[4] memory units = sleeve.unitsOf(334);
        assertEq(units[0], 0);
        assertEq(units[1], 0);
        assertEq(units[2], 0);
        assertGt(units[3], 0);
    }

    function testNFTTransferPreservesHoldingsAndOnlyCurrentOwnerCanSetTarget() public {
        _rebalance(334, 4000, 0, [uint16(10000), 0, 0, 0]);
        address previous = collection.nft().ownerOf(334);
        address next = makeAddr("commodity-new-owner");
        uint256[4] memory beforeUnits = sleeve.unitsOf(334);
        vm.prank(previous);
        nft.transferFrom(previous, next, 334);
        assertEq(sleeve.unitsOf(334)[0], beforeUnits[0]);
        vm.expectRevert(CommoditySleeve.Unauthorized.selector);
        vm.prank(previous);
        sleeve.setTarget(334, 5000, 0, [uint16(10000), 0, 0, 0]);
        _rebalance(334, 0, 0, [uint16(0), 0, 0, 0]);
    }

    function testUnauthorizedAndInvalidTargets() public {
        address owner = nft.ownerOf(334);
        address account = collection.accountOf(334);
        vm.expectRevert(CommoditySleeve.Unauthorized.selector);
        sleeve.setTarget(334, 4000, 0, [uint16(10000), 0, 0, 0]);
        vm.expectRevert(CommoditySleeve.InvalidTarget.selector);
        vm.prank(owner);
        sleeve.setTarget(334, 4000, 0, [uint16(9999), 0, 0, 0]);
        vm.expectRevert(CommoditySleeve.Unauthorized.selector);
        sleeve.deposit(1, account, 1, "");
    }

    function testSwapFailureRollsBackHoldingsAndExecutedRevision() public {
        _rebalance(334, 4000, 0, [uint16(10000), 0, 0, 0]);
        address owner = collection.nft().ownerOf(334);
        uint256[4] memory beforeUnits = sleeve.unitsOf(334);
        uint64 executed = allocator.allocationTargetOf(334).executedRevision;
        CollectionPortfolioAllocator.RebalanceExecution memory e =
            _execution(334, 4000, 0, [uint16(0), 10000, 0, 0]);
        CommoditySleeve.Execution memory deposit =
            abi.decode(e.allocations[1].sleeveData, (CommoditySleeve.Execution));
        deposit.minimumOutputs[1] = type(uint128).max;
        e.allocations[1].sleeveData = abi.encode(deposit);
        vm.prank(owner);
        sleeve.setTarget(334, 4000, 0, [uint16(0), 10000, 0, 0]);
        vm.prank(owner);
        uint64 revision = allocator.setTargetAllocation(
            334, [uint16(0), 4000, 6000], pool, 100, uint48(block.timestamp + 1 hours)
        );
        vm.expectRevert();
        vm.prank(owner);
        router.executeOwnerAllocation(334, revision, e);
        assertEq(sleeve.unitsOf(334)[0], beforeUnits[0]);
        assertEq(sleeve.unitsOf(334)[1], 0);
        assertEq(allocator.allocationTargetOf(334).executedRevision, executed);
    }

    function _rebalance(uint256 bank, uint16 allocation, uint16 lp, uint16[4] memory weights)
        private
    {
        CollectionPortfolioAllocator.RebalanceExecution memory e =
            _execution(bank, allocation, lp, weights);
        address owner = collection.nft().ownerOf(bank);
        vm.prank(owner);
        sleeve.setTarget(bank, allocation, lp, weights);
        vm.prank(owner);
        uint64 revision = allocator.setTargetAllocation(
            bank,
            [uint16(0), allocation + lp, 10000 - allocation - lp],
            allocation + lp == 0 ? address(0) : pool,
            100,
            uint48(block.timestamp + 1 hours)
        );
        vm.prank(owner);
        router.executeOwnerAllocation(bank, revision, e);
    }

    function _execution(uint256 bank, uint16 allocation, uint16 lp, uint16[4] memory weights)
        private
        returns (CollectionPortfolioAllocator.RebalanceExecution memory e)
    {
        if (IERC20(allocator.sleeves(2)).balanceOf(collection.accountOf(bank)) > 0) {
            e.redemptions[2].minimumOutputs = new uint256[](1);
            e.conversions = new CollectionPortfolioAllocator.ConversionCall[](1);
            e.conversions[0] = CollectionPortfolioAllocator.ConversionCall(USDG, 1, "");
        }
        if (sleeve.balanceOf(collection.accountOf(bank)) > 0) {
            CommoditySleeve.Redemption memory r;
            uint256[4] memory units = sleeve.unitsOf(bank);
            for (uint256 i; i < 4; ++i) {
                if (units[i] > 0) {
                    r.minimumOutputs[i] = 1;
                    if (i < 3) {
                        r.routeData[i] = abi.encode(StockDividendRoute.Conversion(1, "", ""));
                    }
                }
            }
            if (sleeve.lpUnitsOf(bank) > 0) {
                r.minimumLPWeth = 1;
                r.lpData = _lpExit();
            }
            e.deltaPoolRedemption.minimumOutputs = new uint256[](1);
            e.deltaPoolRedemption.minimumOutputs[0] = 1;
            e.deltaPoolRedemption.adapterCalls = new YieldBankAdapterRedemptionCall[](1);
            e.deltaPoolRedemption.adapterCalls[0] =
                YieldBankAdapterRedemptionCall(facade, 100, abi.encode(r));
        }
        if (allocation + lp > 0) {
            CommoditySleeve.Execution memory d;
            d.bank = bank;
            d.nonce = sleeve.targetOf(bank).nonce + 1;
            for (uint256 i; i < 4; ++i) {
                if (weights[i] > 0) {
                    d.minimumOutputs[i] = 1;
                    if (i < 3) {
                        d.routeData[i] = abi.encode(StockDividendRoute.Conversion(1, "", ""));
                    }
                }
            }
            if (lp > 0) {
                d.minimumLPUnits = 1;
                d.lpData = _lpEntry(
                    _bankValue(collection.accountOf(bank)) * 1 ether / _price(WETH) * lp / 10000
                );
            }
            e.allocations[1] = CollectionPortfolioAllocator.AllocationCall(1, 1, "", abi.encode(d));
        }
        if (allocation + lp < 10000) {
            e.allocations[2] = CollectionPortfolioAllocator.AllocationCall(1, 1, "", "");
        }
        e.minimumWethRecovered = 1;
        e.deadline = block.timestamp + 1 hours;
    }

    function _lpEntry(uint256 expectedWeth) private view returns (bytes memory) {
        uint256 working = expectedWeth * 9500 / 10000;
        uint256 convert = working / 2;
        uint256 pairedMin = _minimum(convert, WETH, INJOH, 200);
        (, int24 tick,,,,,) = IYieldBankV3Pool(INJOH_POOL).slot0();
        int24 spacing = IYieldBankV3Pool(INJOH_POOL).tickSpacing();
        int24 aligned = tick / spacing * spacing;
        IDeltaPositionBuilder.Rung[] memory rungs = new IDeltaPositionBuilder.Rung[](1);
        rungs[0] = IDeltaPositionBuilder.Rung(
            aligned - spacing * 1000,
            aligned + spacing * 1000,
            working - convert,
            pairedMin,
            (working - convert) * 9000 / 10000,
            pairedMin * 9000 / 10000
        );
        return abi.encode(
            StockCompositeLPAdapter.LPDeposit(
                working,
                1,
                abi.encode(
                    DeltaV3LPAdapter.DepositParams({
                        wethToConvert: convert,
                        minimumPairedAssetOut: pairedMin,
                        routeData: "",
                        rungs: rungs,
                        minimumCurrentTick: tick - spacing * 100,
                        maximumCurrentTick: tick + spacing * 100,
                        deadline: block.timestamp + 15 minutes
                    })
                )
            )
        );
    }

    function _lpExit() private returns (bytes memory) {
        uint256[] memory ids = lpAdapter.positionIds();
        DeltaV3LPAdapter.LiquidityAction[] memory actions =
            new DeltaV3LPAdapter.LiquidityAction[](ids.length);
        for (uint256 i; i < ids.length; ++i) {
            (,,,,,,, uint128 liquidity,,,,) =
                IYieldBankV3PositionManager(OLD_MANAGER).positions(ids[i]);
            actions[i] = DeltaV3LPAdapter.LiquidityAction(ids[i], liquidity, 1, 1);
        }
        uint256[] memory minimumOutputs = new uint256[](2);
        minimumOutputs[0] = 1;
        minimumOutputs[1] = 1;
        YieldBankAdapterRedemptionCall[] memory calls = new YieldBankAdapterRedemptionCall[](1);
        calls[0] = YieldBankAdapterRedemptionCall(
            address(lpAdapter),
            100,
            abi.encode(DeltaV3LPAdapter.ExitParams(actions, block.timestamp + 15 minutes))
        );
        // LP paired output is determined by exact position inventory, including accrued fees.
        // The fork obtains it by a reversible simulation, with the same immutable contracts.
        uint256 snapshot = vm.snapshotState();
        uint256 shares = sleeve.lpUnitsOf(334);
        uint256 pairedBefore = IERC20(INJOH).balanceOf(address(facade));
        vm.prank(address(sleeve));
        IERC20(address(lpVault)).approve(address(facade), shares);
        vm.prank(address(facade));
        lpVault.redeemManaged(shares, address(facade), address(sleeve), minimumOutputs, calls);
        uint256 pairedOut = IERC20(INJOH).balanceOf(address(facade)) - pairedBefore;
        uint256 minimumConverted = _minimum(pairedOut, INJOH, WETH, 100);
        assertTrue(vm.revertToState(snapshot));
        return abi.encode(
            StockCompositeLPAdapter.LPRedemption(minimumOutputs, calls, minimumConverted, "")
        );
    }

    function _minimum(uint256 amount, address input, address output, uint16 loss)
        private
        view
        returns (uint256)
    {
        return Math.mulDiv(
            Math.mulDiv(amount, _price(input), _price(output)),
            10000 - loss,
            10000,
            Math.Rounding.Ceil
        );
    }

    function _price(address asset) private view returns (uint256 price) {
        IPriceHub.FailureReason failure;
        (price,, failure) = hub.quoteUsd18(asset);
        require(
            failure == IPriceHub.FailureReason.NONE && price != 0, "real PriceHub quote unavailable"
        );
    }

    function _bankValue(address bank) private view returns (uint256) {
        MarketMakingSleeve usdgSleeve = MarketMakingSleeve(allocator.sleeves(2));
        (uint256 value,) = usdgSleeve.totalAssetsUsd18();
        return Math.mulDiv(value, usdgSleeve.balanceOf(bank), usdgSleeve.totalSupply());
    }

    function testSeparateBanksNeverShareCommodityUnits() public {
        _rebalance(334, 4000, 0, [uint16(10000), 0, 0, 0]);
        uint256 gold = sleeve.unitsOf(334)[0];
        _rebalance(336, 5000, 0, [uint16(0), 5000, 0, 5000]);
        assertEq(sleeve.unitsOf(334)[0], gold);
        assertEq(sleeve.unitsOf(336)[0], 0);
        assertEq(sleeve.totalUnits(0), gold);
        _rebalance(336, 0, 0, [uint16(0), 0, 0, 0]);
        assertEq(sleeve.unitsOf(334)[0], gold);
        assertEq(sleeve.totalUnits(1), 0);
        assertEq(sleeve.totalUnits(3), 0);
    }

    function testCommodityBasketWithRealLPAndExit() public {
        _rebalance(334, 3000, 2000, [uint16(2500), 2500, 2500, 2500]);
        assertGt(sleeve.lpUnitsOf(334), 0);
        assertEq(lpAdapter.positionIds().length, 1);
        _rebalance(334, 0, 0, [uint16(0), 0, 0, 0]);
        assertEq(sleeve.lpUnitsOf(334), 0);
        assertEq(sleeve.totalLPUnits(), 0);
        assertEq(lpAdapter.positionIds().length, 0);
    }
}
