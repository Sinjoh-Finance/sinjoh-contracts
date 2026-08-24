// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ProjectVotesToken } from "./ProjectVotesToken.sol";

/// @notice Canonical Project V2 token for launchpads that distribute an existing ERC-20.
contract LaunchpadProjectVotesToken is ProjectVotesToken {
    address public immutable votingExclusionConfigurator;
    bool public votingExclusionsFinalized;

    error InvalidVotingExclusionConfigurator(address configurator);
    error VotingExclusionsAlreadyFinalized();
    error OnlyVotingExclusionConfigurator(address caller);

    constructor(
        string memory name_,
        string memory symbol_,
        address registry_,
        address creator_,
        TokenAllocation[] memory allocations_,
        address[] memory votingExclusions_,
        address votingExclusionConfigurator_
    ) ProjectVotesToken(name_, symbol_, registry_, creator_, allocations_, votingExclusions_) {
        if (votingExclusionConfigurator_.code.length == 0) {
            revert InvalidVotingExclusionConfigurator(votingExclusionConfigurator_);
        }
        votingExclusionConfigurator = votingExclusionConfigurator_;
    }

    function finalizeVotingExclusions(address[] calldata exclusions) external {
        if (msg.sender != votingExclusionConfigurator) {
            revert OnlyVotingExclusionConfigurator(msg.sender);
        }
        if (votingExclusionsFinalized) revert VotingExclusionsAlreadyFinalized();
        votingExclusionsFinalized = true;
        _appendPostLaunchVotingExclusions(exclusions);
    }
}
