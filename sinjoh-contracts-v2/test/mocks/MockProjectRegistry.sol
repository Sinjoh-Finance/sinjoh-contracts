// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IProjectControlled } from "../../src/interfaces/IProjectControlled.sol";
import { IProjectModule } from "../../src/interfaces/IProjectModule.sol";
import { ProjectRegistryV2 } from "../../src/core/ProjectRegistryV2.sol";

contract MockRegistryLauncher {
    function register(
        ProjectRegistryV2 registry,
        ProjectRegistryV2.ProjectRegistration calldata registration,
        bytes32 configHash,
        string calldata metadataURI
    ) external returns (bytes32) {
        return registry.registerProject(registration, configHash, metadataURI);
    }
}

contract MockRegistryModule is IProjectModule, IProjectControlled {
    address public immutable override registry;
    address public immutable override subject;
    bytes32 public immutable override(IProjectModule, IProjectControlled) projectId;
    address public immutable override controller;

    constructor(address registry_, address subject_, bytes32 projectId_, address controller_) {
        registry = registry_;
        subject = subject_;
        projectId = projectId_;
        controller = controller_;
    }
}

    contract MockRegistryUncontrolledModule is IProjectModule {
        address public immutable override registry;
        address public immutable override subject;
        bytes32 public immutable override projectId;

        constructor(address registry_, address subject_, bytes32 projectId_) {
            registry = registry_;
            subject = subject_;
            projectId = projectId_;
        }
    }
