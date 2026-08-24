// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ProjectVotesToken } from "./ProjectVotesToken.sol";
import { LaunchpadProjectVotesToken } from "./LaunchpadProjectVotesToken.sol";

/// @notice Ownerless factory for canonical tokens distributed by existing-token launchpads.
contract LaunchpadProjectVotesTokenFactoryV2 {
    struct TokenDeployment {
        string name;
        string symbol;
        address registry;
        address creator;
        ProjectVotesToken.TokenAllocation[] allocations;
        address[] votingExclusions;
        address votingExclusionConfigurator;
        bytes32 salt;
    }

    event ProjectVotesTokenDeployed(
        address indexed token,
        address indexed launchpad,
        address indexed creator,
        bytes32 derivedSalt
    );

    function deploy(TokenDeployment calldata deployment) external returns (address token) {
        bytes32 derived = derivedSalt(msg.sender, deployment.creator, deployment.salt);
        token = address(
            new LaunchpadProjectVotesToken{ salt: derived }(
                deployment.name,
                deployment.symbol,
                deployment.registry,
                deployment.creator,
                deployment.allocations,
                deployment.votingExclusions,
                deployment.votingExclusionConfigurator
            )
        );
        emit ProjectVotesTokenDeployed(token, msg.sender, deployment.creator, derived);
    }

    function predict(TokenDeployment calldata deployment, address launchpad)
        external
        view
        returns (address)
    {
        bytes32 derived = derivedSalt(launchpad, deployment.creator, deployment.salt);
        bytes memory initCode = bytes.concat(
            type(LaunchpadProjectVotesToken).creationCode,
            abi.encode(
                deployment.name,
                deployment.symbol,
                deployment.registry,
                deployment.creator,
                deployment.allocations,
                deployment.votingExclusions,
                deployment.votingExclusionConfigurator
            )
        );
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), address(this), derived, keccak256(initCode))
                    )
                )
            )
        );
    }

    function derivedSalt(address launchpad, address creator, bytes32 userSalt)
        public
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                "SINJOH_PROJECT_V2_LAUNCHPAD_TOKEN",
                block.chainid,
                address(this),
                launchpad,
                creator,
                userSalt
            )
        );
    }
}
