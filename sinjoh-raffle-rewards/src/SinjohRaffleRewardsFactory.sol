// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Clones } from "./libraries/Clones.sol";
import { RaffleTypes } from "./RaffleTypes.sol";
import { SinjohRaffleRewards } from "./SinjohRaffleRewards.sol";

/// @notice Deploys immutable raffles at addresses predictable before the subject token exists.
/// @dev The salt commits to the exact configuration, so a front-runner using the same salt can
/// only produce the identical contract.
contract SinjohRaffleRewardsFactory {
    error InitializationFailed(bytes reason);
    error WrongChain();

    event RaffleDeployed(
        address indexed raffle,
        address indexed creator,
        bytes32 configHash,
        bytes32 userSalt,
        bytes32 derivedSalt,
        uint256 chainId,
        address implementation,
        bool created
    );

    address public immutable implementation;
    uint256 public immutable deploymentChainId;

    constructor(uint256 chainId_) {
        if (block.chainid != chainId_) revert WrongChain();
        implementation = address(new SinjohRaffleRewards());
        deploymentChainId = chainId_;
    }

    function deployRaffle(bytes32 userSalt, RaffleTypes.Config calldata config)
        external
        returns (address raffle)
    {
        bytes32 configHash = keccak256(abi.encode(config));
        bytes32 salt = derivedSalt(config.creator, userSalt, configHash);
        raffle = Clones.predictDeterministicAddress(implementation, salt, address(this));

        bool created;
        if (raffle.code.length == 0) {
            raffle = Clones.cloneDeterministic(implementation, salt);
            try SinjohRaffleRewards(payable(raffle)).initialize(config) { }
            catch (bytes memory reason) {
                revert InitializationFailed(reason);
            }
            created = true;
        }

        emit RaffleDeployed(
            raffle,
            config.creator,
            configHash,
            userSalt,
            salt,
            deploymentChainId,
            implementation,
            created
        );
    }

    function predictRaffle(address creator, bytes32 userSalt, bytes32 configHash)
        external
        view
        returns (address)
    {
        return Clones.predictDeterministicAddress(
            implementation, derivedSalt(creator, userSalt, configHash), address(this)
        );
    }

    function hashConfig(RaffleTypes.Config calldata config) external pure returns (bytes32) {
        return keccak256(abi.encode(config));
    }

    function derivedSalt(address creator, bytes32 userSalt, bytes32 configHash)
        public
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                address(this), implementation, creator, userSalt, configHash, deploymentChainId
            )
        );
    }
}
