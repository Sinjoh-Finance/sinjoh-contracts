// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { SinjohLaunchStakingEngine } from "../src/SinjohLaunchStakingEngine.sol";

interface VmDeployLaunchStakingEngine {
    function startBroadcast() external;
    function stopBroadcast() external;
}

/// @notice Deploys the shared multi-token launch staking sink on Robinhood Chain mainnet.
/// @dev Uses Foundry's selected `--account`; it never reads or parses a private key environment
/// variable. This script deploys infrastructure only and cannot launch a token.
contract DeployLaunchStakingEngine {
    uint256 internal constant ROBINHOOD_MAINNET_CHAIN_ID = 4_663;
    address internal constant PROTOCOL_FEE_RECIPIENT = 0x5Bb7582557F5be30b62c335Ad3ccf4bA79E138c5;

    VmDeployLaunchStakingEngine internal constant vm =
        VmDeployLaunchStakingEngine(address(uint160(uint256(keccak256("hevm cheat code")))));

    error WrongChain(uint256 expected, uint256 actual);
    error DeploymentVerificationFailed();

    event LaunchStakingEngineDeployed(
        address indexed engine, address indexed protocolFeeRecipient, bytes32 runtimeCodeHash
    );

    function run() external returns (SinjohLaunchStakingEngine engine) {
        if (block.chainid != ROBINHOOD_MAINNET_CHAIN_ID) {
            revert WrongChain(ROBINHOOD_MAINNET_CHAIN_ID, block.chainid);
        }
        vm.startBroadcast();
        engine = new SinjohLaunchStakingEngine(PROTOCOL_FEE_RECIPIENT);
        vm.stopBroadcast();

        if (
            address(engine).code.length == 0
                || engine.protocolFeeRecipient() != PROTOCOL_FEE_RECIPIENT
        ) revert DeploymentVerificationFailed();
        emit LaunchStakingEngineDeployed(
            address(engine), PROTOCOL_FEE_RECIPIENT, address(engine).codehash
        );
    }
}
