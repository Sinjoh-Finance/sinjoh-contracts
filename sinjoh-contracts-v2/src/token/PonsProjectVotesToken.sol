// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ProjectVotesToken } from "./ProjectVotesToken.sol";

/// @notice Canonical Project V2 voting token with the metadata surface expected by Pons v2.
/// @dev The entire fixed supply starts in the bonding curve, which must be voting-excluded.
contract PonsProjectVotesToken is ProjectVotesToken {
    struct Socials {
        string twitter;
        string telegram;
        string discord;
        string website;
        string farcaster;
    }

    struct TokenConfig {
        string name;
        string symbol;
        string logo;
        string description;
        Socials socials;
        address registry;
        address creator;
        address curve;
        address launchFactory;
        address votingExclusionConfigurator;
        uint256 supply;
        address[] votingExclusions;
    }

    address public immutable deployer;
    address public immutable launchFactory;
    address public immutable curve;
    address public immutable votingExclusionConfigurator;
    bool public votingExclusionsFinalized;

    string public logo;
    string public description;

    Socials private _socials;

    error InvalidPonsLaunch(address curve, address launchFactory);
    error InvalidVotingExclusionConfigurator(address configurator);
    error VotingExclusionsAlreadyFinalized();
    error OnlyVotingExclusionConfigurator(address caller);

    constructor(TokenConfig memory config)
        ProjectVotesToken(
            config.name,
            config.symbol,
            config.registry,
            config.creator,
            _curveAllocation(config.curve, config.supply),
            config.votingExclusions
        )
    {
        if (config.curve == address(0) || config.launchFactory == address(0)) {
            revert InvalidPonsLaunch(config.curve, config.launchFactory);
        }
        if (config.votingExclusionConfigurator.code.length == 0) {
            revert InvalidVotingExclusionConfigurator(config.votingExclusionConfigurator);
        }
        deployer = config.creator;
        launchFactory = config.launchFactory;
        curve = config.curve;
        votingExclusionConfigurator = config.votingExclusionConfigurator;
        logo = config.logo;
        description = config.description;
        _socials = config.socials;
    }

    function finalizeVotingExclusions(address[] calldata exclusions) external {
        if (msg.sender != votingExclusionConfigurator) {
            revert OnlyVotingExclusionConfigurator(msg.sender);
        }
        if (votingExclusionsFinalized) revert VotingExclusionsAlreadyFinalized();
        votingExclusionsFinalized = true;
        _appendPostLaunchVotingExclusions(exclusions);
    }

    function socials()
        external
        view
        returns (
            string memory twitter,
            string memory telegram,
            string memory discord,
            string memory website,
            string memory farcaster
        )
    {
        Socials memory values = _socials;
        return (values.twitter, values.telegram, values.discord, values.website, values.farcaster);
    }

    function getTokenInfo()
        external
        view
        returns (
            address tokenDeployer,
            string memory tokenLogo,
            string memory tokenDescription,
            Socials memory tokenSocials
        )
    {
        return (deployer, logo, description, _socials);
    }

    function _curveAllocation(address curve_, uint256 supply_)
        private
        pure
        returns (TokenAllocation[] memory allocations)
    {
        allocations = new TokenAllocation[](1);
        allocations[0] = TokenAllocation({ recipient: curve_, amount: supply_ });
    }
}
