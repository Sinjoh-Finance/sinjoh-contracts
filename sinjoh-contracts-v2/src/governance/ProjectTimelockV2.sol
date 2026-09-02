// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { IProjectControlled } from "../interfaces/IProjectControlled.sol";
import { IProjectTokenIdentity } from "../interfaces/IProjectTokenIdentity.sol";
import { ProjectIds } from "../libraries/ProjectIds.sol";
import { ProjectGovernorV2 } from "./ProjectGovernorV2.sol";
import { TokenGovernanceConfig } from "./TokenGovernanceConfig.sol";

/// @notice Immutable execution controller for one project's Token Governance protocol.
/// @dev The constructor deploys and binds the Governor atomically, then freezes all Timelock roles.
contract ProjectTimelockV2 is TimelockController, IProjectControlled {
    uint48 public constant MIN_TIMELOCK_DELAY = 6 hours;
    uint48 public constant MAX_TIMELOCK_DELAY = 7 days;

    address public immutable registry;
    address public immutable subject;
    bytes32 public immutable override projectId;
    address public immutable override controller;
    address public immutable voteSource;
    bool public immutable stakedVoteSource;
    ProjectGovernorV2 public immutable governor;

    error InvalidRegistry(address candidate);
    error InvalidSubject(address candidate);
    error ProjectIdentityMismatch(bytes32 expected, bytes32 actual);
    error InvalidTimelockDelay(uint48 supplied);
    error TimelockConfigurationImmutable();

    event TokenGovernanceCreated(
        bytes32 indexed projectId,
        address indexed governor,
        address indexed timelock,
        address voteSource
    );

    constructor(
        address registry_,
        address subject_,
        address voteSource_,
        bool stakedVoteSource_,
        TokenGovernanceConfig memory config
    ) TimelockController(config.timelockDelay, new address[](0), _openExecutors(), address(0)) {
        if (registry_.code.length == 0) revert InvalidRegistry(registry_);
        if (subject_.code.length == 0) revert InvalidSubject(subject_);
        if (config.timelockDelay < MIN_TIMELOCK_DELAY || config.timelockDelay > MAX_TIMELOCK_DELAY)
        {
            revert InvalidTimelockDelay(config.timelockDelay);
        }

        bytes32 actualProjectId = ProjectIds.derive(block.chainid, registry_, subject_);
        (bool declaresIdentity, address subjectRegistry, bytes32 subjectProjectId) =
            ProjectIds.declaredIdentity(subject_);
        if (
            declaresIdentity
                && (subjectRegistry != registry_ || subjectProjectId != actualProjectId)
        ) revert ProjectIdentityMismatch(actualProjectId, subjectProjectId);

        registry = registry_;
        subject = subject_;
        projectId = actualProjectId;
        controller = address(this);
        voteSource = voteSource_;
        stakedVoteSource = stakedVoteSource_;

        ProjectGovernorV2 deployedGovernor = new ProjectGovernorV2(
            registry_, subject_, voteSource_, stakedVoteSource_, address(this), config
        );
        governor = deployedGovernor;
        _grantRole(PROPOSER_ROLE, address(deployedGovernor));
        _grantRole(CANCELLER_ROLE, address(deployedGovernor));

        emit TokenGovernanceCreated(
            actualProjectId, address(deployedGovernor), address(this), voteSource_
        );
    }

    /// @dev Role membership is fixed at deployment: Governor proposes/cancels and execution is open.
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

    function _openExecutors() private pure returns (address[] memory executors) {
        executors = new address[](1);
        executors[0] = address(0);
    }
}
