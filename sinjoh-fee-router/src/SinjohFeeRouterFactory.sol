// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { RouterTypes } from "./RouterTypes.sol";
import { SinjohFeeRouter } from "./SinjohFeeRouter.sol";
import { Clones } from "./libraries/Clones.sol";

contract SinjohFeeRouterFactory {
    error InvalidImplementation();
    error CreatorMismatch();
    error ConfigMismatch();
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

    /// @notice Deploys a router whose address is predictable from
    /// `(creator, userSalt)` alone, before the subject token exists.
    ///
    /// @dev Deliberately excludes the config from the salt. The config names a
    /// launchpad adapter, and that adapter's own address must be predictable
    /// before the router is deployed — folding the config in would make each
    /// address depend on the other. Address stability is preserved instead by
    /// rejecting a redeploy whose config differs from the one already stored.
    function deployForLaunchpad(
        address creator,
        bytes32 userSalt,
        RouterTypes.Config calldata config
    ) external returns (address router) {
        if (creator != config.creator) revert CreatorMismatch();
        bytes32 configHash = keccak256(abi.encode(config));
        bytes32 salt = _launchpadDerivedSalt(creator, userSalt);
        router = Clones.predictDeterministicAddress(implementation, salt, address(this));

        bool created;
        if (router.code.length == 0) {
            router = Clones.cloneDeterministic(implementation, salt);
            try SinjohFeeRouter(payable(router)).initialize(config) { }
            catch (bytes memory reason) {
                revert InitializationFailed(reason);
            }
            created = true;
        } else if (SinjohFeeRouter(payable(router)).configHash() != configHash) {
            revert ConfigMismatch();
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

    function predictLaunchpadAddress(address creator, bytes32 userSalt)
        external
        view
        returns (address)
    {
        bytes32 salt = _launchpadDerivedSalt(creator, userSalt);
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

    function _launchpadDerivedSalt(address creator, bytes32 userSalt)
        private
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode("SINJOH_LAUNCHPAD_ROUTER_V2", creator, userSalt));
    }
}
