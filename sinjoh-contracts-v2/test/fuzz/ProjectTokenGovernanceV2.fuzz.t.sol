// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IGovernor } from "@openzeppelin/contracts/governance/IGovernor.sol";
import { ProjectGovernorV2 } from "../../src/governance/ProjectGovernorV2.sol";
import { ProjectTimelockV2 } from "../../src/governance/ProjectTimelockV2.sol";
import { TokenGovernanceConfig } from "../../src/governance/TokenGovernanceConfig.sol";
import { GovernanceTestBase } from "../GovernanceTestBase.sol";

contract ProjectLiquidTokenGovernanceV2FuzzTest is GovernanceTestBase {
    string private constant DESCRIPTION = "Fuzz liquid governance";

    function setUp() public {
        _setUpLiquidGovernance();
    }

    function testFuzzPostSnapshotTransferCannotChangeProposalWeight(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, 0, 600e18);
        uint256 proposalId = _propose(ALICE, 1, DESCRIPTION);
        _activate(proposalId);
        vm.prank(ALICE);
        assertTrue(token.transfer(OUTSIDER, amount));
        vm.prank(ALICE);
        assertEq(governor.castVote(proposalId, 1), 600e18);
        vm.prank(OUTSIDER);
        assertEq(governor.castVote(proposalId, 1), 0);
    }

    function testFuzzBurnedBalancesAreRemovedFromFutureQuorum(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, 0, 300e18);
        address burnAddress = token.BURN_ADDRESS();
        vm.prank(BOB);
        assertTrue(token.transfer(burnAddress, amount));
        vm.warp(START + 2);
        uint256 expectedEligibleSupply = REFERENCE_SUPPLY - amount;
        assertEq(governor.quorum(START + 1), expectedEligibleSupply * 1_000 / 10_000);
        assertEq(token.getPastVotes(burnAddress, START + 1), 0);
    }

    function testFuzzAbsoluteProposalThresholdUsesConfiguredLaunchSupply(uint16 rawThresholdBps)
        public
    {
        uint16 thresholdBps = uint16(bound(rawThresholdBps, 10, 1_000));
        TokenGovernanceConfig memory config = _defaultConfig();
        config.proposalThresholdBps = thresholdBps;
        ProjectTimelockV2 otherTimelock = new ProjectTimelockV2(
            address(registry), address(token), address(token), false, config
        );
        ProjectGovernorV2 otherGovernor = otherTimelock.governor();
        assertEq(
            otherGovernor.proposalThreshold(), REFERENCE_SUPPLY * uint256(thresholdBps) / 10_000
        );
    }

    function testFuzzProposalRequiresAtLeastThresholdPower(uint256 rawHolding) public {
        uint256 holding = bound(rawHolding, 0, 600e18);
        vm.prank(ALICE);
        assertTrue(token.transfer(OUTSIDER, 600e18 - holding));
        vm.warp(START + 2);
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) =
            _proposalData(1);
        uint256 threshold = governor.proposalThreshold();
        vm.prank(ALICE);
        if (holding < threshold) {
            vm.expectPartialRevert(IGovernor.GovernorInsufficientProposerVotes.selector);
            governor.propose(targets, values, calldatas, DESCRIPTION);
        } else {
            uint256 proposalId = governor.propose(targets, values, calldatas, DESCRIPTION);
            assertEq(governor.proposalProposer(proposalId), ALICE);
        }
    }
}

contract ProjectStakedTokenGovernanceV2FuzzTest is GovernanceTestBase {
    string private constant DESCRIPTION = "Fuzz staked governance";

    function setUp() public {
        _setUpStakedGovernance(false);
    }

    function testFuzzMultiplePoSPositionsAggregateIntoSnapshotVote(
        uint256 rawFirst,
        uint256 rawSecond
    ) public {
        uint256 first = bound(rawFirst, 5e18, 300e18);
        uint256 second = bound(rawSecond, 5e18, 600e18 - first);
        _stake(ALICE, first);
        _stake(ALICE, second);
        vm.warp(START + 2);
        uint256 proposalId = _propose(ALICE, 1, DESCRIPTION);
        _activate(proposalId);
        vm.prank(ALICE);
        assertEq(governor.castVote(proposalId, 1), first + second);
    }

    function testFuzzPoSNFTTransferChangesOnlyFutureVotes(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, 10e18, 600e18);
        uint256 tokenId = _stake(ALICE, amount);
        vm.warp(START + 2);
        uint256 proposalId = _propose(ALICE, 1, DESCRIPTION);
        _activate(proposalId);
        vm.prank(ALICE);
        posNFT.transferFrom(ALICE, OUTSIDER, tokenId);
        vm.prank(ALICE);
        assertEq(governor.castVote(proposalId, 1), amount);
        vm.prank(OUTSIDER);
        assertEq(governor.castVote(proposalId, 1), 0);
    }

    function testFuzzMatureUnstakePreservesSnapshotVote(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, 10e18, 600e18);
        uint256 tokenId = _stake(ALICE, amount);
        vm.warp(START + 2);
        uint256 proposalId = _propose(ALICE, 1, DESCRIPTION);
        _activate(proposalId);
        vm.prank(ALICE);
        stakingPool.unstake(tokenId, ALICE);
        vm.prank(ALICE);
        assertEq(governor.castVote(proposalId, 1), amount);
        assertEq(stakingPool.getVotes(ALICE), 0);
    }
}
