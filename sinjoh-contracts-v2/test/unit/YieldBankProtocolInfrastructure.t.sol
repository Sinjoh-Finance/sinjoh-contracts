// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { YieldBankProtocolRegistry } from "../../src/yield-banks/YieldBankProtocolRegistry.sol";
import {
    YieldBankSystemFactoryDeployer
} from "../../src/yield-banks/YieldBankSystemFactoryDeployer.sol";

contract YieldBankProtocolInfrastructureTest is Test {
    address internal governance = makeAddr("governance");

    function testDarkDeploymentCreatesOnlyRegistryAndFactoryDeployer() external {
        YieldBankProtocolRegistry registry = new YieldBankProtocolRegistry(governance);
        YieldBankSystemFactoryDeployer factoryDeployer =
            new YieldBankSystemFactoryDeployer(address(registry));

        assertEq(registry.governance(), governance);
        assertEq(address(factoryDeployer.registry()), address(registry));
        assertGt(address(registry).code.length, 0);
        assertGt(address(factoryDeployer).code.length, 0);
    }

    function testOnlyGovernanceCanDeployCollectionSpecificFactory() external {
        YieldBankProtocolRegistry registry = new YieldBankProtocolRegistry(governance);
        YieldBankSystemFactoryDeployer factoryDeployer =
            new YieldBankSystemFactoryDeployer(address(registry));
        address caller = makeAddr("caller");

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(YieldBankSystemFactoryDeployer.OnlyGovernance.selector, caller)
        );
        factoryDeployer.deploy(
            keccak256("factory-salt"),
            keccak256("factory-version"),
            keccak256("collection-code"),
            keccak256("system-plan")
        );
    }

    function testZeroGovernanceIsRejected() external {
        vm.expectRevert(
            abi.encodeWithSelector(YieldBankProtocolRegistry.InvalidAddress.selector, address(0))
        );
        new YieldBankProtocolRegistry(address(0));
    }
}
