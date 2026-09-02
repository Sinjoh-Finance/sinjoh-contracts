// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @notice Collection-configured execution boundary for mutable, bounded collection policy.
contract CollectionTimelock is TimelockController {
    error TimelockConfigurationImmutable();
    error InvalidProposer();

    constructor(address proposer, uint48 delay)
        TimelockController(delay, _single(proposer), _openExecutors(), address(0))
    {
        if (proposer == address(0)) revert InvalidProposer();
    }

    function grantRole(bytes32, address) public pure override {
        revert TimelockConfigurationImmutable();
    }

    function revokeRole(bytes32, address) public pure override {
        revert TimelockConfigurationImmutable();
    }

    function renounceRole(bytes32, address) public pure override {
        revert TimelockConfigurationImmutable();
    }

    function updateDelay(uint256) public pure override {
        revert TimelockConfigurationImmutable();
    }

    function _single(address account) private pure returns (address[] memory accounts) {
        accounts = new address[](1);
        accounts[0] = account;
    }

    function _openExecutors() private pure returns (address[] memory accounts) {
        accounts = new address[](1);
        accounts[0] = address(0);
    }
}
