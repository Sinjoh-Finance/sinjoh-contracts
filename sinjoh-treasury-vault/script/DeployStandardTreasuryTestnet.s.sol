// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { SinjohTreasuryFactory } from "../src/SinjohTreasuryFactory.sol";

interface VmStandardTreasuryTestnet {
    function addr(uint256 privateKey) external returns (address);
    function envAddress(string calldata name) external returns (address);
    function envUint(string calldata name) external returns (uint256);
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
}

contract DeployStandardTreasuryTestnet {
    uint256 internal constant ROBINHOOD_TESTNET_CHAIN_ID = 46_630;
    VmStandardTreasuryTestnet internal constant vm =
        VmStandardTreasuryTestnet(address(uint160(uint256(keccak256("hevm cheat code")))));

    error WrongChain(uint256 actual);
    error WrongDeployer(address actual);
    error DeploymentFailed();

    function run() external returns (SinjohTreasuryFactory factory) {
        if (block.chainid != ROBINHOOD_TESTNET_CHAIN_ID) revert WrongChain(block.chainid);
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        if (deployer != vm.envAddress("TESTNET_DEPLOYER_ADDRESS")) revert WrongDeployer(deployer);

        vm.startBroadcast(deployerKey);
        factory = new SinjohTreasuryFactory();
        vm.stopBroadcast();

        if (
            address(factory).code.length == 0 || factory.GOVERNOR_HANDOFF_DELAY() != 3 days
                || factory.PROPOSAL_TTL() != 30 days
        ) revert DeploymentFailed();
    }
}
