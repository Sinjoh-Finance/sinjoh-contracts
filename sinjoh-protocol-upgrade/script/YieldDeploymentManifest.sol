// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IGovernanceController } from "../src/interfaces/IGovernanceController.sol";
import { YieldDeploymentTypes } from "./YieldDeploymentTypes.sol";

interface VmYieldDeploymentManifest {
    function parseJsonAddress(string calldata json, string calldata key)
        external
        pure
        returns (address);
    function parseJsonBytes(string calldata json, string calldata key)
        external
        pure
        returns (bytes memory);
    function parseJsonBytes32(string calldata json, string calldata key)
        external
        pure
        returns (bytes32);
    function parseJsonString(string calldata json, string calldata key)
        external
        pure
        returns (string memory);
    function parseJsonUint(string calldata json, string calldata key)
        external
        pure
        returns (uint256);
    function toString(uint256 value) external pure returns (string memory);
}

library YieldDeploymentManifest {
    VmYieldDeploymentManifest internal constant vm =
        VmYieldDeploymentManifest(address(uint160(uint256(keccak256("hevm cheat code")))));

    error InvalidGovernanceMode(string mode);
    error NumericOverflow(string field, uint256 value);

    function parse(string memory json)
        external
        pure
        returns (YieldDeploymentTypes.Parameters memory parameters)
    {
        parameters.schemaVersion = vm.parseJsonUint(json, ".schemaVersion");
        parameters.chainId = vm.parseJsonUint(json, ".chainId");
        parameters.expectedDeployer = vm.parseJsonAddress(json, ".expectedDeployer");
        parameters.governanceMode = _parseMode(vm.parseJsonString(json, ".governanceMode"));
        parameters.authority = vm.parseJsonAddress(json, ".authority");
        parameters.authorityRuntimeCodeHash = vm.parseJsonBytes32(json, ".authorityRuntimeCodeHash");
        parameters.tokenGovernor = vm.parseJsonAddress(json, ".tokenGovernor");
        parameters.emergencyGuardian = vm.parseJsonAddress(json, ".emergencyGuardian");
        parameters.treasury = vm.parseJsonAddress(json, ".treasury");
        parameters.treasuryRuntimeCodeHash = vm.parseJsonBytes32(json, ".treasuryRuntimeCodeHash");
        parameters.treasuryGovernorHandoffDelay =
            vm.parseJsonUint(json, ".treasuryGovernorHandoffDelay");
        parameters.treasuryRecoveryAddress = vm.parseJsonAddress(json, ".treasuryRecoveryAddress");
        parameters.treasuryRecoveryInactivityPeriod =
            vm.parseJsonUint(json, ".treasuryRecoveryInactivityPeriod");
        parameters.depositAsset = vm.parseJsonAddress(json, ".depositAsset");
        parameters.depositAssetRuntimeCodeHash =
            vm.parseJsonBytes32(json, ".depositAssetRuntimeCodeHash");
        parameters.expectedBasket = vm.parseJsonAddress(json, ".expectedBasket");

        uint256 adapterCount = vm.parseJsonUint(json, ".adapterCount");
        parameters.adapters = new YieldDeploymentTypes.AdapterPlan[](adapterCount);
        for (uint256 i; i < adapterCount; ++i) {
            string memory prefix = string.concat(".adapters[", vm.toString(i), "]");
            string memory allocationField = string.concat(prefix, ".allocationLimitBps");
            string memory intervalField = string.concat(prefix, ".distributionInterval");
            uint256 allocationLimitBps = vm.parseJsonUint(json, allocationField);
            uint256 distributionInterval = vm.parseJsonUint(json, intervalField);
            if (allocationLimitBps > type(uint16).max) {
                revert NumericOverflow(allocationField, allocationLimitBps);
            }
            if (distributionInterval > type(uint32).max) {
                revert NumericOverflow(intervalField, distributionInterval);
            }
            parameters.adapters[i] = YieldDeploymentTypes.AdapterPlan({
                adapter: vm.parseJsonAddress(json, string.concat(prefix, ".adapter")),
                runtimeCodeHash: vm.parseJsonBytes32(
                    json, string.concat(prefix, ".runtimeCodeHash")
                ),
                allocationLimitBps: uint16(allocationLimitBps),
                distributionInterval: uint32(distributionInterval)
            });
        }

        uint256 routeCount = vm.parseJsonUint(json, ".rewardRouteCount");
        parameters.rewardRoutes = new YieldDeploymentTypes.RewardRoutePlan[](routeCount);
        for (uint256 i; i < routeCount; ++i) {
            string memory prefix = string.concat(".rewardRoutes[", vm.toString(i), "]");
            parameters.rewardRoutes[i] = YieldDeploymentTypes.RewardRoutePlan({
                adapter: vm.parseJsonAddress(json, string.concat(prefix, ".adapter")),
                rewardToken: vm.parseJsonAddress(json, string.concat(prefix, ".rewardToken")),
                rewardTokenRuntimeCodeHash: vm.parseJsonBytes32(
                    json, string.concat(prefix, ".rewardTokenRuntimeCodeHash")
                ),
                distributor: vm.parseJsonAddress(json, string.concat(prefix, ".distributor")),
                distributorRuntimeCodeHash: vm.parseJsonBytes32(
                    json, string.concat(prefix, ".distributorRuntimeCodeHash")
                ),
                distributionConfig: vm.parseJsonBytes(
                    json, string.concat(prefix, ".distributionConfig")
                )
            });
        }
    }

    function _parseMode(string memory value) private pure returns (IGovernanceController.Mode) {
        bytes32 valueHash = keccak256(bytes(value));
        if (valueHash == keccak256("MULTISIG")) return IGovernanceController.Mode.MULTISIG;
        if (valueHash == keccak256("TOKEN_GOVERNOR")) {
            return IGovernanceController.Mode.TOKEN_GOVERNOR;
        }
        revert InvalidGovernanceMode(value);
    }
}
