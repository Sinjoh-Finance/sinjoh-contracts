// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { SinjohRaffleRewardsFactory } from "../src/SinjohRaffleRewardsFactory.sol";

interface VmRaffleRewardsFactoryTestnet {
    function addr(uint256 privateKey) external returns (address);
    function envUint(string calldata name) external returns (uint256);
    function envAddress(string calldata name) external returns (address);
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
}

interface IArbSysTestnet {
    function arbBlockNumber() external view returns (uint256);
}

/// @notice Deploys the raffle factory only on Robinhood Chain testnet.
contract DeployRaffleRewardsFactoryTestnet {
    uint256 internal constant ROBINHOOD_TESTNET_CHAIN_ID = 46_630;
    address internal constant EXPECTED_DEPLOYER = 0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49;
    address internal constant ARBSYS = address(0x64);

    VmRaffleRewardsFactoryTestnet internal constant vm =
        VmRaffleRewardsFactoryTestnet(address(uint160(uint256(keccak256("hevm cheat code")))));

    error WrongChain(uint256 actual);
    error WrongDeployer(address actual);
    error MissingArbSys();
    error AdapterHasNoCode(address adapter);
    error DeploymentFailed();

    function run() external returns (SinjohRaffleRewardsFactory factory) {
        if (block.chainid != ROBINHOOD_TESTNET_CHAIN_ID) revert WrongChain(block.chainid);
        if (IArbSysTestnet(ARBSYS).arbBlockNumber() == 0) revert MissingArbSys();

        address adapter = vm.envAddress("RANDOMNESS_ADAPTER");
        if (adapter.code.length == 0) revert AdapterHasNoCode(adapter);

        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        if (deployer != EXPECTED_DEPLOYER) revert WrongDeployer(deployer);

        vm.startBroadcast(deployerKey);
        factory = new SinjohRaffleRewardsFactory(block.chainid);
        vm.stopBroadcast();

        if (address(factory).code.length == 0 || factory.implementation().code.length == 0) {
            revert DeploymentFailed();
        }
    }
}
