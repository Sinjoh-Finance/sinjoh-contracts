// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AddressGovernanceController } from "../src/governance/AddressGovernanceController.sol";
import { Governed } from "../src/governance/Governed.sol";
import { IGovernanceController } from "../src/interfaces/IGovernanceController.sol";
import { AirdropDistributorV2 } from "../src/AirdropDistributorV2.sol";
import { StakingEngine } from "../src/StakingEngine.sol";
import { TestBase } from "./TestBase.sol";
import { MockERC20 } from "./mocks/Mocks.sol";

contract StakingAirdropTest is TestBase {
    address private constant GUARDIAN = address(0xBEEF);
    address private constant PROTOCOL = address(0xFEE);
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);

    AddressGovernanceController private controller;
    MockERC20 private token;
    StakingEngine private staking;

    function setUp() public {
        controller =
            new AddressGovernanceController(address(this), IGovernanceController.Mode.INDIVIDUAL);
        token = new MockERC20();
        StakingEngine.LockTier[] memory tiers = new StakingEngine.LockTier[](2);
        tiers[0] = StakingEngine.LockTier({
            duration: 1 days, rewardWeightBps: 10_000, governanceWeightBps: 10_000, enabled: true
        });
        tiers[1] = StakingEngine.LockTier({
            duration: 30 days, rewardWeightBps: 12_500, governanceWeightBps: 12_500, enabled: true
        });
        staking = new StakingEngine(controller, GUARDIAN, IERC20(address(token)), tiers);
    }

    function testSameBlockStakeIsConservativelyExcludedFromNewEpoch() public {
        _stake(ALICE, 100e18, 1);
        AirdropDistributorV2 distributor = _distributor();
        uint256 scheduleId = distributor.createSchedule(_schedule(true, 0, 0, 0));
        _fund(distributor, scheduleId, 10_000e18);
        vm.roll(block.number + 1);
        vm.warp(30 minutes + 1);
        vm.expectRevert(AirdropDistributorV2.NoEligibleStake.selector);
        distributor.executeEpoch(scheduleId);
    }

    function testBatchedClaimsAndLiabilityAccounting() public {
        _stake(ALICE, 100e18, 1);
        vm.roll(block.number + 1);
        AirdropDistributorV2 distributor = _distributor();
        uint256 scheduleId = distributor.createSchedule(_schedule(true, 0, 0, 0));

        _fund(distributor, scheduleId, 10_000e18);
        vm.roll(block.number + 1);
        vm.warp(1 hours + 1);
        distributor.executeEpoch(scheduleId);

        _fund(distributor, scheduleId, 20_000e18);
        vm.roll(block.number + 1);
        vm.warp(1 hours + 30 minutes + 1);
        distributor.executeEpoch(scheduleId);

        assertEq(distributor.claimable(scheduleId, 1, ALICE), 9_900e18);
        assertEq(distributor.claimable(scheduleId, 2, ALICE), 19_800e18);
        assertEq(distributor.totalLiability(address(token)), 29_700e18);
        uint64[] memory epochIds = new uint64[](2);
        epochIds[0] = 1;
        epochIds[1] = 2;
        vm.prank(ALICE);
        distributor.claim(scheduleId, epochIds);
        assertEq(distributor.totalLiability(address(token)), 0);
        assertEq(distributor.claimable(scheduleId, 1, ALICE), 0);
    }

    function testExecutorRewardsAreCappedAndRemainSolvent() public {
        _stake(ALICE, 100e18, 1);
        vm.roll(block.number + 1);
        AirdropDistributorV2 distributor = _distributor();
        uint256 scheduleId = distributor.createSchedule(_schedule(true, 100, 100, 50));
        _fund(distributor, scheduleId, 10_000);
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 30 minutes);
        vm.prank(BOB);
        distributor.executeEpoch(scheduleId);
        assertEq(token.balanceOf(BOB), 150);
        assertEq(distributor.totalLiability(address(token)), 9_750);
        assertEq(token.balanceOf(address(distributor)), 9_750);
    }

    function testRestrictedScheduleRequiresGovernanceExecutor() public {
        _stake(ALICE, 100e18, 1);
        vm.roll(block.number + 1);
        AirdropDistributorV2 distributor = _distributor();
        uint256 scheduleId = distributor.createSchedule(_schedule(false, 0, 0, 0));
        _fund(distributor, scheduleId, 10_000);
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 30 minutes);
        vm.prank(BOB);
        vm.expectRevert(Governed.Unauthorized.selector);
        distributor.executeEpoch(scheduleId);
        distributor.executeEpoch(scheduleId);
    }

    function testExpiredPositionCannotBeIncreasedWithoutRenewingLock() public {
        _stake(ALICE, 100e18, 0);
        token.mint(ALICE, 1e18);
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(ALICE);
        token.approve(address(staking), 1e18);
        vm.expectPartialRevert(StakingEngine.PositionExpired.selector);
        staking.increaseStake(1e18);
        vm.stopPrank();
    }

    function testTierChangesApplyOnRenewalNotUnrelatedStakeIncrease() public {
        _stake(ALICE, 100e18, 1);
        StakingEngine.LockTier memory updated = StakingEngine.LockTier({
            duration: 60 days, rewardWeightBps: 20_000, governanceWeightBps: 20_000, enabled: true
        });
        staking.setTier(1, updated);
        token.mint(ALICE, 100e18);
        vm.startPrank(ALICE);
        token.approve(address(staking), 100e18);
        staking.increaseStake(100e18);
        assertEq(staking.currentRewardWeight(ALICE), 250e18);
        staking.extendLock(1);
        vm.stopPrank();
        assertEq(staking.currentRewardWeight(ALICE), 400e18);
    }

    function testHistoricalCheckpointsRemainStableAcrossPositionLifecycle() public {
        _stake(ALICE, 100e18, 0);
        uint256 firstSnapshot = 1;
        vm.roll(2);
        _stake(BOB, 200e18, 1);
        token.mint(ALICE, 50e18);
        vm.startPrank(ALICE);
        token.approve(address(staking), 50e18);
        staking.increaseStake(50e18);
        vm.stopPrank();
        uint256 secondSnapshot = 2;
        vm.roll(3);
        assertEq(staking.getPastRewardWeight(ALICE, firstSnapshot), 100e18);
        assertEq(staking.getPastTotalRewardWeight(firstSnapshot), 100e18);
        assertEq(staking.getPastRewardWeight(ALICE, secondSnapshot), 150e18);
        assertEq(staking.getPastRewardWeight(BOB, secondSnapshot), 250e18);
        assertEq(staking.getPastTotalRewardWeight(secondSnapshot), 400e18);

        vm.prank(ALICE);
        staking.extendLock(1);
        vm.warp(block.timestamp + 30 days);
        vm.prank(ALICE);
        staking.withdraw();
        uint256 withdrawnSnapshot = 3;
        vm.roll(4);
        assertEq(staking.getPastTotalRewardWeight(withdrawnSnapshot), 250e18);
        assertEq(staking.getPastTotalRewardWeight(secondSnapshot), 400e18);
    }

    function testMultipleSchedulesShareOneTokenWithoutCrossingLiabilities() public {
        _stake(ALICE, 100e18, 1);
        _stake(BOB, 300e18, 1);
        vm.roll(block.number + 1);
        AirdropDistributorV2 distributor = _distributor();
        uint256 firstSchedule = distributor.createSchedule(_schedule(true, 0, 0, 0));
        uint256 secondSchedule = distributor.createSchedule(_schedule(true, 0, 0, 0));
        _fund(distributor, firstSchedule, 10_001);
        _fund(distributor, secondSchedule, 20_001);
        vm.warp(block.timestamp + 30 minutes);
        vm.roll(block.number + 1);
        distributor.executeEpoch(firstSchedule);
        distributor.executeEpoch(secondSchedule);
        uint256 firstAlice = distributor.claimable(firstSchedule, 1, ALICE);
        uint256 firstBob = distributor.claimable(firstSchedule, 1, BOB);
        uint256 secondAlice = distributor.claimable(secondSchedule, 1, ALICE);
        uint64[] memory epochIds = new uint64[](1);
        epochIds[0] = 1;
        vm.prank(ALICE);
        distributor.claim(firstSchedule, epochIds);
        vm.prank(BOB);
        distributor.claim(firstSchedule, epochIds);
        vm.prank(ALICE);
        distributor.claim(secondSchedule, epochIds);
        uint256 expectedLiability = 29_702 - firstAlice - firstBob - secondAlice;
        assertEq(distributor.totalLiability(address(token)), expectedLiability);
        assertEq(token.balanceOf(address(distributor)), expectedLiability);
    }

    function testStartOfEpochStakeRemainsEligibleIfLockBecomesWithdrawable() public {
        _stake(ALICE, 100e18, 0);
        vm.warp(23 hours + 45 minutes);
        vm.roll(block.number + 1);
        AirdropDistributorV2 distributor = _distributor();
        uint256 scheduleId = distributor.createSchedule(_schedule(true, 0, 0, 0));
        _fund(distributor, scheduleId, 10_000);
        vm.warp(24 hours + 15 minutes);
        vm.roll(block.number + 1);
        distributor.executeEpoch(scheduleId);
        uint64[] memory epochIds = new uint64[](1);
        epochIds[0] = 1;
        vm.prank(ALICE);
        distributor.claim(scheduleId, epochIds);
        assertEq(token.balanceOf(ALICE), 9_900);
    }

    function testLateExecutionAlwaysCreatesAFreshClaimWindow() public {
        _stake(ALICE, 100e18, 1);
        vm.roll(block.number + 1);
        AirdropDistributorV2 distributor = _distributor();
        uint256 scheduleId = distributor.createSchedule(_schedule(true, 0, 0, 0));
        _fund(distributor, scheduleId, 10_000);
        vm.warp(3 days);
        vm.roll(block.number + 1);
        distributor.executeEpoch(scheduleId);
        AirdropDistributorV2.Epoch memory epoch = distributor.getEpoch(scheduleId, 1);
        assertEq(epoch.claimDeadline, block.timestamp + 1 days);
        uint256 expectedClaim = distributor.claimable(scheduleId, 1, ALICE);
        uint64[] memory epochIds = new uint64[](1);
        epochIds[0] = 1;
        vm.prank(ALICE);
        distributor.claim(scheduleId, epochIds);
        assertEq(token.balanceOf(ALICE), expectedClaim);
        assertTrue(expectedClaim != 0);
    }

    function testEpochPreservesItsOriginalUnclaimedDestination() public {
        _stake(ALICE, 100e18, 1);
        vm.roll(block.number + 1);
        AirdropDistributorV2 distributor = _distributor();
        uint256 scheduleId = distributor.createSchedule(_schedule(true, 0, 0, 0));
        _fund(distributor, scheduleId, 10_000);
        vm.warp(30 minutes + 1);
        vm.roll(block.number + 1);
        distributor.executeEpoch(scheduleId);
        AirdropDistributorV2.ScheduleInput memory updated = _schedule(true, 0, 0, 0);
        updated.unclaimedDestination = ALICE;
        distributor.updateSchedule(scheduleId, updated);
        vm.warp(block.timestamp + 1 days + 1);
        distributor.sweepUnclaimed(scheduleId, 1);
        assertEq(token.balanceOf(BOB), 9_900);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function testUnclaimedRewardsSweepAfterDeadlineAndClearLiability() public {
        _stake(ALICE, 100e18, 1);
        vm.roll(block.number + 1);
        AirdropDistributorV2 distributor = _distributor();
        uint256 scheduleId = distributor.createSchedule(_schedule(true, 0, 0, 0));
        _fund(distributor, scheduleId, 10_000);
        vm.warp(30 minutes + 1);
        vm.roll(block.number + 1);
        distributor.executeEpoch(scheduleId);
        vm.warp(2 days);
        distributor.sweepUnclaimed(scheduleId, 1);
        assertEq(token.balanceOf(BOB), 9_900);
        assertEq(distributor.totalLiability(address(token)), 0);
    }

    function testScheduleUpdateDoesNotRewriteCurrentEpochStart() public {
        _stake(ALICE, 100e18, 1);
        vm.roll(block.number + 1);
        AirdropDistributorV2 distributor = _distributor();
        uint256 scheduleId = distributor.createSchedule(_schedule(true, 0, 0, 0));
        AirdropDistributorV2.ScheduleInput memory updated = _schedule(true, 0, 0, 0);
        updated.interval = 2 days;
        updated.claimPeriod = 3 days;
        distributor.updateSchedule(scheduleId, updated);
        _fund(distributor, scheduleId, 10_000);
        vm.warp(30 minutes + 1);
        vm.roll(block.number + 1);
        distributor.executeEpoch(scheduleId);
        AirdropDistributorV2.Epoch memory epoch = distributor.getEpoch(scheduleId, 1);
        assertEq(epoch.startTime, 1);
        assertEq(epoch.endTime, 30 minutes + 1);
    }

    function _stake(address account, uint128 amount, uint8 tierId) private {
        token.mint(account, amount);
        vm.startPrank(account);
        token.approve(address(staking), amount);
        staking.stake(amount, tierId);
        vm.stopPrank();
    }

    function _distributor() private returns (AirdropDistributorV2) {
        return new AirdropDistributorV2(controller, GUARDIAN, staking, PROTOCOL);
    }

    function _schedule(
        bool permissionless,
        uint128 fixedReward,
        uint16 rewardBps,
        uint128 rewardCap
    ) private view returns (AirdropDistributorV2.ScheduleInput memory) {
        return AirdropDistributorV2.ScheduleInput({
            rewardToken: address(token),
            interval: 30 minutes,
            claimPeriod: 1 days,
            permissionlessExecution: permissionless,
            fixedExecutorReward: fixedReward,
            executorRewardBps: rewardBps,
            executorRewardCap: rewardCap,
            unclaimedDestination: BOB
        });
    }

    function _fund(AirdropDistributorV2 distributor, uint256 scheduleId, uint256 amount) private {
        token.mint(address(this), amount);
        token.approve(address(distributor), amount);
        distributor.fund(address(token), amount, abi.encode(scheduleId));
    }
}
