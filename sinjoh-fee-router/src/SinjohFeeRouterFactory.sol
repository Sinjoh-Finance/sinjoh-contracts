// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { RouterTypes } from "./RouterTypes.sol";
import { SinjohFeeRouter } from "./SinjohFeeRouter.sol";
import { Clones } from "./libraries/Clones.sol";

contract SinjohFeeRouterFactory {
    error InvalidImplementation();
    error CreatorMismatch();
    error InitializationFailed(bytes reason);

    event RouterDeployed(
        address indexed router,
        address indexed creator,
        bytes32 indexed userSalt,
        bytes32 derivedSalt,
        bytes32 configHash,
        bool created
    );

    address public immutable implementation;

    constructor(address implementation_) {
        if (implementation_ == address(0) || implementation_.code.length == 0) {
            revert InvalidImplementation();
        }
        implementation = implementation_;
    }

    function deploy(address creator, bytes32 userSalt, RouterTypes.Config calldata config)
        external
        returns (address router)
    {
        if (creator != config.creator) revert CreatorMismatch();
        bytes32 configHash = keccak256(abi.encode(config));
        bytes32 salt = _derivedSalt(creator, userSalt, configHash);
        router = Clones.predictDeterministicAddress(implementation, salt, address(this));

        bool created;
        if (router.code.length == 0) {
            router = Clones.cloneDeterministic(implementation, salt);
            try SinjohFeeRouter(payable(router)).initialize(config) { }
            catch (bytes memory reason) {
                revert InitializationFailed(reason);
            }
            created = true;
        }

        emit RouterDeployed(router, creator, userSalt, salt, configHash, created);
    }

    function predictAddress(address creator, bytes32 userSalt, RouterTypes.Config calldata config)
        external
        view
        returns (address)
    {
        if (creator != config.creator) revert CreatorMismatch();
        bytes32 salt = _derivedSalt(creator, userSalt, keccak256(abi.encode(config)));
        return Clones.predictDeterministicAddress(implementation, salt, address(this));
    }

    function derivedSalt(address creator, bytes32 userSalt, RouterTypes.Config calldata config)
        external
        pure
        returns (bytes32)
    {
        if (creator != config.creator) revert CreatorMismatch();
        return _derivedSalt(creator, userSalt, keccak256(abi.encode(config)));
    }

    function _derivedSalt(address creator, bytes32 userSalt, bytes32 configHash)
        private
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(creator, userSalt, configHash));
    }
}
