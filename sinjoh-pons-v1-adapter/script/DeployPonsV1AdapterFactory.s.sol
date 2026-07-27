// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { SinjohPonsV1AdapterFactory } from "../src/SinjohPonsV1AdapterFactory.sol";

interface Vm {
    function addr(uint256 privateKey) external returns (address);
    function envUint(string calldata name) external returns (uint256);
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
}

contract DeployPonsV1AdapterFactory {
    uint256 internal constant ROBINHOOD_TESTNET_CHAIN_ID = 46_630;
    address internal constant EXPECTED_DEPLOYER = 0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49;

    address internal constant PONS_V1_LOCKER = 0x9E18AFba6eADDC1A00Edd35FB7AB6C5CD1E1dEE0;
    address internal constant WETH = 0x37E402B8081eFcE1D82A09a066512278006e4691;
    bytes32 internal constant PONS_V1_LOCKER_HASH =
        0xc98810d63174049c9debaab082a05f52ff16b6df65781dda07cc95d85a34730c;
    bytes32 internal constant WETH_HASH =
        0xa7f01c02394c333cc82f3236a0212384759ac2b0a4b982db822e3ff691e6567d;

    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    error WrongChain(uint256 actual);
    error WrongDeployer(address actual);
    error DependencyHashMismatch(address dependency, bytes32 expected, bytes32 actual);
    error DeploymentFailed();

    function run() external returns (SinjohPonsV1AdapterFactory factory) {
        if (block.chainid != ROBINHOOD_TESTNET_CHAIN_ID) {
            revert WrongChain(block.chainid);
        }
        _assertHash(PONS_V1_LOCKER, PONS_V1_LOCKER_HASH);
        _assertHash(WETH, WETH_HASH);

        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        if (deployer != EXPECTED_DEPLOYER) revert WrongDeployer(deployer);

        vm.startBroadcast(deployerKey);
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
