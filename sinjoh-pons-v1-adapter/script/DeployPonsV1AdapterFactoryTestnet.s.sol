// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { SinjohPonsV1AdapterFactory } from "../src/SinjohPonsV1AdapterFactory.sol";

interface VmPonsV1AdapterFactoryTestnet {
    function addr(uint256 privateKey) external returns (address);
    function envAddress(string calldata name) external view returns (address);
    function envBytes32(string calldata name) external view returns (bytes32);
    function envUint(string calldata name) external returns (uint256);
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
}

contract DeployPonsV1AdapterFactoryTestnet {
    uint256 internal constant ROBINHOOD_TESTNET_CHAIN_ID = 46_630;
    VmPonsV1AdapterFactoryTestnet internal constant vm =
        VmPonsV1AdapterFactoryTestnet(address(uint160(uint256(keccak256("hevm cheat code")))));

    error WrongChain(uint256 actual);
    error WrongDeployer(address actual);
    error InvalidDependency(address dependency);
    error DependencyHashMismatch(address dependency, bytes32 expected, bytes32 actual);
    error DeploymentFailed();

    function run() external returns (SinjohPonsV1AdapterFactory factory) {
        if (block.chainid != ROBINHOOD_TESTNET_CHAIN_ID) revert WrongChain(block.chainid);
        address locker = _dependency("PONS_V1_LOCKER", "PONS_V1_LOCKER_CODEHASH");
        address weth = _dependency("WETH", "WETH_CODEHASH");

        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        if (deployer != vm.envAddress("TESTNET_DEPLOYER_ADDRESS")) revert WrongDeployer(deployer);

        vm.startBroadcast(deployerKey);
        factory = new SinjohPonsV1AdapterFactory(locker, weth, block.chainid);
        vm.stopBroadcast();

        if (address(factory).code.length == 0 || factory.implementation().code.length == 0) {
            revert DeploymentFailed();
        }
    }

    function _dependency(string memory addressName, string memory hashName)
        private
        view
        returns (address dependency)
    {
        dependency = vm.envAddress(addressName);
        bytes32 expected = vm.envBytes32(hashName);
        if (dependency == address(0) || dependency.code.length == 0 || expected == bytes32(0)) {
            revert InvalidDependency(dependency);
        }
        bytes32 actual = dependency.codehash;
        if (actual != expected) revert DependencyHashMismatch(dependency, expected, actual);
    }
}
