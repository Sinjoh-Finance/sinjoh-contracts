// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { SinjohRaffleRewardsFactory } from "../src/SinjohRaffleRewardsFactory.sol";

interface Vm {
    function addr(uint256 privateKey) external returns (address);
    function envAddress(string calldata name) external returns (address);
    function startBroadcast() external;
    function stopBroadcast() external;
}

/// @notice Deploys the raffle factory and its implementation.
/// @dev `RANDOMNESS_ADAPTER` is a production smoke check for the intended adapter. Every raffle
/// independently rejects a configured adapter without code during its immutable initialization.
contract DeployRaffleRewardsFactory {
    uint256 internal constant ROBINHOOD_MAINNET_CHAIN_ID = 4_663;

    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    error WrongChain(uint256 actual);
    error AdapterHasNoCode(address adapter);
    error DeploymentFailed();

    function run() external returns (SinjohRaffleRewardsFactory factory) {
        // The chain id is the only viable chain probe here. ArbSys cannot be
        // consulted: it is node-implemented, its account holds a single
        // INVALID opcode, and forge's pre-broadcast simulation runs in a
        // local EVM where any call to it reverts — so an ArbSys check makes
        // every simulated run fail unconditionally.
        if (block.chainid != ROBINHOOD_MAINNET_CHAIN_ID) revert WrongChain(block.chainid);

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
