// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { PonsAirdropClaimAdapter } from "../../src/yield-banks/airdrop/PonsAirdropClaimAdapter.sol";
import { DeltaV3TwapUsdFeed } from "../../src/yield-banks/adapters/DeltaV3TwapUsdFeed.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import {
    AirdropCompositeInfrastructureForkTest
} from "./AirdropCompositeInfrastructure.fork.t.sol";
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
import {
    AirdropCompositeSleeve as StockCompositeSleeve
} from "../../src/yield-banks/airdrop/AirdropCompositeSleeve.sol";
import { AirdropTargetBook } from "../../src/yield-banks/airdrop/AirdropTargetBook.sol";
import { AirdropVault } from "../../src/yield-banks/airdrop/AirdropVault.sol";
import { AirdropAssetRegistry } from "../../src/yield-banks/airdrop/AirdropAssetRegistry.sol";
import {
    SinjohAirdropClaimAdapter
} from "../../src/yield-banks/airdrop/SinjohAirdropClaimAdapter.sol";
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

/// @notice Existing bank backing, live stock token/Chainlink proxy, original INJOH LP venue.
/// Governance calls are simulated only on the fork. No oracle or stock token is mocked.
contract AirdropCompositeLifecycleForkTest is AirdropCompositeInfrastructureForkTest {
    address internal constant INJOH = 0x2cC0FAC44B8252f6B10208B091aFf2c94B4da77D;
    address private constant OLD_MANAGER = 0x73991a25C818Bf1f1128dEAaB1492D45638DE0D3;
    address private constant OLD_BUILDER = 0x6235cF6bd8419b34942F4EDDB39C880BD96dD700;
    address internal constant NVDA = 0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC;
    address private constant NVDA_POOL = 0x62AB521f71431f78ac374CdbadC6cda3c8916b6C;
    // Chainlink documentation's reference directory, retrieved 2026-09-14.
    address private constant NVDA_FEED = 0x379EC4f7C378F34a1B47E4F3cbeBCbAC3E8E9F15;
    address private constant AAPL = 0xaF3D76f1834A1d425780943C99Ea8A608f8a93f9;
    address private constant META = 0xc0D6457C16Cc70d6790Dd43521C899C87ce02f35;
    address constant MICRODUCK=0xD5f1afEA47b1A9eab414D2ee740cF1d6d039E725;
    address constant GG=0xcaCB0e9caCcee63ec4d82952E561a291c68Bcb68;
    uint8 internal airCount=1;
    address[] private chosenAir;
    uint16[] private chosenAirWeights;
    PriceHub internal hub;
    AirdropTargetBook internal book;
    AirdropVault internal airVault;
    MarketMakingSleeve internal lpVault;
    DeltaV3LPAdapter internal lpAdapter;
    StockDividendVault internal stockVault;

    function testExistingBankStockAndRealLPPositionRoundTrip() public {
        _roundTrip(1);
    }

    function testExistingBankTwoStockBasketAndRealLPPositionRoundTrip() public {
        _roundTrip(2);
    }

    function testExistingBankThreeStockBasketAndRealLPPositionRoundTrip() public {
        _roundTrip(3);
    }

    function testExistingBankTwoRealAirdropBasketAndThreeStocksRoundTrip() public {airCount=2;_roundTrip(3);}
    function testExistingBankThreeRealAirdropBasketAndThreeStocksRoundTrip() public {airCount=3;_roundTrip(3);}
    function _maximumCompositeLoss() internal view override returns(uint16){return airCount>1?500:200;}
    function _forkBlockNumber() internal view override returns(uint256){return airCount>1?63143073:super._forkBlockNumber();}
    function _roundTrip(uint8 count) private {
        _fork();
        DeltaPoolController controller =
            DeltaPoolController(address(ALLOCATOR.deltaPoolController()));
        _deployInfrastructure();
        _registerComposite(controller);
        _configure(controller);
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
        address[] memory airAssets = new address[](airCount);
        uint16[] memory airWeights = new uint16[](airCount);
        address[3] memory candidatesAir=[INJOH,MICRODUCK,GG];
        for(uint256 i;i<airCount;i++) {airAssets[i]=candidatesAir[i];airWeights[i]=uint16(10000/airCount+(i==airCount-1?10000%airCount:0));}
        chosenAir=airAssets;chosenAirWeights=airWeights;
        vm.prank(owner);
        book.setTarget(
            334,
            AirdropTargetBook.TargetInput(
                1000,
                3000,
                1000,
                AirdropTargetBook.Basket(assets, weights),
                AirdropTargetBook.Basket(airAssets, airWeights),
                uint48(block.timestamp + 1 hours)
            )
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
            minima[i] = Math.mulDiv(assigned, _price(WETH), _price(assets[i])) * (airCount>1?9500:9950) / 10000;
        }
        execution.allocations[1].minimumOutput = 1;
        execution.allocations[1].minimumShares = 1;
        execution.allocations[1].sleeveData = abi.encode(
            StockCompositeSleeve.DepositExecution({
                bank: 334,
                targetNonce: book.targetOf(334).nonce,
                minimumAirdropUnits: _airMinimum(bankWeth),
                airdropRouteData: new bytes[](airCount),
                minimumStockUnits: minima,
                stockRouteData: new bytes[](count),
                minimumLPUnits: 1,
                lpData: _lpEntry(bankWeth * 1000 / 10000)
            })
        );
        YieldBankSelfServiceExecutionRouter router =
            YieldBankSelfServiceExecutionRouter(ALLOCATOR.allocationOperator());
        vm.prank(owner);
        uint64 revision = ALLOCATOR.setTargetAllocation(
            334, [uint16(0), 5000, 5000], registrationPool, _maximumCompositeLoss(), uint48(block.timestamp + 1 hours)
        );
        vm.prank(owner);
        router.executeOwnerAllocation(334, revision, execution);
        (uint256 stockUnits,,,) = stockVault.positions(334, NVDA);
        assertGt(stockUnits, 0);
        assertEq(stockVault.accountedUnits(NVDA), stockUnits);
        assertEq(IERC20(NVDA).balanceOf(address(stockVault)), stockUnits);
        assertGt(composite.lpUnitsOf(334), 0);
        for(uint256 i;i<airCount;i++) {
            assertGt(airVault.principalOf(334,chosenAir[i]),0);
            assertEq(IERC20(chosenAir[i]).balanceOf(address(airVault.custodyOf(334,chosenAir[i]))),airVault.principalOf(334,chosenAir[i]));
        }
        assertGt(airVault.principalOf(334, INJOH), 0);
        assertEq(
            IERC20(INJOH).balanceOf(address(airVault.custodyOf(334, INJOH))),
            airVault.principalOf(334, INJOH)
        );
        assertGt(IERC20(ALLOCATOR.sleeves(2)).balanceOf(bank), 0);
        assertEq(lpAdapter.positionIds().length, 1);
        assertEq(
            IYieldBankV3PositionManager(OLD_MANAGER).ownerOf(lpAdapter.positionIds()[0]),
            address(lpAdapter)
        );
        assertEq(facade.lpPool(), INJOH_POOL);
        assertTrue(controller.isAllocationPool(INJOH_POOL));
        if (count == 3) _checkLPMaintenance();

        execution = _baseExecution();
        execution.deltaPoolRedemption.minimumOutputs = new uint256[](1);
        execution.deltaPoolRedemption.minimumOutputs[0] = 1;
        execution.deltaPoolRedemption.adapterCalls = new YieldBankAdapterRedemptionCall[](1);
        uint256[] memory stockExitMin = new uint256[](count);
        for (uint256 i; i < count; ++i) {
            (uint256 units,,,) = stockVault.positions(334, assets[i]);
            assertGt(units, 0);
            assertEq(IERC20(assets[i]).balanceOf(address(stockVault)), units);
            stockExitMin[i] = _minimum(units, assets[i], WETH, airCount>1?500:100);
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
            200,
            abi.encode(
                StockCompositeSleeve.RedemptionExecution(
                    stockExitMin,
                    new bytes[](count),
                    _airExitMinimum(),
                    new bytes[](airCount),
                    minLP,
                    _lpExit()
                )
            )
        );
        vm.prank(owner);
        revision = ALLOCATOR.setTargetAllocation(
            334, [uint16(0), 0, 10000], address(0), 100, uint48(block.timestamp + 1 hours)
        );
        execution.deltaPoolRedemption.adapterCalls[0].maxLossBps = 100;
        vm.prank(owner);
        vm.expectRevert();
        router.executeOwnerAllocation(334, revision, execution);
        assertGt(airVault.principalOf(334, INJOH), 0);
        execution.deltaPoolRedemption.adapterCalls[0].maxLossBps = _maximumCompositeLoss();
        vm.prank(owner);
        revision = ALLOCATOR.setTargetAllocation(
            334, [uint16(0), 0, 10000], address(0), _maximumCompositeLoss(), uint48(block.timestamp + 1 hours)
        );
        vm.prank(owner);
        router.executeOwnerAllocation(334, revision, execution);
        assertEq(composite.balanceOf(bank), 0);
        assertEq(composite.totalSupply(), 0);
        for(uint256 i;i<airCount;i++) assertEq(airVault.principalOf(334,chosenAir[i]),0);
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
        assertGe(_bankValue(bank), bankValue * 9800 / 10000, "round-trip loss exceeds owner limit");
    }

    function _airMinimum(uint256 bankWeth) private view returns (uint256[] memory values) {
        values = new uint256[](airCount);uint256 used;
        for(uint256 i;i<airCount;i++){
            uint256 assigned=i==airCount-1?bankWeth/10-used:bankWeth/10*chosenAirWeights[i]/10000;
            used+=assigned;values[i]=_minimum(assigned,WETH,chosenAir[i],airCount==1?100:500);
        }
    }

    function _airExitMinimum() private view returns (uint256[] memory values) {
        values = new uint256[](airCount);
        for(uint256 i;i<airCount;i++)values[i]=_minimum(airVault.principalOf(334,chosenAir[i]),chosenAir[i],WETH,_maximumCompositeLoss());
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

    function _configure(DeltaPoolController controller) internal {
        address governance = COLLECTION.collectionTimelock();
        hub = PriceHub(composite.priceHub());
        vm.prank(governance);
        hub.configureFeed(NVDA, NVDA_FEED, address(0), 86400, 0, true, true, 100);
        StockCorporateActionRegistry registry = new StockCorporateActionRegistry(governance);
        vm.prank(governance);
        registry.register(
            NVDA, keccak256("fork-only NVDA identity baseline, not production admission")
        );
        stockVault = new StockDividendVault(
            address(COLLECTION),
            address(composite),
            governance,
            USDG,
            address(registry),
            address(hub),
            100
        );
        vm.prank(governance);
        composite.configureVault(address(stockVault));
        address stockEntry = _route(NVDA_POOL, WETH, NVDA);
        address stockExit = _route(NVDA_POOL, NVDA, WETH);
        vm.prank(governance);
        composite.bindStockRoutes(NVDA, stockEntry, stockExit);
        _configureStock(
            registry,
            AAPL,
            0x8bb3514e2204E1cDF3Ac149EFEe7Ff04D91B719f,
            0x6B22A786bAa607d76728168703a39Ea9C99f2cD0
        );
        _configureStock(
            registry,
            META,
            0xa4BdB396a69617eb7F70E2cc1EF526f7340b1B0d,
            0x7C38C00C30BEe9378381E7B6135d7283356D71b1
        );
        lpVault = new MarketMakingSleeve(
            "Piggy Banks INJOH LP",
            "PB-INJOH-LP",
            WETH,
            address(facade),
            governance,
            composite.guardian(),
            address(hub),
            composite.strategyRegistry(),
            composite.eligibilityPolicy(),
            1,
            10000,
            100
        );
        address lpEntry = _route(INJOH_POOL, WETH, INJOH);
        address lpExit = _route(INJOH_POOL, INJOH, WETH);
        lpAdapter = new DeltaV3LPAdapter(
            DeltaV3LPAdapter.Config({
                sleeve: address(lpVault),
                weth: WETH,
                pairedAsset: INJOH,
                priceHub: address(hub),
                pool: INJOH_POOL,
                positionManager: OLD_MANAGER,
                positionBuilder: OLD_BUILDER,
                entryRoute: lpEntry,
                exitRoute: lpExit,
                poolCodeHash: INJOH_POOL.codehash,
                factoryCodeHash: OLD_FACTORY.codehash,
                positionManagerCodeHash: OLD_MANAGER.codehash,
                positionBuilderCodeHash: OLD_BUILDER.codehash,
                entryRouteCodeHash: lpEntry.codehash,
                exitRouteCodeHash: lpExit.codehash,
                maximumPositions: 64
            })
        );
        StrategyRegistry strategies = StrategyRegistry(composite.strategyRegistry());
        vm.prank(governance);
        strategies.register(address(lpAdapter), YieldBankIds.MARKET_MAKING);
        vm.prank(governance);
        lpVault.addAdapter(address(lpAdapter), 10000);
        vm.prank(governance);
        facade.configureLP(address(lpVault), address(lpAdapter), lpExit);
        AirdropAssetRegistry airRegistry =
            new AirdropAssetRegistry(governance, keccak256("fork-approved-catalog"));
        vm.prank(governance);
        airRegistry.register(INJOH, keccak256("fork-eligible-INJOH"));
        SinjohAirdropClaimAdapter claimAdapter = new SinjohAirdropClaimAdapter(
            0xA1d65242D367501D9A261389a69005e584F4786a,
            0x7E97EadeA120321c65CC09B6FDECc6Eb15D55b2f,
            INJOH,
            NVDA
        );
        vm.prank(governance);
        airRegistry.addClaimRoute(INJOH, address(claimAdapter));
        vm.prank(governance);
        airRegistry.setEnabled(INJOH, true);
        airVault = new AirdropVault(address(composite), address(COLLECTION), address(airRegistry));
        vm.prank(governance);
        composite.configureAirdropVault(address(airVault));
        book = new AirdropTargetBook(address(composite));
        vm.prank(governance);
        composite.configureTargetBook(address(book));
        vm.prank(governance);
        composite.bindAirdropRoutes(INJOH, lpEntry, lpExit);
        if(airCount>=2)_addRealAirdrop(airRegistry,MICRODUCK,0xb87C3c63b53d19984f3b4A927e26B667e32087E8,0xe25E9Bc31d24BB652Fb6E2E466d7c9c89701173e);
        if(airCount>=3)_addRealAirdrop(airRegistry,GG,0xd89F6933a8eF11C2939054c0e287eCb327817242,0x44dB4eCd5b0048d55c762E32FF53aFAEcCf75ed7);
        vm.prank(governance);
        controller.setPoolDepositsPaused(registrationPool, false);
    }

    function _addRealAirdrop(AirdropAssetRegistry registry,address asset,address pool,address distributor) private {
        address gov=COLLECTION.collectionTimelock();address wethFeed=hub.feedDetails(WETH).feed;
        DeltaV3TwapUsdFeed feed=new DeltaV3TwapUsdFeed(asset,WETH,pool,OLD_FACTORY,wethFeed,pool.codehash,OLD_FACTORY.codehash,wethFeed.codehash,1800,300,1e18,uint128(IYieldBankV3Pool(pool).liquidity()/2),"Airdrop V3 TWAP / USD");
        vm.prank(gov);hub.configureFeed(asset,address(feed),address(0),86400,0,false,false,300);
        vm.prank(gov);registry.register(asset,keccak256(abi.encode("fork-real-token",asset)));
        PonsAirdropClaimAdapter adapter=new PonsAirdropClaimAdapter(distributor,0xa125492aca28449D2291f5415A818697345cfA09);
        vm.prank(gov);registry.addClaimRoute(asset,address(adapter));vm.prank(gov);registry.setEnabled(asset,true);
        address entry=_route(pool,WETH,asset);address exit=_route(pool,asset,WETH);
        vm.prank(gov);composite.bindAirdropRoutes(asset,entry,exit);
    }

    function _configureStock(
        StockCorporateActionRegistry registry,
        address asset,
        address pool,
        address feed
    ) private {
        address governance = COLLECTION.collectionTimelock();
        vm.prank(governance);
        hub.configureFeed(asset, feed, address(0), 86400, 0, true, true, 100);
        vm.prank(governance);
        registry.register(asset, keccak256(abi.encode("fork-only identity baseline", asset)));
        address entry = _route(pool, WETH, asset);
        address exit = _route(pool, asset, WETH);
        vm.prank(governance);
        composite.bindStockRoutes(asset, entry, exit);
    }

    function _route(address pool, address input, address output) internal returns (address) {
        return address(
            new DeltaV3SinglePoolRoute(
                pool, OLD_FACTORY, input, output, pool.codehash, OLD_FACTORY.codehash
            )
        );
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
        uint256 minimumConverted = _minimum(pairedOut, INJOH, WETH, 200);
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
