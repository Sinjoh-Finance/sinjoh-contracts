// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

/// @notice Immutable authority binding shared by governed Sinjoh v2 modules.
interface IProjectAuthority {
    enum Mode {
        MULTISIG,
        TOKEN_HOLDER
    }

    function projectId() external view returns (bytes32);
    function mode() external view returns (Mode);
    function executor() external view returns (address);
}
