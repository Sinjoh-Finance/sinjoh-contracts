// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ProjectRegistryV2 } from "../../src/core/ProjectRegistryV2.sol";
import { ProjectTimelockV2 } from "../../src/governance/ProjectTimelockV2.sol";
import { TokenGovernanceConfig } from "../../src/governance/TokenGovernanceConfig.sol";
import { ProjectModuleBits } from "../../src/libraries/ProjectModuleBits.sol";
import { ProjectStakingPoolV2 } from "../../src/staking/ProjectStakingPoolV2.sol";
import { ProjectTreasuryVaultV2 } from "../../src/treasury/ProjectTreasuryVaultV2.sol";
import { RegistryTestBase } from "../RegistryTestBase.sol";
import { MockRegistryModule } from "../mocks/MockProjectRegistry.sol";

contract ProjectRegistryV2Test is RegistryTestBase {
    function setUp() public {
        _setUpRegistry();
    }

    function testConstructorPublishesOnlyLauncherAndVersion() public view {
        assertEq(registry.launcher(), address(registryLauncher));
        assertEq(registry.PROTOCOL_VERSION(), 2);
        assertEq(registry.projectCount(), 0);
    }

    function testOnlyLauncherCanRegister() public {
        ProjectRegistryV2.ProjectRegistration memory registration = _multisigRegistration();
        vm.expectPartialRevert(ProjectRegistryV2.OnlyLauncher.selector);
        registry.registerProject(registration, CONFIG_HASH, "ipfs://project");
    }

    function testRegistrationPublishesCompleteCanonicalRecordAndDiscoveryViews() public {
        ProjectRegistryV2.ProjectRegistration memory registration = _multisigRegistration();
        bytes32 projectId = _register(registration, "ipfs://project");
        ProjectRegistryV2.ProjectRecord memory record = registry.project(projectId);
        assertEq(record.projectId, token.projectId());
        assertEq(record.subject, address(token));
        assertEq(record.creator, CREATOR);
        assertEq(record.controller, address(projectController));
        assertEq(record.multisigAccount, address(projectController));
        assertEq(record.referenceSupply, 1_000e18);
        assertEq(record.launchedAt, START);
        assertEq(record.protocolVersion, 2);
        assertEq(record.enabledModules, 0);
        assertEq(registry.projectIdBySubject(address(token)), projectId);
        assertEq(registry.projectIdAt(0), projectId);
        assertEq(registry.launchConfigHash(projectId), CONFIG_HASH);
        assertEq(registry.metadataURI(projectId), "ipfs://project");
        assertEq(registry.metadataVersion(projectId), 1);
        assertEq(registry.projectBySubject(address(token)).projectId, projectId);
    }

    function testProjectAndSubjectCanNeverBeRegisteredTwice() public {
        ProjectRegistryV2.ProjectRegistration memory registration = _multisigRegistration();
        _register(registration, "");
        vm.expectPartialRevert(ProjectRegistryV2.ProjectAlreadyRegistered.selector);
        _register(registration, "");
        assertEq(registry.projectCount(), 1);
    }

    function testReferenceSupplyMustMatchTokenFixedLaunchSupply() public {
        ProjectRegistryV2.ProjectRegistration memory registration = _multisigRegistration();
        registration.referenceSupply -= 1;
        vm.expectPartialRevert(ProjectRegistryV2.InvalidReferenceSupply.selector);
        _register(registration, "");
    }

    function testMultisigModeRejectsTokenGovernanceAddresses() public {
        ProjectRegistryV2.ProjectRegistration memory registration = _multisigRegistration();
        registration.voteSource = address(token);
        vm.expectPartialRevert(ProjectRegistryV2.InvalidGovernanceConfiguration.selector);
        _register(registration, "");
    }

    function testTokenGovernanceModePublishesExplicitWorkflowAddresses() public {
        TokenGovernanceConfig memory config = TokenGovernanceConfig({
            votingDelay: 1 days,
            votingPeriod: 3 days,
            proposalThresholdBps: 100,
            quorumBps: 1_000,
            timelockDelay: 1 days,
            referenceSupply: token.initialSupply()
        });
        ProjectTimelockV2 timelock = ProjectTimelockV2(
            payable(vm.deployCode(
                    "ProjectTimelockV2.sol:ProjectTimelockV2",
                    abi.encode(address(registry), address(token), address(token), config)
                ))
        );
        ProjectRegistryV2.ProjectRegistration memory registration = _multisigRegistration();
        registration.governanceMode = ProjectRegistryV2.GovernanceMode.TOKEN_HOLDER;
        registration.controller = address(timelock);
        registration.multisigAccount = address(0);
        registration.tokenGovernor = address(timelock.governor());
        registration.tokenTimelock = address(timelock);
        registration.voteSource = address(token);
        bytes32 projectId = _register(registration, "");
        ProjectRegistryV2.ProjectRecord memory record = registry.project(projectId);
        assertEq(record.controller, address(timelock));
        assertEq(record.tokenGovernor, address(timelock.governor()));
        assertEq(record.tokenTimelock, address(timelock));
        assertEq(record.voteSource, address(token));
        assertEq(record.multisigAccount, address(0));
    }

    function testStakedGovernanceRejectsPoolNotControlledByItsTimelock() public {
        ProjectStakingPoolV2 staking = ProjectStakingPoolV2(
            vm.deployCode(
                "ProjectStakingPoolV2.sol:ProjectStakingPoolV2",
                abi.encode(
                    address(registry),
                    address(token),
                    address(0x777),
                    address(projectController),
                    address(0),
                    1 days,
                    new address[](0)
                )
            )
        );
        TokenGovernanceConfig memory config = TokenGovernanceConfig({
            votingDelay: 1 days,
            votingPeriod: 3 days,
            proposalThresholdBps: 100,
            quorumBps: 1_000,
            timelockDelay: 1 days,
            referenceSupply: token.initialSupply()
        });
        ProjectTimelockV2 timelock = ProjectTimelockV2(
            payable(vm.deployCode(
                    "ProjectTimelockV2.sol:ProjectTimelockV2",
                    abi.encode(address(registry), address(token), address(staking), config)
                ))
        );
        ProjectRegistryV2.ProjectRegistration memory registration = _multisigRegistration();
        registration.governanceMode = ProjectRegistryV2.GovernanceMode.TOKEN_HOLDER;
        registration.controller = address(timelock);
        registration.multisigAccount = address(0);
        registration.tokenGovernor = address(timelock.governor());
        registration.tokenTimelock = address(timelock);
        registration.voteSource = address(staking);
        registration.stakingPool = address(staking);
        registration.posNft = address(staking.posNFT());
        registration.enabledModules = ProjectModuleBits.STAKING;
        vm.expectPartialRevert(ProjectRegistryV2.ModuleControllerMismatch.selector);
        _register(registration, "");
    }

    function testTreasuryModuleIsValidatedAndIndexedWithoutControllerProbingByUI() public {
        ProjectTreasuryVaultV2 treasury = ProjectTreasuryVaultV2(
            payable(vm.deployCode(
                    "ProjectTreasuryVaultV2.sol:ProjectTreasuryVaultV2",
                    abi.encode(
                        address(registry),
                        address(token),
                        CREATOR,
                        address(projectController),
                        bytes32(0),
                        address(0)
                    )
                ))
        );
        ProjectRegistryV2.ProjectRegistration memory registration = _multisigRegistration();
        registration.treasury = address(treasury);
        registration.enabledModules = ProjectModuleBits.TREASURY;
        bytes32 projectId = _register(registration, "");
        assertTrue(registry.hasModule(projectId, ProjectModuleBits.TREASURY));
        assertTrue(registry.isProjectModule(projectId, address(treasury)));
        assertEq(registry.moduleBits(projectId, address(treasury)), ProjectModuleBits.TREASURY);
    }

    function testEnabledModuleRequiresNonzeroContractAndDisabledModuleRequiresZero() public {
        ProjectRegistryV2.ProjectRegistration memory registration = _multisigRegistration();
        registration.enabledModules = ProjectModuleBits.TREASURY;
        vm.expectPartialRevert(ProjectRegistryV2.ModuleSelectionMismatch.selector);
        _register(registration, "");

        registration.enabledModules = 0;
        registration.treasury = address(0x1234);
        vm.expectPartialRevert(ProjectRegistryV2.ModuleSelectionMismatch.selector);
        _register(registration, "");
    }

    function testModuleMustShareExactProjectIdentityAndController() public {
        MockRegistryModule wrongIdentity = MockRegistryModule(
            vm.deployCode(
                "MockProjectRegistry.sol:MockRegistryModule",
                abi.encode(
                    address(registry),
                    address(token),
                    bytes32(uint256(123)),
                    address(projectController)
                )
            )
        );
        ProjectRegistryV2.ProjectRegistration memory registration = _multisigRegistration();
        registration.treasury = address(wrongIdentity);
        registration.enabledModules = ProjectModuleBits.TREASURY;
        vm.expectPartialRevert(ProjectRegistryV2.ModuleIdentityMismatch.selector);
        _register(registration, "");

        MockRegistryModule wrongController = MockRegistryModule(
            vm.deployCode(
                "MockProjectRegistry.sol:MockRegistryModule",
                abi.encode(address(registry), address(token), token.projectId(), address(0x999))
            )
        );
        registration.treasury = address(wrongController);
        vm.expectPartialRevert(ProjectRegistryV2.ModuleControllerMismatch.selector);
        _register(registration, "");
    }

    function testStakingRegistrationValidatesBoundPoSNftAndIndexesBoth() public {
        ProjectStakingPoolV2 staking = ProjectStakingPoolV2(
            vm.deployCode(
                "ProjectStakingPoolV2.sol:ProjectStakingPoolV2",
                abi.encode(
                    address(registry),
                    address(token),
                    address(0x777),
                    address(projectController),
                    address(0),
                    1 days,
                    new address[](0)
                )
            )
        );
        ProjectRegistryV2.ProjectRegistration memory registration = _multisigRegistration();
        registration.stakingPool = address(staking);
        registration.posNft = address(staking.posNFT());
        registration.enabledModules = ProjectModuleBits.STAKING;
        bytes32 projectId = _register(registration, "");
        assertEq(registry.moduleBits(projectId, address(staking)), ProjectModuleBits.STAKING);
        assertEq(
            registry.moduleBits(projectId, address(staking.posNFT())), ProjectModuleBits.STAKING
        );
    }

    function testBasketRequiresTreasuryAndAirdropBeforeAnyModuleCall() public {
        ProjectRegistryV2.ProjectRegistration memory registration = _multisigRegistration();
        registration.enabledModules = ProjectModuleBits.BASKET;
        registration.basketManager = address(0x1234);
        vm.expectPartialRevert(ProjectRegistryV2.InvalidModuleDependencies.selector);
        _register(registration, "");
    }

    function testUnknownEnabledBitsAreRejected() public {
        ProjectRegistryV2.ProjectRegistration memory registration = _multisigRegistration();
        registration.enabledModules = 1 << 255;
        vm.expectPartialRevert(ProjectRegistryV2.InvalidEnabledModules.selector);
        _register(registration, "");
    }

    function testControllerCanPublishMetadataWithoutChangingCanonicalRecord() public {
        bytes32 projectId = _register(_multisigRegistration(), "ipfs://v1");
        bytes32 recordHashBefore = keccak256(abi.encode(registry.project(projectId)));
        projectController.execute(
            address(registry), abi.encodeCall(registry.updateMetadataURI, (projectId, "ipfs://v2"))
        );
        assertEq(registry.metadataURI(projectId), "ipfs://v2");
        assertEq(registry.metadataVersion(projectId), 2);
        assertEq(keccak256(abi.encode(registry.project(projectId))), recordHashBefore);
    }

    function testMetadataUpdateRejectsNonControllerOversizedAndUnchangedValues() public {
        bytes32 projectId = _register(_multisigRegistration(), "ipfs://v1");
        vm.expectPartialRevert(ProjectRegistryV2.OnlyProjectController.selector);
        registry.updateMetadataURI(projectId, "ipfs://v2");

        vm.expectPartialRevert(ProjectRegistryV2.MetadataUnchanged.selector);
        projectController.execute(
            address(registry), abi.encodeCall(registry.updateMetadataURI, (projectId, "ipfs://v1"))
        );

        string memory oversized = string(new bytes(registry.MAX_METADATA_URI_BYTES() + 1));
        vm.expectPartialRevert(ProjectRegistryV2.MetadataURITooLong.selector);
        projectController.execute(
            address(registry), abi.encodeCall(registry.updateMetadataURI, (projectId, oversized))
        );
    }

    function testUnknownProjectViewsGiveExplicitError() public {
        vm.expectPartialRevert(ProjectRegistryV2.UnknownProject.selector);
        registry.project(bytes32(uint256(123)));
        vm.expectPartialRevert(ProjectRegistryV2.UnknownProject.selector);
        registry.projectBySubject(address(0x1234));
        vm.expectPartialRevert(ProjectRegistryV2.UnknownProject.selector);
        registry.metadataURI(bytes32(uint256(123)));
    }

    function testRegistryHasNoAssetCustodyOrGenericExecutionSurface() public {
        vm.deal(address(registry), 1 ether);
        (bool success,) = address(registry).call{ value: 1 ether }("");
        assertFalse(success);
        assertEq(address(registry).balance, 1 ether);
    }
}
