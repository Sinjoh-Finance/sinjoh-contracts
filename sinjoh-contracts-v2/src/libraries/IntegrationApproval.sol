// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

/// @notice Release-wide approval leaves for reusable swap integrations.
/// @dev A project address and route cannot be known when the immutable release root is created.
/// The approved unit is therefore one exact, already-deployed adapter/guard pair. The guard is
/// responsible for deriving and validating the concrete pair, route and price on every call.
library IntegrationApproval {
    bytes32 internal constant SWAP_INTEGRATION_DOMAIN =
        keccak256("SINJOH_V2_SWAP_INTEGRATION_APPROVAL");

    function swapLeaf(address adapter, address priceGuard) internal view returns (bytes32) {
        bytes32 inner = keccak256(
            abi.encode(
                SWAP_INTEGRATION_DOMAIN,
                block.chainid,
                adapter,
                adapter.codehash,
                priceGuard,
                priceGuard.codehash
            )
        );
        return keccak256(bytes.concat(inner));
    }
}
