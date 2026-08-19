// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { SinjohRevenueCollector } from "../src/SinjohRevenueCollector.sol";

interface Vm {
    function addr(uint256 privateKey) external returns (address);
    function envUint(string calldata name) external returns (uint256);
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
}

contract DeployRevenueCollector {
    uint256 internal constant ROBINHOOD_MAINNET_CHAIN_ID = 4_663;
    address internal constant EXPECTED_DEPLOYER = 0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49;
    address internal constant GOVERNANCE = 0x39E2f5eFdFd808F26B98979a06BA11ea82E1C85f;
    address internal constant INITIAL_PROCESSOR = GOVERNANCE;
    address internal constant ARBSYS = address(0x64);
    bytes32 internal constant ARBSYS_MARKER_HASH =
        0xbcc90f2d6dada5b18e155c17a1c0a55920aae94f39857d39d0d8ed07ae8f228b;

    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    error WrongChain(uint256 actual);
    error WrongDeployer(address actual);
    error InvalidArbSys();
    error DeploymentFailed();

    function run() external returns (SinjohRevenueCollector collector) {
        if (block.chainid != ROBINHOOD_MAINNET_CHAIN_ID) {
            revert WrongChain(block.chainid);
        }
        if (ARBSYS.codehash != ARBSYS_MARKER_HASH) revert InvalidArbSys();

        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        if (deployer != EXPECTED_DEPLOYER) revert WrongDeployer(deployer);

        vm.startBroadcast(deployerKey);
        collector = new SinjohRevenueCollector(GOVERNANCE, INITIAL_PROCESSOR);
        vm.stopBroadcast();

        if (
            address(collector).code.length == 0 || collector.owner() != GOVERNANCE
                || collector.processor() != INITIAL_PROCESSOR
        ) {
            revert DeploymentFailed();
        }
    }
}
