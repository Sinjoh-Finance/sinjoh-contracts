// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ProjectRegistryV2 } from "../src/core/ProjectRegistryV2.sol";
import { ProjectVotesToken } from "../src/token/ProjectVotesToken.sol";
import { MockProjectController } from "./mocks/MockTreasuryIntegrations.sol";
import { MockRegistryLauncher } from "./mocks/MockProjectRegistry.sol";
import { TestBase } from "./TestBase.sol";

abstract contract RegistryTestBase is TestBase {
    uint256 internal constant START = 1_000_000;
    address internal constant CREATOR = address(0xC0FFEE);
    address internal constant HOLDER = address(0xA11CE);
    bytes32 internal constant CONFIG_HASH = keccak256("launch config");

    MockRegistryLauncher internal registryLauncher;
    ProjectRegistryV2 internal registry;
    ProjectVotesToken internal token;
    MockProjectController internal projectController;

    function _setUpRegistry() internal {
        vm.warp(START);
        registryLauncher =
            MockRegistryLauncher(vm.deployCode("MockProjectRegistry.sol:MockRegistryLauncher"));
        registry = ProjectRegistryV2(
            vm.deployCode(
                "ProjectRegistryV2.sol:ProjectRegistryV2", abi.encode(address(registryLauncher))
            )
        );
        ProjectVotesToken.TokenAllocation[] memory allocations =
            new ProjectVotesToken.TokenAllocation[](1);
        allocations[0] = ProjectVotesToken.TokenAllocation({ recipient: HOLDER, amount: 1_000e18 });
        token = ProjectVotesToken(
            vm.deployCode(
                "ProjectVotesToken.sol:ProjectVotesToken",
                abi.encode(
                    "Project Token",
                    "PROJECT",
                    address(registry),
                    CREATOR,
                    allocations,
                    new address[](0)
                )
            )
        );
        projectController = MockProjectController(
            vm.deployCode(
                "MockTreasuryIntegrations.sol:MockProjectController", abi.encode(token.projectId())
            )
        );
    }

    function _multisigRegistration()
        internal
        view
        returns (ProjectRegistryV2.ProjectRegistration memory registration)
    {
        registration.subject = address(token);
        registration.creator = CREATOR;
        registration.governanceMode = ProjectRegistryV2.GovernanceMode.MULTISIG;
        registration.controller = address(projectController);
        registration.multisigAccount = address(projectController);
        registration.referenceSupply = token.initialSupply();
    }

    function _register(
        ProjectRegistryV2.ProjectRegistration memory registration,
        string memory metadataURI
    ) internal returns (bytes32) {
        return registryLauncher.register(registry, registration, CONFIG_HASH, metadataURI);
    }
}
