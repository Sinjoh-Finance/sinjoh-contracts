// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { SinjohJoint } from "./SinjohJoint.sol";
import { SinjohTreasuryVault } from "./SinjohTreasuryVault.sol";

/// @title SinjohTreasuryFactory
/// @notice Permissionless factory for Standard treasuries: one `SinjohJoint` (2-of-3) governing
///         one `SinjohTreasuryVault`. Standard parameters are frozen in the factory; callers
///         supply only their three signer addresses.
/// @dev The factory keeps no privileges over what it deploys and cannot be paused or upgraded.
///      `jointForVault` lets integrators verify that a vault was deployed here with the Standard
///      configuration instead of trusting an off-chain record.
contract SinjohTreasuryFactory {
    uint256 public constant GOVERNOR_HANDOFF_DELAY = 3 days;
    uint256 public constant PROPOSAL_TTL = 30 days;

    mapping(address vault => address joint) public jointForVault;

    event TreasuryCreated(
        address indexed creator, address indexed vault, address indexed joint, address[3] signers
    );

    /// @notice Deploys a Standard treasury controlled by the supplied 2-of-3 signer set.
    function createStandardTreasury(address[3] calldata signers)
        external
        returns (SinjohJoint joint, SinjohTreasuryVault vault)
    {
        joint = new SinjohJoint(signers, PROPOSAL_TTL);
        vault = new SinjohTreasuryVault(address(joint), GOVERNOR_HANDOFF_DELAY, address(0), 0);

        jointForVault[address(vault)] = address(joint);
        emit TreasuryCreated(msg.sender, address(vault), address(joint), signers);
    }
}
