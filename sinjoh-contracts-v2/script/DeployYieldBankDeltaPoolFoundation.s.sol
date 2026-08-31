// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Script } from "forge-std/Script.sol";
import { DeltaV3SinglePoolRoute } from "../src/yield-banks/adapters/DeltaV3SinglePoolRoute.sol";
import { MarketMakingSleeve } from "../src/yield-banks/sleeves/MarketMakingSleeve.sol";

/// @notice Deploys the two exact-direction routes and isolated one-adapter sleeve for one Delta pool.
/// @dev The adapter is deployed in a second reviewed step after these three addresses are known.
contract DeployYieldBankDeltaPoolFoundation is Script {
    struct Plan {
        uint256 chainId;
        address pool;
        address factory;
        address weth;
        address pairedAsset;
        bytes32 poolCodeHash;
        bytes32 factoryCodeHash;
        address allocator;
        address timelock;
        address guardian;
        address priceHub;
        address strategyRegistry;
        address eligibilityPolicy;
        uint16 maximumAdapterCapBps;
        uint16 maximumOperatorLossBps;
        bytes32 expectedEntryRouteRuntimeCodeHash;
        bytes32 expectedExitRouteRuntimeCodeHash;
        bytes32 expectedSleeveRuntimeCodeHash;
    }

    error WrongChain(uint256 expected, uint256 actual);
    error RuntimeCodeHashMismatch(bytes32 expected, bytes32 actual);
    error InvalidBasisPoints(uint256 supplied);

    function preview()
        external
        returns (bytes32 entryRouteHash, bytes32 exitRouteHash, bytes32 sleeveHash)
    {
        Plan memory plan = _readPlan(vm.readFile(vm.envString("YIELD_BANK_DELTA_POOL_PLAN")));
        _requireChain(plan.chainId);
        (address entryRoute, address exitRoute, address sleeve) = _deploy(plan);
        return (entryRoute.codehash, exitRoute.codehash, sleeve.codehash);
    }

    function run() external returns (address entryRoute, address exitRoute, address sleeve) {
        Plan memory plan = _readPlan(vm.readFile(vm.envString("YIELD_BANK_DELTA_POOL_PLAN")));
        _requireChain(plan.chainId);

        (address rehearsalEntry, address rehearsalExit, address rehearsalSleeve) = _deploy(plan);
        _checkHash(plan.expectedEntryRouteRuntimeCodeHash, rehearsalEntry.codehash);
        _checkHash(plan.expectedExitRouteRuntimeCodeHash, rehearsalExit.codehash);
        _checkHash(plan.expectedSleeveRuntimeCodeHash, rehearsalSleeve.codehash);

        vm.startBroadcast();
        (entryRoute, exitRoute, sleeve) = _deploy(plan);
        vm.stopBroadcast();

        _checkHash(plan.expectedEntryRouteRuntimeCodeHash, entryRoute.codehash);
        _checkHash(plan.expectedExitRouteRuntimeCodeHash, exitRoute.codehash);
        _checkHash(plan.expectedSleeveRuntimeCodeHash, sleeve.codehash);
    }

    function _deploy(Plan memory plan)
        private
        returns (address entryRoute, address exitRoute, address sleeve)
    {
        entryRoute = address(
            new DeltaV3SinglePoolRoute(
                plan.pool,
                plan.factory,
                plan.weth,
                plan.pairedAsset,
                plan.poolCodeHash,
                plan.factoryCodeHash
            )
        );
        exitRoute = address(
            new DeltaV3SinglePoolRoute(
                plan.pool,
                plan.factory,
                plan.pairedAsset,
                plan.weth,
                plan.poolCodeHash,
                plan.factoryCodeHash
            )
        );
        sleeve = address(
            new MarketMakingSleeve(
                plan.weth,
                plan.allocator,
                plan.timelock,
                plan.guardian,
                plan.priceHub,
                plan.strategyRegistry,
                plan.eligibilityPolicy,
                1,
                plan.maximumAdapterCapBps,
                plan.maximumOperatorLossBps
            )
        );
    }

    function _readPlan(string memory json) private view returns (Plan memory plan) {
        plan.chainId = vm.parseJsonUint(json, ".chainId");
        plan.pool = vm.parseJsonAddress(json, ".pool");
        plan.factory = vm.parseJsonAddress(json, ".factory");
        plan.weth = vm.parseJsonAddress(json, ".weth");
        plan.pairedAsset = vm.parseJsonAddress(json, ".pairedAsset");
        plan.poolCodeHash = vm.parseJsonBytes32(json, ".poolCodeHash");
        plan.factoryCodeHash = vm.parseJsonBytes32(json, ".factoryCodeHash");
        plan.allocator = vm.parseJsonAddress(json, ".allocator");
        plan.timelock = vm.parseJsonAddress(json, ".timelock");
        plan.guardian = vm.parseJsonAddress(json, ".guardian");
        plan.priceHub = vm.parseJsonAddress(json, ".priceHub");
        plan.strategyRegistry = vm.parseJsonAddress(json, ".strategyRegistry");
        plan.eligibilityPolicy = vm.parseJsonAddress(json, ".eligibilityPolicy");
        plan.maximumAdapterCapBps = _parseBps(json, ".maximumAdapterCapBps", true);
        plan.maximumOperatorLossBps = _parseBps(json, ".maximumOperatorLossBps", false);
        plan.expectedEntryRouteRuntimeCodeHash =
            vm.parseJsonBytes32(json, ".expectedEntryRouteRuntimeCodeHash");
        plan.expectedExitRouteRuntimeCodeHash =
            vm.parseJsonBytes32(json, ".expectedExitRouteRuntimeCodeHash");
        plan.expectedSleeveRuntimeCodeHash =
            vm.parseJsonBytes32(json, ".expectedSleeveRuntimeCodeHash");
    }

    function _requireChain(uint256 expected) private view {
        if (expected != block.chainid) revert WrongChain(expected, block.chainid);
    }

    function _checkHash(bytes32 expected, bytes32 actual) private pure {
        if (expected != actual) revert RuntimeCodeHashMismatch(expected, actual);
    }

    function _parseBps(string memory json, string memory path, bool requirePositive)
        private
        view
        returns (uint16 value)
    {
        uint256 parsed = vm.parseJsonUint(json, path);
        if (parsed > 10_000 || (requirePositive && parsed == 0)) {
            revert InvalidBasisPoints(parsed);
        }
        // The explicit 10,000 upper bound makes this conversion exact.
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint16(parsed);
    }
}
