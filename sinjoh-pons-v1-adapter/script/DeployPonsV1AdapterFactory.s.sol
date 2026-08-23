// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { SinjohPonsV1AdapterFactory } from "../src/SinjohPonsV1AdapterFactory.sol";

interface Vm {
    function envAddress(string calldata name) external returns (address);
    function startBroadcast(address signer) external;
    function stopBroadcast() external;
}

contract DeployPonsV1AdapterFactory {
    uint256 internal constant ROBINHOOD_MAINNET_CHAIN_ID = 4_663;
    address internal constant EXPECTED_DEPLOYER = 0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49;

    address internal constant PONS_V1_LOCKER = 0x736D76699C26D0d966744cAe304C000d471f7F35;
    address internal constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    bytes32 internal constant PONS_V1_LOCKER_HASH =
        0xa7880a625a649da833de5597c9f41585bb75e20ef91d45830ccc6f4e49cc281c;
    bytes32 internal constant WETH_HASH =
        0x5706be52f64875fee65a2cec0d80e47a23d8793cbe85d214b48445e2d05f5353;

    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    error WrongChain(uint256 actual);
    error WrongDeployer(address actual);
    error DependencyHashMismatch(address dependency, bytes32 expected, bytes32 actual);
    error DeploymentFailed();

    function run() external returns (SinjohPonsV1AdapterFactory factory) {
        if (block.chainid != ROBINHOOD_MAINNET_CHAIN_ID) {
            revert WrongChain(block.chainid);
        }
        _assertHash(PONS_V1_LOCKER, PONS_V1_LOCKER_HASH);
        _assertHash(WETH, WETH_HASH);

        address deployer = vm.envAddress("DEPLOYER_ADDRESS");
        if (deployer != EXPECTED_DEPLOYER) revert WrongDeployer(deployer);

        vm.startBroadcast(deployer);
        factory = new SinjohPonsV1AdapterFactory(PONS_V1_LOCKER, WETH, block.chainid);
        vm.stopBroadcast();

        if (address(factory).code.length == 0 || factory.implementation().code.length == 0) {
            revert DeploymentFailed();
        }
    }

    function _assertHash(address dependency, bytes32 expected) private view {
        bytes32 actual = dependency.codehash;
        if (actual != expected) {
            revert DependencyHashMismatch(dependency, expected, actual);
        }
    }
}
