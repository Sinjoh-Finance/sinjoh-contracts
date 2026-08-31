// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Script } from "forge-std/Script.sol";
import { DeltaV3LPAdapter } from "../src/yield-banks/adapters/DeltaV3LPAdapter.sol";

/// @notice Deploys a Delta adapter from one reviewed JSON plan and verifies its runtime hash.
/// @dev Registry approval and sleeve activation remain separate governance/timelock operations.
contract DeployYieldBankDeltaAdapter is Script {
    struct DeploymentPlan {
        uint256 chainId;
        bytes32 expectedRuntimeCodeHash;
        DeltaV3LPAdapter.Config config;
    }

    error WrongChain(uint256 expected, uint256 actual);
    error RuntimeCodeHashMismatch(bytes32 expected, bytes32 actual);

    /// @notice Rehearses a draft plan without broadcasting so its immutable-aware runtime hash can
    /// be placed into the final reviewed plan.
    function preview() external returns (bytes32 runtimeCodeHash) {
        string memory json = vm.readFile(vm.envString("YIELD_BANK_DELTA_ADAPTER_PLAN"));
        uint256 chainId = vm.parseJsonUint(json, ".chainId");
        if (chainId != block.chainid) revert WrongChain(chainId, block.chainid);
        address rehearsal = address(new DeltaV3LPAdapter(_readConfig(json)));
        runtimeCodeHash = rehearsal.codehash;
    }

    function run() external returns (address adapter) {
        string memory path = vm.envString("YIELD_BANK_DELTA_ADAPTER_PLAN");
        DeploymentPlan memory plan = _readPlan(vm.readFile(path));
        if (plan.chainId != block.chainid) revert WrongChain(plan.chainId, block.chainid);

        // Rehearse the exact constructor before recording any broadcast transaction. This prevents
        // a stale reviewed runtime hash from leaving an unauthorized orphan deployment onchain.
        address rehearsal = address(new DeltaV3LPAdapter(plan.config));
        if (rehearsal.codehash != plan.expectedRuntimeCodeHash) {
            revert RuntimeCodeHashMismatch(plan.expectedRuntimeCodeHash, rehearsal.codehash);
        }

        vm.startBroadcast();
        adapter = address(new DeltaV3LPAdapter(plan.config));
        vm.stopBroadcast();

        if (adapter.codehash != plan.expectedRuntimeCodeHash) {
            revert RuntimeCodeHashMismatch(plan.expectedRuntimeCodeHash, adapter.codehash);
        }
    }

    function _readPlan(string memory json) private view returns (DeploymentPlan memory plan) {
        plan.chainId = vm.parseJsonUint(json, ".chainId");
        plan.expectedRuntimeCodeHash = vm.parseJsonBytes32(json, ".expectedRuntimeCodeHash");
        plan.config = _readConfig(json);
    }

    function _readConfig(string memory json)
        private
        view
        returns (DeltaV3LPAdapter.Config memory config)
    {
        uint256 maximumPositions_ = vm.parseJsonUint(json, ".config.maximumPositions");
        if (maximumPositions_ == 0 || maximumPositions_ > 64) {
            revert DeltaV3LPAdapter.InvalidConfiguration();
        }
        // The explicit bound above makes this conversion exact.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint8 maximumPositions = uint8(maximumPositions_);
        config = DeltaV3LPAdapter.Config({
            sleeve: vm.parseJsonAddress(json, ".config.sleeve"),
            weth: vm.parseJsonAddress(json, ".config.weth"),
            pairedAsset: vm.parseJsonAddress(json, ".config.pairedAsset"),
            priceHub: vm.parseJsonAddress(json, ".config.priceHub"),
            pool: vm.parseJsonAddress(json, ".config.pool"),
            positionManager: vm.parseJsonAddress(json, ".config.positionManager"),
            positionBuilder: vm.parseJsonAddress(json, ".config.positionBuilder"),
            entryRoute: vm.parseJsonAddress(json, ".config.entryRoute"),
            exitRoute: vm.parseJsonAddress(json, ".config.exitRoute"),
            poolCodeHash: vm.parseJsonBytes32(json, ".config.poolCodeHash"),
            factoryCodeHash: vm.parseJsonBytes32(json, ".config.factoryCodeHash"),
            positionManagerCodeHash: vm.parseJsonBytes32(json, ".config.positionManagerCodeHash"),
            positionBuilderCodeHash: vm.parseJsonBytes32(json, ".config.positionBuilderCodeHash"),
            entryRouteCodeHash: vm.parseJsonBytes32(json, ".config.entryRouteCodeHash"),
            exitRouteCodeHash: vm.parseJsonBytes32(json, ".config.exitRouteCodeHash"),
            maximumPositions: maximumPositions
        });
    }
}
