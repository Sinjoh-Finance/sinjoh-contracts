// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IGovernanceController } from "../src/interfaces/IGovernanceController.sol";

library YieldDeploymentTypes {
    struct AdapterPlan {
        address adapter;
        bytes32 runtimeCodeHash;
        uint16 allocationLimitBps;
        uint32 distributionInterval;
    }

    struct RewardRoutePlan {
        address adapter;
        address rewardToken;
        bytes32 rewardTokenRuntimeCodeHash;
        address distributor;
        bytes32 distributorRuntimeCodeHash;
        bytes distributionConfig;
    }

    struct Parameters {
        uint256 schemaVersion;
        uint256 chainId;
        address expectedDeployer;
        IGovernanceController.Mode governanceMode;
        address authority;
        bytes32 authorityRuntimeCodeHash;
        address tokenGovernor;
        address emergencyGuardian;
        address treasury;
        bytes32 treasuryRuntimeCodeHash;
        uint256 treasuryGovernorHandoffDelay;
        address treasuryRecoveryAddress;
        uint256 treasuryRecoveryInactivityPeriod;
        address depositAsset;
        bytes32 depositAssetRuntimeCodeHash;
        address expectedBasket;
        AdapterPlan[] adapters;
        RewardRoutePlan[] rewardRoutes;
    }
}
