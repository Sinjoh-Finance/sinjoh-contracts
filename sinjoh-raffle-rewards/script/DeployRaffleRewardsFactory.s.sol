// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { SinjohRaffleRewardsFactory } from "../src/SinjohRaffleRewardsFactory.sol";

interface Vm {
    function addr(uint256 privateKey) external returns (address);
    function envAddress(string calldata name) external returns (address);
    function startBroadcast() external;
    function stopBroadcast() external;
}

interface IArbSys {
    function arbBlockNumber() external view returns (uint256);
}

/// @notice Deploys the raffle factory and its implementation.
/// @dev `RANDOMNESS_ADAPTER` is a production smoke check for the intended adapter. Every raffle
/// independently rejects a configured adapter without code during its immutable initialization.
contract DeployRaffleRewardsFactory {
    uint256 internal constant ROBINHOOD_MAINNET_CHAIN_ID = 4_663;
    address internal constant ARBSYS = address(0x64);

    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    error WrongChain(uint256 actual);
    error MissingArbSys();
    error AdapterHasNoCode(address adapter);
    error DeploymentFailed();

    function run() external returns (SinjohRaffleRewardsFactory factory) {
        if (block.chainid != ROBINHOOD_MAINNET_CHAIN_ID) revert WrongChain(block.chainid);
        if (IArbSys(ARBSYS).arbBlockNumber() == 0) revert MissingArbSys();

        address adapter = vm.envAddress("RANDOMNESS_ADAPTER");
        if (adapter.code.length == 0) revert AdapterHasNoCode(adapter);

        // Signing comes from forge's --account/--ledger machinery; the key
        // never enters an environment variable.
        vm.startBroadcast();
        factory = new SinjohRaffleRewardsFactory(block.chainid);
        vm.stopBroadcast();

        if (address(factory).code.length == 0 || factory.implementation().code.length == 0) {
            revert DeploymentFailed();
        }
    }
}
