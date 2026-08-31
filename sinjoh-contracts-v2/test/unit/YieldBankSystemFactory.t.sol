// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { Create3V2 } from "../../src/libraries/Create3V2.sol";
import { YieldBankCollection } from "../../src/yield-banks/YieldBankCollection.sol";
import { YieldBankAccount } from "../../src/yield-banks/YieldBankAccount.sol";
import { YieldBankProtocolRegistry } from "../../src/yield-banks/YieldBankProtocolRegistry.sol";
import { YieldBankSystemFactory } from "../../src/yield-banks/YieldBankSystemFactory.sol";
import {
    YieldBankSystemFactoryDeployer
} from "../../src/yield-banks/YieldBankSystemFactoryDeployer.sol";
import { YieldBankConfig } from "../../src/yield-banks/YieldBankTypes.sol";
import {
    MockYieldBankAsset,
    MockYieldBankEligibilityPolicy,
    MockYieldBankPlannedComponent,
    MockYieldBankRenderer
} from "../mocks/MockYieldBankIntegrations.sol";

contract YieldBankSystemFactoryTest is Test {
    bytes32 private constant VERSION = keccak256("YIELD_BANK_SYSTEM_FACTORY_V1");
    bytes32 private constant COLLECTION_ID = keccak256("SYSTEM_FACTORY_COLLECTION");
    bytes32 private constant COLLECTION_SALT = keccak256("COLLECTION_SALT");

    function testFactoryAddressIsDeterministicFromFactorySalt() external {
        YieldBankProtocolRegistry registry = new YieldBankProtocolRegistry(address(this));
        YieldBankSystemFactoryDeployer deployer =
            new YieldBankSystemFactoryDeployer(address(registry));
        bytes32 factorySalt = keccak256("YIELD_BANK_FACTORY_SALT");
        bytes32 collectionCodeHash = keccak256(type(YieldBankCollection).creationCode);
        bytes32 plan = keccak256("REVIEWED_SYSTEM_PLAN");
        address predicted = deployer.predict(factorySalt);

        address factory = deployer.deploy(factorySalt, VERSION, collectionCodeHash, plan);

        assertEq(factory, predicted);
        YieldBankSystemFactory systemFactory = YieldBankSystemFactory(factory);
        assertEq(address(systemFactory.registry()), address(registry));
        assertEq(systemFactory.factoryVersion(), VERSION);
        assertEq(systemFactory.collectionCreationCodeHash(), collectionCodeHash);
        assertEq(systemFactory.systemPlanHash(), plan);
        vm.expectRevert(abi.encodeWithSelector(Create3V2.AlreadyDeployed.selector, predicted));
        deployer.deploy(factorySalt, VERSION, collectionCodeHash, plan);
    }

    function testOnlyGovernanceCanDeployFactory() external {
        YieldBankProtocolRegistry registry = new YieldBankProtocolRegistry(address(this));
        YieldBankSystemFactoryDeployer deployer =
            new YieldBankSystemFactoryDeployer(address(registry));
        address caller = address(0xBAD);
        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(YieldBankSystemFactoryDeployer.OnlyGovernance.selector, caller)
        );
        deployer.deploy(
            keccak256("YIELD_BANK_FACTORY_SALT"),
            VERSION,
            keccak256(type(YieldBankCollection).creationCode),
            keccak256("REVIEWED_SYSTEM_PLAN")
        );
    }

    function testCreate3PlanningResolvesImmutableComponentDependencyCycle() external {
        YieldBankProtocolRegistry registry = new YieldBankProtocolRegistry(address(this));
        MockYieldBankAsset weth = new MockYieldBankAsset("Wrapped Ether", "WETH");
        MockYieldBankEligibilityPolicy policy = new MockYieldBankEligibilityPolicy();
        MockYieldBankRenderer renderer = new MockYieldBankRenderer();

        address predictedFactory =
            vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        bytes32[8] memory salts;
        address[8] memory predicted;
        for (uint256 i; i < 8; ++i) {
            salts[i] = keccak256(abi.encode("YIELD_BANK_COMPONENT", i));
            predicted[i] = Create3V2.predict(predictedFactory, salts[i]);
        }

        YieldBankConfig memory config = _config(weth, policy, renderer, predicted);
        bytes memory collectionCreationCode = type(YieldBankCollection).creationCode;
        address predictedCollection = _predictCreate2(
            predictedFactory,
            COLLECTION_SALT,
            keccak256(abi.encodePacked(collectionCreationCode, abi.encode(config)))
        );
        bytes32 expectedRuntimeHash = keccak256(type(MockYieldBankPlannedComponent).runtimeCode);
        YieldBankSystemFactory.ComponentDeployment[] memory components =
            new YieldBankSystemFactory.ComponentDeployment[](8);
        bytes32[8] memory kinds = [
            keccak256("REVENUE_ROUTER"),
            keccak256("PORTFOLIO_ALLOCATOR"),
            keccak256("COLLECTION_TIMELOCK"),
            keccak256("CORE_SLEEVE"),
            keccak256("MARKET_MAKING_SLEEVE"),
            keccak256("USDG_SLEEVE"),
            keccak256("ACCOUNT_IMPLEMENTATION"),
            keccak256("DELTA_POOL_CONTROLLER")
        ];
        uint16[6] memory economics = [
            uint16(7_500), uint16(1_200), uint16(1_300), uint16(4_000), uint16(3_750), uint16(2_250)
        ];
        for (uint256 i; i < 6; ++i) {
            address dependency = i == 1 ? predicted[7] : predicted[(i + 1) % 6];
            components[i] = YieldBankSystemFactory.ComponentDeployment({
                kind: kinds[i],
                salt: salts[i],
                initCode: abi.encodePacked(
                    type(MockYieldBankPlannedComponent).creationCode,
                    abi.encode(predictedCollection, dependency, economics)
                ),
                expectedRuntimeCodeHash: expectedRuntimeHash
            });
        }
        components[6] = YieldBankSystemFactory.ComponentDeployment({
            kind: kinds[6],
            salt: salts[6],
            initCode: type(YieldBankAccount).creationCode,
            expectedRuntimeCodeHash: keccak256(type(YieldBankAccount).runtimeCode)
        });
        components[7] = YieldBankSystemFactory.ComponentDeployment({
            kind: kinds[7],
            salt: salts[7],
            initCode: abi.encodePacked(
                type(MockYieldBankPlannedComponent).creationCode,
                abi.encode(predictedCollection, predicted[1], economics)
            ),
            expectedRuntimeCodeHash: expectedRuntimeHash
        });

        bytes32 plan = _planHash(
            components,
            keccak256(collectionCreationCode),
            keccak256(abi.encode(config)),
            COLLECTION_SALT
        );
        YieldBankSystemFactory factory = new YieldBankSystemFactory(
            address(registry), VERSION, keccak256(collectionCreationCode), plan
        );
        assertEq(address(factory), predictedFactory);
        registry.registerFactory(address(factory), VERSION, address(factory).codehash);

        address deployed =
            factory.deploySystem(components, collectionCreationCode, config, COLLECTION_SALT);
        assertEq(deployed, predictedCollection);
        for (uint256 i; i < 6; ++i) {
            assertEq(factory.predictComponent(salts[i]), predicted[i]);
            MockYieldBankPlannedComponent component = MockYieldBankPlannedComponent(predicted[i]);
            assertEq(component.collection(), predictedCollection);
            assertEq(component.dependency(), i == 1 ? predicted[7] : predicted[(i + 1) % 6]);
        }
        assertEq(factory.predictComponent(salts[6]), predicted[6]);
        assertEq(predicted[6].codehash, keccak256(type(YieldBankAccount).runtimeCode));
        assertEq(factory.predictComponent(salts[7]), predicted[7]);
        (address recordedFactory,,,,, bool registered) = registry.collections(deployed);
        assertEq(recordedFactory, address(factory));
        assertTrue(registered);
    }

    function _config(
        MockYieldBankAsset weth,
        MockYieldBankEligibilityPolicy policy,
        MockYieldBankRenderer renderer,
        address[8] memory predicted
    ) private view returns (YieldBankConfig memory config) {
        config = YieldBankConfig({
            collectionId: COLLECTION_ID,
            maxSupply: 777,
            secondaryRoyaltyBps: 500,
            primaryBackingBps: 7_500,
            primaryCreatorBps: 1_200,
            primarySinjohBps: 1_300,
            coreWeightBps: 4_000,
            marketMakingWeightBps: 3_750,
            usdgWeightBps: 2_250,
            creator: address(0xC0FFEE),
            openSeaManager: address(0xC0FFEE),
            sinjohFeeRecipient: address(0x51A70A),
            redemptionToken: address(0),
            redemptionTokenAmount: 0,
            redemptionTokenCodeHash: bytes32(0),
            revenueRouter: predicted[0],
            eligibilityPolicy: address(policy),
            portfolioAllocator: predicted[1],
            allocationOperator: address(0xA110C),
            collectionTimelock: predicted[2],
            guardian: address(0x6A4D1A),
            renderer: address(renderer),
            weth: address(weth),
            seaDrop: address(renderer),
            coreSleeve: predicted[3],
            marketMakingSleeve: predicted[4],
            usdgSleeve: predicted[5],
            accountImplementation: predicted[6],
            integrationCodeHashes: [
                keccak256(type(MockYieldBankPlannedComponent).runtimeCode),
                address(policy).codehash,
                keccak256(type(MockYieldBankPlannedComponent).runtimeCode),
                keccak256(type(MockYieldBankPlannedComponent).runtimeCode),
                address(renderer).codehash,
                address(weth).codehash,
                address(renderer).codehash,
                keccak256(type(MockYieldBankPlannedComponent).runtimeCode),
                keccak256(type(MockYieldBankPlannedComponent).runtimeCode),
                keccak256(type(MockYieldBankPlannedComponent).runtimeCode)
            ]
        });
    }

    function _planHash(
        YieldBankSystemFactory.ComponentDeployment[] memory components,
        bytes32 collectionCodeHash,
        bytes32 configurationHash,
        bytes32 collectionSalt
    ) private pure returns (bytes32) {
        bytes32[] memory records = new bytes32[](components.length);
        for (uint256 i; i < components.length; ++i) {
            YieldBankSystemFactory.ComponentDeployment memory component = components[i];
            records[i] = keccak256(
                abi.encode(
                    component.kind,
                    component.salt,
                    keccak256(component.initCode),
                    component.expectedRuntimeCodeHash
                )
            );
        }
        return keccak256(abi.encode(records, collectionCodeHash, configurationHash, collectionSalt));
    }

    function _predictCreate2(address deployer, bytes32 salt, bytes32 initCodeHash)
        private
        pure
        returns (address)
    {
        return address(
            uint160(
                uint256(keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, initCodeHash)))
            )
        );
    }
}
