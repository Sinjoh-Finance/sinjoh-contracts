// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { SinjohV3RouteTwapPriceGuard } from "./SinjohV3RouteTwapPriceGuard.sol";

/// @notice Deterministically deploys route price guards.
/// @dev Split out of {SinjohV3RouteExecutionFactory} because a factory carries
/// its children's creation code in its own runtime, and carrying all three
/// children put that factory over the EIP-170 limit. Guards are deployed from
/// this address instead, which keeps both contracts deployable without giving
/// anyone a new privilege: every deployment is still permissionless, keyed to
/// the caller-supplied creator and salt, and idempotent.
contract SinjohV3RouteGuardDeployer {
    error InvalidCreator();

    event RouteGuardDeployed(
        address indexed guard,
        address indexed creator,
        bytes32 indexed userSalt,
        bytes32 derivedSalt,
        bool created
    );

    function deployGuard(
        address creator,
        bytes32 userSalt,
        SinjohV3RouteTwapPriceGuard.RouteGuard memory config
    ) external returns (address guard) {
        if (creator == address(0)) revert InvalidCreator();
        bytes32 salt = _guardSalt(creator, userSalt, config);
        guard = predictGuard(creator, userSalt, config);
        bool created;
        if (guard.code.length == 0) {
            guard = address(new SinjohV3RouteTwapPriceGuard{ salt: salt }(config));
            created = true;
        }
        emit RouteGuardDeployed(guard, creator, userSalt, salt, created);
    }

    function predictGuard(
        address creator,
        bytes32 userSalt,
        SinjohV3RouteTwapPriceGuard.RouteGuard memory config
    ) public view returns (address) {
        if (creator == address(0)) revert InvalidCreator();
        bytes32 initCodeHash = keccak256(
            abi.encodePacked(
                type(SinjohV3RouteTwapPriceGuard).creationCode, abi.encode(config)
            )
        );
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            address(this),
                            _guardSalt(creator, userSalt, config),
                            initCodeHash
                        )
                    )
                )
            )
        );
    }

    function _guardSalt(
        address creator,
        bytes32 userSalt,
        SinjohV3RouteTwapPriceGuard.RouteGuard memory config
    ) private view returns (bytes32) {
        return keccak256(abi.encode(block.chainid, creator, userSalt, config));
    }
}
