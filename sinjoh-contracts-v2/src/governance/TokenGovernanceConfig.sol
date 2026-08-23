// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

/// @notice Immutable first-release parameters for one Token Governance deployment.
struct TokenGovernanceConfig {
    uint48 votingDelay;
    uint32 votingPeriod;
    uint16 proposalThresholdBps;
    uint16 quorumBps;
    uint48 timelockDelay;
    uint256 referenceSupply;
}
