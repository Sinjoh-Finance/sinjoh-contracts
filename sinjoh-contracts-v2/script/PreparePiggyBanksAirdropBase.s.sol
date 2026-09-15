// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;
import {AirdropCompositeSleeve} from "../src/yield-banks/airdrop/AirdropCompositeSleeve.sol";
import {AirdropInfrastructureSeed} from "../src/yield-banks/airdrop/AirdropInfrastructureSeed.sol";
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
import { StockCompositeSleeve } from "../src/yield-banks/stock/StockCompositeSleeve.sol";
import { StockCompositeLPAdapter } from "../src/yield-banks/stock/StockCompositeLPAdapter.sol";
import {
    StockCorporateActionRegistry
} from "../src/yield-banks/stock/StockCorporateActionRegistry.sol";
import { StockDividendVault } from "../src/yield-banks/stock/StockDividendVault.sol";
import { StockDividendRoute } from "../src/yield-banks/stock/StockDividendRoute.sol";
import { StockReleaseVerifier } from "../src/yield-banks/stock/StockReleaseVerifier.sol";
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

/// @notice Airdrop infrastructure preparation, reusing the existing Stock/LP deployment pattern.
/// @dev --broadcast deploys auxiliary infrastructure with the deployer; it NEVER impersonates
/// governance onchain. The resulting schedule/execute calldata requires the existing governance
/// signer. No owner allocation is included. Run without --broadcast first and review the artifact.
abstract contract PreparePiggyBanksAirdropBase is Script {
    YieldBankCollection constant COLLECTION =
        YieldBankCollection(0xc275fa302Cd53DFa42D41b1C5b770661d923ba43);
    CollectionPortfolioAllocator constant ALLOCATOR =
        CollectionPortfolioAllocator(0x42e14eA9f926ad7b530ce49d433CB6f748f8D0a1);
    address internal DEPLOYER;
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
    address registry;
    address vault;
    address verifier;
    address lpExit;
    address[] targets;
    bytes[] payloads;
    address[] stocks;
    address[] feeds;
    address[] pools;
    address[] entries;
    address[] exits;
    address[] dividendRoutes;
    bytes32 manifestHash;
    bytes32 originalInfrastructureHash;
    uint64 controllerNonce;

    function run() external {
        DEPLOYER = vm.envOr("AIRDROP_DEPLOYER_ADDRESS", address(0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49));
        require(DEPLOYER != address(0), "missing deployment account");
        _beforePreparation();
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
        string memory manifest =
            vm.readFile("deployments/stock-infrastructure/execution-manifest.v1.json");
        require(
            vm.parseJsonUint(manifest, ".chainId") == 4663
                && vm.parseJsonAddress(manifest, ".collection") == address(COLLECTION),
            "manifest identity"
        );
        manifestHash = keccak256(bytes(manifest));
        for (uint256 i; i < 3; ++i) {
            string memory prefix = string.concat(".stocks[", vm.toString(i), "]");
            address stock = vm.parseJsonAddress(manifest, string.concat(prefix, ".token"));
            address feed = vm.parseJsonAddress(manifest, string.concat(prefix, ".feed"));
            address venue = vm.parseJsonAddress(manifest, string.concat(prefix, ".pool"));
            require(
                stock.codehash
                    == vm.parseJsonBytes32(
                        manifest, string.concat(prefix, ".tokenRuntimeCodeHash")
                    ),
                "stock code changed"
            );
            require(
                feed.codehash
                    == vm.parseJsonBytes32(manifest, string.concat(prefix, ".feedRuntimeCodeHash")),
                "feed code changed"
            );
            require(
                venue.codehash
                    == vm.parseJsonBytes32(manifest, string.concat(prefix, ".poolRuntimeCodeHash")),
                "pool code changed"
            );
            require(IYieldBankV3Pool(venue).liquidity() > 0, "stock pool empty");
            stocks.push(stock);
            feeds.push(feed);
            pools.push(venue);
        }
        controllerNonce = vm.getNonce(address(controller));
        // materializePool creates entry route, exit route, sleeve, then adapter.
        composite = vm.computeCreateAddress(address(controller), controllerNonce + 2);
        facade = vm.computeCreateAddress(address(controller), controllerNonce + 3);
        require(composite.code.length == 0 && facade.code.length == 0, "prediction occupied");
        vm.startBroadcast(DEPLOYER);
        _deployInfrastructure();
        registry = address(new StockCorporateActionRegistry(governance));
        vault = address(
            new StockDividendVault(
                address(COLLECTION), composite, governance, USDG, registry, address(hub), 100
            )
        );
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
        address cashRoute = _route(USDG_POOL, WETH, USDG);
        for (uint256 i; i < stocks.length; ++i) {
            entries.push(_route(pools[i], WETH, stocks[i]));
            exits.push(_route(pools[i], stocks[i], WETH));
            dividendRoutes.push(address(new StockDividendRoute(exits[i], cashRoute)));
        }
        verifier = _deployAirdrop();
        vm.stopBroadcast();
        _activation();
        _airdropActivation();
        // Local-only simulation. This operation is never recorded for the deployer to broadcast.
        for (uint256 i; i < targets.length; ++i) {
            vm.prank(governance);
            (bool success, bytes memory reason) = targets[i].call(payloads[i]);
            if (!success) assembly ("memory-safe") { revert(add(reason, 32), mload(reason)) }
        }
        _writePlan();
    }

    function _deployInfrastructure() private {
        factory = _artifact("UniswapV3Factory", "");
        address descriptor = address(new StockInfrastructurePositionDescriptor());
        manager = _artifact("NonfungiblePositionManager", abi.encode(factory, WETH, descriptor));
        builder = address(new StockInfrastructureBuilder(factory, manager, WETH));
        IStockPrepareFactory(factory).enableFeeAmount(100, 1);
        pool = IStockPrepareFactory(factory).createPool(WETH, USDG, 100);
        // Fixed 0.01 ETH infrastructure budget from the authorized deployer, never bank backing.
        address route = _route(USDG_POOL, WETH, USDG);
        new AirdropInfrastructureSeed{value: 0.01 ether}(
            pool, USDG_POOL, IDeltaPositionBuilder(builder), DeltaV3SinglePoolRoute(route),
            hub, governance, DEPLOYER
        );
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
                        sleeveCreationCodeHash: keccak256(type(AirdropCompositeSleeve).creationCode),
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
                    1, controller.maximumAdapterCapBps(), 500
                ),
                type(DeltaV3SinglePoolRoute).creationCode,
                type(AirdropCompositeSleeve).creationCode,
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
        for (uint256 i; i < stocks.length; ++i) {
            _call(
                address(hub),
                abi.encodeWithSignature(
                    "configureFeed(address,address,address,uint32,uint32,bool,bool,uint16)",
                    stocks[i],
                    feeds[i],
                    address(0),
                    uint32(86400),
                    uint32(0),
                    true,
                    true,
                    uint16(100)
                )
            );
            _call(
                registry,
                abi.encodeCall(StockCorporateActionRegistry.register, (stocks[i], manifestHash))
            );
        }
        _call(composite, abi.encodeCall(StockCompositeSleeve.configureVault, (vault)));
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
        for (uint256 i; i < stocks.length; ++i) {
            _call(
                composite,
                abi.encodeCall(
                    StockCompositeSleeve.bindStockRoutes, (stocks[i], entries[i], exits[i])
                )
            );
            _call(
                vault,
                abi.encodeCall(StockDividendVault.setDividendRoute, (stocks[i], dividendRoutes[i]))
            );
        }

    }

    function _writePlan() private {
        _writeAirdropPlan();
        string memory key = "airdropPreparation";
        vm.serializeString(key, "status", "prepared-not-activated");
        vm.serializeUint(key, "chainId", block.chainid);
        vm.serializeUint(key, "observedBlock", block.number);
        vm.serializeAddress(key, "deployer", DEPLOYER);
        vm.serializeAddress(key, "governance", governance);
        vm.serializeBytes32(key, "manifestHash", manifestHash);
        vm.serializeUint(key, "controllerNonce", controllerNonce);
        vm.serializeAddress(key, "factory", factory);
        vm.serializeAddress(key, "positionManager", manager);
        vm.serializeAddress(key, "positionBuilder", builder);
        vm.serializeAddress(key, "registrationPool", pool);
        vm.serializeAddress(key, "composite", composite);
        vm.serializeAddress(key, "facade", facade);
        vm.serializeAddress(key, "vault", vault);
        vm.serializeAddress(key, "escrow", address(StockDividendVault(vault).escrow()));
        vm.serializeAddress(key, "registry", registry);
        vm.serializeAddress(key, "lpVault", lpVault);
        vm.serializeAddress(key, "lpAdapter", lpAdapter);
        vm.serializeAddress(key, "verifier", verifier);
        vm.serializeAddress(key, "stocks", stocks);
        vm.serializeAddress(key, "entryRoutes", entries);
        vm.serializeAddress(key, "exitRoutes", exits);
        vm.serializeAddress(key, "dividendRoutes", dividendRoutes);
        vm.serializeAddress(key, "targets", targets);
        vm.serializeBytes(key, "payloads", payloads);
        uint256[] memory values = new uint256[](targets.length);
        bytes32 salt = keccak256(abi.encode(manifestHash, factory, composite));
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
                _predecessor(),
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
                _predecessor(),
                salt
            )
        );
        vm.writeJson(json, "deployments/piggy-banks-airdrop-preparation.json");
    }

    function _call(address target, bytes memory payload) internal {
        targets.push(target);
        payloads.push(payload);
    }

    function _route(address venue, address input, address output) internal returns (address) {
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
    function _beforePreparation() internal virtual;
    function _deployAirdrop() internal virtual returns(address);
    function _airdropActivation() internal virtual;
    function _writeAirdropPlan() internal virtual;
    function _predecessor() internal view virtual returns(bytes32);
}
