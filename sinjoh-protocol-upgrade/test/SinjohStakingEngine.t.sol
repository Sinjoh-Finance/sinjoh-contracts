// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AddressGovernanceController } from "../src/governance/AddressGovernanceController.sol";
import { Governed } from "../src/governance/Governed.sol";
import { IGovernanceController } from "../src/interfaces/IGovernanceController.sol";
import { SinjohStakingEngine } from "../src/SinjohStakingEngine.sol";
import { StakingEngine } from "../src/StakingEngine.sol";
import { TestBase } from "./TestBase.sol";
import { MockERC20 } from "./mocks/Mocks.sol";

contract SinjohStakingEngineTest is TestBase {
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
        staking = new StakingEngine(controller, GUARDIAN, IERC20(address(token)));
    }

    function testZeroStakeEpochRollsPendingFundingIntoNextEligibleWindow() public {
        _stake(ALICE, 100e18);
        SinjohStakingEngine distributor = _distributor();
        uint256 scheduleId = distributor.createSchedule(_schedule(true, 0, 0, 0));
        _fund(distributor, scheduleId, 10_000e18);
        vm.roll(block.number + 1);
        vm.warp(30 minutes + 1);
        distributor.executeEpoch(scheduleId);
        SinjohStakingEngine.DistributionSchedule memory schedule =
            distributor.getSchedule(scheduleId);
        assertEq(schedule.latestEpochId, 0);
        assertEq(schedule.pendingRewards, 9_900e18);
        assertEq(distributor.totalLiability(address(token)), 9_900e18);

        vm.warp(schedule.nextEpoch);
        vm.roll(block.number + 1);
        distributor.executeEpoch(scheduleId);
        assertEq(distributor.claimable(scheduleId, 1, ALICE), 9_900e18);
    }

    function testBatchedClaimsAndLiabilityAccounting() public {
        _stake(ALICE, 100e18);
        vm.warp(2);
        vm.roll(block.number + 1);
        SinjohStakingEngine distributor = _distributor();
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

    function testFuzzProportionalClaimsRemainSolvent(
        uint96 rawAliceStake,
        uint96 rawBobStake,
        uint96 rawFunding
    ) public {
        uint128 aliceStake = uint128(rawAliceStake) + 1;
        uint128 bobStake = uint128(rawBobStake) + 1;
        uint256 grossFunding = uint256(rawFunding) + 100;
        _stake(ALICE, aliceStake);
        _stake(BOB, bobStake);
        vm.warp(2);
        vm.roll(block.number + 1);
        SinjohStakingEngine distributor = _distributor();
        uint256 scheduleId = distributor.createSchedule(_schedule(true, 0, 0, 0));
        _fund(distributor, scheduleId, grossFunding);
        vm.warp(block.timestamp + 30 minutes);
        vm.roll(block.number + 1);
        distributor.executeEpoch(scheduleId);

        uint256 aliceClaim = distributor.claimable(scheduleId, 1, ALICE);
        uint256 bobClaim = distributor.claimable(scheduleId, 1, BOB);
        SinjohStakingEngine.Epoch memory epoch = distributor.getEpoch(scheduleId, 1);
        assertTrue(aliceClaim + bobClaim <= epoch.fundedAmount);
        assertTrue(epoch.fundedAmount - aliceClaim - bobClaim <= 1);

        uint64[] memory epochIds = new uint64[](1);
        epochIds[0] = 1;
        if (aliceClaim != 0) {
            vm.prank(ALICE);
            distributor.claim(scheduleId, epochIds);
        }
        if (bobClaim != 0) {
            vm.prank(BOB);
            distributor.claim(scheduleId, epochIds);
        }
        assertEq(
            distributor.totalLiability(address(token)), epoch.fundedAmount - aliceClaim - bobClaim
        );
    }

    function testExecutorRewardsAreCappedAndRemainSolvent() public {
        _stake(ALICE, 100e18);
        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);
        SinjohStakingEngine distributor = _distributor();
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
        _stake(ALICE, 100e18);
        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);
        SinjohStakingEngine distributor = _distributor();
        uint256 scheduleId = distributor.createSchedule(_schedule(false, 0, 0, 0));
        _fund(distributor, scheduleId, 10_000);
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 30 minutes);
        vm.prank(BOB);
        vm.expectRevert(Governed.Unauthorized.selector);
        distributor.executeEpoch(scheduleId);
        distributor.executeEpoch(scheduleId);
    }

    function testRepeatedStakesAddRawBalanceWithoutMultiplier() public {
        _stake(ALICE, 100e18);
        _stake(ALICE, 50e18);
        assertEq(staking.balanceOf(ALICE), 150e18);
        assertEq(staking.totalStaked(), 150e18);
    }

    function testPartialAndFullUnstakeAreImmediate() public {
        _stake(ALICE, 100e18);
        vm.startPrank(ALICE);
        staking.unstake(40e18);
        assertEq(staking.balanceOf(ALICE), 60e18);
        assertEq(token.balanceOf(ALICE), 40e18);
        staking.unstake(60e18);
        vm.stopPrank();
        assertEq(staking.balanceOf(ALICE), 0);
        assertEq(staking.totalStaked(), 0);
        assertEq(token.balanceOf(ALICE), 100e18);
    }

    function testStakeRejectsInexactIncomingTransfer() public {
        token.mint(ALICE, 100e18);
        token.setFeeBps(100);
        vm.startPrank(ALICE);
        token.approve(address(staking), 100e18);
        vm.expectPartialRevert(StakingEngine.InexactTransfer.selector);
        staking.stake(100e18);
        vm.stopPrank();
        assertEq(staking.balanceOf(ALICE), 0);
        assertEq(staking.totalStaked(), 0);
    }

    function testUnstakeRejectsInexactOutgoingTransferWithoutChangingStake() public {
        _stake(ALICE, 100e18);
        token.setFeeBps(100);
        vm.prank(ALICE);
        vm.expectPartialRevert(StakingEngine.InexactTransfer.selector);
        staking.unstake(100e18);
        assertEq(staking.balanceOf(ALICE), 100e18);
        assertEq(staking.totalStaked(), 100e18);
        assertEq(token.balanceOf(address(staking)), 100e18);
    }

    function testUnstakeRejectsMoreThanAvailable() public {
        _stake(ALICE, 100e18);
        vm.prank(ALICE);
        vm.expectPartialRevert(StakingEngine.InsufficientStake.selector);
        staking.unstake(100e18 + 1);
    }

    function testUnstakeRemainsAvailableWhilePaused() public {
        _stake(ALICE, 100e18);
        vm.prank(GUARDIAN);
        staking.pause();
        vm.prank(ALICE);
        staking.unstake(100e18);
        assertEq(token.balanceOf(ALICE), 100e18);
    }

    function testHistoricalSnapshotsRemainStableAcrossStakeAndUnstake() public {
        vm.warp(100);
        _stake(ALICE, 100e18);
        vm.warp(101);
        _stake(BOB, 200e18);
        _stake(ALICE, 50e18);
        vm.warp(102);
        vm.prank(ALICE);
        staking.unstake(150e18);
        vm.warp(103);

        assertEq(staking.getPastBalance(ALICE, 100), 100e18);
        assertEq(staking.getPastTotalStaked(100), 100e18);
        assertEq(staking.getPastBalance(ALICE, 101), 150e18);
        assertEq(staking.getPastBalance(BOB, 101), 200e18);
        assertEq(staking.getPastTotalStaked(101), 350e18);
        assertEq(staking.getPastBalance(ALICE, 102), 0);
        assertEq(staking.getPastTotalStaked(102), 200e18);
    }

    function testUnstakedBeforeEpochSnapshotIsExcluded() public {
        _stake(ALICE, 100e18);
        _stake(BOB, 100e18);
        vm.prank(ALICE);
        staking.unstake(100e18);
        vm.warp(block.timestamp + 1);
        SinjohStakingEngine distributor = _distributor();
        uint256 scheduleId = distributor.createSchedule(_schedule(true, 0, 0, 0));
        _fund(distributor, scheduleId, 10_000);
        vm.warp(block.timestamp + 30 minutes);
        distributor.executeEpoch(scheduleId);

        SinjohStakingEngine.Epoch memory epoch = distributor.getEpoch(scheduleId, 1);
        assertEq(epoch.eligibleStake, 100e18);
        assertEq(distributor.claimable(scheduleId, 1, ALICE), 0);
        assertEq(distributor.claimable(scheduleId, 1, BOB), 9_900);
    }

    function testFuzzRawStakeAndImmediateUnstakeAccounting(uint96 rawAliceStake, uint96 rawBobStake)
        public
    {
        uint256 aliceStake = uint256(rawAliceStake) + 1;
        uint256 bobStake = uint256(rawBobStake) + 1;
        _stake(ALICE, uint128(aliceStake));
        _stake(BOB, uint128(bobStake));
        assertEq(staking.totalStaked(), aliceStake + bobStake);
        assertEq(staking.balanceOf(ALICE), aliceStake);
        assertEq(staking.balanceOf(BOB), bobStake);

        vm.prank(ALICE);
        staking.unstake(aliceStake);
        assertEq(staking.totalStaked(), bobStake);
        vm.prank(BOB);
        staking.unstake(bobStake);
        assertEq(staking.totalStaked(), 0);
    }

    function testMultipleSchedulesShareOneTokenWithoutCrossingLiabilities() public {
        _stake(ALICE, 100e18);
        _stake(BOB, 300e18);
        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);
        SinjohStakingEngine distributor = _distributor();
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

    function testStartOfEpochStakeRemainsEligibleAfterImmediateUnstake() public {
        _stake(ALICE, 100e18);
        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);
        SinjohStakingEngine distributor = _distributor();
        uint256 scheduleId = distributor.createSchedule(_schedule(true, 0, 0, 0));
        _fund(distributor, scheduleId, 10_000);
        vm.prank(ALICE);
        staking.unstake(100e18);
        vm.warp(block.timestamp + 30 minutes);
        vm.roll(block.number + 1);
        distributor.executeEpoch(scheduleId);
        uint64[] memory epochIds = new uint64[](1);
        epochIds[0] = 1;
        vm.prank(ALICE);
        distributor.claim(scheduleId, epochIds);
        assertEq(token.balanceOf(ALICE), 100e18 + 9_900);
    }

    function testLateExecutionAlwaysCreatesAFreshClaimWindow() public {
        _stake(ALICE, 100e18);
        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);
        SinjohStakingEngine distributor = _distributor();
        uint256 scheduleId = distributor.createSchedule(_schedule(true, 0, 0, 0));
        _fund(distributor, scheduleId, 10_000);
        vm.warp(3 days);
        vm.roll(block.number + 1);
        distributor.executeEpoch(scheduleId);
        SinjohStakingEngine.Epoch memory epoch = distributor.getEpoch(scheduleId, 1);
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
        _stake(ALICE, 100e18);
        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);
        SinjohStakingEngine distributor = _distributor();
        uint256 scheduleId = distributor.createSchedule(_schedule(true, 0, 0, 0));
        _fund(distributor, scheduleId, 10_000);
        vm.warp(distributor.getSchedule(scheduleId).nextEpoch);
        vm.roll(block.number + 1);
        distributor.executeEpoch(scheduleId);
        SinjohStakingEngine.ScheduleInput memory updated = _schedule(true, 0, 0, 0);
        updated.unclaimedDestination = ALICE;
        distributor.updateSchedule(scheduleId, updated);
        vm.warp(block.timestamp + 1 days + 1);
        distributor.sweepUnclaimed(scheduleId, 1);
        assertEq(token.balanceOf(BOB), 9_900);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function testUnclaimedRewardsSweepAfterDeadlineAndClearLiability() public {
        _stake(ALICE, 100e18);
        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);
        SinjohStakingEngine distributor = _distributor();
        uint256 scheduleId = distributor.createSchedule(_schedule(true, 0, 0, 0));
        _fund(distributor, scheduleId, 10_000);
        vm.warp(distributor.getSchedule(scheduleId).nextEpoch);
        vm.roll(block.number + 1);
        distributor.executeEpoch(scheduleId);
        vm.warp(2 days);
        distributor.sweepUnclaimed(scheduleId, 1);
        assertEq(token.balanceOf(BOB), 9_900);
        assertEq(distributor.totalLiability(address(token)), 0);
    }

    function testScheduleUpdateDoesNotRewriteCurrentEpochStart() public {
        _stake(ALICE, 100e18);
        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);
        SinjohStakingEngine distributor = _distributor();
        uint256 scheduleId = distributor.createSchedule(_schedule(true, 0, 0, 0));
        SinjohStakingEngine.DistributionSchedule memory original =
            distributor.getSchedule(scheduleId);
        SinjohStakingEngine.ScheduleInput memory updated = _schedule(true, 0, 0, 0);
        updated.interval = 2 days;
        updated.claimPeriod = 3 days;
        distributor.updateSchedule(scheduleId, updated);
        _fund(distributor, scheduleId, 10_000);
        vm.warp(original.nextEpoch);
        vm.roll(block.number + 1);
        distributor.executeEpoch(scheduleId);
        SinjohStakingEngine.Epoch memory epoch = distributor.getEpoch(scheduleId, 1);
        assertEq(epoch.startTime, original.epochStartTime);
        assertEq(epoch.endTime, original.nextEpoch);
    }

    function _stake(address account, uint128 amount) private {
        token.mint(account, amount);
        vm.startPrank(account);
        token.approve(address(staking), amount);
        staking.stake(amount);
        vm.stopPrank();
    }

    function _distributor() private returns (SinjohStakingEngine) {
        return new SinjohStakingEngine(controller, GUARDIAN, staking, PROTOCOL);
    }

    function _schedule(
        bool permissionless,
        uint128 fixedReward,
        uint16 rewardBps,
        uint128 rewardCap
    ) private view returns (SinjohStakingEngine.ScheduleInput memory) {
        return SinjohStakingEngine.ScheduleInput({
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

    function _fund(SinjohStakingEngine distributor, uint256 scheduleId, uint256 amount) private {
        token.mint(address(this), amount);
        token.approve(address(distributor), amount);
        distributor.fund(address(token), amount, abi.encode(scheduleId));
    }
}
