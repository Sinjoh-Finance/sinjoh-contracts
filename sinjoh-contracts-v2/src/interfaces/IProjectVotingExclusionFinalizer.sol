// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

interface IProjectVotingExclusionFinalizer {
    function votingExclusionConfigurator() external view returns (address);
    function votingExclusionsFinalized() external view returns (bool);
    function finalizeVotingExclusions(address[] calldata exclusions) external;
}
