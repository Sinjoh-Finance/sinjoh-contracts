// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { SinjohLaunchStakingEngine } from "../src/SinjohLaunchStakingEngine.sol";
import { TestBase } from "./TestBase.sol";
import { MockERC20 } from "./mocks/Mocks.sol";

contract SinjohLaunchStakingEngineTest is TestBase {
    address private constant PROTOCOL = address(0xFEE);
    address private constant CREATOR = address(0xC0FFEE);
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);

    SinjohLaunchStakingEngine private engine;
    MockERC20 private subject;
    MockERC20 private otherSubject;
    MockERC20 private reward;

    function setUp() public {
        vm.warp(100);
        engine = new SinjohLaunchStakingEngine(PROTOCOL);
        subject = new MockERC20();
        otherSubject = new MockERC20();
        reward = new MockERC20();
    }

    function testFundingAndSnapshotClaimsUseRawActiveStake() public {
        _stake(subject, ALICE, 100e18);
        _stake(subject, BOB, 300e18);
        bytes32 id = _fund(subject, reward, 10_000e18, _config(CREATOR));

        vm.warp(block.timestamp + 1 hours);
        engine.executeEpoch(address(this), address(subject), address(reward));

        assertEq(engine.claimable(id, 1, ALICE), 2_475e18);
        assertEq(engine.claimable(id, 1, BOB), 7_425e18);
        assertEq(reward.balanceOf(PROTOCOL), 100e18);

        uint64[] memory epochs = _one(1);
        vm.prank(ALICE);
        engine.claim(id, epochs);
        vm.prank(BOB);
        engine.claim(id, epochs);
        assertEq(reward.balanceOf(ALICE), 2_475e18);
        assertEq(reward.balanceOf(BOB), 7_425e18);
        assertEq(engine.rewardLiability(address(reward)), 0);
    }

    function testUnstakedBeforeSnapshotGetsNoReward() public {
        _stake(subject, ALICE, 100e18);
        _stake(subject, BOB, 100e18);
        bytes32 id = _fund(subject, reward, 10_000e18, _config(CREATOR));

        vm.warp(block.timestamp + 30 minutes);
        vm.prank(BOB);
        engine.unstake(address(subject), 100e18);
        vm.warp(block.timestamp + 30 minutes + 1);
        engine.executeEpoch(address(this), address(subject), address(reward));

        assertEq(engine.claimable(id, 1, ALICE), 9_900e18);
        assertEq(engine.claimable(id, 1, BOB), 0);
    }

    function testUnstakeAfterCompletedSnapshotIsImmediateAndDoesNotEraseClaim() public {
        _stake(subject, ALICE, 100e18);
        bytes32 id = _fund(subject, reward, 10_000e18, _config(CREATOR));
        vm.warp(block.timestamp + 1 hours);
        engine.executeEpoch(address(this), address(subject), address(reward));

        vm.prank(ALICE);
        engine.unstake(address(subject), 100e18);
        assertEq(subject.balanceOf(ALICE), 100e18);
        assertEq(engine.balanceOf(address(subject), ALICE), 0);
        assertEq(engine.claimable(id, 1, ALICE), 9_900e18);
    }

    function testZeroStakeRollsFundingIntoNextWindow() public {
        bytes32 id = _fund(subject, reward, 10_000e18, _config(CREATOR));
        vm.warp(block.timestamp + 1 hours);
        engine.executeEpoch(address(this), address(subject), address(reward));

        (,,,,,,, uint64 latestEpochId,, uint256 pendingRewards,,,) = engine.accounts(id);
        assertEq(latestEpochId, 0);
        assertEq(pendingRewards, 9_900e18);

        _stake(subject, ALICE, 100e18);
        vm.warp(block.timestamp + 1 hours + 1);
        engine.executeEpoch(address(this), address(subject), address(reward));
        assertEq(engine.claimable(id, 1, ALICE), 9_900e18);
    }

    function testSubjectsHaveIndependentStakeLedgers() public {
        _stake(subject, ALICE, 100e18);
        _stake(otherSubject, BOB, 400e18);
        assertEq(engine.totalStaked(address(subject)), 100e18);
        assertEq(engine.totalStaked(address(otherSubject)), 400e18);
        assertEq(engine.balanceOf(address(subject), BOB), 0);
        assertEq(engine.balanceOf(address(otherSubject), ALICE), 0);
    }

    function testSameTokenPrincipalAndRewardsRemainSolvent() public {
        _stake(subject, ALICE, 100e18);
        bytes32 id = _fund(subject, subject, 10_000e18, _config(CREATOR));
        assertEq(subject.balanceOf(address(engine)), 10_000e18);
        assertEq(engine.stakingLiability(address(subject)), 100e18);
        assertEq(engine.rewardLiability(address(subject)), 9_900e18);

        vm.warp(block.timestamp + 1 hours);
        engine.executeEpoch(address(this), address(subject), address(subject));
        vm.prank(ALICE);
        engine.claim(id, _one(1));
        vm.prank(ALICE);
        engine.unstake(address(subject), 100e18);
        assertEq(subject.balanceOf(address(engine)), 0);
    }

    function testAccountConfigurationCannotChangeAfterFirstFunding() public {
        _fund(subject, reward, 1_000, _config(CREATOR));
        reward.mint(address(this), 1_000);
        reward.approve(address(engine), 1_000);
        bytes memory changed = abi.encode(
            SinjohLaunchStakingEngine.Config({
                interval: 6 hours, claimPeriod: 30 days, unclaimedDestination: CREATOR
            })
        );
        vm.expectRevert(SinjohLaunchStakingEngine.ConfigurationMismatch.selector);
        engine.fund(address(subject), address(reward), 1_000, changed);
    }

    function testSweepUsesDestinationPinnedWhenAccountWasConfigured() public {
        _stake(subject, ALICE, 100e18);
        bytes32 id = _fund(subject, reward, 10_000e18, _config(CREATOR));
        vm.warp(block.timestamp + 1 hours);
        engine.executeEpoch(address(this), address(subject), address(reward));
        vm.warp(block.timestamp + 30 days + 1);
        engine.sweepUnclaimed(id, 1);
        assertEq(reward.balanceOf(CREATOR), 9_900e18);
        assertEq(engine.rewardLiability(address(reward)), 0);
    }

    function testRejectsFeeOnTransferStakeAndFunding() public {
        subject.setFeeBps(100);
        subject.mint(ALICE, 100e18);
        vm.startPrank(ALICE);
        subject.approve(address(engine), 100e18);
        vm.expectPartialRevert(SinjohLaunchStakingEngine.InexactTransfer.selector);
        engine.stake(address(subject), 100e18);
        vm.stopPrank();

        reward.setFeeBps(100);
        reward.mint(address(this), 1_000);
        reward.approve(address(engine), 1_000);
        vm.expectPartialRevert(SinjohLaunchStakingEngine.InexactTransfer.selector);
        engine.fund(address(subject), address(reward), 1_000, _config(CREATOR));
    }

    function _stake(MockERC20 token, address account, uint256 amount) private {
        token.mint(account, amount);
        vm.startPrank(account);
        token.approve(address(engine), amount);
        engine.stake(address(token), amount);
        vm.stopPrank();
    }

    function _fund(
        MockERC20 subjectToken,
        MockERC20 rewardToken,
        uint256 amount,
        bytes memory config
    ) private returns (bytes32 id) {
        rewardToken.mint(address(this), amount);
        rewardToken.approve(address(engine), amount);
        engine.fund(address(subjectToken), address(rewardToken), amount, config);
        id = engine.accountId(address(this), address(subjectToken), address(rewardToken));
    }

    function _config(address destination) private pure returns (bytes memory) {
        return abi.encode(
            SinjohLaunchStakingEngine.Config({
                interval: 1 hours, claimPeriod: 30 days, unclaimedDestination: destination
            })
        );
    }

    function _one(uint64 epochId) private pure returns (uint64[] memory values) {
        values = new uint64[](1);
        values[0] = epochId;
    }
}
