// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Script } from "forge-std/Script.sol";
import { YieldBankConfig } from "../src/yield-banks/YieldBankTypes.sol";
import { YieldBankProtocolRegistry } from "../src/yield-banks/YieldBankProtocolRegistry.sol";
import { YieldBankSystemFactory } from "../src/yield-banks/YieldBankSystemFactory.sol";
import {
    YieldBankSystemFactoryDeployer
} from "../src/yield-banks/YieldBankSystemFactoryDeployer.sol";

/// @notice Executes one pre-reviewed, fully committed Yield Banks deployment plan.
/// @dev The JSON is decoded as `DeploymentPlan`; no address, salt, init code, or configuration is
///      sourced from mutable environment variables. Run with `YIELD_BANK_DEPLOYMENT_PLAN` set to an
///      absolute path and the governance broadcaster configured through standard Forge options.
contract DeployYieldBanks is Script {
    struct DeploymentPlan {
        uint256 chainId;
        address factoryDeployer;
        bytes32 factorySalt;
        bytes32 factoryVersion;
        bytes32 collectionCreationCodeHash;
        bytes32 systemPlanHash;
        address expectedFactory;
        address expectedCollection;
        YieldBankSystemFactory.ComponentDeployment[] components;
        bytes collectionCreationCode;
        YieldBankConfig config;
        bytes32 collectionSalt;
    }

    error WrongChain(uint256 expected, uint256 actual);
    error InvalidDeploymentPlan();
    error AddressMismatch(address expected, address actual);
    error HashMismatch(bytes32 expected, bytes32 actual);

    function run() external returns (address factory, address collection) {
        string memory path = vm.envString("YIELD_BANK_DEPLOYMENT_PLAN");
        DeploymentPlan memory plan = _readPlan(vm.readFile(path));
        if (plan.chainId != block.chainid) revert WrongChain(plan.chainId, block.chainid);
        if (plan.factoryDeployer.code.length == 0 || plan.expectedFactory == address(0)) {
            revert InvalidDeploymentPlan();
        }
        YieldBankSystemFactoryDeployer deployer =
            YieldBankSystemFactoryDeployer(plan.factoryDeployer);
        if (deployer.predict(plan.factorySalt) != plan.expectedFactory) {
            revert AddressMismatch(plan.expectedFactory, deployer.predict(plan.factorySalt));
        }
        bytes32 configurationHash = keccak256(abi.encode(plan.config));
        bytes32 collectionCodeHash = keccak256(plan.collectionCreationCode);
        if (collectionCodeHash != plan.collectionCreationCodeHash) {
            revert HashMismatch(plan.collectionCreationCodeHash, collectionCodeHash);
        }

        vm.startBroadcast();
        factory = deployer.deploy(
            plan.factorySalt,
            plan.factoryVersion,
            plan.collectionCreationCodeHash,
            plan.systemPlanHash
        );
        if (factory != plan.expectedFactory) {
            revert AddressMismatch(plan.expectedFactory, factory);
        }
        YieldBankProtocolRegistry registry = deployer.registry();
        registry.registerFactory(factory, plan.factoryVersion, factory.codehash);
        YieldBankSystemFactory systemFactory = YieldBankSystemFactory(factory);
        bytes32 computedPlanHash = systemFactory.planHash(
            plan.components, collectionCodeHash, configurationHash, plan.collectionSalt
        );
        if (computedPlanHash != plan.systemPlanHash) {
            revert HashMismatch(plan.systemPlanHash, computedPlanHash);
        }
        address predictedCollection = systemFactory.predictCollection(
            plan.collectionCreationCode, plan.config, plan.collectionSalt
        );
        if (predictedCollection != plan.expectedCollection) {
            revert AddressMismatch(plan.expectedCollection, predictedCollection);
        }
        collection = systemFactory.deploySystem(
            plan.components, plan.collectionCreationCode, plan.config, plan.collectionSalt
        );
        vm.stopBroadcast();
        if (collection != plan.expectedCollection) {
            revert AddressMismatch(plan.expectedCollection, collection);
        }
    }

    function _readPlan(string memory json) private view returns (DeploymentPlan memory plan) {
        plan.chainId = vm.parseJsonUint(json, ".chainId");
        plan.factoryDeployer = vm.parseJsonAddress(json, ".factoryDeployer");
        plan.factorySalt = vm.parseJsonBytes32(json, ".factorySalt");
        plan.factoryVersion = vm.parseJsonBytes32(json, ".factoryVersion");
        plan.collectionCreationCodeHash = vm.parseJsonBytes32(json, ".collectionCreationCodeHash");
        plan.systemPlanHash = vm.parseJsonBytes32(json, ".systemPlanHash");
        plan.expectedFactory = vm.parseJsonAddress(json, ".expectedFactory");
        plan.expectedCollection = vm.parseJsonAddress(json, ".expectedCollection");
        plan.collectionCreationCode = vm.parseJsonBytes(json, ".collectionCreationCode");
        plan.collectionSalt = vm.parseJsonBytes32(json, ".collectionSalt");
        plan.components = new YieldBankSystemFactory.ComponentDeployment[](7);
        for (uint256 i; i < 7; ++i) {
            string memory base = string.concat(".components[", vm.toString(i), "]");
            plan.components[i] = YieldBankSystemFactory.ComponentDeployment({
                kind: vm.parseJsonBytes32(json, string.concat(base, ".kind")),
                salt: vm.parseJsonBytes32(json, string.concat(base, ".salt")),
                initCode: vm.parseJsonBytes(json, string.concat(base, ".initCode")),
                expectedRuntimeCodeHash: vm.parseJsonBytes32(
                    json, string.concat(base, ".expectedRuntimeCodeHash")
                )
            });
        }
        bytes32[] memory integrationCodeHashes =
            abi.decode(vm.parseJson(json, ".config.integrationCodeHashes"), (bytes32[]));
        if (integrationCodeHashes.length != 10) revert InvalidDeploymentPlan();
        bytes32[10] memory pinnedHashes;
        for (uint256 i; i < 10; ++i) {
            pinnedHashes[i] = integrationCodeHashes[i];
        }
        plan.config = YieldBankConfig({
            collectionId: vm.parseJsonBytes32(json, ".config.collectionId"),
            maxSupply: vm.parseJsonUint(json, ".config.maxSupply"),
            primaryBackingBps: _parseBps(json, ".config.primaryBackingBps"),
            primaryCreatorBps: _parseBps(json, ".config.primaryCreatorBps"),
            primarySinjohBps: _parseBps(json, ".config.primarySinjohBps"),
            primaryOperationsBps: _parseBps(json, ".config.primaryOperationsBps"),
            coreWeightBps: _parseBps(json, ".config.coreWeightBps"),
            marketMakingWeightBps: _parseBps(json, ".config.marketMakingWeightBps"),
            usdgWeightBps: _parseBps(json, ".config.usdgWeightBps"),
            creator: vm.parseJsonAddress(json, ".config.creator"),
            sinjohFeeRecipient: vm.parseJsonAddress(json, ".config.sinjohFeeRecipient"),
            operationsReserve: vm.parseJsonAddress(json, ".config.operationsReserve"),
            revenueRouter: vm.parseJsonAddress(json, ".config.revenueRouter"),
            eligibilityPolicy: vm.parseJsonAddress(json, ".config.eligibilityPolicy"),
            portfolioAllocator: vm.parseJsonAddress(json, ".config.portfolioAllocator"),
            allocationOperator: vm.parseJsonAddress(json, ".config.allocationOperator"),
            collectionTimelock: vm.parseJsonAddress(json, ".config.collectionTimelock"),
            guardian: vm.parseJsonAddress(json, ".config.guardian"),
            renderer: vm.parseJsonAddress(json, ".config.renderer"),
            weth: vm.parseJsonAddress(json, ".config.weth"),
            seaDrop: vm.parseJsonAddress(json, ".config.seaDrop"),
            coreSleeve: vm.parseJsonAddress(json, ".config.coreSleeve"),
            marketMakingSleeve: vm.parseJsonAddress(json, ".config.marketMakingSleeve"),
            usdgSleeve: vm.parseJsonAddress(json, ".config.usdgSleeve"),
            integrationCodeHashes: pinnedHashes
        });
    }

    function _parseBps(string memory json, string memory path) private pure returns (uint16) {
        uint256 value = vm.parseJsonUint(json, path);
        if (value > 10_000) revert InvalidDeploymentPlan();
        // The bound above makes this uint16 conversion exact.
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint16(value);
    }
}
