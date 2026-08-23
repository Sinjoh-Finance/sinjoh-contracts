// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Governor } from "@openzeppelin/contracts/governance/Governor.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import {
    GovernorCountingSimple
} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {
    GovernorTimelockControl
} from "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";
import { GovernorVotes } from "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import { IVotes } from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import { IERC5805 } from "@openzeppelin/contracts/interfaces/IERC5805.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IProjectControlled } from "../interfaces/IProjectControlled.sol";
import { IProjectReferenceSupply } from "../interfaces/IProjectReferenceSupply.sol";
import { IProjectStakedVoteSource } from "../interfaces/IProjectStakedVoteSource.sol";
import { IProjectTokenIdentity } from "../interfaces/IProjectTokenIdentity.sol";
import { ProjectIds } from "../libraries/ProjectIds.sol";
import { TokenGovernanceConfig } from "./TokenGovernanceConfig.sol";

/// @notice Immutable token-holder Governor using a direct liquid-token or staking-pool vote source.
contract ProjectGovernorV2 is
    Governor,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorTimelockControl,
    IProjectControlled
{
    uint48 public constant MIN_VOTING_DELAY = 1 hours;
    uint48 public constant MAX_VOTING_DELAY = 7 days;
    uint32 public constant MIN_VOTING_PERIOD = 1 days;
    uint32 public constant MAX_VOTING_PERIOD = 14 days;
    uint16 public constant MIN_PROPOSAL_THRESHOLD_BPS = 10;
    uint16 public constant MAX_PROPOSAL_THRESHOLD_BPS = 1_000;
    uint16 public constant MIN_QUORUM_BPS = 100;
    uint16 public constant MAX_QUORUM_BPS = 3_000;
    uint256 private constant BPS_DENOMINATOR = 10_000;
    bytes32 private constant TIMESTAMP_CLOCK_MODE_HASH = keccak256("mode=timestamp");

    address public immutable registry;
    address public immutable subject;
    bytes32 public immutable override projectId;
    address public immutable override controller;
    address public immutable voteSource;
    bool public immutable stakedVoteSource;
    uint256 public immutable referenceSupply;
    uint48 public immutable votingDelaySeconds;
    uint32 public immutable votingPeriodSeconds;
    uint16 public immutable proposalThresholdBps;
    uint16 public immutable quorumBps;
    uint256 public immutable proposalThresholdAmount;

    error InvalidRegistry(address candidate);
    error InvalidSubject(address candidate);
    error InvalidVoteSource(address candidate);
    error InvalidTimelock(address candidate, address deployer);
    error ProjectIdentityMismatch(bytes32 expected, bytes32 actual);
    error StakedVoteSourceSubjectMismatch(address expected, address actual);
    error UnsupportedClockMode(string supplied);
    error InvalidVotingDelay(uint48 supplied);
    error InvalidVotingPeriod(uint32 supplied);
    error InvalidProposalThresholdBps(uint16 supplied);
    error InvalidQuorumBps(uint16 supplied);
    error InvalidReferenceSupply(uint256 supplied);
    error ReferenceSupplyMismatch(uint256 expected, uint256 supplied);
    error TimelockImmutable();

    constructor(
        address registry_,
        address subject_,
        address voteSource_,
        address timelock_,
        TokenGovernanceConfig memory config
    )
        Governor("Sinjoh Project Governor")
        GovernorVotes(IVotes(voteSource_))
        GovernorTimelockControl(TimelockController(payable(timelock_)))
    {
        if (registry_.code.length == 0) revert InvalidRegistry(registry_);
        if (subject_.code.length == 0) revert InvalidSubject(subject_);
        if (voteSource_.code.length == 0) revert InvalidVoteSource(voteSource_);
        if (timelock_ == address(0) || msg.sender != timelock_) {
            revert InvalidTimelock(timelock_, msg.sender);
        }

        bytes32 expectedProjectId = ProjectIds.derive(block.chainid, registry_, subject_);
        bytes32 subjectProjectId = IProjectTokenIdentity(subject_).projectId();
        if (
            IProjectTokenIdentity(subject_).registry() != registry_
                || subjectProjectId != expectedProjectId
        ) {
            revert ProjectIdentityMismatch(expectedProjectId, subjectProjectId);
        }

        bytes32 voteProjectId = IProjectTokenIdentity(voteSource_).projectId();
        if (
            IProjectTokenIdentity(voteSource_).registry() != registry_
                || voteProjectId != expectedProjectId
        ) {
            revert ProjectIdentityMismatch(expectedProjectId, voteProjectId);
        }

        bool isStaked = voteSource_ != subject_;
        if (isStaked) {
            address voteSubject = address(IProjectStakedVoteSource(voteSource_).subject());
            if (voteSubject != subject_) {
                revert StakedVoteSourceSubjectMismatch(subject_, voteSubject);
            }
        }

        string memory clockMode;
        try IERC5805(voteSource_).CLOCK_MODE() returns (string memory suppliedMode) {
            clockMode = suppliedMode;
        } catch {
            revert InvalidVoteSource(voteSource_);
        }
        if (keccak256(bytes(clockMode)) != TIMESTAMP_CLOCK_MODE_HASH) {
            revert UnsupportedClockMode(clockMode);
        }

        _validateConfig(config);
        uint256 subjectReferenceSupply = IProjectReferenceSupply(subject_).initialSupply();
        if (config.referenceSupply != subjectReferenceSupply) {
            revert ReferenceSupplyMismatch(subjectReferenceSupply, config.referenceSupply);
        }
        uint256 thresholdAmount = Math.mulDiv(
            config.referenceSupply, config.proposalThresholdBps, BPS_DENOMINATOR, Math.Rounding.Ceil
        );

        registry = registry_;
        subject = subject_;
        projectId = expectedProjectId;
        controller = timelock_;
        voteSource = voteSource_;
        stakedVoteSource = isStaked;
        referenceSupply = config.referenceSupply;
        votingDelaySeconds = config.votingDelay;
        votingPeriodSeconds = config.votingPeriod;
        proposalThresholdBps = config.proposalThresholdBps;
        quorumBps = config.quorumBps;
        proposalThresholdAmount = thresholdAmount;
    }

    function votingDelay() public view override returns (uint256) {
        return votingDelaySeconds;
    }

    function votingPeriod() public view override returns (uint256) {
        return votingPeriodSeconds;
    }

    function proposalThreshold() public view override returns (uint256) {
        return proposalThresholdAmount;
    }

    function quorum(uint256 timepoint) public view override returns (uint256) {
        return Math.mulDiv(token().getPastTotalSupply(timepoint), quorumBps, BPS_DENOMINATOR);
    }

    /// @dev The first-release Timelock address is immutable.
    function updateTimelock(TimelockController) public pure override {
        revert TimelockImmutable();
    }

    function state(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (ProposalState)
    {
        return super.state(proposalId);
    }

    function proposalNeedsQueuing(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (bool)
    {
        return super.proposalNeedsQueuing(proposalId);
    }

    function _queueOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint48) {
        return super._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) {
        super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    function _executor()
        internal
        view
        override(Governor, GovernorTimelockControl)
        returns (address)
    {
        return super._executor();
    }

    function _validateConfig(TokenGovernanceConfig memory config) private pure {
        if (config.votingDelay < MIN_VOTING_DELAY || config.votingDelay > MAX_VOTING_DELAY) {
            revert InvalidVotingDelay(config.votingDelay);
        }
        if (config.votingPeriod < MIN_VOTING_PERIOD || config.votingPeriod > MAX_VOTING_PERIOD) {
            revert InvalidVotingPeriod(config.votingPeriod);
        }
        if (
            config.proposalThresholdBps < MIN_PROPOSAL_THRESHOLD_BPS
                || config.proposalThresholdBps > MAX_PROPOSAL_THRESHOLD_BPS
        ) {
            revert InvalidProposalThresholdBps(config.proposalThresholdBps);
        }
        if (config.quorumBps < MIN_QUORUM_BPS || config.quorumBps > MAX_QUORUM_BPS) {
            revert InvalidQuorumBps(config.quorumBps);
        }
        if (config.referenceSupply == 0) revert InvalidReferenceSupply(0);
    }
}
