// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IGovernor } from "@openzeppelin/contracts/governance/IGovernor.sol";
import { Vm } from "forge-std/Vm.sol";
import { ProjectGovernorV2 } from "../../src/governance/ProjectGovernorV2.sol";
import { ProjectTimelockV2 } from "../../src/governance/ProjectTimelockV2.sol";
import { ProjectVotesToken } from "../../src/token/ProjectVotesToken.sol";
import { MockControlledModule } from "../mocks/MockControlledModule.sol";
import { GovernanceTestBase } from "../GovernanceTestBase.sol";

contract ProjectTokenGovernanceV2Handler {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant CAROL = address(0xCA901);
    address private constant OUTSIDER = address(0xBAD);
    uint256 private constant PROPOSAL_VALUE = 777;
    string private constant DESCRIPTION = "Invariant controlled operation";

    ProjectGovernorV2 public immutable governor;
    ProjectTimelockV2 public immutable timelock;
    MockControlledModule public immutable module;

    uint256 public proposalId;
    uint256 public queuedEta;
    uint256 public executedAt;
    uint256 public unauthorizedModuleCalls;
    uint256 public unauthorizedSchedules;
    uint256 public roleMutationSuccesses;
    uint256 public earlyExecutionSuccesses;

    constructor(
        ProjectGovernorV2 governor_,
        ProjectTimelockV2 timelock_,
        MockControlledModule module_
    ) {
        governor = governor_;
        timelock = timelock_;
        module = module_;
    }

    function propose() external {
        if (proposalId != 0) return;
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) =
            _proposalData();
        vm.prank(ALICE);
        try governor.propose(targets, values, calldatas, DESCRIPTION) returns (uint256 created) {
            proposalId = created;
        } catch { }
    }

    function advanceToActive() external {
        if (proposalId == 0) return;
        try governor.state(proposalId) returns (IGovernor.ProposalState current) {
            if (current == IGovernor.ProposalState.Pending) {
                vm.warp(governor.proposalSnapshot(proposalId) + 1);
            }
        } catch { }
    }

    function castVote(uint256 rawVoter, uint8 rawSupport) external {
        if (proposalId == 0) return;
        IGovernor.ProposalState current;
        try governor.state(proposalId) returns (IGovernor.ProposalState supplied) {
            current = supplied;
        } catch {
            return;
        }
        if (current != IGovernor.ProposalState.Active) return;
        address voter = _voter(rawVoter);
        if (governor.hasVoted(proposalId, voter)) return;
        uint8 support = rawSupport % 3;
        vm.prank(voter);
        try governor.castVote(proposalId, support) { } catch { }
    }

    function advancePastVoting() external {
        if (proposalId == 0) return;
        try governor.state(proposalId) returns (IGovernor.ProposalState current) {
            if (current == IGovernor.ProposalState.Active) {
                vm.warp(governor.proposalDeadline(proposalId) + 1);
            }
        } catch { }
    }

    function queue() external {
        if (proposalId == 0 || queuedEta != 0) return;
        try governor.state(proposalId) returns (IGovernor.ProposalState current) {
            if (current != IGovernor.ProposalState.Succeeded) return;
        } catch {
            return;
        }
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) =
            _proposalData();
        try governor.queue(targets, values, calldatas, keccak256(bytes(DESCRIPTION))) {
            queuedEta = governor.proposalEta(proposalId);
        } catch { }
    }

    function advanceToReady() external {
        if (queuedEta == 0 || executedAt != 0) return;
        if (vm.getBlockTimestamp() < queuedEta) vm.warp(queuedEta);
    }

    function execute() external {
        uint256 currentTime = vm.getBlockTimestamp();
        if (queuedEta == 0 || executedAt != 0 || currentTime < queuedEta) return;
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) =
            _proposalData();
        vm.prank(OUTSIDER);
        try governor.execute(targets, values, calldatas, keccak256(bytes(DESCRIPTION))) {
            executedAt = currentTime;
        } catch { }
    }

    function attemptEarlyExecution() external {
        if (queuedEta == 0 || executedAt != 0 || vm.getBlockTimestamp() >= queuedEta) return;
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) =
            _proposalData();
        vm.prank(OUTSIDER);
        try governor.execute(targets, values, calldatas, keccak256(bytes(DESCRIPTION))) {
            earlyExecutionSuccesses += 1;
        } catch { }
    }

    function attemptControllerBypass(uint256 rawCaller) external {
        address caller = _unauthorizedCaller(rawCaller);
        vm.prank(caller);
        (bool success,) = address(module).call(abi.encodeCall(module.setValue, (999)));
        if (success) unauthorizedModuleCalls += 1;
    }

    function attemptUnauthorizedSchedule() external {
        vm.prank(ALICE);
        (bool success,) = address(timelock)
            .call(
                abi.encodeCall(
                    timelock.schedule,
                    (
                        address(module),
                        0,
                        abi.encodeCall(module.setValue, (999)),
                        bytes32(0),
                        bytes32(0),
                        1 days
                    )
                )
            );
        if (success) unauthorizedSchedules += 1;
    }

    function attemptRoleMutation(uint256 rawAccount) external {
        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        address candidate = _unauthorizedCaller(rawAccount);
        vm.prank(candidate);
        (bool success,) =
            address(timelock).call(abi.encodeCall(timelock.grantRole, (proposerRole, candidate)));
        if (success) roleMutationSuccesses += 1;
    }

    function advanceTime(uint32 rawSeconds) external {
        uint256 elapsed = uint256(rawSeconds % uint32(8 days));
        vm.warp(block.timestamp + elapsed);
    }

    function _proposalData()
        private
        view
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas)
    {
        targets = new address[](1);
        values = new uint256[](1);
        calldatas = new bytes[](1);
        targets[0] = address(module);
        calldatas[0] = abi.encodeCall(module.setValue, (PROPOSAL_VALUE));
    }

    function _voter(uint256 rawVoter) private pure returns (address) {
        uint256 selected = rawVoter % 3;
        if (selected == 0) return ALICE;
        if (selected == 1) return BOB;
        return CAROL;
    }

    function _unauthorizedCaller(uint256 rawCaller) private view returns (address) {
        uint256 selected = rawCaller % 4;
        if (selected == 0) return ALICE;
        if (selected == 1) return BOB;
        if (selected == 2) return OUTSIDER;
        return address(governor);
    }
}

contract ProjectTokenGovernanceV2InvariantTest is GovernanceTestBase {
    ProjectTokenGovernanceV2Handler private handler;

    function setUp() public {
        _setUpLiquidGovernance();
        handler = new ProjectTokenGovernanceV2Handler(governor, timelock, module);
        targetContract(address(handler));
    }

    function invariantProjectControllerAndVoteSourceNeverChange() public view {
        assertEq(timelock.registry(), address(registry));
        assertEq(timelock.subject(), address(token));
        assertEq(timelock.projectId(), token.projectId());
        assertEq(timelock.controller(), address(timelock));
        assertEq(timelock.voteSource(), address(token));
        assertEq(address(timelock.governor()), address(governor));
        assertEq(governor.controller(), address(timelock));
        assertEq(governor.timelock(), address(timelock));
        assertEq(governor.voteSource(), address(token));
        assertEq(module.controller(), address(timelock));
    }

    function invariantTimelockRolesRemainAtAtomicLaunchConfiguration() public view {
        assertTrue(timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), address(timelock)));
        assertFalse(timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), ALICE));
        assertTrue(timelock.hasRole(timelock.PROPOSER_ROLE(), address(governor)));
        assertTrue(timelock.hasRole(timelock.CANCELLER_ROLE(), address(governor)));
        assertFalse(timelock.hasRole(timelock.PROPOSER_ROLE(), ALICE));
        assertTrue(timelock.hasRole(timelock.EXECUTOR_ROLE(), address(0)));
    }

    function invariantGovernanceParametersRemainImmutable() public view {
        assertEq(timelock.getMinDelay(), 1 days);
        assertEq(governor.votingDelay(), 1 days);
        assertEq(governor.votingPeriod(), 3 days);
        assertEq(governor.proposalThreshold(), 10e18);
        assertEq(governor.referenceSupply(), REFERENCE_SUPPLY);
        assertEq(governor.quorumBps(), 1_000);
    }

    function invariantUnauthorizedPathsNeverOperateControlledModule() public view {
        assertEq(handler.unauthorizedModuleCalls(), 0);
        assertEq(handler.unauthorizedSchedules(), 0);
        assertEq(handler.roleMutationSuccesses(), 0);
        assertEq(handler.earlyExecutionSuccesses(), 0);
    }

    function invariantControlledCallOnlyOccursThroughMaturedExecutedProposal() public view {
        uint256 executedAt = handler.executedAt();
        uint256 eta = handler.queuedEta();
        if (module.calls() == 0) {
            assertEq(executedAt, 0);
        } else {
            assertEq(module.calls(), 1);
            assertEq(module.value(), 777);
            assertGt(executedAt, 0);
            assertGe(executedAt, eta);
            assertEq(
                uint8(governor.state(handler.proposalId())), uint8(IGovernor.ProposalState.Executed)
            );
        }
    }

    function invariantBurnAddressNeverContributesVotingPower() public view {
        assertEq(token.getVotes(token.BURN_ADDRESS()), 0);
    }
}
