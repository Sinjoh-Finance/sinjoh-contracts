// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ProjectVotesToken } from "./ProjectVotesToken.sol";
import { PonsProjectVotesToken } from "./PonsProjectVotesToken.sol";

/// @notice Ownerless canonical token factory for launchpads integrating with Project V2.
/// @dev Salts are namespaced by caller, so one launchpad cannot consume another's prediction.
contract ProjectVotesTokenFactoryV2 {
    struct TokenDeployment {
        string name;
        string symbol;
        address registry;
        address creator;
        ProjectVotesToken.TokenAllocation[] allocations;
        address[] votingExclusions;
        bytes32 salt;
    }

    struct PonsTokenDeployment {
        PonsProjectVotesToken.TokenConfig token;
        bytes32 salt;
    }

    event ProjectVotesTokenDeployed(
        address indexed token,
        address indexed launchpad,
        address indexed creator,
        bytes32 derivedSalt,
        bool ponsCompatible
    );

    function deploy(TokenDeployment calldata deployment) external returns (address token) {
        bytes32 derived = derivedSalt(msg.sender, deployment.creator, deployment.salt, false);
        token = address(
            new ProjectVotesToken{ salt: derived }(
                deployment.name,
                deployment.symbol,
                deployment.registry,
                deployment.creator,
                deployment.allocations,
                deployment.votingExclusions
            )
        );
        emit ProjectVotesTokenDeployed(token, msg.sender, deployment.creator, derived, false);
    }

    function deployPons(PonsTokenDeployment calldata deployment) external returns (address token) {
        bytes32 derived = derivedSalt(msg.sender, deployment.token.creator, deployment.salt, true);
        token = address(new PonsProjectVotesToken{ salt: derived }(deployment.token));
        emit ProjectVotesTokenDeployed(token, msg.sender, deployment.token.creator, derived, true);
    }

    function predict(TokenDeployment calldata deployment, address launchpad)
        external
        view
        returns (address)
    {
        bytes32 derived = derivedSalt(launchpad, deployment.creator, deployment.salt, false);
        bytes memory initCode = bytes.concat(
            type(ProjectVotesToken).creationCode,
            abi.encode(
                deployment.name,
                deployment.symbol,
                deployment.registry,
                deployment.creator,
                deployment.allocations,
                deployment.votingExclusions
            )
        );
        return _predict(derived, keccak256(initCode));
    }

    function predictPons(PonsTokenDeployment calldata deployment, address launchpad)
        external
        view
        returns (address)
    {
        bytes32 derived = derivedSalt(launchpad, deployment.token.creator, deployment.salt, true);
        bytes memory initCode =
            bytes.concat(type(PonsProjectVotesToken).creationCode, abi.encode(deployment.token));
        return _predict(derived, keccak256(initCode));
    }

    function derivedSalt(address launchpad, address creator, bytes32 userSalt, bool ponsCompatible)
        public
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                "SINJOH_PROJECT_V2_TOKEN",
                block.chainid,
                address(this),
                launchpad,
                creator,
                userSalt,
                ponsCompatible
            )
        );
    }

    function _predict(bytes32 salt, bytes32 initCodeHash) private view returns (address) {
        return address(
            uint160(
                uint256(
                    keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, initCodeHash))
                )
            )
        );
    }
}
