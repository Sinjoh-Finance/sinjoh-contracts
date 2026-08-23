// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { IGovernor } from "@openzeppelin/contracts/governance/IGovernor.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { ProjectGovernorV2 } from "../../src/governance/ProjectGovernorV2.sol";
import { ProjectTimelockV2 } from "../../src/governance/ProjectTimelockV2.sol";
import { TokenGovernanceConfig } from "../../src/governance/TokenGovernanceConfig.sol";
import { ProjectPoSNFT } from "../../src/staking/ProjectPoSNFT.sol";
import { ProjectStakingPoolV2 } from "../../src/staking/ProjectStakingPoolV2.sol";
import { ProjectVotesToken } from "../../src/token/ProjectVotesToken.sol";
import { MockBatchTarget, MockControlledModule } from "../mocks/MockControlledModule.sol";
import { MockRegistry } from "../mocks/MockRegistry.sol";
import { MockVoteSource } from "../mocks/MockVoteSource.sol";
import { GovernanceTestBase } from "../GovernanceTestBase.sol";

contract ProjectLiquidTokenGovernanceV2Test is GovernanceTestBase {
    string private constant DESCRIPTION = "Set the project module value";

    function setUp() public {
        _setUpLiquidGovernance();
    }

    function testDeploymentPublishesImmutableProjectAndConfiguration() public view {
        assertEq(timelock.registry(), address(registry));
        assertEq(timelock.subject(), address(token));
        assertEq(timelock.projectId(), token.projectId());
        assertEq(timelock.controller(), address(timelock));
        assertEq(timelock.voteSource(), address(token));
        assertEq(address(timelock.governor()), address(governor));

        assertEq(governor.registry(), address(registry));
        assertEq(governor.subject(), address(token));
        assertEq(governor.projectId(), token.projectId());
        assertEq(governor.controller(), address(timelock));
        assertEq(governor.timelock(), address(timelock));
        assertEq(governor.voteSource(), address(token));
        assertFalse(governor.stakedVoteSource());
        assertEq(governor.referenceSupply(), REFERENCE_SUPPLY);
        assertEq(governor.proposalThreshold(), 10e18);
        assertEq(governor.votingDelay(), 1 days);
        assertEq(governor.votingPeriod(), 3 days);
        assertEq(governor.CLOCK_MODE(), "mode=timestamp");
        assertEq(governor.COUNTING_MODE(), "support=bravo&quorum=for,abstain");
    }

    function testTimelockRolesAreFinalAndExecutionIsPermissionless() public view {
        assertTrue(timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), address(timelock)));
        assertFalse(timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), address(this)));
        assertFalse(timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), ALICE));
        assertTrue(timelock.hasRole(timelock.PROPOSER_ROLE(), address(governor)));
        assertTrue(timelock.hasRole(timelock.CANCELLER_ROLE(), address(governor)));
        assertFalse(timelock.hasRole(timelock.PROPOSER_ROLE(), ALICE));
        assertFalse(timelock.hasRole(timelock.CANCELLER_ROLE(), ALICE));
        assertTrue(timelock.hasRole(timelock.EXECUTOR_ROLE(), address(0)));
        assertFalse(timelock.hasRole(timelock.EXECUTOR_ROLE(), ALICE));
        assertEq(timelock.getMinDelay(), 1 days);
    }

    function testTimelockRoleDelayAndGovernorBindingCannotChange() public {
        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        vm.expectRevert(ProjectTimelockV2.TimelockConfigurationImmutable.selector);
        timelock.grantRole(proposerRole, ALICE);
        vm.expectRevert(ProjectTimelockV2.TimelockConfigurationImmutable.selector);
        timelock.revokeRole(proposerRole, address(governor));
        vm.expectRevert(ProjectTimelockV2.TimelockConfigurationImmutable.selector);
        timelock.renounceRole(executorRole, address(0));
        vm.expectRevert(ProjectTimelockV2.TimelockConfigurationImmutable.selector);
        timelock.updateDelay(2 days);
        vm.expectRevert(ProjectGovernorV2.TimelockImmutable.selector);
        governor.updateTimelock(TimelockController(payable(address(timelock))));
    }

    function testConfigurationBoundsRejectEveryOutOfRangeField() public {
        TokenGovernanceConfig memory config = _defaultConfig();
        config.votingDelay = 1 hours - 1;
        vm.expectPartialRevert(ProjectGovernorV2.InvalidVotingDelay.selector);
        _newTimelock(address(token), config);

        config = _defaultConfig();
        config.votingPeriod = 14 days + 1;
        vm.expectPartialRevert(ProjectGovernorV2.InvalidVotingPeriod.selector);
        _newTimelock(address(token), config);

        config = _defaultConfig();
        config.proposalThresholdBps = 9;
        vm.expectPartialRevert(ProjectGovernorV2.InvalidProposalThresholdBps.selector);
        _newTimelock(address(token), config);

        config = _defaultConfig();
        config.quorumBps = 3_001;
        vm.expectPartialRevert(ProjectGovernorV2.InvalidQuorumBps.selector);
        _newTimelock(address(token), config);

        config = _defaultConfig();
        config.timelockDelay = 6 hours - 1;
        vm.expectPartialRevert(ProjectTimelockV2.InvalidTimelockDelay.selector);
        _newTimelock(address(token), config);
    }

    function testReferenceSupplyMustEqualSubjectFixedLaunchSupply() public {
        TokenGovernanceConfig memory config = _defaultConfig();
        config.referenceSupply -= 1;
        vm.expectPartialRevert(ProjectGovernorV2.ReferenceSupplyMismatch.selector);
        _newTimelock(address(token), config);
    }

    function testSmallSupplyThresholdRoundsUpInsteadOfMakingGovernanceUndeployable() public {
        MockRegistry smallRegistry = new MockRegistry();
        ProjectVotesToken.TokenAllocation[] memory allocations =
            new ProjectVotesToken.TokenAllocation[](1);
        allocations[0] = ProjectVotesToken.TokenAllocation({ recipient: ALICE, amount: 99 });
        ProjectVotesToken smallToken = new ProjectVotesToken(
            "Small Project", "SMALL", address(smallRegistry), ALICE, allocations, new address[](0)
        );
        TokenGovernanceConfig memory config = _defaultConfig();
        config.referenceSupply = 99;
        ProjectTimelockV2 smallTimelock = new ProjectTimelockV2(
            address(smallRegistry), address(smallToken), address(smallToken), config
        );
        assertEq(smallTimelock.governor().proposalThreshold(), 1);
    }

    function testGovernorCanOnlyBeCreatedByItsBoundTimelock() public {
        vm.expectPartialRevert(ProjectGovernorV2.InvalidTimelock.selector);
        new ProjectGovernorV2(
            address(registry), address(token), address(token), address(timelock), _defaultConfig()
        );
    }

    function testSubjectMustBelongToSuppliedRegistry() public {
        MockRegistry otherRegistry = new MockRegistry();
        vm.expectPartialRevert(ProjectTimelockV2.ProjectIdentityMismatch.selector);
        new ProjectTimelockV2(
            address(otherRegistry), address(token), address(token), _defaultConfig()
        );
    }

    function testVoteSourceMustShareExactProjectIdentity() public {
        address otherToken = address(_deployToken(registry));
        vm.expectPartialRevert(ProjectGovernorV2.ProjectIdentityMismatch.selector);
        _newTimelock(otherToken, _defaultConfig());
    }

    function testVoteSourceMustUseTimestampClock() public {
        MockVoteSource badClock = new MockVoteSource(
            address(registry), token.projectId(), address(token), "mode=blocknumber"
        );
        vm.expectPartialRevert(ProjectGovernorV2.UnsupportedClockMode.selector);
        _newTimelock(address(badClock), _defaultConfig());
    }

    function testStakedVoteSourceMustPointToExactSubject() public {
        address otherToken = address(_deployToken(registry));
        MockVoteSource wrongSubject = new MockVoteSource(
            address(registry), token.projectId(), otherToken, "mode=timestamp"
        );
        vm.expectPartialRevert(ProjectGovernorV2.StakedVoteSourceSubjectMismatch.selector);
        _newTimelock(address(wrongSubject), _defaultConfig());
    }

    function testHolderProposesAndVotesWithoutDelegation() public {
        uint256 proposalId = _propose(ALICE, 42, DESCRIPTION);
        _activate(proposalId);
        vm.prank(ALICE);
        uint256 weight = governor.castVote(proposalId, 1);
        assertEq(weight, 600e18);
        assertTrue(governor.hasVoted(proposalId, ALICE));
    }

    function testAccountBelowAbsoluteThresholdCannotPropose() public {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) =
            _proposalData(42);
        vm.prank(OUTSIDER);
        vm.expectPartialRevert(IGovernor.GovernorInsufficientProposerVotes.selector);
        governor.propose(targets, values, calldatas, DESCRIPTION);
    }

    function testExactProposalVoteQueueAndPermissionlessExecuteTiming() public {
        uint256 proposalId = _propose(ALICE, 42, DESCRIPTION);
        uint256 snapshot = governor.proposalSnapshot(proposalId);
        uint256 deadline = governor.proposalDeadline(proposalId);
        assertEq(snapshot, block.timestamp + 1 days);
        assertEq(deadline, snapshot + 3 days);
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Pending));

        vm.warp(snapshot);
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Pending));
        vm.warp(snapshot + 1);
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Active));
        assertEq(governor.quorum(snapshot), 100e18);
        vm.prank(ALICE);
        governor.castVote(proposalId, 1);

        vm.warp(deadline);
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Active));
        vm.warp(deadline + 1);
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Succeeded));
        _queue(42, DESCRIPTION);
        uint256 eta = governor.proposalEta(proposalId);
        assertEq(eta, deadline + 1 + 1 days);
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Queued));

        vm.warp(eta - 1);
        vm.expectPartialRevert(TimelockController.TimelockUnexpectedOperationState.selector);
        _execute(42, DESCRIPTION);
        vm.warp(eta);
        vm.prank(OUTSIDER);
        _execute(42, DESCRIPTION);
        assertEq(module.value(), 42);
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Executed));
    }

    function testForPlusAbstainReachQuorumWhileOnlyForDeterminesSuccess() public {
        uint256 proposalId = _propose(ALICE, 55, DESCRIPTION);
        _activate(proposalId);
        vm.prank(CAROL);
        governor.castVote(proposalId, 1);
        vm.prank(BOB);
        governor.castVote(proposalId, 2);
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) =
            governor.proposalVotes(proposalId);
        assertEq(againstVotes, 0);
        assertEq(forVotes, 100e18);
        assertEq(abstainVotes, 300e18);
        _finishVoting(proposalId);
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Succeeded));
    }

    function testTieIsDefeatedEvenWhenQuorumIsReached() public {
        vm.prank(ALICE);
        assertTrue(token.transfer(OUTSIDER, 300e18));
        vm.warp(block.timestamp + 1);
        uint256 proposalId = _propose(ALICE, 55, DESCRIPTION);
        _activate(proposalId);
        vm.prank(ALICE);
        governor.castVote(proposalId, 1);
        vm.prank(BOB);
        governor.castVote(proposalId, 0);
        _finishVoting(proposalId);
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Defeated));
    }

    function testVoteCanOnlyBeCastOnceAndMustUseSupportedChoice() public {
        uint256 proposalId = _propose(ALICE, 55, DESCRIPTION);
        _activate(proposalId);
        vm.prank(ALICE);
        governor.castVote(proposalId, 1);
        vm.prank(ALICE);
        vm.expectPartialRevert(IGovernor.GovernorAlreadyCastVote.selector);
        governor.castVote(proposalId, 1);
        vm.prank(BOB);
        vm.expectRevert(IGovernor.GovernorInvalidVoteType.selector);
        governor.castVote(proposalId, 3);
    }

    function testPostSnapshotTransferChangesOnlyFutureVotingPower() public {
        uint256 proposalId = _propose(ALICE, 55, DESCRIPTION);
        _activate(proposalId);
        vm.prank(ALICE);
        assertTrue(token.transfer(OUTSIDER, 600e18));
        vm.prank(ALICE);
        assertEq(governor.castVote(proposalId, 1), 600e18);
        vm.prank(OUTSIDER);
        assertEq(governor.castVote(proposalId, 1), 0);
        assertEq(token.getVotes(ALICE), 0);
        assertEq(token.getVotes(OUTSIDER), 600e18);
    }

    function testQueuedBatchFailureRollsBackAndRemainsRetryable() public {
        MockBatchTarget reverter = new MockBatchTarget();
        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory calldatas = new bytes[](2);
        targets[0] = address(module);
        targets[1] = address(reverter);
        calldatas[0] = abi.encodeCall(module.setValue, (77));
        calldatas[1] = abi.encodeCall(reverter.run, ());
        string memory description = "Atomic retry";
        bytes32 descriptionHash = keccak256(bytes(description));

        vm.prank(ALICE);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);
        _activate(proposalId);
        vm.prank(ALICE);
        governor.castVote(proposalId, 1);
        _finishVoting(proposalId);
        governor.queue(targets, values, calldatas, descriptionHash);
        vm.warp(governor.proposalEta(proposalId));

        vm.expectRevert(MockBatchTarget.ForcedFailure.selector);
        governor.execute(targets, values, calldatas, descriptionHash);
        assertEq(module.value(), 0);
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Queued));

        reverter.setShouldRevert(false);
        vm.prank(OUTSIDER);
        governor.execute(targets, values, calldatas, descriptionHash);
        assertEq(module.value(), 77);
        assertEq(reverter.calls(), 1);
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Executed));
    }

    function testOnlyProposerCanCancelWhileProposalIsPending() public {
        uint256 proposalId = _propose(ALICE, 55, DESCRIPTION);
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) =
            _proposalData(55);
        bytes32 descriptionHash = keccak256(bytes(DESCRIPTION));
        vm.prank(BOB);
        vm.expectPartialRevert(IGovernor.GovernorUnableToCancel.selector);
        governor.cancel(targets, values, calldatas, descriptionHash);
        vm.prank(ALICE);
        governor.cancel(targets, values, calldatas, descriptionHash);
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Canceled));
    }

    function testGovernorHolderAndCreatorCannotBypassTimelockController() public {
        vm.prank(ALICE);
        vm.expectPartialRevert(MockControlledModule.OnlyController.selector);
        module.setValue(1);
        vm.prank(address(governor));
        vm.expectPartialRevert(MockControlledModule.OnlyController.selector);
        module.setValue(2);
        vm.prank(OUTSIDER);
        vm.expectPartialRevert(MockControlledModule.OnlyController.selector);
        module.setValue(3);
    }

    function testTimelockCanForwardNativeValueThroughApprovedProposal() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(module);
        values[0] = 1 ether;
        calldatas[0] = abi.encodeCall(module.setValuePayable, (91));
        string memory description = "Fund controlled module";
        bytes32 descriptionHash = keccak256(bytes(description));
        vm.deal(address(timelock), 1 ether);

        vm.prank(ALICE);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);
        _activate(proposalId);
        vm.prank(ALICE);
        governor.castVote(proposalId, 1);
        _finishVoting(proposalId);
        governor.queue(targets, values, calldatas, descriptionHash);
        vm.warp(governor.proposalEta(proposalId));
        vm.prank(OUTSIDER);
        governor.execute(targets, values, calldatas, descriptionHash);
        assertEq(module.value(), 91);
        assertEq(module.nativeReceived(), 1 ether);
        assertEq(address(timelock).balance, 0);
    }

    function testBurnAddressHasNoVotesAndLowersOnlyFutureQuorum() public {
        uint256 priorTimepoint = block.timestamp - 1;
        address burnAddress = token.BURN_ADDRESS();
        assertEq(governor.quorum(priorTimepoint), 100e18);
        vm.prank(BOB);
        assertTrue(token.transfer(burnAddress, 200e18));
        assertEq(token.getVotes(burnAddress), 0);
        vm.warp(START + 2);
        assertEq(token.getPastVotes(burnAddress, START + 1), 0);
        assertEq(governor.quorum(START + 1), 80e18);
        assertEq(governor.quorum(priorTimepoint), 100e18);
    }

    function testNonGovernorCannotScheduleTimelockOperation() public {
        vm.prank(ALICE);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        timelock.schedule(address(module), 0, abi.encodeCall(module.setValue, (1)), 0, 0, 1 days);
    }

    function _newTimelock(address voteSource, TokenGovernanceConfig memory config)
        private
        returns (ProjectTimelockV2)
    {
        return new ProjectTimelockV2(address(registry), address(token), voteSource, config);
    }
}

contract ProjectStakedTokenGovernanceV2Test is GovernanceTestBase {
    string private constant DESCRIPTION = "Set with staked votes";

    function setUp() public {
        _setUpStakedGovernance(true);
    }

    function testDeploymentUsesDirectStakingPoolVoteSource() public view {
        assertEq(timelock.voteSource(), address(stakingPool));
        assertEq(governor.voteSource(), address(stakingPool));
        assertEq(address(governor.token()), address(stakingPool));
        assertTrue(governor.stakedVoteSource());
        assertEq(governor.subject(), address(token));
        assertEq(governor.projectId(), token.projectId());
    }

    function testGovernanceCanDeployBeforeAnyTokensAreStaked() public {
        ProjectStakingPoolV2 emptyPool = new ProjectStakingPoolV2(
            address(registry),
            address(token),
            TREASURY,
            STAKING_CONTROLLER,
            address(0),
            LOCK_DURATION
        );
        ProjectTimelockV2 emptyGovernance = new ProjectTimelockV2(
            address(registry), address(token), address(emptyPool), _defaultConfig()
        );
        assertEq(emptyGovernance.voteSource(), address(emptyPool));
        assertEq(emptyGovernance.governor().proposalThreshold(), 10e18);
        assertEq(emptyPool.totalActiveStake(), 0);
    }

    function testStakerCompletesFullProposalLifecycleWithoutDelegation() public {
        uint256 proposalId = _propose(ALICE, 404, DESCRIPTION);
        _activate(proposalId);
        vm.prank(ALICE);
        assertEq(governor.castVote(proposalId, 1), 600e18);
        _finishVoting(proposalId);
        _queue(404, DESCRIPTION);
        vm.warp(governor.proposalEta(proposalId));
        vm.prank(OUTSIDER);
        _execute(404, DESCRIPTION);
        assertEq(module.value(), 404);
    }

    function testPositionTransferAfterSnapshotChangesOnlyFutureVotes() public {
        uint256 proposalId = _propose(ALICE, 10, DESCRIPTION);
        _activate(proposalId);
        vm.prank(ALICE);
        posNFT.transferFrom(ALICE, OUTSIDER, 1);
        vm.prank(ALICE);
        assertEq(governor.castVote(proposalId, 1), 600e18);
        vm.prank(OUTSIDER);
        assertEq(governor.castVote(proposalId, 1), 0);
        assertEq(stakingPool.getVotes(ALICE), 0);
        assertEq(stakingPool.getVotes(OUTSIDER), 600e18);
    }

    function testUnstakingAfterSnapshotDoesNotChangeProposalWeight() public {
        uint256 proposalId = _propose(ALICE, 10, DESCRIPTION);
        _activate(proposalId);
        vm.prank(ALICE);
        stakingPool.unstake(1, ALICE);
        assertEq(stakingPool.getVotes(ALICE), 0);
        vm.prank(ALICE);
        assertEq(governor.castVote(proposalId, 1), 600e18);
        assertEq(stakingPool.totalActiveStake(), 400e18);
    }

    function testBurnAddressCannotOwnPositionOrContributeStakedVotes() public {
        address burnAddress = token.BURN_ADDRESS();
        vm.prank(ALICE);
        vm.expectPartialRevert(ProjectPoSNFT.InvalidPositionRecipient.selector);
        posNFT.transferFrom(ALICE, burnAddress, 1);
        assertEq(stakingPool.getVotes(burnAddress), 0);
        vm.warp(block.timestamp + 1);
        assertEq(stakingPool.getPastVotes(burnAddress, block.timestamp - 1), 0);
    }
}
