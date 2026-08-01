// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { SinjohEcvrfRandomness } from "../src/SinjohEcvrfRandomness.sol";

interface Vm {
    function envUint(string calldata name) external returns (uint256);
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
}

interface IArbSys {
    function arbBlockNumber() external view returns (uint256);
}

/// @notice Deploys the ECVRF randomness adapter.
/// @dev The public key is immutable and every consumer binds to this adapter immutably, so a
/// wrong key here cannot be corrected without stranding every consumer deployed against it. The
/// constructor rejects a key that is not on secp256k1, but it cannot check that anyone actually
/// holds the matching secret. Prove that offchain first: seal a throwaway request and verify a
/// real proof against this deployment before any consumer is configured.
contract DeployEcvrfRandomness {
    uint256 internal constant ROBINHOOD_MAINNET_CHAIN_ID = 4_663;
    address internal constant ARBSYS = address(0x64);

    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    error WrongChain(uint256 actual);
    error MissingArbSys();
    error DeploymentFailed();

    function run() external returns (SinjohEcvrfRandomness adapter) {
        if (block.chainid != ROBINHOOD_MAINNET_CHAIN_ID) revert WrongChain(block.chainid);
        if (IArbSys(ARBSYS).arbBlockNumber() == 0) revert MissingArbSys();

        uint256 publicKeyX = vm.envUint("ECVRF_PUBLIC_KEY_X");
        uint256 publicKeyY = vm.envUint("ECVRF_PUBLIC_KEY_Y");

        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerKey);
        adapter = new SinjohEcvrfRandomness(publicKeyX, publicKeyY, block.chainid);
        vm.stopBroadcast();

        if (address(adapter).code.length == 0) revert DeploymentFailed();
    }
}
