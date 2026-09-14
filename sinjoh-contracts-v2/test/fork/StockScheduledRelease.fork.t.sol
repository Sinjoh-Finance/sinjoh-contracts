// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { stdStorage, StdStorage } from "forge-std/StdStorage.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { StockDividendAccounting } from "../../src/yield-banks/stock/StockDividendAccounting.sol";
import { StockDividendRoute } from "../../src/yield-banks/stock/StockDividendRoute.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Test } from "forge-std/Test.sol";
import { YieldBankCollection } from "../../src/yield-banks/YieldBankCollection.sol";
import {
    CollectionPortfolioAllocator
} from "../../src/yield-banks/CollectionPortfolioAllocator.sol";
import {
    YieldBankSelfServiceExecutionRouter
} from "../../src/yield-banks/YieldBankSelfServiceExecutionRouter.sol";
import { DeltaPoolController } from "../../src/yield-banks/DeltaPoolController.sol";
import { PriceHub } from "../../src/yield-banks/PriceHub.sol";
import { IPriceHub } from "../../src/yield-banks/interfaces/IPriceHub.sol";
import { StrategyRegistry } from "../../src/yield-banks/StrategyRegistry.sol";
import { YieldBankIds } from "../../src/yield-banks/libraries/YieldBankIds.sol";
import { MarketMakingSleeve } from "../../src/yield-banks/sleeves/MarketMakingSleeve.sol";
import { DeltaV3LPAdapter } from "../../src/yield-banks/adapters/DeltaV3LPAdapter.sol";
import { DeltaV3SinglePoolRoute } from "../../src/yield-banks/adapters/DeltaV3SinglePoolRoute.sol";
import { StockCompositeSleeve } from "../../src/yield-banks/stock/StockCompositeSleeve.sol";
import { StockCompositeLPAdapter } from "../../src/yield-banks/stock/StockCompositeLPAdapter.sol";
import { StockDividendVault } from "../../src/yield-banks/stock/StockDividendVault.sol";
import {
    StockCorporateActionRegistry
} from "../../src/yield-banks/stock/StockCorporateActionRegistry.sol";
import { IDeltaPositionBuilder } from "../../src/yield-banks/interfaces/IDeltaPositionBuilder.sol";
import {
    IYieldBankV3Pool,
    IYieldBankV3PositionManager
} from "../../src/yield-banks/interfaces/IYieldBankV3.sol";
import {
    YieldBankAdapterRedemptionCall
} from "../../src/yield-banks/interfaces/IYieldBankManagedSleeve.sol";

/// @notice Replays the exact scheduled mainnet activation, then existing-bank lifecycle.
/// Only the three-stock case includes an explicitly mocked issuer dividend transition.
contract StockScheduledReleaseForkTest is Test {
    YieldBankCollection internal constant COLLECTION =
        YieldBankCollection(0xc275fa302Cd53DFa42D41b1C5b770661d923ba43);
    CollectionPortfolioAllocator internal constant ALLOCATOR =
        CollectionPortfolioAllocator(0x42e14eA9f926ad7b530ce49d433CB6f748f8D0a1);
    address internal constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    address internal constant USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;
    address internal constant OLD_FACTORY = 0x1f7d7550B1b028f7571E69A784071F0205FD2EfA;
    address internal constant INJOH_POOL = 0xB09fa4f04032b9d9e690ac4a1d29523b5f9A72DC;
    address internal registrationPool;
    StockCompositeSleeve internal composite;
    StockCompositeLPAdapter internal facade;
    using stdStorage for StdStorage;
    bool private simulateBlockedPayment;
    address private constant INJOH = 0x2cC0FAC44B8252f6B10208B091aFf2c94B4da77D;
    address private constant OLD_MANAGER = 0x73991a25C818Bf1f1128dEAaB1492D45638DE0D3;
    address private constant OLD_BUILDER = 0x6235cF6bd8419b34942F4EDDB39C880BD96dD700;
    address private constant NVDA = 0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC;
    address private constant NVDA_POOL = 0x62AB521f71431f78ac374CdbadC6cda3c8916b6C;
    // Chainlink documentation's reference directory, retrieved 2026-09-14.
    address private constant NVDA_FEED = 0x379EC4f7C378F34a1B47E4F3cbeBCbAC3E8E9F15;
    address private constant AAPL = 0xaF3D76f1834A1d425780943C99Ea8A608f8a93f9;
    address private constant META = 0xc0D6457C16Cc70d6790Dd43521C899C87ce02f35;
    PriceHub private hub;
    MarketMakingSleeve private lpVault;
    DeltaV3LPAdapter private lpAdapter;
    StockDividendVault private stockVault;

    function testExistingBankStockAndRealLPPositionRoundTrip() public {
        _roundTrip(1);
    }

    function testExistingBankTwoStockBasketAndRealLPPositionRoundTrip() public {
        _roundTrip(2);
    }

    function testExistingBankThreeStockBasketAndRealLPPositionRoundTrip() public {
        _roundTrip(3);
    }

    function testExistingBankBlockedDividendPaymentSurvivesNftTransfer() public {
        simulateBlockedPayment = true;
        _roundTrip(3);
    }

    function _roundTrip(uint8 count) private {
        _activateScheduledRelease();
        DeltaPoolController controller =
            DeltaPoolController(address(ALLOCATOR.deltaPoolController()));
        address owner = COLLECTION.nft().ownerOf(334);
        address bank = COLLECTION.accountOf(334);
        uint96 feeWeight = COLLECTION.feeWeightOf(334);
        uint256 initialInjoh = IERC20(INJOH).balanceOf(bank);
        uint256 supply = COLLECTION.liveSupply();
        address[] memory assets = new address[](count);
        uint16[] memory weights = new uint16[](count);
        address[3] memory candidates = [NVDA, AAPL, META];
        for (uint256 i; i < count; ++i) {
            assets[i] = candidates[i];
            weights[i] = uint16(10000 / count + (i == 0 ? 10000 % count : 0));
        }
        vm.prank(owner);
        composite.setTarget(
            334, 2000, 3000, count > 1, assets, weights, uint48(block.timestamp + 1 hours)
        );
        uint256 bankValue = _bankValue(bank);
        uint256 bankWeth = Math.mulDiv(bankValue, 1 ether, _price(WETH));
        CollectionPortfolioAllocator.RebalanceExecution memory execution = _baseExecution();
        uint256[] memory minima = new uint256[](count);
        uint256 availableStock = bankWeth * 3000 / 10000;
        uint256 used;
        for (uint256 i; i < count; ++i) {
            uint256 assigned =
                i == count - 1 ? availableStock - used : availableStock * weights[i] / 10000;
            used += assigned;
            minima[i] = Math.mulDiv(assigned, _price(WETH), _price(assets[i])) * 9950 / 10000;
        }
        execution.allocations[1].minimumOutput = 1;
        execution.allocations[1].minimumShares = 1;
        execution.allocations[1].sleeveData = abi.encode(
            StockCompositeSleeve.DepositExecution({
                bank: 334,
                targetNonce: composite.targetOf(334).nonce,
                minimumStockUnits: minima,
                stockRouteData: new bytes[](count),
                minimumLPUnits: 1,
                lpData: _lpEntry(bankWeth * 2000 / 10000)
            })
        );
        YieldBankSelfServiceExecutionRouter router =
            YieldBankSelfServiceExecutionRouter(ALLOCATOR.allocationOperator());
        vm.prank(owner);
        uint64 revision = ALLOCATOR.setTargetAllocation(
            334, [uint16(0), 5000, 5000], registrationPool, 100, uint48(block.timestamp + 1 hours)
        );
        vm.prank(owner);
        router.executeOwnerAllocation(334, revision, execution);
        (uint256 stockUnits,,,) = stockVault.positions(334, NVDA);
        assertGt(stockUnits, 0);
        assertEq(stockVault.accountedUnits(NVDA), stockUnits);
        assertEq(IERC20(NVDA).balanceOf(address(stockVault)), stockUnits);
        assertGt(composite.lpUnitsOf(334), 0);
        assertGt(IERC20(ALLOCATOR.sleeves(2)).balanceOf(bank), 0);
        assertEq(lpAdapter.positionIds().length, 1);
        assertEq(
            IYieldBankV3PositionManager(OLD_MANAGER).ownerOf(lpAdapter.positionIds()[0]),
            address(lpAdapter)
        );
        assertEq(facade.lpPool(), INJOH_POOL);
        assertTrue(controller.isAllocationPool(INJOH_POOL));
        if (count == 3) {
            _checkLPMaintenance();
            _exerciseDividend();
        }

        execution = _baseExecution();
        execution.deltaPoolRedemption.minimumOutputs = new uint256[](1);
        execution.deltaPoolRedemption.minimumOutputs[0] = 1;
        execution.deltaPoolRedemption.adapterCalls = new YieldBankAdapterRedemptionCall[](1);
        uint256[] memory stockExitMin = new uint256[](count);
        for (uint256 i; i < count; ++i) {
            (uint256 units,,,) = stockVault.positions(334, assets[i]);
            assertGt(units, 0);
            assertEq(IERC20(assets[i]).balanceOf(address(stockVault)), units);
            stockExitMin[i] = _minimum(units, assets[i], WETH, 100);
        }
        (uint256 lpPrice,) = facade.lpUnitPriceUsd18();
        uint256 minLP = Math.mulDiv(
            Math.mulDiv(composite.lpUnitsOf(334), lpPrice, _price(WETH)),
            9900,
            10000,
            Math.Rounding.Ceil
        );
        execution.deltaPoolRedemption.adapterCalls[0] = YieldBankAdapterRedemptionCall(
            address(facade),
            100,
            abi.encode(
                StockCompositeSleeve.RedemptionExecution(
                    stockExitMin, new bytes[](count), minLP, _lpExit()
                )
            )
        );
        vm.prank(owner);
        revision = ALLOCATOR.setTargetAllocation(
            334, [uint16(0), 0, 10000], address(0), 100, uint48(block.timestamp + 1 hours)
        );
        vm.prank(owner);
        router.executeOwnerAllocation(334, revision, execution);
        assertEq(composite.balanceOf(bank), 0);
        assertEq(composite.totalSupply(), 0);
        for (uint256 i; i < count; ++i) {
            assertEq(stockVault.accountedUnits(assets[i]), 0);
        }
        assertEq(lpAdapter.positionIds().length, 0);
        assertEq(lpVault.totalSupply(), 0);
        assertEq(ALLOCATOR.activeDeltaPoolOf(334), address(0));
        assertEq(COLLECTION.accountOf(334), bank);
        assertEq(COLLECTION.nft().ownerOf(334), owner);
        assertEq(COLLECTION.feeWeightOf(334), feeWeight);
        assertEq(COLLECTION.liveSupply(), supply);
        assertEq(IERC20(INJOH).balanceOf(bank), initialInjoh);
    }

    function _checkLPMaintenance() private {
        uint256 beforeShares = lpVault.totalSupply();
        uint256 idle = IERC20(WETH).balanceOf(address(lpVault));
        StockCompositeLPAdapter.LPDeposit memory deployment =
            abi.decode(_lpEntry(idle), (StockCompositeLPAdapter.LPDeposit));
        vm.prank(address(0xBAD));
        vm.expectRevert(StockCompositeLPAdapter.Unauthorized.selector);
        facade.rebalanceLP(
            0,
            100,
            "",
            deployment.assetsToDeploy,
            deployment.minimumPositionUnits,
            deployment.adapterData
        );
        address governance = COLLECTION.collectionTimelock();
        vm.prank(governance);
        facade.rebalanceLP(
            0,
            100,
            "",
            deployment.assetsToDeploy,
            deployment.minimumPositionUnits,
            deployment.adapterData
        );
        assertEq(lpAdapter.positionIds().length, 2);
        assertEq(lpVault.totalSupply(), beforeShares);
        facade.collectLP(abi.encode(lpAdapter.positionIds()));
        assertEq(lpVault.totalSupply(), beforeShares);
    }

    /// The sole activation cheat is marking THIS queued operation ready in the local fork.
    /// No bank balances, market prices, pool liquidity, code, or contract nonces are replaced.
    function _activateScheduledRelease() private {
        string memory rpc = vm.envOr("ROBINHOOD_MAINNET_RPC_URL", string(""));
        if (bytes(rpc).length == 0) vm.skip(true);
        vm.createSelectFork(rpc, vm.envUint("STOCK_FORK_BLOCK"));
        assertEq(block.chainid, 4663);
        string memory preparation = vm.readFile("deployments/piggy-banks-stock-preparation.json");
        bytes memory payload = vm.parseJsonBytes(preparation, ".executeCalldata");
        address gov = vm.parseJsonAddress(preparation, ".governance");
        bytes32 operation = 0xdf428b6330c22c6029ed837808480ee237fc3c797202a015d03c09f1aef28bf3;
        TimelockController timelock = TimelockController(payable(gov));
        assertTrue(timelock.isOperationPending(operation));
        assertFalse(timelock.isOperationReady(operation));
        assertEq(timelock.getTimestamp(operation), 1789482538);
        bytes32 oldInfra = _oldInfra();
        address bank = COLLECTION.accountOf(334);
        uint256 originalBacking = IERC20(ALLOCATOR.sleeves(2)).balanceOf(bank);
        stdstore.target(gov).sig("getTimestamp(bytes32)").with_key(operation)
            .checked_write(block.timestamp);
        vm.prank(vm.parseJsonAddress(preparation, ".deployer"));
        (bool ok, bytes memory reason) = gov.call(payload);
        if (!ok) assembly ("memory-safe") { revert(add(reason, 32), mload(reason)) }
        assertTrue(timelock.isOperationDone(operation));
        assertEq(_oldInfra(), oldInfra);
        assertEq(IERC20(ALLOCATOR.sleeves(2)).balanceOf(bank), originalBacking);
        composite = StockCompositeSleeve(vm.parseJsonAddress(preparation, ".composite"));
        facade = StockCompositeLPAdapter(vm.parseJsonAddress(preparation, ".facade"));
        registrationPool = vm.parseJsonAddress(preparation, ".registrationPool");
        hub = PriceHub(composite.priceHub());
        stockVault = StockDividendVault(vm.parseJsonAddress(preparation, ".vault"));
        lpVault = MarketMakingSleeve(vm.parseJsonAddress(preparation, ".lpVault"));
        lpAdapter = DeltaV3LPAdapter(vm.parseJsonAddress(preparation, ".lpAdapter"));
        assertFalse(composite.depositsPaused());
        assertEq(address(composite.stockVault()), address(stockVault));
        assertEq(composite.portfolioAdapter(), address(facade));
    }

    function _oldInfra() private view returns (bytes32) {
        (bool ok, bytes memory data) = address(ALLOCATOR.deltaPoolController())
            .staticcall(abi.encodeWithSignature("infrastructureOfFactory(address)", OLD_FACTORY));
        require(ok);
        return keccak256(data);
    }

    /// Controlled issuer-transition fixture; actual deployed vault, escrow, routes, tokens,
    /// liquidity, price feeds and existing bank capital. This is not a real issuer dividend.
    function _exerciseDividend() private {
        address owner = COLLECTION.nft().ownerOf(334);
        (uint256 beforePrincipal,,,) = stockVault.positions(334, NVDA);
        StockCorporateActionRegistry registry = stockVault.registry();
        (, uint256 beforeMultiplier) = registry.requireCurrent(NVDA, false);
        uint256 afterMultiplier = beforeMultiplier + beforeMultiplier / 500; // 0.2% fixture
        vm.mockCall(NVDA, abi.encodeWithSignature("uiMultiplier()"), abi.encode(afterMultiplier));
        address account = COLLECTION.accountOf(334);
        vm.expectRevert(StockCorporateActionRegistry.AssetNotCurrent.selector);
        composite.balanceOf(account);
        vm.prank(COLLECTION.collectionTimelock());
        registry.publish(
            NVDA,
            StockCorporateActionRegistry.Action(
                beforeMultiplier,
                afterMultiplier,
                uint48(block.timestamp),
                StockDividendAccounting.ActionKind.CashDividend,
                keccak256("fork-only controlled issuer evidence"),
                keccak256("fork-only dividend source")
            )
        );
        stockVault.checkpoint(334, NVDA, 32);
        (uint256 principal, uint256 reserved,,) = stockVault.positions(334, NVDA);
        assertGt(reserved, 0);
        assertEq(principal + reserved, beforePrincipal);
        uint256 inputBefore = IERC20(NVDA).balanceOf(address(stockVault));
        uint256 cashBefore = IERC20(USDG).balanceOf(owner);
        uint256 nonceBefore = stockVault.settlementNonce();
        // Failed conversion must preserve both principal and reserve; then retry successfully.
        vm.expectRevert();
        stockVault.settleDividend(334, NVDA, reserved, type(uint256).max / 2, "");
        assertEq(IERC20(NVDA).balanceOf(address(stockVault)), inputBefore);
        assertEq(stockVault.settlementNonce(), nonceBefore);
        (uint256 p, uint256 r,,) = stockVault.positions(334, NVDA);
        assertEq(p, principal);
        assertEq(r, reserved);
        uint256 cashQuote =
            Math.mulDiv(Math.mulDiv(reserved, _price(NVDA), 1 ether), 1e6, _price(USDG));
        uint256 wethMin = Math.mulDiv(
            Math.mulDiv(reserved, _price(NVDA), _price(WETH)), 9900, 10000, Math.Rounding.Ceil
        );
        bytes memory data = abi.encode(StockDividendRoute.Conversion(wethMin, "", ""));
        if (simulateBlockedPayment) {
            vm.mockCall(
                USDG,
                abi.encodePacked(IERC20.transfer.selector, abi.encode(owner)),
                abi.encode(false)
            );
        }
        uint256 proceeds = stockVault.settleDividend(
            334, NVDA, reserved, Math.mulDiv(cashQuote, 9900, 10000, Math.Rounding.Ceil), data
        );
        assertGt(proceeds, 0);
        if (simulateBlockedPayment) {
            assertEq(IERC20(USDG).balanceOf(owner), cashBefore);
            assertEq(stockVault.escrow().creditOf(owner), proceeds);
            assertEq(IERC20(USDG).balanceOf(address(stockVault.escrow())), proceeds);
            address buyer = address(0xB0B);
            IERC721 nft = IERC721(address(COLLECTION.nft()));
            vm.prank(owner);
            nft.transferFrom(owner, buyer, 334);
            vm.clearMockedCalls();
            vm.mockCall(
                NVDA, abi.encodeWithSignature("uiMultiplier()"), abi.encode(afterMultiplier)
            );
            stockVault.escrow().pay(owner);
            assertEq(stockVault.escrow().creditOf(buyer), 0);
            vm.prank(buyer);
            nft.transferFrom(buyer, owner, 334);
        }
        assertEq(IERC20(USDG).balanceOf(owner), cashBefore + proceeds);
        assertEq(stockVault.escrow().creditOf(owner), 0);
        assertEq(stockVault.escrow().totalCredits(), 0);
        (p, r,,) = stockVault.positions(334, NVDA);
        assertEq(p, principal);
        assertEq(r, 0);
        assertEq(IERC20(NVDA).balanceOf(address(stockVault)), inputBefore - reserved);
        assertEq(stockVault.accountedUnits(NVDA), inputBefore - reserved);
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
        uint256 shares = composite.lpUnitsOf(334);
        uint256 pairedBefore = IERC20(INJOH).balanceOf(address(facade));
        vm.prank(address(composite));
        IERC20(address(lpVault)).approve(address(facade), shares);
        vm.prank(address(facade));
        lpVault.redeemManaged(shares, address(facade), address(composite), minimumOutputs, calls);
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
        MarketMakingSleeve usdgSleeve = MarketMakingSleeve(ALLOCATOR.sleeves(2));
        (uint256 value,) = usdgSleeve.totalAssetsUsd18();
        return Math.mulDiv(value, usdgSleeve.balanceOf(bank), usdgSleeve.totalSupply());
    }

    function _baseExecution()
        private
        view
        returns (CollectionPortfolioAllocator.RebalanceExecution memory execution)
    {
        execution.redemptions[2].minimumOutputs = new uint256[](1);
        execution.redemptions[2].minimumOutputs[0] = 1;
        execution.conversions = new CollectionPortfolioAllocator.ConversionCall[](1);
        execution.conversions[0] = CollectionPortfolioAllocator.ConversionCall(USDG, 1, "");
        execution.allocations[2].minimumOutput = 1;
        execution.allocations[2].minimumShares = 1;
        execution.minimumWethRecovered = 1;
        execution.deadline = block.timestamp + 1 hours;
    }
}
