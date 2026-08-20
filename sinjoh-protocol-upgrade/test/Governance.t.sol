// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IGovernor } from "@openzeppelin/contracts/governance/IGovernor.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { AddressGovernanceController } from "../src/governance/AddressGovernanceController.sol";
import { Governed } from "../src/governance/Governed.sol";
import { SinjohGovernor } from "../src/governance/SinjohGovernor.sol";
import { StakedVotesAdapter } from "../src/governance/StakedVotesAdapter.sol";
import { IGovernanceController } from "../src/interfaces/IGovernanceController.sol";
import { FeeRouterV2 } from "../src/FeeRouterV2.sol";
import { StakingEngine } from "../src/StakingEngine.sol";
import { TestBase } from "./TestBase.sol";
import { MockERC20 } from "./mocks/Mocks.sol";

contract GovernanceTest is TestBase {
    address private constant GUARDIAN = address(0xBEEF);
    address private constant PROTOCOL = address(0xFEE);
    address private constant ALICE = address(0xA11CE);

    function testContractAuthorityRequiredForMultisigAndGovernorDisclosure() public {
        vm.expectRevert(AddressGovernanceController.InvalidAuthority.selector);
        new AddressGovernanceController(ALICE, IGovernanceController.Mode.MULTISIG);

        vm.expectRevert(AddressGovernanceController.InvalidAuthority.selector);
        new AddressGovernanceController(ALICE, IGovernanceController.Mode.TOKEN_GOVERNOR);

        MockERC20 contractAuthority = new MockERC20();
        AddressGovernanceController controller = new AddressGovernanceController(
            address(contractAuthority), IGovernanceController.Mode.MULTISIG
        );
        assertEq(controller.authority(), address(contractAuthority));
    }

    function testConfiguredDeploymentCanBeIrreversiblyFrozen() public {
        MockERC20 token = new MockERC20();
        AddressGovernanceController controller =
            new AddressGovernanceController(address(this), IGovernanceController.Mode.INDIVIDUAL);
        FeeRouterV2 router = new FeeRouterV2(controller, GUARDIAN, PROTOCOL, 1 hours, 1 days);
        FeeRouterV2.Route[] memory routes = new FeeRouterV2.Route[](1);
        routes[0] = FeeRouterV2.Route({
            inputToken: address(token),
            recipient: ALICE,
            shareBps: 10_000,
            action: FeeRouterV2.Action.SEND,
            config: ""
        });
        uint256 configId = router.proposeConfiguration(routes);
        vm.warp(block.timestamp + 1 hours);
        router.activateConfiguration(configId);
        controller.freeze();
        assertTrue(controller.mode() == IGovernanceController.Mode.IMMUTABLE);
        assertEq(controller.authority(), address(0));
        vm.expectRevert(Governed.Unauthorized.selector);
        router.proposeConfiguration(routes);

        token.mint(address(router), 10_000);
        router.sync(address(token));
        assertEq(token.balanceOf(ALICE), 9_900);
    }

    function testStakedGovernorExecutesOnlyAfterVoteAndTimelock() public {
        MockERC20 token = new MockERC20();
        StakingEngine staking = _staking(token);
        token.mint(ALICE, 100e18);
        vm.startPrank(ALICE);
        token.approve(address(staking), 100e18);
        staking.stake(100e18, 0);
        vm.stopPrank();
        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);

        StakedVotesAdapter votes = new StakedVotesAdapter(staking);
        address[] memory noProposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0);
        TimelockController timelock =
            new TimelockController(1 hours, noProposers, executors, address(this));
        SinjohGovernor governor =
            new SinjohGovernor("Sinjoh Staked Governor", votes, timelock, 1, 5, 0, 10, GUARDIAN);
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), address(this));
        assertTrue(!timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), address(this)));

        AddressGovernanceController controller = new AddressGovernanceController(
            address(timelock), IGovernanceController.Mode.TOKEN_GOVERNOR
        );
        FeeRouterV2 router = new FeeRouterV2(controller, GUARDIAN, PROTOCOL, 1 hours, 1 days);
        vm.prank(GUARDIAN);
        router.pause();

        address[] memory targets = new address[](1);
        targets[0] = address(router);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(router.resume, ());
        string memory description = "Resume the governed fee router";
        bytes32 descriptionHash = keccak256(bytes(description));

        vm.prank(ALICE);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);
        vm.warp(governor.proposalSnapshot(proposalId) + 1);
        vm.prank(ALICE);
        governor.castVote(proposalId, uint8(GovernorCountingVote.FOR));
        vm.warp(governor.proposalDeadline(proposalId) + 1);
        governor.queue(targets, values, calldatas, descriptionHash);

        vm.expectRevert();
        governor.execute(targets, values, calldatas, descriptionHash);
        vm.warp(block.timestamp + 1 hours);
        governor.execute(targets, values, calldatas, descriptionHash);
        assertTrue(!router.paused());
        assertTrue(governor.state(proposalId) == IGovernor.ProposalState.Executed);
    }

    function testExpiredLocksHaveNoGovernancePowerWithoutWithdrawal() public {
        MockERC20 token = new MockERC20();
        StakingEngine staking = _staking(token);
        token.mint(ALICE, 100e18);
        vm.startPrank(ALICE);
        token.approve(address(staking), 100e18);
        staking.stake(100e18, 0);
        vm.stopPrank();
        (,, uint48 unlockTime,,,) = staking.positions(ALICE);
        uint256 activeTime = uint256(unlockTime) - 30 days;
        StakedVotesAdapter votes = new StakedVotesAdapter(staking);
        assertEq(votes.getVotes(ALICE), 100e18);

        vm.warp(unlockTime);
        assertEq(votes.getVotes(ALICE), 0);
        vm.warp(uint256(unlockTime) + 1);
        assertEq(votes.getPastVotes(ALICE, activeTime), 100e18);
        assertEq(votes.getPastVotes(ALICE, unlockTime), 0);
        assertEq(votes.getPastTotalSupply(unlockTime), 0);
    }

    function testStakedVotesAdapterDoesNotPermitDelegatingLockedVotes() public {
        MockERC20 token = new MockERC20();
        StakingEngine staking = _staking(token);
        StakedVotesAdapter votes = new StakedVotesAdapter(staking);
        vm.prank(ALICE);
        votes.delegate(ALICE);
        vm.prank(ALICE);
        vm.expectRevert(StakedVotesAdapter.DelegationUnsupported.selector);
        votes.delegate(address(123));
    }

    function _staking(MockERC20 token) private returns (StakingEngine staking) {
        AddressGovernanceController controller =
            new AddressGovernanceController(address(this), IGovernanceController.Mode.INDIVIDUAL);
        StakingEngine.LockTier[] memory tiers = new StakingEngine.LockTier[](1);
        tiers[0] = StakingEngine.LockTier({
            duration: 30 days, rewardWeightBps: 10_000, governanceWeightBps: 10_000, enabled: true
        });
        staking = new StakingEngine(controller, GUARDIAN, IERC20(address(token)), tiers);
    }
}

library GovernorCountingVote {
    uint8 internal constant FOR = 1;
}
