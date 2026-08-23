// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { SinjohFeeRouter } from "../src/SinjohFeeRouter.sol";
import { SinjohFeeRouterFactory } from "../src/SinjohFeeRouterFactory.sol";
import { RouterTypes } from "../src/RouterTypes.sol";

interface VmFeeRouterFactory {
    function envAddress(string calldata name) external returns (address);
    function startBroadcast(address signer) external;
    function stopBroadcast() external;
}

contract DeployFeeRouterFactory {
    uint256 internal constant ROBINHOOD_MAINNET_CHAIN_ID = 4_663;
    address internal constant EXPECTED_DEPLOYER = 0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49;
    VmFeeRouterFactory internal constant vm =
        VmFeeRouterFactory(address(uint160(uint256(keccak256("hevm cheat code")))));

    error WrongChain(uint256 actual);
    error WrongDeployer(address actual);
    error InvalidImplementation(address implementation);
    error DeploymentFailed();

    /// @notice Stage two: deploy the factory against the exact implementation
    /// address emitted by DeployFeeRouter.
    function run() external returns (SinjohFeeRouterFactory factory) {
        if (block.chainid != ROBINHOOD_MAINNET_CHAIN_ID) revert WrongChain(block.chainid);
        address deployer = vm.envAddress("DEPLOYER_ADDRESS");
        if (deployer != EXPECTED_DEPLOYER) revert WrongDeployer(deployer);

        address implementationAddress = vm.envAddress("ROUTER_IMPLEMENTATION");
        if (
            implementationAddress.code.length == 0
                || implementationAddress.codehash != RouterTypes.IMPLEMENTATION_CODEHASH
        ) {
            revert InvalidImplementation(implementationAddress);
        }
        try SinjohFeeRouter(payable(implementationAddress)).initialized() returns (bool locked) {
            if (!locked) revert InvalidImplementation(implementationAddress);
        } catch {
            revert InvalidImplementation(implementationAddress);
        }

        vm.startBroadcast(deployer);
        factory = new SinjohFeeRouterFactory(implementationAddress);
        vm.stopBroadcast();

        if (address(factory).code.length == 0) revert DeploymentFailed();
        if (factory.implementation() != implementationAddress) revert DeploymentFailed();
    }
}
