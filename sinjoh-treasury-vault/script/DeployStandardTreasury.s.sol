// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { SinjohJoint } from "../src/SinjohJoint.sol";
import { SinjohTreasuryVault } from "../src/SinjohTreasuryVault.sol";

interface Vm {
    function addr(uint256 privateKey) external returns (address);
    function envUint(string calldata name) external returns (uint256);
    function envAddress(string calldata name) external returns (address);
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
}

/// @notice Deploys the Standard treasury preset: one `SinjohJoint` (2-of-3) governing one
///         `SinjohTreasuryVault`. Signers are supplied through `SIGNER_1..3` environment
///         variables; the recovery rail is disabled for Standard.
contract DeployStandardTreasury {
    uint256 internal constant ROBINHOOD_MAINNET_CHAIN_ID = 4_663;
    uint256 internal constant GOVERNOR_HANDOFF_DELAY = 3 days;
    uint256 internal constant PROPOSAL_TTL = 30 days;
    address internal constant ARBSYS = address(0x64);
    bytes32 internal constant ARBSYS_MARKER_HASH =
        0xbcc90f2d6dada5b18e155c17a1c0a55920aae94f39857d39d0d8ed07ae8f228b;

    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    error WrongChain(uint256 actual);
    error InvalidArbSys();
    error DeploymentFailed();

    function run() external returns (SinjohJoint joint, SinjohTreasuryVault vault) {
        if (block.chainid != ROBINHOOD_MAINNET_CHAIN_ID) {
            revert WrongChain(block.chainid);
        }
        if (ARBSYS.codehash != ARBSYS_MARKER_HASH) revert InvalidArbSys();

        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address[3] memory signers =
            [vm.envAddress("SIGNER_1"), vm.envAddress("SIGNER_2"), vm.envAddress("SIGNER_3")];

        vm.startBroadcast(deployerKey);
        joint = new SinjohJoint(signers, PROPOSAL_TTL);
        vault = new SinjohTreasuryVault(address(joint), GOVERNOR_HANDOFF_DELAY, address(0), 0);
        vm.stopBroadcast();

        if (
            address(joint).code.length == 0 || address(vault).code.length == 0
                || vault.governor() != address(joint)
                || vault.GOVERNOR_HANDOFF_DELAY() != GOVERNOR_HANDOFF_DELAY
                || vault.RECOVERY_ADDRESS() != address(0) || joint.PROPOSAL_TTL() != PROPOSAL_TTL
                || !joint.isSigner(signers[0]) || !joint.isSigner(signers[1])
                || !joint.isSigner(signers[2])
        ) {
            revert DeploymentFailed();
        }
    }
}
