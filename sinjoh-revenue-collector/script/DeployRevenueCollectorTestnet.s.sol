// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { SinjohRevenueCollector } from "../src/SinjohRevenueCollector.sol";

interface VmRevenueCollectorTestnet {
    function addr(uint256 privateKey) external returns (address);
    function envAddress(string calldata name) external returns (address);
    function envUint(string calldata name) external returns (uint256);
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
}

/// @notice Deploys the production Revenue Collector implementation on Robinhood testnet.
contract DeployRevenueCollectorTestnet {
    uint256 internal constant ROBINHOOD_TESTNET_CHAIN_ID = 46_630;
    VmRevenueCollectorTestnet internal constant vm =
        VmRevenueCollectorTestnet(address(uint160(uint256(keccak256("hevm cheat code")))));

    error WrongChain(uint256 actual);
    error WrongDeployer(address actual);
    error InvalidConfiguration();
    error DeploymentFailed();

    function run() external returns (SinjohRevenueCollector collector) {
        if (block.chainid != ROBINHOOD_TESTNET_CHAIN_ID) revert WrongChain(block.chainid);

        address governance = vm.envAddress("GOVERNANCE");
        address initialProcessor = vm.envAddress("INITIAL_PROCESSOR");
        if (governance == address(0) || initialProcessor == address(0)) {
            revert InvalidConfiguration();
        }

        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        if (deployer != vm.envAddress("TESTNET_DEPLOYER_ADDRESS")) revert WrongDeployer(deployer);

        vm.startBroadcast(deployerKey);
        collector = new SinjohRevenueCollector(governance, initialProcessor);
        vm.stopBroadcast();

        if (
            address(collector).code.length == 0 || collector.owner() != governance
                || collector.processor() != initialProcessor
        ) revert DeploymentFailed();
    }
}
