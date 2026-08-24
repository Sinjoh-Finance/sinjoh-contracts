// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC4626BasketYieldAdapter } from "../../src/adapters/ERC4626BasketYieldAdapter.sol";
import {
    ERC4626BasketYieldAdapterFactory
} from "../../src/adapters/ERC4626BasketYieldAdapterFactory.sol";
import { MockBasketAsset } from "../mocks/MockBasketIntegrations.sol";
import { MockERC4626 } from "../mocks/MockERC4626.sol";

contract ERC4626BasketYieldAdapterFactoryTest is Test {
    ERC4626BasketYieldAdapterFactory private factory;
    MockERC4626 private vault;

    function setUp() public {
        factory = new ERC4626BasketYieldAdapterFactory();
        MockBasketAsset asset = new MockBasketAsset("Yield", "YIELD");
        vault = new MockERC4626(IERC20(address(asset)));
    }

    function testPredictionDeploymentAndRepeatCallAreDeterministic() public {
        address basket = address(0xB45);
        bytes32 salt = keccak256("BASKET_ADAPTER");
        address predicted = factory.predict(basket, address(vault), salt);
        address deployed = factory.deploy(basket, address(vault), salt);
        assertEq(deployed, predicted);
        assertEq(deployed.codehash, factory.ADAPTER_RUNTIME_HASH());
        assertEq(ERC4626BasketYieldAdapter(deployed).basketVault(), basket);
        assertEq(address(ERC4626BasketYieldAdapter(deployed).vault()), address(vault));
        assertEq(factory.deploy(basket, address(vault), salt), deployed);
    }

    function testDifferentBasketAndSaltProduceDifferentAdaptersWithSameRuntimeHash() public {
        address first = factory.deploy(address(0xB01), address(vault), bytes32(uint256(1)));
        address second = factory.deploy(address(0xB02), address(vault), bytes32(uint256(1)));
        address third = factory.deploy(address(0xB01), address(vault), bytes32(uint256(2)));
        assertTrue(first != second && first != third && second != third);
        assertEq(first.codehash, second.codehash);
        assertEq(second.codehash, third.codehash);
    }
}
