// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Script } from "forge-std/Script.sol";
import { DeltaV3TwapUsdFeed } from "../src/yield-banks/adapters/DeltaV3TwapUsdFeed.sol";

/// @notice Deploys and prepares one guarded Delta V3 TWAP/USD feed from a reviewed JSON plan.
/// @dev PriceHub configuration remains a separate timelock operation after the TWAP window ages.
contract DeployYieldBankDeltaTwapFeed is Script {
    struct Plan {
        uint256 chainId;
        address pairedAsset;
        address weth;
        address pool;
        address factory;
        address wethUsdFeed;
        bytes32 poolCodeHash;
        bytes32 factoryCodeHash;
        bytes32 wethUsdFeedCodeHash;
        uint32 twapWindow;
        uint16 maxSpotDeviationBps;
        uint128 comparisonAmount;
        uint128 minimumLiquidity;
        string description;
        bytes32 expectedRuntimeCodeHash;
    }

    error WrongChain(uint256 expected, uint256 actual);
    error RuntimeCodeHashMismatch(bytes32 expected, bytes32 actual);
    error InvalidNumericValue(string field, uint256 value);

    function preview() external returns (bytes32 runtimeCodeHash) {
        Plan memory plan = _readPlan(vm.readFile(vm.envString("YIELD_BANK_DELTA_TWAP_FEED_PLAN")));
        _requireChain(plan.chainId);
        runtimeCodeHash = address(_deploy(plan)).codehash;
    }

    function run() external returns (address feed) {
        Plan memory plan = _readPlan(vm.readFile(vm.envString("YIELD_BANK_DELTA_TWAP_FEED_PLAN")));
        _requireChain(plan.chainId);

        address rehearsal = address(_deploy(plan));
        _checkHash(plan.expectedRuntimeCodeHash, rehearsal.codehash);

        vm.startBroadcast();
        DeltaV3TwapUsdFeed deployed = _deploy(plan);
        deployed.preparePoolOracle();
        vm.stopBroadcast();

        feed = address(deployed);
        _checkHash(plan.expectedRuntimeCodeHash, feed.codehash);
    }

    function _deploy(Plan memory plan) private returns (DeltaV3TwapUsdFeed feed) {
        feed = new DeltaV3TwapUsdFeed(
            plan.pairedAsset,
            plan.weth,
            plan.pool,
            plan.factory,
            plan.wethUsdFeed,
            plan.poolCodeHash,
            plan.factoryCodeHash,
            plan.wethUsdFeedCodeHash,
            plan.twapWindow,
            plan.maxSpotDeviationBps,
            plan.comparisonAmount,
            plan.minimumLiquidity,
            plan.description
        );
    }

    function _readPlan(string memory json) private view returns (Plan memory plan) {
        plan.chainId = vm.parseJsonUint(json, ".chainId");
        plan.pairedAsset = vm.parseJsonAddress(json, ".pairedAsset");
        plan.weth = vm.parseJsonAddress(json, ".weth");
        plan.pool = vm.parseJsonAddress(json, ".pool");
        plan.factory = vm.parseJsonAddress(json, ".factory");
        plan.wethUsdFeed = vm.parseJsonAddress(json, ".wethUsdFeed");
        plan.poolCodeHash = vm.parseJsonBytes32(json, ".poolCodeHash");
        plan.factoryCodeHash = vm.parseJsonBytes32(json, ".factoryCodeHash");
        plan.wethUsdFeedCodeHash = vm.parseJsonBytes32(json, ".wethUsdFeedCodeHash");
        plan.twapWindow = _parseUint32(json, ".twapWindow");
        plan.maxSpotDeviationBps = _parseUint16(json, ".maxSpotDeviationBps");
        plan.comparisonAmount = _parseUint128(json, ".comparisonAmount");
        plan.minimumLiquidity = _parseUint128(json, ".minimumLiquidity");
        plan.description = vm.parseJsonString(json, ".description");
        plan.expectedRuntimeCodeHash = vm.parseJsonBytes32(json, ".expectedRuntimeCodeHash");
    }

    function _parseUint16(string memory json, string memory path)
        private
        pure
        returns (uint16 value)
    {
        uint256 parsed = vm.parseJsonUint(json, path);
        if (parsed > type(uint16).max) revert InvalidNumericValue(path, parsed);
        return uint16(parsed);
    }

    function _parseUint32(string memory json, string memory path)
        private
        pure
        returns (uint32 value)
    {
        uint256 parsed = vm.parseJsonUint(json, path);
        if (parsed > type(uint32).max) revert InvalidNumericValue(path, parsed);
        return uint32(parsed);
    }

    function _parseUint128(string memory json, string memory path)
        private
        pure
        returns (uint128 value)
    {
        uint256 parsed = vm.parseJsonUint(json, path);
        if (parsed > type(uint128).max) revert InvalidNumericValue(path, parsed);
        return uint128(parsed);
    }

    function _requireChain(uint256 expected) private view {
        if (expected != block.chainid) revert WrongChain(expected, block.chainid);
    }

    function _checkHash(bytes32 expected, bytes32 actual) private pure {
        if (expected != actual) revert RuntimeCodeHashMismatch(expected, actual);
    }
}
