// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IGovernanceController } from "../interfaces/IGovernanceController.sol";

/// @notice Controller for deployments that irrevocably disable all governance mutations.
contract ImmutableGovernanceController is IGovernanceController {
    function mode() external pure returns (Mode) {
        return Mode.IMMUTABLE;
    }

    function authority() external pure returns (address) {
        return address(0);
    }

    function canCall(address, address, bytes4) external pure returns (bool) {
        return false;
    }
}
