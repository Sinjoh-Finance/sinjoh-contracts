// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

/// @notice Canonical Sinjoh v2 project identity derivation.
library ProjectIds {
    function derive(uint256 chainId, address registry, address subject)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(chainId, registry, subject));
    }
}
