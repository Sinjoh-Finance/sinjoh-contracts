// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { YieldBankCollection } from "../src/yield-banks/YieldBankCollection.sol";
import { CollectionPortfolioAllocator } from "../src/yield-banks/CollectionPortfolioAllocator.sol";
import { MarketMakingSleeve } from "../src/yield-banks/sleeves/MarketMakingSleeve.sol";
import { DeltaPoolController } from "../src/yield-banks/DeltaPoolController.sol";
import { PriceHub } from "../src/yield-banks/PriceHub.sol";
import { StrategyRegistry } from "../src/yield-banks/StrategyRegistry.sol";
import { DeltaV3LPAdapter } from "../src/yield-banks/adapters/DeltaV3LPAdapter.sol";
import { DeltaV3SinglePoolRoute } from "../src/yield-banks/adapters/DeltaV3SinglePoolRoute.sol";
import { DeltaV3TwapUsdFeed } from "../src/yield-banks/adapters/DeltaV3TwapUsdFeed.sol";

/// @notice Configures a disposable weighted test collection against one caller-supplied live
/// WETH-paired Delta pool. Every external address and expected runtime hash is supplied at runtime.
contract ConfigureYieldBankWeightedTestMainnet is Script {
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
        PriceHub priceHub = PriceHub(address(controller.priceHub()));
        StrategyRegistry strategyRegistry = controller.strategyRegistry();

        address weth = address(collection.weth());
        address pairedAsset = vm.envAddress("LIVE_PAIRED_ASSET");
        address factory = vm.envAddress("LIVE_DELTA_FACTORY");
        address positionManager = vm.envAddress("LIVE_POSITION_MANAGER");
        address positionBuilder = vm.envAddress("LIVE_POSITION_BUILDER");
        address pool = vm.envAddress("LIVE_PAIRED_WETH_POOL");
        address wethUsdFeed = vm.envAddress("LIVE_WETH_USD_FEED");

        _requireCodeHash(pairedAsset, vm.envBytes32("LIVE_PAIRED_ASSET_CODE_HASH"));
        _requireCodeHash(factory, vm.envBytes32("LIVE_DELTA_FACTORY_CODE_HASH"));
        _requireCodeHash(positionManager, vm.envBytes32("LIVE_POSITION_MANAGER_CODE_HASH"));
        _requireCodeHash(positionBuilder, vm.envBytes32("LIVE_POSITION_BUILDER_CODE_HASH"));
        _requireCodeHash(pool, vm.envBytes32("LIVE_PAIRED_WETH_POOL_CODE_HASH"));
        _requireCodeHash(wethUsdFeed, vm.envBytes32("LIVE_WETH_USD_FEED_CODE_HASH"));
        if (
            owner == address(0) || address(collection).code.length == 0 || weth.code.length == 0
                || pairedAsset.code.length == 0 || allocator.allocationOperator() != owner
                || allocator.coreWeightBps() != 0 || allocator.marketMakingWeightBps() != 10_000
                || allocator.usdgWeightBps() != 0
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
            keccak256("yield-bank-weighted-test:weth-feed")
        );
        _timelock(
            timelock,
            address(priceHub),
            abi.encodeCall(priceHub.setRegistrar, (address(controller), true)),
            keccak256("yield-bank-weighted-test:delta-registrar")
        );
        _timelock(
            timelock,
            address(strategyRegistry),
            abi.encodeCall(strategyRegistry.setRegistrar, (address(controller), true)),
            keccak256("yield-bank-weighted-test:strategy-registrar")
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
            keccak256("yield-bank-weighted-test:delta-infrastructure")
        );

        controller.configurePoolDerivedFeed(
            pool,
            DeltaPoolController.PoolFeedConfig({
                referenceSource: address(0),
                heartbeat: uint32(1 days),
                gracePeriod: uint32(1 days),
                twapWindow: uint32(5 minutes),
                maxDeviationBps: 0,
                maxSpotDeviationBps: 1_000,
                comparisonAmount: 1e18,
                minimumLiquidity: 1,
                description: "Runtime-paired asset / USD (Delta V3 TWAP)"
            }),
            type(DeltaV3TwapUsdFeed).creationCode
        );

        DeltaV3SinglePoolRoute pairedToWeth = new DeltaV3SinglePoolRoute(
            pool, factory, pairedAsset, weth, pool.codehash, factory.codehash
        );
        DeltaV3SinglePoolRoute wethToPaired = new DeltaV3SinglePoolRoute(
            pool, factory, weth, pairedAsset, pool.codehash, factory.codehash
        );
        address marketMakingSleeve = allocator.sleeves(1);
        _timelock(
            timelock,
            address(allocator),
            abi.encodeCall(
                allocator.bindRoute,
                (
                    pairedAsset,
                    marketMakingSleeve,
                    address(pairedToWeth),
                    address(pairedToWeth).codehash
                )
            ),
            keccak256("yield-bank-weighted-test:paired-route")
        );
        _timelock(
            timelock,
            address(allocator),
            abi.encodeCall(
                allocator.bindRebalanceRoute,
                (pairedAsset, address(pairedToWeth), address(pairedToWeth).codehash)
            ),
            keccak256("yield-bank-weighted-test:paired-rebalance-route")
        );

        (address deltaSleeve, address deltaAdapter) = controller.materializePool(
            pool,
            DeltaPoolController.MaterializationConfig({
                maximumPositions: 1, adapterCapBps: 10_000, maximumOperatorLossBps: 0
            }),
            type(DeltaV3SinglePoolRoute).creationCode,
            type(MarketMakingSleeve).creationCode,
            type(DeltaV3LPAdapter).creationCode
        );
        vm.stopBroadcast();

        (uint256 wethPrice,,) = priceHub.quoteUsd18(weth);
        (uint256 pairedPrice,,) = priceHub.quoteUsd18(pairedAsset);
        if (
            !controller.isAllocationPool(pool) || allocator.deltaPoolOfSleeve(deltaSleeve) != pool
                || wethPrice == 0 || pairedPrice == 0
        ) revert InvalidConfiguration();

        console2.log("Paired asset to WETH route", address(pairedToWeth));
        console2.log("WETH to paired asset route", address(wethToPaired));
        console2.log("Delta sleeve", deltaSleeve);
        console2.log("Delta adapter", deltaAdapter);
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
