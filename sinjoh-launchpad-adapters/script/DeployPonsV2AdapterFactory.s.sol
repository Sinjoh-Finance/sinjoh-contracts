// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { SinjohPonsV2Adapter } from "../src/SinjohPonsV2Adapter.sol";
import { SinjohPonsV2AdapterFactory } from "../src/SinjohPonsV2AdapterFactory.sol";

interface VmPonsV2AdapterFactory {
    function addr(uint256 privateKey) external returns (address);
    function envUint(string calldata name) external returns (uint256);
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
}

contract DeployPonsV2AdapterFactory {
    uint256 internal constant ROBINHOOD_MAINNET_CHAIN_ID = 4_663;
    address internal constant EXPECTED_DEPLOYER = 0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49;
    address internal constant PONS_V2_FACTORY = 0x7E1EAbd52Ae29598e6483F72dCf1a70b14284dB8;
    address internal constant PONS_V2_FEE_ESCROW = 0xbc39B6502E1a6Ab36E4A5c5026A35F08342A0A9c;
    address internal constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;

    bytes32 internal constant PONS_V2_FACTORY_HASH =
        0x9d6391ccd6730301cf53ea0f520b42d9f13d9dd11ba803c19ae3a01d145b7d9e;
    bytes32 internal constant PONS_V2_FEE_ESCROW_HASH =
        0x1eb61e9e2e95e83b3fae2e70d998a29cfa033902e9092c9496e087152d4beed9;
    bytes32 internal constant WETH_HASH =
        0x5706be52f64875fee65a2cec0d80e47a23d8793cbe85d214b48445e2d05f5353;

    VmPonsV2AdapterFactory internal constant vm =
        VmPonsV2AdapterFactory(address(uint160(uint256(keccak256("hevm cheat code")))));

    error WrongChain(uint256 actual);
    error WrongDeployer(address actual);
    error DependencyHashMismatch(address dependency, bytes32 expected, bytes32 actual);
    error DeploymentFailed();

    function run() external returns (SinjohPonsV2AdapterFactory factory) {
        if (block.chainid != ROBINHOOD_MAINNET_CHAIN_ID) revert WrongChain(block.chainid);
        _assertHash(PONS_V2_FACTORY, PONS_V2_FACTORY_HASH);
        _assertHash(PONS_V2_FEE_ESCROW, PONS_V2_FEE_ESCROW_HASH);
        _assertHash(WETH, WETH_HASH);

        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        if (deployer != EXPECTED_DEPLOYER) revert WrongDeployer(deployer);

        vm.startBroadcast(deployerKey);
        factory = new SinjohPonsV2AdapterFactory(
            PONS_V2_FACTORY, PONS_V2_FEE_ESCROW, WETH, ROBINHOOD_MAINNET_CHAIN_ID
        );
        vm.stopBroadcast();

        if (
            address(factory).code.length == 0 || factory.launchFactory() != PONS_V2_FACTORY
                || factory.feeEscrow() != PONS_V2_FEE_ESCROW || factory.weth() != WETH
                || factory.deploymentChainId() != ROBINHOOD_MAINNET_CHAIN_ID
                || !SinjohPonsV2Adapter(payable(factory.implementation())).initialized()
        ) revert DeploymentFailed();
    }

    function _assertHash(address dependency, bytes32 expected) private view {
        bytes32 actual = dependency.codehash;
        if (actual != expected) {
            revert DependencyHashMismatch(dependency, expected, actual);
        }
    }
}
