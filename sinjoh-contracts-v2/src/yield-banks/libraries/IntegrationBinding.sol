// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

library IntegrationBinding {
    error InvalidIntegration(address integration);
    error RuntimeCodeHashMismatch(address integration, bytes32 expected, bytes32 actual);

    function runtimeCodeHash(address integration) internal view returns (bytes32 hash) {
        assembly ("memory-safe") {
            hash := extcodehash(integration)
        }
    }

    function requireBound(address integration, bytes32 expected) internal view {
        if (integration.code.length == 0 || expected == bytes32(0)) {
            revert InvalidIntegration(integration);
        }
        bytes32 actual = runtimeCodeHash(integration);
        if (actual != expected) revert RuntimeCodeHashMismatch(integration, expected, actual);
    }
}
