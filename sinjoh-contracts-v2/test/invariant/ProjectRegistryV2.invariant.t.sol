// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ProjectRegistryV2 } from "../../src/core/ProjectRegistryV2.sol";
import { MockProjectController } from "../mocks/MockTreasuryIntegrations.sol";
import { RegistryTestBase } from "../RegistryTestBase.sol";

contract ProjectRegistryV2Handler {
    ProjectRegistryV2 public immutable registry;
    MockProjectController public immutable projectController;
    bytes32 public immutable projectId;

    constructor(
        ProjectRegistryV2 registry_,
        MockProjectController projectController_,
        bytes32 projectId_
    ) {
        registry = registry_;
        projectController = projectController_;
        projectId = projectId_;
    }

    function updateMetadata(bytes32 rawMetadata) external {
        string memory uri = string(abi.encodePacked("ipfs://", rawMetadata));
        try projectController.execute(
            address(registry), abi.encodeCall(registry.updateMetadataURI, (projectId, uri))
        ) { }
            catch { }
    }

    function attemptDirectUpdate(bytes32 rawMetadata) external {
        string memory uri = string(abi.encodePacked("ipfs://", rawMetadata));
        try registry.updateMetadataURI(projectId, uri) { } catch { }
    }
}

contract ProjectRegistryV2InvariantTest is RegistryTestBase {
    ProjectRegistryV2Handler private handler;
    bytes32 private projectId;
    bytes32 private initialRecordHash;

    function setUp() public {
        _setUpRegistry();
        projectId = _register(_multisigRegistration(), "ipfs://initial");
        initialRecordHash = keccak256(abi.encode(registry.project(projectId)));
        handler = new ProjectRegistryV2Handler(registry, projectController, projectId);
        targetContract(address(handler));
    }

    function invariantCanonicalRecordNeverChanges() public view {
        assertEq(keccak256(abi.encode(registry.project(projectId))), initialRecordHash);
    }

    function invariantSubjectResolutionAndEnumerationNeverChange() public view {
        assertEq(registry.projectIdBySubject(address(token)), projectId);
        assertEq(registry.projectIdAt(0), projectId);
        assertEq(registry.projectCount(), 1);
    }

    function invariantLaunchFactsNeverChangeWithMetadata() public view {
        assertEq(registry.launchConfigHash(projectId), CONFIG_HASH);
        assertEq(registry.project(projectId).controller, address(projectController));
        assertEq(registry.project(projectId).referenceSupply, token.initialSupply());
    }

    function invariantMetadataHashAlwaysMatchesPublishedURI() public view {
        assertEq(
            registry.metadataHash(projectId), keccak256(bytes(registry.metadataURI(projectId)))
        );
        assertGe(registry.metadataVersion(projectId), 1);
    }

    function invariantNoModulesCanAppearAfterRegistration() public view {
        assertEq(registry.project(projectId).enabledModules, 0);
        assertFalse(registry.isProjectModule(projectId, address(handler)));
    }
}
