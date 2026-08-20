// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

interface IGovernanceController {
    enum Mode {
        IMMUTABLE,
        INDIVIDUAL,
        MULTISIG,
        TOKEN_GOVERNOR
    }

    function mode() external view returns (Mode);
    function authority() external view returns (address);
    function canCall(address caller, address target, bytes4 selector) external view returns (bool);
}
