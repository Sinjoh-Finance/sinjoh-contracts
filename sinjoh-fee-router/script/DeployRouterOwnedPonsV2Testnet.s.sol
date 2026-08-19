// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { SinjohFeeRouter } from "../src/SinjohFeeRouter.sol";
import { SinjohFeeRouterFactory } from "../src/SinjohFeeRouterFactory.sol";
import { IPonsV2LaunchFactory } from "../src/interfaces/IPonsV2.sol";

interface VmPonsV2Testnet {
    function addr(uint256 privateKey) external returns (address);
    function envAddress(string calldata name) external returns (address);
    function envBytes32(string calldata name) external returns (bytes32);
    function envUint(string calldata name) external returns (uint256);
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
}

/// @notice Deploys the Sinjoh v2-capable router pair only after Pons publishes
/// hash-pinned Robinhood testnet contracts. It does not launch a token.
contract DeployRouterOwnedPonsV2Testnet {
    uint256 internal constant ROBINHOOD_TESTNET_CHAIN_ID = 46_630;
    address internal constant EXPECTED_DEPLOYER = 0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49;

    VmPonsV2Testnet internal constant vm =
        VmPonsV2Testnet(address(uint160(uint256(keccak256("hevm cheat code")))));

    error WrongChain(uint256 actual);
    error WrongDeployer(address actual);
    error InvalidDependency(address dependency);
    error DependencyHashMismatch(address dependency, bytes32 expected, bytes32 actual);
    error DeploymentFailed();

    function run()
        external
        returns (SinjohFeeRouter implementation, SinjohFeeRouterFactory factory)
    {
        if (block.chainid != ROBINHOOD_TESTNET_CHAIN_ID) {
            revert WrongChain(block.chainid);
        }

        address ponsFactory = vm.envAddress("PONS_V2_FACTORY");
        bytes32 expectedFactoryHash = vm.envBytes32("PONS_V2_FACTORY_CODEHASH");
        bytes32 expectedEscrowHash = vm.envBytes32("PONS_V2_FEE_ESCROW_CODEHASH");
        _assertHash(ponsFactory, expectedFactoryHash);

        address feeEscrow = IPonsV2LaunchFactory(ponsFactory).feeEscrow();
        _assertHash(feeEscrow, expectedEscrowHash);

        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        if (deployer != EXPECTED_DEPLOYER) revert WrongDeployer(deployer);

        vm.startBroadcast(deployerKey);
        implementation = new SinjohFeeRouter();
        factory = new SinjohFeeRouterFactory(address(implementation));
        vm.stopBroadcast();

        if (address(implementation).code.length == 0 || address(factory).code.length == 0) {
            revert DeploymentFailed();
        }
        if (factory.implementation() != address(implementation)) revert DeploymentFailed();
    }

    function _assertHash(address dependency, bytes32 expected) private view {
        if (dependency == address(0) || dependency.code.length == 0 || expected == bytes32(0)) {
            revert InvalidDependency(dependency);
        }
        bytes32 actual = dependency.codehash;
        if (actual != expected) {
            revert DependencyHashMismatch(dependency, expected, actual);
        }
    }
}
