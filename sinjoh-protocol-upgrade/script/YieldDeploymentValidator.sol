// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IGovernanceController } from "../src/interfaces/IGovernanceController.sol";
import { IYieldAdapter } from "../src/interfaces/IYieldAdapter.sol";
import { YieldDeploymentTypes } from "./YieldDeploymentTypes.sol";

interface ITreasuryDeploymentReadback {
    function governor() external view returns (address);
    function pendingGovernor() external view returns (address);
    function GOVERNOR_HANDOFF_DELAY() external view returns (uint256);
    function RECOVERY_ADDRESS() external view returns (address);
    function RECOVERY_INACTIVITY_PERIOD() external view returns (uint256);
}

interface ITimelockDeploymentReadback {
    function hasRole(bytes32 role, address account) external view returns (bool);
}

library YieldDeploymentValidator {
    uint256 internal constant ROBINHOOD_MAINNET_CHAIN_ID = 4_663;
    uint16 internal constant BPS = 10_000;
    uint8 internal constant MAX_ADAPTERS = 16;
    uint8 internal constant MAX_REWARDS_PER_ADAPTER = 8;
    bytes32 internal constant DEFAULT_ADMIN_ROLE = bytes32(0);
    bytes32 internal constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 internal constant CANCELLER_ROLE = keccak256("CANCELLER_ROLE");
    bytes32 internal constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    error InvalidSchemaVersion(uint256 actual);
    error WrongChain(uint256 expected, uint256 actual);
    error WrongDeployer(address expected, address actual);
    error InvalidAddress(string field, address value);
    error InvalidGovernanceMode();
    error InvalidGuardian();
    error RuntimeCodeHashMismatch(string field, bytes32 expected, bytes32 actual);
    error TreasuryReadbackMismatch();
    error TimelockRoleMismatch();
    error InvalidAdapterPlan(uint256 index);
    error InvalidRewardRoute(uint256 index);
    error TooManyAdapters(uint256 actual);
    error TooManyRewardRoutes(uint256 adapterIndex, uint256 actual);

    function validate(YieldDeploymentTypes.Parameters memory parameters, address deployer)
        external
        view
    {
        if (parameters.schemaVersion != 1) {
            revert InvalidSchemaVersion(parameters.schemaVersion);
        }
        if (parameters.chainId != ROBINHOOD_MAINNET_CHAIN_ID) {
            revert WrongChain(ROBINHOOD_MAINNET_CHAIN_ID, parameters.chainId);
        }
        if (block.chainid != ROBINHOOD_MAINNET_CHAIN_ID) {
            revert WrongChain(ROBINHOOD_MAINNET_CHAIN_ID, block.chainid);
        }
        if (parameters.expectedDeployer == address(0)) {
            revert InvalidAddress("expectedDeployer", parameters.expectedDeployer);
        }
        if (deployer != parameters.expectedDeployer) {
            revert WrongDeployer(parameters.expectedDeployer, deployer);
        }
        if (parameters.governanceMode == IGovernanceController.Mode.INDIVIDUAL) {
            revert InvalidGovernanceMode();
        }
        _requireCodeHash("authority", parameters.authority, parameters.authorityRuntimeCodeHash);
        if (
            parameters.emergencyGuardian == address(0)
                || parameters.emergencyGuardian == parameters.authority
                || parameters.emergencyGuardian == parameters.treasury
        ) revert InvalidGuardian();
        _requireCodeHash("treasury", parameters.treasury, parameters.treasuryRuntimeCodeHash);
        _requireCodeHash(
            "depositAsset", parameters.depositAsset, parameters.depositAssetRuntimeCodeHash
        );
        if (parameters.expectedBasket == address(0)) {
            revert InvalidAddress("expectedBasket", parameters.expectedBasket);
        }
        ITreasuryDeploymentReadback treasury = ITreasuryDeploymentReadback(parameters.treasury);
        if (
            treasury.governor() != parameters.authority || treasury.pendingGovernor() != address(0)
                || treasury.GOVERNOR_HANDOFF_DELAY() != parameters.treasuryGovernorHandoffDelay
                || treasury.RECOVERY_ADDRESS() != parameters.treasuryRecoveryAddress
                || treasury.RECOVERY_INACTIVITY_PERIOD()
                    != parameters.treasuryRecoveryInactivityPeriod
        ) revert TreasuryReadbackMismatch();

        if (parameters.governanceMode == IGovernanceController.Mode.MULTISIG) {
            if (parameters.tokenGovernor != address(0)) {
                revert InvalidAddress("tokenGovernor", parameters.tokenGovernor);
            }
        } else if (parameters.governanceMode == IGovernanceController.Mode.TOKEN_GOVERNOR) {
            if (parameters.tokenGovernor.code.length == 0) {
                revert InvalidAddress("tokenGovernor", parameters.tokenGovernor);
            }
            ITimelockDeploymentReadback timelock = ITimelockDeploymentReadback(parameters.authority);
            if (
                timelock.hasRole(DEFAULT_ADMIN_ROLE, deployer)
                    || !timelock.hasRole(PROPOSER_ROLE, parameters.tokenGovernor)
                    || !timelock.hasRole(CANCELLER_ROLE, parameters.tokenGovernor)
                    || !timelock.hasRole(EXECUTOR_ROLE, address(0))
            ) revert TimelockRoleMismatch();
        } else {
            revert InvalidGovernanceMode();
        }

        uint256 adapterCount = parameters.adapters.length;
        if (adapterCount == 0 || adapterCount > MAX_ADAPTERS) {
            revert TooManyAdapters(adapterCount);
        }
        uint256[] memory routeCounts = new uint256[](adapterCount);
        for (uint256 i; i < adapterCount; ++i) {
            YieldDeploymentTypes.AdapterPlan memory plan = parameters.adapters[i];
            _requireCodeHash("adapter", plan.adapter, plan.runtimeCodeHash);
            if (
                IYieldAdapter(plan.adapter).asset() != parameters.depositAsset
                    || IYieldAdapter(plan.adapter).basket() != parameters.expectedBasket
                    || plan.allocationLimitBps == 0 || plan.allocationLimitBps > BPS
                    || plan.distributionInterval < 30 minutes
            ) revert InvalidAdapterPlan(i);
            for (uint256 j; j < i; ++j) {
                if (parameters.adapters[j].adapter == plan.adapter) revert InvalidAdapterPlan(i);
            }
        }
        for (uint256 i; i < parameters.rewardRoutes.length; ++i) {
            YieldDeploymentTypes.RewardRoutePlan memory route = parameters.rewardRoutes[i];
            uint256 adapterIndex = type(uint256).max;
            for (uint256 j; j < adapterCount; ++j) {
                if (parameters.adapters[j].adapter == route.adapter) adapterIndex = j;
            }
            if (
                adapterIndex == type(uint256).max || route.rewardToken == parameters.depositAsset
                    || route.distributionConfig.length > 2_048
            ) revert InvalidRewardRoute(i);
            _requireCodeHash("rewardToken", route.rewardToken, route.rewardTokenRuntimeCodeHash);
            _requireCodeHash("distributor", route.distributor, route.distributorRuntimeCodeHash);
            for (uint256 j; j < i; ++j) {
                if (
                    parameters.rewardRoutes[j].adapter == route.adapter
                        && parameters.rewardRoutes[j].rewardToken == route.rewardToken
                ) revert InvalidRewardRoute(i);
            }
            ++routeCounts[adapterIndex];
            if (routeCounts[adapterIndex] > MAX_REWARDS_PER_ADAPTER) {
                revert TooManyRewardRoutes(adapterIndex, routeCounts[adapterIndex]);
            }
        }
    }

    function _requireCodeHash(string memory field, address account, bytes32 expected) private view {
        if (account.code.length == 0) revert InvalidAddress(field, account);
        bytes32 actual = account.codehash;
        if (actual != expected) revert RuntimeCodeHashMismatch(field, expected, actual);
    }
}
