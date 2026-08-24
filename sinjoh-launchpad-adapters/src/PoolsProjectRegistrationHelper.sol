// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {
    ProjectLaunchConfig,
    ProjectLaunchPreview
} from "@sinjoh-v2/core/ProjectLauncherTypes.sol";

interface IProjectLauncherRegistrationTarget {
    function predictExistingTokenLaunch(ProjectLaunchConfig calldata config, address subject)
        external
        view
        returns (ProjectLaunchPreview memory);
    function launchExistingToken(
        ProjectLaunchConfig calldata config,
        address subject,
        bytes32[] calldata proof
    ) external returns (ProjectLaunchPreview memory);
}

/// @notice Stateless delegate target for Pools adapters registering their canonical token.
contract PoolsProjectRegistrationHelper {
    error MissingProjectCustodyExclusion(address account);
    error ProjectRouterMismatch(address expected, address actual);
    error ProjectLaunchMismatch(address expected, address actual);
    error ProjectSaltMismatch(bytes32 expected, bytes32 actual);

    function registerEncoded(
        address projectLauncher,
        address token,
        address router,
        address[] calldata requiredCustody,
        bytes32 expectedSalt,
        bytes calldata projectLaunchData
    ) external {
        (ProjectLaunchConfig memory config, bytes32[] memory proof) =
            abi.decode(projectLaunchData, (ProjectLaunchConfig, bytes32[]));
        if (config.salt != expectedSalt) revert ProjectSaltMismatch(expectedSalt, config.salt);
        for (uint256 i; i < requiredCustody.length; ++i) {
            _requireCustody(config.launchProfile.additionalCustodyExclusions, requiredCustody[i]);
        }
        IProjectLauncherRegistrationTarget launcher =
            IProjectLauncherRegistrationTarget(projectLauncher);
        ProjectLaunchPreview memory predicted = launcher.predictExistingTokenLaunch(config, token);
        if (predicted.addresses.router != router) {
            revert ProjectRouterMismatch(router, predicted.addresses.router);
        }
        ProjectLaunchPreview memory result = launcher.launchExistingToken(config, token, proof);
        if (
            result.addresses.subject != token || result.addresses.router != router
                || result.projectId != predicted.projectId
        ) revert ProjectLaunchMismatch(token, result.addresses.subject);
    }

    function _requireCustody(address[] memory values, address required) private pure {
        for (uint256 i; i < values.length; ++i) {
            if (values[i] == required) return;
        }
        revert MissingProjectCustodyExclusion(required);
    }
}
