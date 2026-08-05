// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { SinjohEcvrfRandomness } from "../src/SinjohEcvrfRandomness.sol";

interface Vm {
    function envUint(string calldata name) external returns (uint256);
    function startBroadcast() external;
    function stopBroadcast() external;
}

/// @notice Deploys the ECVRF randomness adapter.
/// @dev The public key is immutable and every consumer binds to this adapter immutably, so a
/// wrong key here cannot be corrected without stranding every consumer deployed against it. The
/// constructor rejects a key that is not on secp256k1, but it cannot check that anyone actually
/// holds the matching secret. Prove that offchain first: seal a throwaway request and verify a
/// real proof against this deployment before any consumer is configured.
contract DeployEcvrfRandomness {
    uint256 internal constant ROBINHOOD_MAINNET_CHAIN_ID = 4_663;

    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    error WrongChain(uint256 actual);
    error DeploymentFailed();

    function run() external returns (SinjohEcvrfRandomness adapter) {
        // The chain id is the only viable chain probe here. ArbSys cannot be
        // consulted: it is node-implemented, its account holds a single
        // INVALID opcode, and forge's pre-broadcast simulation runs in a
        // local EVM where any call to it reverts — so an ArbSys check makes
        // every simulated run fail unconditionally.
        if (block.chainid != ROBINHOOD_MAINNET_CHAIN_ID) revert WrongChain(block.chainid);

        uint256 publicKeyX = vm.envUint("ECVRF_PUBLIC_KEY_X");
        uint256 publicKeyY = vm.envUint("ECVRF_PUBLIC_KEY_Y");

        // Signing comes from forge's --account/--ledger machinery; the key
        // never enters an environment variable.
        vm.startBroadcast();
        adapter = new SinjohEcvrfRandomness(publicKeyX, publicKeyY, block.chainid);
        vm.stopBroadcast();

        if (address(adapter).code.length == 0) revert DeploymentFailed();
    }
}
