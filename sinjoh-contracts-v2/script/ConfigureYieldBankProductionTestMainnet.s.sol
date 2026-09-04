// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { YieldBankCollection } from "../src/yield-banks/YieldBankCollection.sol";
import { CollectionPortfolioAllocator } from "../src/yield-banks/CollectionPortfolioAllocator.sol";
import { CoreStockTokenSleeve } from "../src/yield-banks/sleeves/CoreStockTokenSleeve.sol";
import { MarketMakingSleeve } from "../src/yield-banks/sleeves/MarketMakingSleeve.sol";
import { DeltaPoolController } from "../src/yield-banks/DeltaPoolController.sol";
import { PriceHub } from "../src/yield-banks/PriceHub.sol";
import { StrategyRegistry } from "../src/yield-banks/StrategyRegistry.sol";
import { DeltaV3LPAdapter } from "../src/yield-banks/adapters/DeltaV3LPAdapter.sol";
import { DeltaV3SinglePoolRoute } from "../src/yield-banks/adapters/DeltaV3SinglePoolRoute.sol";
import { DeltaV3TwapUsdFeed } from "../src/yield-banks/adapters/DeltaV3TwapUsdFeed.sol";

/// @notice Configures a disposable collection against caller-supplied, code-hash-pinned live
/// infrastructure. No collection or external integration address is compiled into this script.
contract ConfigureYieldBankProductionTestMainnet is Script {
    uint256 private constant EXPECTED_CHAIN_ID = 4_663;

    error InvalidConfiguration();
    error WrongChain(uint256 expected, uint256 actual);

    function run() external {
        if (block.chainid != EXPECTED_CHAIN_ID) {
            revert WrongChain(EXPECTED_CHAIN_ID, block.chainid);
        }

        YieldBankCollection collection = YieldBankCollection(vm.envAddress("TEST_COLLECTION"));
        address owner = vm.envAddress("TEST_COLLECTION_OWNER");
        CollectionPortfolioAllocator allocator =
            CollectionPortfolioAllocator(collection.portfolioAllocator());
        DeltaPoolController controller =
            DeltaPoolController(address(allocator.deltaPoolController()));
        TimelockController timelock = TimelockController(payable(collection.collectionTimelock()));
        CoreStockTokenSleeve core = CoreStockTokenSleeve(allocator.sleeves(0));
        address usdgSleeve = allocator.sleeves(2);
        PriceHub priceHub = PriceHub(address(controller.priceHub()));
        StrategyRegistry strategyRegistry = controller.strategyRegistry();

        address weth = address(collection.weth());
        address usdg = vm.envAddress("LIVE_USDG");
        address stockToken = vm.envAddress("LIVE_STOCK_TOKEN");
        address factory = vm.envAddress("LIVE_DELTA_FACTORY");
        address positionManager = vm.envAddress("LIVE_POSITION_MANAGER");
        address positionBuilder = vm.envAddress("LIVE_POSITION_BUILDER");
        address usdgPool = vm.envAddress("LIVE_USDG_WETH_POOL");
        address stockPool = vm.envAddress("LIVE_STOCK_WETH_POOL");
        address wethUsdFeed = vm.envAddress("LIVE_WETH_USD_FEED");

        _requireCodeHash(usdg, vm.envBytes32("LIVE_USDG_CODE_HASH"));
        _requireCodeHash(stockToken, vm.envBytes32("LIVE_STOCK_TOKEN_CODE_HASH"));
        _requireCodeHash(factory, vm.envBytes32("LIVE_DELTA_FACTORY_CODE_HASH"));
        _requireCodeHash(positionManager, vm.envBytes32("LIVE_POSITION_MANAGER_CODE_HASH"));
        _requireCodeHash(positionBuilder, vm.envBytes32("LIVE_POSITION_BUILDER_CODE_HASH"));
        _requireCodeHash(usdgPool, vm.envBytes32("LIVE_USDG_WETH_POOL_CODE_HASH"));
        _requireCodeHash(stockPool, vm.envBytes32("LIVE_STOCK_WETH_POOL_CODE_HASH"));
        _requireCodeHash(wethUsdFeed, vm.envBytes32("LIVE_WETH_USD_FEED_CODE_HASH"));
        if (
            owner == address(0) || address(collection).code.length == 0 || weth.code.length == 0
                || usdg.code.length == 0 || stockToken.code.length == 0
                || allocator.allocationOperator() != owner
        ) revert InvalidConfiguration();

        vm.startBroadcast();

        _timelock(
            timelock,
            address(priceHub),
            abi.encodeWithSignature(
                "configureFeed(address,address,address,uint32,uint32,bool,uint16)",
                weth,
                wethUsdFeed,
                address(0),
                uint32(1 days),
                uint32(1 days),
                false,
                uint16(0)
            ),
            keccak256("yield-bank-test:weth-feed")
        );
        _timelock(
            timelock,
            address(priceHub),
            abi.encodeCall(priceHub.setRegistrar, (address(controller), true)),
            keccak256("yield-bank-test:delta-registrar")
        );
        _timelock(
            timelock,
            address(strategyRegistry),
            abi.encodeCall(strategyRegistry.setRegistrar, (address(controller), true)),
            keccak256("yield-bank-test:strategy-registrar")
        );

        DeltaPoolController.InfrastructureConfig memory infrastructure =
            DeltaPoolController.InfrastructureConfig({
                positionManager: positionManager,
                positionBuilder: positionBuilder,
                factoryRuntimeCodeHash: factory.codehash,
                positionManagerRuntimeCodeHash: positionManager.codehash,
                positionBuilderRuntimeCodeHash: positionBuilder.codehash,
                routeCreationCodeHash: keccak256(type(DeltaV3SinglePoolRoute).creationCode),
                sleeveCreationCodeHash: keccak256(type(MarketMakingSleeve).creationCode),
                adapterCreationCodeHash: keccak256(type(DeltaV3LPAdapter).creationCode),
                feedCreationCodeHash: keccak256(type(DeltaV3TwapUsdFeed).creationCode)
            });
        _timelock(
            timelock,
            address(controller),
            abi.encodeCall(controller.configureInfrastructure, (factory, infrastructure)),
            keccak256("yield-bank-test:delta-infrastructure")
        );

        DeltaPoolController.PoolFeedConfig memory usdgFeedConfig =
            _poolFeedConfig(1e6, "USDG / USD (Delta V3 TWAP)");
        controller.configurePoolDerivedFeed(
            usdgPool, usdgFeedConfig, type(DeltaV3TwapUsdFeed).creationCode
        );
        DeltaPoolController.PoolFeedConfig memory stockFeedConfig =
            _poolFeedConfig(1e18, "Stock Token / USD (Delta V3 TWAP)");
        controller.configurePoolDerivedFeed(
            stockPool, stockFeedConfig, type(DeltaV3TwapUsdFeed).creationCode
        );

        DeltaV3SinglePoolRoute wethToUsdg = new DeltaV3SinglePoolRoute(
            usdgPool, factory, weth, usdg, usdgPool.codehash, factory.codehash
        );
        DeltaV3SinglePoolRoute usdgToWeth = new DeltaV3SinglePoolRoute(
            usdgPool, factory, usdg, weth, usdgPool.codehash, factory.codehash
        );
        DeltaV3SinglePoolRoute wethToStock = new DeltaV3SinglePoolRoute(
            stockPool, factory, weth, stockToken, stockPool.codehash, factory.codehash
        );
        DeltaV3SinglePoolRoute stockToWeth = new DeltaV3SinglePoolRoute(
            stockPool, factory, stockToken, weth, stockPool.codehash, factory.codehash
        );

        _timelock(
            timelock,
            address(core),
            abi.encodeCall(
                core.addConstituent,
                (stockToken, address(wethToStock), address(wethToStock).codehash, uint16(10_000))
            ),
            keccak256("yield-bank-test:stock-constituent")
        );
        _timelock(
            timelock,
            address(allocator),
            abi.encodeCall(
                allocator.bindRoute,
                (weth, usdgSleeve, address(wethToUsdg), address(wethToUsdg).codehash)
            ),
            keccak256("yield-bank-test:usdg-route")
        );
        _timelock(
            timelock,
            address(allocator),
            abi.encodeCall(
                allocator.bindRebalanceRoute,
                (usdg, address(usdgToWeth), address(usdgToWeth).codehash)
            ),
            keccak256("yield-bank-test:usdg-rebalance-route")
        );
        _timelock(
            timelock,
            address(allocator),
            abi.encodeCall(
                allocator.bindRebalanceRoute,
                (stockToken, address(stockToWeth), address(stockToWeth).codehash)
            ),
            keccak256("yield-bank-test:stock-rebalance-route")
        );

        (address deltaSleeve, address deltaAdapter) = controller.materializePool(
            usdgPool,
            DeltaPoolController.MaterializationConfig({
                maximumPositions: 1, adapterCapBps: 10_000, maximumOperatorLossBps: 0
            }),
            type(DeltaV3SinglePoolRoute).creationCode,
            type(MarketMakingSleeve).creationCode,
            type(DeltaV3LPAdapter).creationCode
        );
        vm.stopBroadcast();

        (uint256 wethPrice,,) = priceHub.quoteUsd18(weth);
        (uint256 usdgPrice,,) = priceHub.quoteUsd18(usdg);
        (uint256 stockPrice,,) = priceHub.quoteUsd18(stockToken);
        if (
            !controller.isAllocationPool(usdgPool)
                || allocator.deltaPoolOfSleeve(deltaSleeve) != usdgPool || wethPrice == 0
                || usdgPrice == 0 || stockPrice == 0
        ) revert InvalidConfiguration();

        console2.log("WETH to USDG route", address(wethToUsdg));
        console2.log("USDG to WETH route", address(usdgToWeth));
        console2.log("WETH to stock route", address(wethToStock));
        console2.log("Stock to WETH route", address(stockToWeth));
        console2.log("Delta sleeve", deltaSleeve);
        console2.log("Delta adapter", deltaAdapter);
    }

    function _poolFeedConfig(uint128 comparisonAmount, string memory description)
        private
        pure
        returns (DeltaPoolController.PoolFeedConfig memory config)
    {
        config = DeltaPoolController.PoolFeedConfig({
            referenceSource: address(0),
            heartbeat: uint32(1 days),
            gracePeriod: uint32(1 days),
            twapWindow: uint32(5 minutes),
            maxDeviationBps: 0,
            maxSpotDeviationBps: 1_000,
            comparisonAmount: comparisonAmount,
            minimumLiquidity: 1,
            description: description
        });
    }

    function _timelock(TimelockController timelock, address target, bytes memory data, bytes32 salt)
        private
    {
        bytes32 predecessor;
        timelock.schedule(target, 0, data, predecessor, salt, 0);
        timelock.execute(target, 0, data, predecessor, salt);
    }

    function _requireCodeHash(address target, bytes32 expected) private view {
        if (target.codehash != expected || expected == bytes32(0)) revert InvalidConfiguration();
    }
}
