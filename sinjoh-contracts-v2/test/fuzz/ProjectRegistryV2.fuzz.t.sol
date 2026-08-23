// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ProjectRegistryV2 } from "../../src/core/ProjectRegistryV2.sol";
import { ProjectModuleBits } from "../../src/libraries/ProjectModuleBits.sol";
import { RegistryTestBase } from "../RegistryTestBase.sol";
import {
    MockRegistryModule,
    MockRegistryUncontrolledModule
} from "../mocks/MockProjectRegistry.sol";

contract ProjectRegistryV2FuzzTest is RegistryTestBase {
    function setUp() public {
        _setUpRegistry();
    }

    function testFuzzMetadataWithinBoundPublishesExactBytes(bytes memory rawURI) public {
        vm.assume(rawURI.length <= registry.MAX_METADATA_URI_BYTES());
        bytes32 projectId = _register(_multisigRegistration(), "");
        if (rawURI.length == 0) rawURI = bytes("changed");
        string memory uri = string(rawURI);
        projectController.execute(
            address(registry), abi.encodeCall(registry.updateMetadataURI, (projectId, uri))
        );
        assertEq(keccak256(bytes(registry.metadataURI(projectId))), keccak256(rawURI));
        assertEq(registry.metadataHash(projectId), keccak256(rawURI));
        assertEq(registry.metadataVersion(projectId), 2);
    }

    function testFuzzOversizedMetadataAlwaysReverts(uint16 rawExtra) public {
        uint256 length = registry.MAX_METADATA_URI_BYTES() + 1 + uint256(rawExtra % 512);
        string memory oversized = string(new bytes(length));
        ProjectRegistryV2.ProjectRegistration memory registration = _multisigRegistration();
        vm.expectPartialRevert(ProjectRegistryV2.MetadataURITooLong.selector);
        _register(registration, oversized);
    }

    function testFuzzReferenceSupplyMismatchAlwaysRejects(uint256 supplied) public {
        vm.assume(supplied != token.initialSupply());
        ProjectRegistryV2.ProjectRegistration memory registration = _multisigRegistration();
        registration.referenceSupply = supplied;
        vm.expectPartialRevert(ProjectRegistryV2.InvalidReferenceSupply.selector);
        _register(registration, "");
    }

    function testFuzzLaunchConfigHashRoundTripsExactly(bytes32 configHash) public {
        ProjectRegistryV2.ProjectRegistration memory registration = _multisigRegistration();
        bytes32 projectId = registryLauncher.register(registry, registration, configHash, "");
        assertEq(registry.launchConfigHash(projectId), configHash);
    }

    function testFuzzUnknownModuleBitsAlwaysReject(uint248 rawUnknown) public {
        uint256 unknown = (uint256(rawUnknown) << 8) | (1 << 8);
        ProjectRegistryV2.ProjectRegistration memory registration = _multisigRegistration();
        registration.enabledModules = unknown;
        vm.expectPartialRevert(ProjectRegistryV2.InvalidEnabledModules.selector);
        _register(registration, "");
    }

    function testFuzzOneEnabledModuleGetsExactConstantTimeMembership(uint8 rawChoice) public {
        uint256 choice = uint256(rawChoice % 6);
        ProjectRegistryV2.ProjectRegistration memory registration = _multisigRegistration();
        uint256 bit;
        address module;
        if (choice < 3) {
            bit = choice == 0
                ? ProjectModuleBits.TREASURY
                : choice == 1 ? ProjectModuleBits.ROUTER : ProjectModuleBits.FUNDING_BANDS;
            module = vm.deployCode(
                "MockProjectRegistry.sol:MockRegistryModule",
                abi.encode(
                    address(registry), address(token), token.projectId(), address(projectController)
                )
            );
            if (choice == 0) registration.treasury = module;
            else if (choice == 1) registration.router = module;
            else registration.fundingBands = module;
        } else {
            bit = choice == 3
                ? ProjectModuleBits.AIRDROP
                : choice == 4 ? ProjectModuleBits.RAFFLE : ProjectModuleBits.LIQUIDITY;
            module = address(
                MockRegistryUncontrolledModule(
                    vm.deployCode(
                        "MockProjectRegistry.sol:MockRegistryUncontrolledModule",
                        abi.encode(address(registry), address(token), token.projectId())
                    )
                )
            );
            if (choice == 3) registration.airdrop = module;
            else if (choice == 4) registration.raffle = module;
            else registration.liquidityManager = module;
        }
        registration.enabledModules = bit;
        bytes32 projectId = _register(registration, "");
        assertEq(registry.moduleBits(projectId, module), bit);
        assertTrue(registry.isProjectModule(projectId, module));
        assertTrue(registry.hasModule(projectId, bit));
        assertEq(registry.project(projectId).enabledModules, bit);
    }
}
