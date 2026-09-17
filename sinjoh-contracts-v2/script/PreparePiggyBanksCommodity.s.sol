// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;
import {
    StockDividendRoute as CommodityTwoHopRoute
} from "../src/yield-banks/stock/StockDividendRoute.sol";
import { Script } from "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { YieldBankCollection } from "../src/yield-banks/YieldBankCollection.sol";
import { CollectionPortfolioAllocator } from "../src/yield-banks/CollectionPortfolioAllocator.sol";
import { DeltaPoolController } from "../src/yield-banks/DeltaPoolController.sol";
import {
    YieldBankSelfServiceExecutionRouter
} from "../src/yield-banks/YieldBankSelfServiceExecutionRouter.sol";
import { PriceHub } from "../src/yield-banks/PriceHub.sol";
import { IPriceHub } from "../src/yield-banks/interfaces/IPriceHub.sol";
import { StrategyRegistry } from "../src/yield-banks/StrategyRegistry.sol";
import { YieldBankIds } from "../src/yield-banks/libraries/YieldBankIds.sol";
import { IYieldBankV3Pool } from "../src/yield-banks/interfaces/IYieldBankV3.sol";
import { IDeltaPositionBuilder } from "../src/yield-banks/interfaces/IDeltaPositionBuilder.sol";
import { MarketMakingSleeve } from "../src/yield-banks/sleeves/MarketMakingSleeve.sol";
import { DeltaV3LPAdapter } from "../src/yield-banks/adapters/DeltaV3LPAdapter.sol";
import { DeltaV3SinglePoolRoute } from "../src/yield-banks/adapters/DeltaV3SinglePoolRoute.sol";
import { DeltaV3TwapUsdFeed } from "../src/yield-banks/adapters/DeltaV3TwapUsdFeed.sol";
import { CommoditySleeve } from "../src/yield-banks/commodity/CommoditySleeve.sol";
import { StockCompositeLPAdapter } from "../src/yield-banks/stock/StockCompositeLPAdapter.sol";
import {
    StockInfrastructureBuilder,
    StockInfrastructurePositionDescriptor
} from "../src/yield-banks/stock/StockInfrastructureBuilder.sol";

interface IStockPrepareFactory {
    function createPool(address, address, uint24) external returns (address);
    function enableFeeAmount(uint24, int24) external;
    function setOwner(address) external;
}

interface IStockPreparePool {
    function initialize(uint160) external;
}

interface IStockPrepareWETH {
    function deposit() external payable;
}

interface IStockPrepareNFT {
    function transferFrom(address, address, uint256) external;
}

interface IStockPrepareTimelock {
    function getMinDelay() external view returns (uint256);
}

/// @notice Deploy-only preparation plus a locally simulated, atomic 24h timelock activation.
/// @dev --broadcast deploys auxiliary infrastructure with the deployer; it NEVER impersonates
/// governance onchain. The resulting schedule/execute calldata requires the existing governance
/// signer. No owner allocation is included. Run without --broadcast first and review the artifact.
contract PreparePiggyBanksCommodity is Script {
    YieldBankCollection constant COLLECTION =
        YieldBankCollection(0xc275fa302Cd53DFa42D41b1C5b770661d923ba43);
    CollectionPortfolioAllocator constant ALLOCATOR =
        CollectionPortfolioAllocator(0x42e14eA9f926ad7b530ce49d433CB6f748f8D0a1);
    address constant DEPLOYER = 0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49;
    address constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    address constant USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;
    address constant INJOH = 0x2cC0FAC44B8252f6B10208B091aFf2c94B4da77D;
    address constant OLD_FACTORY = 0x1f7d7550B1b028f7571E69A784071F0205FD2EfA;
    address constant OLD_MANAGER = 0x73991a25C818Bf1f1128dEAaB1492D45638DE0D3;
    address constant OLD_BUILDER = 0x6235cF6bd8419b34942F4EDDB39C880BD96dD700;
    address constant USDG_POOL = 0x52e65B17fB6E5BA00Ed806f37Afcd2DaA50271Ca;
    address constant INJOH_POOL = 0xB09fa4f04032b9d9e690ac4a1d29523b5f9A72DC;
    address governance;
    DeltaPoolController controller;
    PriceHub hub;
    address factory;
    address manager;
    address builder;
    address pool;
    address composite;
    address facade;
    address lpVault;
    address lpAdapter;
    address lpExit;
    address[] targets;
    bytes[] payloads;
    address[] stocks;
    address[] pools;
    address[] entries;
    address[] exits;
    bytes32 originalInfrastructureHash;
    uint64 controllerNonce;

    function run() external {
        require(block.chainid == 4663, "wrong chain");
        governance = COLLECTION.collectionTimelock();
        controller = DeltaPoolController(address(ALLOCATOR.deltaPoolController()));
        hub = PriceHub(address(controller.priceHub()));
        require(governance == 0x7C15804A2d7F5981035895CAb953e5E76393E1B8, "governance changed");
        require(controller.isAllocationPool(INJOH_POOL), "existing LP unavailable");
        (bool ok, bytes memory original) = address(controller)
            .staticcall(abi.encodeWithSignature("infrastructureOfFactory(address)", OLD_FACTORY));
        require(ok);
        originalInfrastructureHash = keccak256(original);
        stocks.push(0xC9a981FEE1F9DEc688bb123ccDeCc63D0deBFC4e);
        stocks.push(0x411eFb0E7f985935DAec3D4C3ebaEa0d0AD7D89f);
        stocks.push(0xa30FA36Db767ad9eD3f7a60fC79526fB4d56D344);
        stocks.push(0xCEC185eB182c47d1bA1EFc84e6959e18cd620Be4);
        pools.push(0xBA2f1ed4cEB2169D538d1e614D847E83C5A55913);
        pools.push(0x8cB787e6c315D464775289BaD00FDD67d53Ecb3D);
        pools.push(0x02175608F1b5E6b5ed221cCFdC7Be197D111D915);
        pools.push(0xD30e44aaE604B42a63f6F9A8109FD0408F35b9fb);
        for (uint256 i; i < 4; ++i) {
            require(IYieldBankV3Pool(pools[i]).liquidity() > 0, "commodity pool empty");
        }
        controllerNonce = vm.getNonce(address(controller));
        // materializePool creates entry route, exit route, sleeve, then adapter.
        composite = vm.computeCreateAddress(address(controller), controllerNonce + 2);
        facade = vm.computeCreateAddress(address(controller), controllerNonce + 3);
        require(composite.code.length == 0 && facade.code.length == 0, "prediction occupied");
        vm.startBroadcast(DEPLOYER);
        _deployInfrastructure();
        lpVault = address(
            new MarketMakingSleeve(
                "Piggy Banks INJOH LP",
                "PB-INJOH-LP",
                WETH,
                facade,
                governance,
                controller.guardian(),
                address(hub),
                address(controller.strategyRegistry()),
                controller.eligibilityPolicy(),
                1,
                10000,
                100
            )
        );
        address lpEntry = _route(INJOH_POOL, WETH, INJOH);
        lpExit = _route(INJOH_POOL, INJOH, WETH);
        lpAdapter = address(
            new DeltaV3LPAdapter(
                DeltaV3LPAdapter.Config({
                    sleeve: lpVault,
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
            )
        );
        address buyCash = _route(USDG_POOL, WETH, USDG);
        address sellCash = _route(USDG_POOL, USDG, WETH);
        for (uint256 i; i < 4; ++i) {
            if (i == 3) {
                entries.push(_route(pools[i], WETH, stocks[i]));
                exits.push(_route(pools[i], stocks[i], WETH));
            } else {
                entries.push(
                    address(new CommodityTwoHopRoute(buyCash, _route(pools[i], USDG, stocks[i])))
                );
                exits.push(
                    address(new CommodityTwoHopRoute(_route(pools[i], stocks[i], USDG), sellCash))
                );
            }
        }
        vm.stopBroadcast();
        _activation();
        // Local-only simulation. This operation is never recorded for the deployer to broadcast.
        for (uint256 i; i < targets.length; ++i) {
            vm.prank(governance);
            (bool success, bytes memory reason) = targets[i].call(payloads[i]);
            if (!success) assembly ("memory-safe") { revert(add(reason, 32), mload(reason)) }
        }
        (bool preserved, bytes memory infrastructure) = address(controller)
            .staticcall(abi.encodeWithSignature("infrastructureOfFactory(address)", OLD_FACTORY));
        require(
            preserved && keccak256(infrastructure) == originalInfrastructureHash,
            "existing LP infrastructure changed"
        );
        require(controller.isAllocationPool(INJOH_POOL), "existing LP became unavailable");
        _writePlan();
    }

    function _deployInfrastructure() private {
        factory = _artifact("UniswapV3Factory", "");
        address descriptor = address(new StockInfrastructurePositionDescriptor());
        manager = _artifact("NonfungiblePositionManager", abi.encode(factory, WETH, descriptor));
        builder = address(new StockInfrastructureBuilder(factory, manager, WETH));
        IStockPrepareFactory(factory).enableFeeAmount(100, 1);
        pool = IStockPrepareFactory(factory).createPool(WETH, USDG, 100);
        (uint160 sqrtPrice, int24 tick,,,,,) = IYieldBankV3Pool(USDG_POOL).slot0();
        IStockPreparePool(pool).initialize(sqrtPrice);
        // Fixed 0.01 ETH infrastructure budget from the authorized deployer, never bank backing.
        IStockPrepareWETH(WETH).deposit{ value: 0.01 ether }();
        address route = _route(USDG_POOL, WETH, USDG);
        (uint256 wethPrice,, IPriceHub.FailureReason wf) = hub.quoteUsd18(WETH);
        (uint256 usdgPrice,, IPriceHub.FailureReason uf) = hub.quoteUsd18(USDG);
        require(
            wf == IPriceHub.FailureReason.NONE && uf == IPriceHub.FailureReason.NONE,
            "bootstrap price unavailable"
        );
        uint256 minimum = Math.mulDiv(Math.mulDiv(0.005 ether, wethPrice, 1 ether), 1e6, usdgPrice)
            * 9900 / 10000;
        IERC20(WETH).approve(route, 0.005 ether);
        uint256 cash = DeltaV3SinglePoolRoute(route).convert(0.005 ether, minimum, DEPLOYER, "");
        IERC20(WETH).approve(builder, 0.005 ether);
        IERC20(USDG).approve(builder, cash);
        IDeltaPositionBuilder.Rung[] memory rungs = new IDeltaPositionBuilder.Rung[](1);
        rungs[0] = IDeltaPositionBuilder.Rung(tick - 1000, tick + 1000, 0.005 ether, cash, 1, 1);
        uint256[] memory ids = StockInfrastructureBuilder(builder)
            .mintLadder(pool, rungs, tick - 1, tick + 1, block.timestamp + 15 minutes);
        IStockPrepareNFT(manager).transferFrom(DEPLOYER, governance, ids[0]);
        IStockPrepareFactory(factory).setOwner(governance);
    }

    function _activation() private {
        _call(
            address(controller),
            abi.encodeCall(
                DeltaPoolController.configureInfrastructure,
                (
                    factory,
                    DeltaPoolController.InfrastructureConfig({
                        positionManager: manager,
                        positionBuilder: builder,
                        factoryRuntimeCodeHash: factory.codehash,
                        positionManagerRuntimeCodeHash: manager.codehash,
                        positionBuilderRuntimeCodeHash: builder.codehash,
                        routeCreationCodeHash: keccak256(type(DeltaV3SinglePoolRoute).creationCode),
                        sleeveCreationCodeHash: keccak256(type(CommoditySleeve).creationCode),
                        adapterCreationCodeHash: keccak256(
                            type(StockCompositeLPAdapter).creationCode
                        ),
                        feedCreationCodeHash: keccak256(type(DeltaV3TwapUsdFeed).creationCode)
                    })
                )
            )
        );
        bytes memory materialize = abi.encodeCall(
            DeltaPoolController.materializePool,
            (
                pool,
                DeltaPoolController.MaterializationConfig(
                    1, controller.maximumAdapterCapBps(), 100
                ),
                type(DeltaV3SinglePoolRoute).creationCode,
                type(CommoditySleeve).creationCode,
                type(StockCompositeLPAdapter).creationCode
            )
        );
        _call(
            ALLOCATOR.allocationOperator(),
            abi.encodeCall(
                YieldBankSelfServiceExecutionRouter.executeGovernanceCall,
                (address(controller), materialize)
            )
        );
        address[4] memory tokens_;
        address[4] memory pools_;
        address[4] memory entries_;
        address[4] memory exits_;
        for (uint256 i; i < 4; ++i) {
            tokens_[i] = stocks[i];
            pools_[i] = pools[i];
            entries_[i] = entries[i];
            exits_[i] = exits[i];
        }
        _call(
            composite,
            abi.encodeCall(CommoditySleeve.configureAssets, (tokens_, pools_, entries_, exits_))
        );
        _call(
            address(controller.strategyRegistry()),
            abi.encodeCall(StrategyRegistry.register, (lpAdapter, YieldBankIds.MARKET_MAKING))
        );
        _call(
            lpVault, abi.encodeWithSignature("addAdapter(address,uint16)", lpAdapter, uint16(10000))
        );
        _call(
            facade,
            abi.encodeCall(StockCompositeLPAdapter.configureLP, (lpVault, lpAdapter, lpExit))
        );
        _call(
            address(controller),
            abi.encodeCall(DeltaPoolController.setPoolDepositsPaused, (pool, false))
        );
    }

    function _writePlan() private {
        string memory key = "commodityPreparation";
        vm.serializeString(key, "status", "candidate-requires-confirmed-deployment-receipts");
        vm.serializeString(
            key, "environment", vm.envOr("COMMODITY_PLAN_ENVIRONMENT", string("simulation"))
        );
        vm.serializeUint(key, "infrastructureSeedWei", 0.01 ether);
        vm.serializeUint(key, "chainId", block.chainid);
        vm.serializeUint(key, "observedBlock", block.number);
        vm.serializeAddress(key, "deployer", DEPLOYER);
        vm.serializeAddress(key, "governance", governance);
        vm.serializeString(key, "execution", "existing-full-bank-rebalance");
        vm.serializeUint(key, "controllerNonce", controllerNonce);
        vm.serializeAddress(key, "factory", factory);
        vm.serializeAddress(key, "positionManager", manager);
        vm.serializeAddress(key, "positionBuilder", builder);
        vm.serializeAddress(key, "registrationPool", pool);
        vm.serializeAddress(key, "composite", composite);
        vm.serializeAddress(key, "facade", facade);
        vm.serializeBytes32(key, "sleeveRuntimeCodeHash", composite.codehash);
        vm.serializeBytes32(key, "adapterRuntimeCodeHash", facade.codehash);
        vm.serializeAddress(key, "lpVault", lpVault);
        vm.serializeAddress(key, "lpAdapter", lpAdapter);
        vm.serializeAddress(key, "tokens", stocks);
        vm.serializeAddress(key, "pools", pools);
        vm.serializeAddress(key, "lpExitRoute", lpExit);
        vm.serializeAddress(key, "entryRoutes", entries);
        vm.serializeAddress(key, "exitRoutes", exits);
        vm.serializeAddress(key, "targets", targets);
        vm.serializeBytes(key, "payloads", payloads);
        uint256[] memory values = new uint256[](targets.length);
        bytes32 salt = keccak256(abi.encode("COMMODITY_V1", factory, composite));
        uint256 delay = IStockPrepareTimelock(governance).getMinDelay();
        vm.serializeUint(key, "delaySeconds", delay);
        vm.serializeBytes32(key, "salt", salt);
        vm.serializeBytes(
            key,
            "scheduleCalldata",
            abi.encodeWithSignature(
                "scheduleBatch(address[],uint256[],bytes[],bytes32,bytes32,uint256)",
                targets,
                values,
                payloads,
                bytes32(0),
                salt,
                delay
            )
        );
        string memory json = vm.serializeBytes(
            key,
            "executeCalldata",
            abi.encodeWithSignature(
                "executeBatch(address[],uint256[],bytes[],bytes32,bytes32)",
                targets,
                values,
                payloads,
                bytes32(0),
                salt
            )
        );
        vm.writeJson(
            json,
            vm.envOr(
                "COMMODITY_PLAN_PATH", string("deployments/piggy-banks-commodity-preparation.json")
            )
        );
    }

    function _call(address target, bytes memory payload) private {
        targets.push(target);
        payloads.push(payload);
    }

    function _route(address venue, address input, address output) private returns (address) {
        return address(
            new DeltaV3SinglePoolRoute(
                venue, OLD_FACTORY, input, output, venue.codehash, OLD_FACTORY.codehash
            )
        );
    }

    function _artifact(string memory name, bytes memory args) private returns (address deployed) {
        string memory json =
            vm.readFile(string.concat("deployments/stock-infrastructure/", name, ".json"));
        bytes memory code = abi.encodePacked(vm.parseJsonBytes(json, ".bytecode"), args);
        assembly ("memory-safe") { deployed := create(0, add(code, 32), mload(code)) }
        require(deployed.code.length != 0, "canonical artifact deployment failed");
    }
}
