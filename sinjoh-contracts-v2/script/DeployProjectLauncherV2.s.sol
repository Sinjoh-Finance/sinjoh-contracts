// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { ProjectAirdropV2 } from "../src/airdrop/ProjectAirdropV2.sol";
import { ProjectFundingBandsV2 } from "../src/bands/ProjectFundingBandsV2.sol";
import { FundingBandV3IntegrationFactory } from "../src/bands/FundingBandV3IntegrationFactory.sol";
import {
    UniswapV3FundingBandMarketCapGuard
} from "../src/bands/UniswapV3FundingBandMarketCapGuard.sol";
import {
    UniswapV3FundingBandPositionAdapter
} from "../src/bands/UniswapV3FundingBandPositionAdapter.sol";
import { ProjectTimelockV2 } from "../src/governance/ProjectTimelockV2.sol";
import { ProjectLiquidityManagerV2 } from "../src/liquidity/ProjectLiquidityManagerV2.sol";
import { ProjectMultisigAccountV2 } from "../src/multisig/ProjectMultisigAccountV2.sol";
import { ProjectRaffleV2 } from "../src/raffle/ProjectRaffleV2.sol";
import { ProjectRouterV2 } from "../src/router/ProjectRouterV2.sol";
import { ProjectStakingPoolV2 } from "../src/staking/ProjectStakingPoolV2.sol";
import { ProjectVotesToken } from "../src/token/ProjectVotesToken.sol";
import { ProjectTreasuryVaultV2 } from "../src/treasury/ProjectTreasuryVaultV2.sol";
import { CreationCodeStoreV2 } from "../src/core/CreationCodeStoreV2.sol";
import { ProjectLaunchDeployerV2 } from "../src/core/ProjectLaunchDeployerV2.sol";
import { ProjectLauncherV2 } from "../src/core/ProjectLauncherV2.sol";
import { CreationCodeBinding, LauncherReleaseConfig } from "../src/core/ProjectLauncherTypes.sol";
import { ProjectRegistryV2 } from "../src/core/ProjectRegistryV2.sol";

/// @notice Deploys one immutable v2 release from environment-supplied infrastructure addresses.
/// @dev Registry, engine, and Launcher are deployed in a verified nonce sequence. Project creators
/// interact only with the resulting Launcher address.
contract DeployProjectLauncherV2 is Script {
    function run()
        external
        returns (
            ProjectLauncherV2 launcher,
            ProjectRegistryV2 registry,
            ProjectLaunchDeployerV2 deployer
        )
    {
        address broadcaster = vm.envAddress("DEPLOYER_ADDRESS");
        uint256 expectedChainId = vm.envUint("EXPECTED_CHAIN_ID");
        require(block.chainid == expectedChainId, "WRONG_CHAIN");

        vm.startBroadcast();
        ProjectRaffleV2 raffleImplementation = new ProjectRaffleV2();
        address v3Factory = vm.envAddress("V3_FACTORY");
        address v3PositionManager = vm.envAddress("V3_POSITION_MANAGER");
        FundingBandV3IntegrationFactory fundingBandV3IntegrationFactory =
            new FundingBandV3IntegrationFactory(v3Factory, v3PositionManager);
        CreationCodeBinding[] memory bindings = _deployCreationCodeStores();

        LauncherReleaseConfig memory release = LauncherReleaseConfig({
            protocolFeeRecipient: vm.envAddress("PROTOCOL_FEE_RECIPIENT"),
            integrationApprovalRoot: vm.envBytes32("INTEGRATION_APPROVAL_ROOT"),
            basketEnabled: false,
            raffleImplementation: address(raffleImplementation),
            randomnessAdapter: vm.envAddress("RANDOMNESS_ADAPTER"),
            basketVaultImplementation: address(0),
            erc4626YieldAdapterFactory: address(0),
            fundingBandV3IntegrationFactory: address(fundingBandV3IntegrationFactory),
            v3Factory: v3Factory,
            v3PositionManager: v3PositionManager,
            v4PositionManager: vm.envAddress("V4_POSITION_MANAGER"),
            v4StateView: vm.envAddress("V4_STATE_VIEW"),
            permit2: vm.envAddress("PERMIT2")
        });

        uint64 nonce = vm.getNonce(broadcaster);
        address predictedRegistry = vm.computeCreateAddress(broadcaster, nonce);
        address predictedDeployer = vm.computeCreateAddress(broadcaster, nonce + 1);
        address predictedLauncher = vm.computeCreateAddress(broadcaster, nonce + 2);

        registry = new ProjectRegistryV2(predictedLauncher);
        deployer =
            new ProjectLaunchDeployerV2(predictedLauncher, predictedRegistry, release, bindings);
        launcher = new ProjectLauncherV2(predictedRegistry, predictedDeployer);
        vm.stopBroadcast();

        require(address(registry) == predictedRegistry, "REGISTRY_ADDRESS_MISMATCH");
        require(address(deployer) == predictedDeployer, "DEPLOYER_ADDRESS_MISMATCH");
        require(address(launcher) == predictedLauncher, "LAUNCHER_ADDRESS_MISMATCH");
        _verifyRelease(launcher, registry, deployer);
        string memory manifestPath = _writeManifest(launcher, registry, deployer, broadcaster);
        console2.log("ProjectRegistryV2", address(registry));
        console2.log("ProjectLaunchDeployerV2", address(deployer));
        console2.log("ProjectLauncherV2", address(launcher));
        console2.log("Deployment manifest", manifestPath);
    }

    function _deployCreationCodeStores() private returns (CreationCodeBinding[] memory bindings) {
        bindings = new CreationCodeBinding[](9);
        bindings[0] = _binding(keccak256("TOKEN"), type(ProjectVotesToken).creationCode);
        bindings[1] = _binding(keccak256("MULTISIG"), type(ProjectMultisigAccountV2).creationCode);
        bindings[2] = _binding(keccak256("TIMELOCK"), type(ProjectTimelockV2).creationCode);
        bindings[3] = _binding(keccak256("STAKING"), type(ProjectStakingPoolV2).creationCode);
        bindings[4] = _binding(keccak256("TREASURY"), type(ProjectTreasuryVaultV2).creationCode);
        bindings[5] = _binding(keccak256("AIRDROP"), type(ProjectAirdropV2).creationCode);
        bindings[6] = _binding(keccak256("ROUTER"), type(ProjectRouterV2).creationCode);
        bindings[7] = _binding(keccak256("BANDS"), type(ProjectFundingBandsV2).creationCode);
        bindings[8] = _binding(keccak256("LIQUIDITY"), type(ProjectLiquidityManagerV2).creationCode);
    }

    function _binding(bytes32 key, bytes memory creationCode)
        private
        returns (CreationCodeBinding memory)
    {
        return CreationCodeBinding({
            moduleKey: key, store: address(new CreationCodeStoreV2(creationCode))
        });
    }

    function _verifyRelease(
        ProjectLauncherV2 launcher,
        ProjectRegistryV2 registry,
        ProjectLaunchDeployerV2 deployer
    ) private view {
        require(address(launcher.registry()) == address(registry), "LAUNCHER_REGISTRY_MISMATCH");
        require(address(launcher.deployer()) == address(deployer), "LAUNCHER_ENGINE_MISMATCH");
        require(registry.launcher() == address(launcher), "REGISTRY_LAUNCHER_MISMATCH");
        require(deployer.launcher() == address(launcher), "ENGINE_LAUNCHER_MISMATCH");
        require(deployer.registry() == address(registry), "ENGINE_REGISTRY_MISMATCH");
        require(
            deployer.raffleImplementation().codehash
                == keccak256(type(ProjectRaffleV2).runtimeCode),
            "RAFFLE_IMPLEMENTATION_HASH_MISMATCH"
        );
        _verifyExternalRuntime(deployer.randomnessAdapter(), "RANDOMNESS_ADAPTER_RUNTIME_HASH");
        require(!deployer.basketEnabled(), "BASKET_MUST_BE_DISABLED");
        require(deployer.basketVaultImplementation() == address(0), "BASKET_IMPLEMENTATION_SET");
        require(address(deployer.erc4626YieldAdapterFactory()) == address(0), "ERC4626_FACTORY_SET");
        require(
            address(deployer.fundingBandV3IntegrationFactory()).code.length != 0,
            "FUNDING_BAND_V3_FACTORY_MISSING"
        );
        require(
            deployer.fundingBandV3IntegrationFactory().v3Factory() == deployer.v3Factory()
                && deployer.fundingBandV3IntegrationFactory().v3PositionManager()
                    == deployer.v3PositionManager(),
            "FUNDING_BAND_V3_FACTORY_BINDING_MISMATCH"
        );
        _verifyExternalRuntime(deployer.v3Factory(), "V3_FACTORY_RUNTIME_HASH");
        _verifyExternalRuntime(deployer.v3PositionManager(), "V3_POSITION_MANAGER_RUNTIME_HASH");
        _verifyExternalRuntime(deployer.v4PositionManager(), "V4_POSITION_MANAGER_RUNTIME_HASH");
        _verifyExternalRuntime(deployer.v4StateView(), "V4_STATE_VIEW_RUNTIME_HASH");
        _verifyExternalRuntime(deployer.permit2(), "PERMIT2_RUNTIME_HASH");

        _verifyCreationCode(deployer, keccak256("TOKEN"), type(ProjectVotesToken).creationCode);
        _verifyCreationCode(
            deployer, keccak256("MULTISIG"), type(ProjectMultisigAccountV2).creationCode
        );
        _verifyCreationCode(deployer, keccak256("TIMELOCK"), type(ProjectTimelockV2).creationCode);
        _verifyCreationCode(deployer, keccak256("STAKING"), type(ProjectStakingPoolV2).creationCode);
        _verifyCreationCode(
            deployer, keccak256("TREASURY"), type(ProjectTreasuryVaultV2).creationCode
        );
        _verifyCreationCode(deployer, keccak256("AIRDROP"), type(ProjectAirdropV2).creationCode);
        _verifyCreationCode(deployer, keccak256("ROUTER"), type(ProjectRouterV2).creationCode);
        _verifyCreationCode(deployer, keccak256("BANDS"), type(ProjectFundingBandsV2).creationCode);
        _verifyCreationCode(
            deployer, keccak256("LIQUIDITY"), type(ProjectLiquidityManagerV2).creationCode
        );
    }

    function _verifyExternalRuntime(address target, string memory environmentKey) private view {
        require(target.codehash == vm.envBytes32(environmentKey), "EXTERNAL_RUNTIME_HASH_MISMATCH");
    }

    function _verifyCreationCode(
        ProjectLaunchDeployerV2 deployer,
        bytes32 moduleKey,
        bytes memory expectedCreationCode
    ) private view {
        require(
            deployer.creationCodeHash(moduleKey) == keccak256(expectedCreationCode),
            "CREATION_CODE_HASH_MISMATCH"
        );
        require(
            address(deployer.creationCodeStore(moduleKey)).code.length != 0, "CODE_STORE_MISSING"
        );
    }

    function _writeManifest(
        ProjectLauncherV2 launcher,
        ProjectRegistryV2 registry,
        ProjectLaunchDeployerV2 deployer,
        address broadcaster
    ) private returns (string memory path) {
        string memory object = "sinjohV2Release";
        vm.serializeUint(object, "chainId", block.chainid);
        vm.serializeUint(object, "protocolVersion", launcher.PROTOCOL_VERSION());
        vm.serializeString(object, "gitCommit", vm.envString("RELEASE_GIT_COMMIT"));
        vm.serializeString(object, "sourceTreeHash", vm.envString("RELEASE_SOURCE_TREE_HASH"));
        vm.serializeString(object, "buildHash", vm.envString("RELEASE_BUILD_HASH"));
        vm.serializeString(object, "compiler", "solc-0.8.28");
        vm.serializeString(object, "evmVersion", "cancun");
        vm.serializeBool(object, "optimizerEnabled", true);
        vm.serializeUint(object, "optimizerRuns", 1_000);
        vm.serializeBool(object, "viaIr", true);
        vm.serializeString(object, "auditReportVersion", vm.envString("AUDIT_REPORT_VERSION"));
        vm.serializeString(object, "auditEvidence", vm.envString("AUDIT_EVIDENCE_PATH"));
        vm.serializeString(object, "auditEvidenceHash", vm.envString("AUDIT_EVIDENCE_HASH"));
        vm.serializeString(object, "forkEvidence", vm.envString("FORK_EVIDENCE_PATH"));
        vm.serializeString(object, "forkEvidenceHash", vm.envString("FORK_EVIDENCE_HASH"));
        vm.serializeString(object, "testnetEvidence", vm.envString("TESTNET_EVIDENCE_PATH"));
        vm.serializeString(object, "testnetEvidenceHash", vm.envString("TESTNET_EVIDENCE_HASH"));
        vm.serializeString(object, "roleEvidence", vm.envString("ROLE_EVIDENCE_PATH"));
        vm.serializeString(object, "roleEvidenceHash", vm.envString("ROLE_EVIDENCE_HASH"));
        vm.serializeString(object, "assetFlowEvidence", vm.envString("ASSET_FLOW_EVIDENCE_PATH"));
        vm.serializeString(
            object, "assetFlowEvidenceHash", vm.envString("ASSET_FLOW_EVIDENCE_HASH")
        );
        vm.serializeAddress(object, "broadcaster", broadcaster);
        vm.serializeAddress(object, "protocolFeeRecipient", deployer.protocolFeeRecipient());
        vm.serializeAddress(object, "registry", address(registry));
        vm.serializeAddress(object, "deploymentEngine", address(deployer));
        vm.serializeAddress(object, "launcher", address(launcher));
        vm.serializeAddress(object, "raffleImplementation", deployer.raffleImplementation());
        vm.serializeBytes32(
            object, "raffleImplementationRuntimeHash", deployer.raffleImplementation().codehash
        );
        vm.serializeAddress(object, "randomnessAdapter", deployer.randomnessAdapter());
        vm.serializeBytes32(
            object, "randomnessAdapterRuntimeHash", deployer.randomnessAdapter().codehash
        );
        vm.serializeBool(object, "basketEnabled", deployer.basketEnabled());
        vm.serializeAddress(
            object, "basketVaultImplementation", deployer.basketVaultImplementation()
        );
        vm.serializeBytes32(object, "basketVaultImplementationRuntimeHash", bytes32(0));
        vm.serializeAddress(
            object, "erc4626YieldAdapterFactory", address(deployer.erc4626YieldAdapterFactory())
        );
        vm.serializeBytes32(object, "erc4626YieldAdapterFactoryRuntimeHash", bytes32(0));
        vm.serializeBytes32(object, "erc4626YieldAdapterRuntimeHash", bytes32(0));
        vm.serializeAddress(
            object,
            "fundingBandV3IntegrationFactory",
            address(deployer.fundingBandV3IntegrationFactory())
        );
        vm.serializeBytes32(
            object,
            "fundingBandV3IntegrationFactoryRuntimeHash",
            address(deployer.fundingBandV3IntegrationFactory()).codehash
        );
        vm.serializeBytes32(
            object,
            "fundingBandMarketCapGuardRuntimeHash",
            keccak256(type(UniswapV3FundingBandMarketCapGuard).runtimeCode)
        );
        vm.serializeBytes32(
            object,
            "fundingBandPositionAdapterRuntimeHash",
            keccak256(type(UniswapV3FundingBandPositionAdapter).runtimeCode)
        );
        vm.serializeAddress(object, "v3Factory", deployer.v3Factory());
        vm.serializeBytes32(object, "v3FactoryRuntimeHash", deployer.v3Factory().codehash);
        vm.serializeAddress(object, "v3PositionManager", deployer.v3PositionManager());
        vm.serializeBytes32(
            object, "v3PositionManagerRuntimeHash", deployer.v3PositionManager().codehash
        );
        vm.serializeAddress(object, "v4PositionManager", deployer.v4PositionManager());
        vm.serializeBytes32(
            object, "v4PositionManagerRuntimeHash", deployer.v4PositionManager().codehash
        );
        vm.serializeAddress(object, "v4StateView", deployer.v4StateView());
        vm.serializeBytes32(object, "v4StateViewRuntimeHash", deployer.v4StateView().codehash);
        vm.serializeAddress(object, "permit2", deployer.permit2());
        vm.serializeBytes32(object, "permit2RuntimeHash", deployer.permit2().codehash);
        vm.serializeBytes32(
            object, "tokenCreationCodeHash", deployer.creationCodeHash(keccak256("TOKEN"))
        );
        vm.serializeBytes32(
            object, "multisigCreationCodeHash", deployer.creationCodeHash(keccak256("MULTISIG"))
        );
        vm.serializeBytes32(
            object, "timelockCreationCodeHash", deployer.creationCodeHash(keccak256("TIMELOCK"))
        );
        vm.serializeBytes32(
            object, "stakingCreationCodeHash", deployer.creationCodeHash(keccak256("STAKING"))
        );
        vm.serializeBytes32(
            object, "treasuryCreationCodeHash", deployer.creationCodeHash(keccak256("TREASURY"))
        );
        vm.serializeBytes32(
            object, "airdropCreationCodeHash", deployer.creationCodeHash(keccak256("AIRDROP"))
        );
        vm.serializeBytes32(
            object, "routerCreationCodeHash", deployer.creationCodeHash(keccak256("ROUTER"))
        );
        vm.serializeBytes32(object, "basketCreationCodeHash", bytes32(0));
        vm.serializeBytes32(
            object, "bandsCreationCodeHash", deployer.creationCodeHash(keccak256("BANDS"))
        );
        vm.serializeBytes32(
            object, "liquidityCreationCodeHash", deployer.creationCodeHash(keccak256("LIQUIDITY"))
        );
        vm.serializeBytes32(object, "integrationApprovalRoot", deployer.integrationApprovalRoot());
        vm.serializeBytes32(object, "registryRuntimeHash", address(registry).codehash);
        vm.serializeBytes32(object, "deploymentEngineRuntimeHash", address(deployer).codehash);
        string memory json =
            vm.serializeBytes32(object, "launcherRuntimeHash", address(launcher).codehash);
        path = vm.envOr(
            "DEPLOYMENT_MANIFEST_PATH",
            string.concat("deployments/project-launcher-v2-", vm.toString(block.chainid), ".json")
        );
        vm.writeJson(json, path);
    }
}
