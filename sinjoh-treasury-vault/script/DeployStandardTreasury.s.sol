// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { SinjohTreasuryFactory } from "../src/SinjohTreasuryFactory.sol";

interface Vm {
    function startBroadcast() external;
    function stopBroadcast() external;
}

/// @notice Deploys the permissionless Standard treasury factory. Individual treasuries are
///         created later by anyone calling `createStandardTreasury` with their three signers.
contract DeployStandardTreasury {
    uint256 internal constant ROBINHOOD_MAINNET_CHAIN_ID = 4_663;
    address internal constant ARBSYS = address(0x64);
    bytes32 internal constant ARBSYS_MARKER_HASH =
        0xbcc90f2d6dada5b18e155c17a1c0a55920aae94f39857d39d0d8ed07ae8f228b;

    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    error WrongChain(uint256 actual);
    error InvalidArbSys();
    error DeploymentFailed();

    function run() external returns (SinjohTreasuryFactory factory) {
        if (block.chainid != ROBINHOOD_MAINNET_CHAIN_ID) {
            revert WrongChain(block.chainid);
        }
        if (ARBSYS.codehash != ARBSYS_MARKER_HASH) revert InvalidArbSys();

        vm.startBroadcast();
        factory = new SinjohTreasuryFactory();
        vm.stopBroadcast();

        if (
            address(factory).code.length == 0 || factory.GOVERNOR_HANDOFF_DELAY() != 3 days
                || factory.PROPOSAL_TTL() != 30 days
        ) {
            revert DeploymentFailed();
        }
    }
}
