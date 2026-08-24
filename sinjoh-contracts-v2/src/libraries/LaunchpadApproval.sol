// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

/// @notice Release-wide approval leaf for a concrete launch-adapter factory generation.
/// @dev The factory must maintain its own registry of adapters it created. Pinning the factory
/// address and runtime code binds the release to both that registry and its deployment policy.
library LaunchpadApproval {
    bytes32 internal constant LAUNCHPAD_FACTORY_DOMAIN =
        keccak256("SINJOH_V2_LAUNCHPAD_FACTORY_APPROVAL");

    function factoryLeaf(address factory) internal view returns (bytes32) {
        bytes32 inner = keccak256(
            abi.encode(LAUNCHPAD_FACTORY_DOMAIN, block.chainid, factory, factory.codehash)
        );
        return keccak256(bytes.concat(inner));
    }
}
