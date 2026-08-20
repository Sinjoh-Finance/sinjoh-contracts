// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { AddressGovernanceController } from "./AddressGovernanceController.sol";
import { ImmutableGovernanceController } from "./ImmutableGovernanceController.sol";
import { IGovernanceController } from "../interfaces/IGovernanceController.sol";

/// @notice Deploys the small controller adapters shared by every protocol module.
/// @dev Token governors and their timelocks are deployed separately, then bound as the authority.
contract GovernanceControllerFactory {
    event AddressControllerDeployed(
        address indexed controller, address indexed authority, IGovernanceController.Mode mode
    );
    event ImmutableControllerDeployed(address indexed controller);

    function deployAddressController(address authority, IGovernanceController.Mode mode)
        external
        returns (AddressGovernanceController controller)
    {
        controller = new AddressGovernanceController(authority, mode);
        emit AddressControllerDeployed(address(controller), authority, mode);
    }

    function deployImmutableController()
        external
        returns (ImmutableGovernanceController controller)
    {
        controller = new ImmutableGovernanceController();
        emit ImmutableControllerDeployed(address(controller));
    }
}
