// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

/// @notice Canonical Sinjoh v2 project identity derivation.
library ProjectIds {
    bytes4 private constant REGISTRY_SELECTOR = bytes4(keccak256("registry()"));
    bytes4 private constant PROJECT_ID_SELECTOR = bytes4(keccak256("projectId()"));

    function derive(uint256 chainId, address registry, address subject)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(chainId, registry, subject));
    }

    /// @notice Reads the canonical identity when the subject implements it.
    /// Ordinary launchpad ERC-20s intentionally return `declared = false`.
    function declaredIdentity(address subject)
        internal
        view
        returns (bool declared, address registry, bytes32 projectId)
    {
        (bool registryOk, bytes memory registryData) =
            subject.staticcall(abi.encodeWithSelector(REGISTRY_SELECTOR));
        (bool projectIdOk, bytes memory projectIdData) =
            subject.staticcall(abi.encodeWithSelector(PROJECT_ID_SELECTOR));
        if (!registryOk && !projectIdOk) return (false, address(0), bytes32(0));
        if (!registryOk || !projectIdOk || registryData.length != 32 || projectIdData.length != 32)
        {
            return (true, address(0), bytes32(0));
        }
        registry = abi.decode(registryData, (address));
        projectId = abi.decode(projectIdData, (bytes32));
        declared = true;
    }
}
