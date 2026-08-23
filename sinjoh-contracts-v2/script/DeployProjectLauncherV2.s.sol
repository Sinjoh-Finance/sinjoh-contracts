// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { ProjectAirdropV2 } from "../src/airdrop/ProjectAirdropV2.sol";
import {
    ERC4626BasketYieldAdapterFactory
} from "../src/adapters/ERC4626BasketYieldAdapterFactory.sol";
import { BasketManagerV2 } from "../src/basket/BasketManagerV2.sol";
import { BasketVaultV2 } from "../src/basket/BasketVaultV2.sol";
import { ProjectFundingBandsV2 } from "../src/bands/ProjectFundingBandsV2.sol";
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
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address broadcaster = vm.addr(privateKey);

        vm.startBroadcast(privateKey);
        ProjectRaffleV2 raffleImplementation = new ProjectRaffleV2();
        BasketVaultV2 basketVaultImplementation = new BasketVaultV2();
        ERC4626BasketYieldAdapterFactory erc4626YieldAdapterFactory =
            new ERC4626BasketYieldAdapterFactory();
        CreationCodeBinding[] memory bindings = _deployCreationCodeStores();

        LauncherReleaseConfig memory release = LauncherReleaseConfig({
            protocolFeeRecipient: vm.envAddress("PROTOCOL_FEE_RECIPIENT"),
            integrationApprovalRoot: vm.envBytes32("INTEGRATION_APPROVAL_ROOT"),
            raffleImplementation: address(raffleImplementation),
            basketVaultImplementation: address(basketVaultImplementation),
            erc4626YieldAdapterFactory: address(erc4626YieldAdapterFactory),
            v3Factory: vm.envAddress("V3_FACTORY"),
            v3PositionManager: vm.envAddress("V3_POSITION_MANAGER"),
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
        string memory manifestPath = _writeManifest(launcher, registry, deployer);
        console2.log("ProjectRegistryV2", address(registry));
        console2.log("ProjectLaunchDeployerV2", address(deployer));
        console2.log("ProjectLauncherV2", address(launcher));
        console2.log("Deployment manifest", manifestPath);
    }

    function _deployCreationCodeStores() private returns (CreationCodeBinding[] memory bindings) {
        bindings = new CreationCodeBinding[](10);
        bindings[0] = _binding(keccak256("TOKEN"), type(ProjectVotesToken).creationCode);
        bindings[1] = _binding(keccak256("MULTISIG"), type(ProjectMultisigAccountV2).creationCode);
        bindings[2] = _binding(keccak256("TIMELOCK"), type(ProjectTimelockV2).creationCode);
        bindings[3] = _binding(keccak256("STAKING"), type(ProjectStakingPoolV2).creationCode);
        bindings[4] = _binding(keccak256("TREASURY"), type(ProjectTreasuryVaultV2).creationCode);
        bindings[5] = _binding(keccak256("AIRDROP"), type(ProjectAirdropV2).creationCode);
        bindings[6] = _binding(keccak256("ROUTER"), type(ProjectRouterV2).creationCode);
        bindings[7] = _binding(keccak256("BASKET"), type(BasketManagerV2).creationCode);
        bindings[8] = _binding(keccak256("BANDS"), type(ProjectFundingBandsV2).creationCode);
        bindings[9] = _binding(keccak256("LIQUIDITY"), type(ProjectLiquidityManagerV2).creationCode);
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
        _verifyCreationCode(deployer, keccak256("BASKET"), type(BasketManagerV2).creationCode);
        _verifyCreationCode(deployer, keccak256("BANDS"), type(ProjectFundingBandsV2).creationCode);
        _verifyCreationCode(
            deployer, keccak256("LIQUIDITY"), type(ProjectLiquidityManagerV2).creationCode
        );
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
        ProjectLaunchDeployerV2 deployer
    ) private returns (string memory path) {
        string memory object = "sinjohV2Release";
        vm.serializeUint(object, "chainId", block.chainid);
        vm.serializeUint(object, "protocolVersion", launcher.PROTOCOL_VERSION());
        vm.serializeAddress(object, "registry", address(registry));
        vm.serializeAddress(object, "deploymentEngine", address(deployer));
        vm.serializeAddress(object, "launcher", address(launcher));
        vm.serializeAddress(object, "raffleImplementation", deployer.raffleImplementation());
        vm.serializeAddress(
            object, "basketVaultImplementation", deployer.basketVaultImplementation()
        );
        vm.serializeAddress(
            object, "erc4626YieldAdapterFactory", address(deployer.erc4626YieldAdapterFactory())
        );
        vm.serializeBytes32(
            object,
            "erc4626YieldAdapterRuntimeHash",
            deployer.erc4626YieldAdapterFactory().ADAPTER_RUNTIME_HASH()
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
