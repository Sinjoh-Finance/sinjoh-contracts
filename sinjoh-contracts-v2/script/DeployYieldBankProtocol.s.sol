// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Script } from "forge-std/Script.sol";
import { YieldBankProtocolRegistry } from "../src/yield-banks/YieldBankProtocolRegistry.sol";
import {
    YieldBankSystemFactoryDeployer
} from "../src/yield-banks/YieldBankSystemFactoryDeployer.sol";

/// @notice Dark-deploys only the shared Yield Banks protocol infrastructure.
/// @dev This script deliberately cannot deploy a system factory, collection, NFT, sleeve, adapter,
///      or any collection-owned component. Every input comes from one reviewed JSON plan.
contract DeployYieldBankProtocol is Script {
    struct DeploymentPlan {
        uint256 chainId;
        address deployer;
        uint64 deployerNonce;
        address governance;
        address expectedRegistry;
        address expectedFactoryDeployer;
        bytes32 registryCreationCodeHash;
        bytes32 factoryDeployerCreationCodeHash;
    }

    error WrongChain(uint256 expected, uint256 actual);
    error WrongBroadcaster(address expected, address actual);
    error WrongNonce(uint64 expected, uint64 actual);
    error InvalidDeploymentPlan();
    error AddressMismatch(address expected, address actual);
    error HashMismatch(bytes32 expected, bytes32 actual);

    function run() external returns (address registryAddress, address factoryDeployerAddress) {
        DeploymentPlan memory plan =
            _readPlan(vm.readFile(vm.envString("YIELD_BANK_PROTOCOL_PLAN")));
        if (plan.chainId != block.chainid) revert WrongChain(plan.chainId, block.chainid);
        if (plan.deployer == address(0) || plan.governance == address(0)) {
            revert InvalidDeploymentPlan();
        }
        if (tx.origin != plan.deployer) revert WrongBroadcaster(plan.deployer, tx.origin);

        uint64 currentNonce = vm.getNonce(plan.deployer);
        if (currentNonce != plan.deployerNonce) {
            revert WrongNonce(plan.deployerNonce, currentNonce);
        }
        address predictedRegistry = vm.computeCreateAddress(plan.deployer, currentNonce);
        address predictedFactoryDeployer = vm.computeCreateAddress(plan.deployer, currentNonce + 1);
        if (predictedRegistry != plan.expectedRegistry) {
            revert AddressMismatch(plan.expectedRegistry, predictedRegistry);
        }
        if (predictedFactoryDeployer != plan.expectedFactoryDeployer) {
            revert AddressMismatch(plan.expectedFactoryDeployer, predictedFactoryDeployer);
        }
        if (predictedRegistry.code.length != 0 || predictedFactoryDeployer.code.length != 0) {
            revert InvalidDeploymentPlan();
        }

        bytes32 registryCreationHash = keccak256(
            abi.encodePacked(
                type(YieldBankProtocolRegistry).creationCode, abi.encode(plan.governance)
            )
        );
        if (registryCreationHash != plan.registryCreationCodeHash) {
            revert HashMismatch(plan.registryCreationCodeHash, registryCreationHash);
        }
        bytes32 factoryDeployerCreationHash = keccak256(
            abi.encodePacked(
                type(YieldBankSystemFactoryDeployer).creationCode, abi.encode(plan.expectedRegistry)
            )
        );
        if (factoryDeployerCreationHash != plan.factoryDeployerCreationCodeHash) {
            revert HashMismatch(plan.factoryDeployerCreationCodeHash, factoryDeployerCreationHash);
        }

        vm.startBroadcast();
        YieldBankProtocolRegistry registry = new YieldBankProtocolRegistry(plan.governance);
        YieldBankSystemFactoryDeployer factoryDeployer =
            new YieldBankSystemFactoryDeployer(address(registry));
        vm.stopBroadcast();

        registryAddress = address(registry);
        factoryDeployerAddress = address(factoryDeployer);
        if (registryAddress != plan.expectedRegistry) {
            revert AddressMismatch(plan.expectedRegistry, registryAddress);
        }
        if (factoryDeployerAddress != plan.expectedFactoryDeployer) {
            revert AddressMismatch(plan.expectedFactoryDeployer, factoryDeployerAddress);
        }
        if (registry.governance() != plan.governance) revert InvalidDeploymentPlan();
        if (address(factoryDeployer.registry()) != registryAddress) revert InvalidDeploymentPlan();
    }

    function _readPlan(string memory json) private pure returns (DeploymentPlan memory plan) {
        plan.chainId = vm.parseJsonUint(json, ".chainId");
        plan.deployer = vm.parseJsonAddress(json, ".deployer");
        plan.deployerNonce = uint64(vm.parseJsonUint(json, ".deployerNonce"));
        plan.governance = vm.parseJsonAddress(json, ".governance");
        plan.expectedRegistry = vm.parseJsonAddress(json, ".expectedRegistry");
        plan.expectedFactoryDeployer = vm.parseJsonAddress(json, ".expectedFactoryDeployer");
        plan.registryCreationCodeHash = vm.parseJsonBytes32(json, ".registryCreationCodeHash");
        plan.factoryDeployerCreationCodeHash =
            vm.parseJsonBytes32(json, ".factoryDeployerCreationCodeHash");
    }
}
