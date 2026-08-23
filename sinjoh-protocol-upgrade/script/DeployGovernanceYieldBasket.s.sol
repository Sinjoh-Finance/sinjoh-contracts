// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AddressGovernanceController } from "../src/governance/AddressGovernanceController.sol";
import { YieldBasket } from "../src/YieldBasket.sol";
import { YieldDeploymentCalls } from "./YieldDeploymentCalls.sol";
import { YieldDeploymentManifest } from "./YieldDeploymentManifest.sol";
import { YieldDeploymentTypes } from "./YieldDeploymentTypes.sol";
import { YieldDeploymentValidator } from "./YieldDeploymentValidator.sol";

interface VmDeployGovernanceYieldBasket {
    function envAddress(string calldata name) external returns (address);
    function envString(string calldata name) external returns (string memory);
    function getCode(string calldata artifactPath) external returns (bytes memory creationCode);
    function readFile(string calldata path) external view returns (string memory);
    function startBroadcast(address signer) external;
    function stopBroadcast() external;
}

/// @notice Manifest-gated deployment of a governance controller and treasury-bound Yield Basket.
/// @dev Adapter configuration calls are returned, not executed: the declared Joint or timelock
/// remains the only authority that can activate them after reviewing the deployed addresses.
contract DeployGovernanceYieldBasket {
    VmDeployGovernanceYieldBasket internal constant vm =
        VmDeployGovernanceYieldBasket(address(uint160(uint256(keccak256("hevm cheat code")))));

    struct Deployment {
        bytes32 manifestHash;
        bytes32 configurationHash;
        AddressGovernanceController controller;
        YieldBasket basket;
        bytes32 controllerRuntimeCodeHash;
        bytes32 basketRuntimeCodeHash;
        address[] configurationTargets;
        bytes[] configurationCalldatas;
    }

    error DeploymentVerificationFailed();
    error ContractCreationFailed(string artifact);

    event DeploymentPrepared(
        bytes32 indexed manifestHash,
        bytes32 indexed configurationHash,
        address indexed controller,
        address basket,
        address authority,
        address treasury
    );

    function run() external returns (Deployment memory deployment) {
        string memory manifestPath = vm.envString("YIELD_DEPLOYMENT_MANIFEST");
        string memory json = vm.readFile(manifestPath);
        YieldDeploymentTypes.Parameters memory parameters = YieldDeploymentManifest.parse(json);
        address deployer = vm.envAddress("DEPLOYER_ADDRESS");
        YieldDeploymentValidator.validate(parameters, deployer);

        vm.startBroadcast(deployer);
        deployment = _deploy(parameters, keccak256(bytes(json)));
        vm.stopBroadcast();
        _verify(parameters, deployment);

        emit DeploymentPrepared(
            deployment.manifestHash,
            deployment.configurationHash,
            address(deployment.controller),
            address(deployment.basket),
            parameters.authority,
            parameters.treasury
        );
    }

    function _deploy(YieldDeploymentTypes.Parameters memory parameters, bytes32 manifestHash)
        internal
        returns (Deployment memory deployment)
    {
        deployment.manifestHash = manifestHash;
        deployment.configurationHash =
            keccak256(abi.encode(parameters.adapters, parameters.rewardRoutes));
        deployment.controller = AddressGovernanceController(
            _create(
                "AddressGovernanceController.sol:AddressGovernanceController",
                abi.encode(parameters.authority, parameters.governanceMode)
            )
        );
        deployment.basket = YieldBasket(
            _create(
                "YieldBasket.sol:YieldBasket",
                abi.encode(
                    deployment.controller,
                    parameters.emergencyGuardian,
                    IERC20(parameters.depositAsset),
                    parameters.treasury
                )
            )
        );
        deployment.controllerRuntimeCodeHash = address(deployment.controller).codehash;
        deployment.basketRuntimeCodeHash = address(deployment.basket).codehash;
        (deployment.configurationTargets, deployment.configurationCalldatas) =
            YieldDeploymentCalls.build(deployment.basket, parameters);
    }

    function _create(string memory artifact, bytes memory constructorArguments)
        private
        returns (address deployed)
    {
        bytes memory creationCode = abi.encodePacked(vm.getCode(artifact), constructorArguments);
        assembly ("memory-safe") {
            deployed := create(0, add(creationCode, 0x20), mload(creationCode))
        }
        if (deployed == address(0)) revert ContractCreationFailed(artifact);
    }

    function _verify(
        YieldDeploymentTypes.Parameters memory parameters,
        Deployment memory deployment
    ) internal view {
        if (
            address(deployment.controller).code.length == 0
                || address(deployment.basket).code.length == 0
                || deployment.controllerRuntimeCodeHash == bytes32(0)
                || deployment.basketRuntimeCodeHash == bytes32(0)
                || deployment.controller.authority() != parameters.authority
                || deployment.controller.mode() != parameters.governanceMode
                || address(deployment.basket.governanceController())
                    != address(deployment.controller)
                || deployment.basket.emergencyGuardian() != parameters.emergencyGuardian
                || deployment.basket.treasury() != parameters.treasury
                || address(deployment.basket.depositAsset()) != parameters.depositAsset
                || address(deployment.basket) != parameters.expectedBasket
                || deployment.configurationTargets.length
                    != deployment.configurationCalldatas.length
        ) revert DeploymentVerificationFailed();
    }
}
