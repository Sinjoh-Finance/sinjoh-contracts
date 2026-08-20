// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IGovernanceController } from "../interfaces/IGovernanceController.sol";

abstract contract Governed {
    IGovernanceController public immutable governanceController;
    address public immutable emergencyGuardian;
    bool public paused;

    error Unauthorized();
    error InvalidGovernanceController();
    error Paused();
    error NotPaused();

    event EmergencyPaused(address indexed guardian);
    event GovernanceResumed(address indexed governance);

    constructor(IGovernanceController controller, address guardian) {
        if (address(controller).code.length == 0 || guardian == address(0)) {
            revert InvalidGovernanceController();
        }
        governanceController = controller;
        emergencyGuardian = guardian;
    }

    modifier onlyGovernance() {
        if (!governanceController.canCall(msg.sender, address(this), msg.sig)) {
            revert Unauthorized();
        }
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert Paused();
        _;
    }

    function pause() external {
        if (msg.sender != emergencyGuardian) revert Unauthorized();
        if (paused) revert Paused();
        paused = true;
        emit EmergencyPaused(msg.sender);
    }

    function resume() external onlyGovernance {
        if (!paused) revert NotPaused();
        paused = false;
        emit GovernanceResumed(msg.sender);
    }
}
