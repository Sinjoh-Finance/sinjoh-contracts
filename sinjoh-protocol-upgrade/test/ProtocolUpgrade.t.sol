// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AddressGovernanceController } from "../src/governance/AddressGovernanceController.sol";
import { ImmutableGovernanceController } from "../src/governance/ImmutableGovernanceController.sol";
import { IGovernanceController } from "../src/interfaces/IGovernanceController.sol";
import { FeeRouterV2 } from "../src/FeeRouterV2.sol";
import { StakingEngine } from "../src/StakingEngine.sol";
import { SinjohStakingEngine } from "../src/SinjohStakingEngine.sol";
import { YieldBasket } from "../src/YieldBasket.sol";
import { DynamicFundingBands } from "../src/DynamicFundingBands.sol";
import { TestBase } from "./TestBase.sol";
import { MockERC20, MockFundable, MockYieldAdapter, MockTwapOracle } from "./mocks/Mocks.sol";

contract ProtocolUpgradeTest is TestBase {
    address private constant GUARDIAN = address(0xBEEF);
    address private constant PROTOCOL = address(0xFEE);
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);

    AddressGovernanceController private controller;
    MockERC20 private token;

    function setUp() public {
        controller =
            new AddressGovernanceController(address(this), IGovernanceController.Mode.INDIVIDUAL);
        token = new MockERC20();
    }

    function testGovernanceModesAndGuardianPause() public {
        assertEq(controller.authority(), address(this));
        assertTrue(controller.canCall(address(this), address(123), bytes4(0)));
        ImmutableGovernanceController immutableController = new ImmutableGovernanceController();
        assertTrue(!immutableController.canCall(address(this), address(123), bytes4(0)));

        FeeRouterV2 router = new FeeRouterV2(controller, GUARDIAN, PROTOCOL, 1 hours, 1 days);
        vm.prank(GUARDIAN);
        router.pause();
        assertTrue(router.paused());
        router.resume();
        assertTrue(!router.paused());
    }

    function testFeeRouterAtomicDelayRollbackAndInvariantFee() public {
        FeeRouterV2 router = new FeeRouterV2(controller, GUARDIAN, PROTOCOL, 1 hours, 1 days);
        FeeRouterV2.Route[] memory first = _directRoutes(ALICE, BOB);
        uint256 firstId = router.proposeConfiguration(first);
        vm.expectPartialRevert(FeeRouterV2.ConfigurationNotReady.selector);
        router.activateConfiguration(firstId);
        vm.warp(block.timestamp + 1 hours);
        router.activateConfiguration(firstId);

        token.mint(address(router), 10_000);
        router.sync(address(token));
        assertEq(token.balanceOf(PROTOCOL), 100);
        assertEq(token.balanceOf(ALICE), 4_950);
        assertEq(token.balanceOf(BOB), 4_950);
        assertEq(router.cumulativeProtocolFee(address(token)), 100);

        FeeRouterV2.Route[] memory second = new FeeRouterV2.Route[](1);
        second[0] = FeeRouterV2.Route({
            inputToken: address(token),
            recipient: ALICE,
            shareBps: 10_000,
            action: FeeRouterV2.Action.TREASURY,
            config: ""
        });
        uint256 secondId = router.proposeConfiguration(second);
        vm.warp(block.timestamp + 1 hours + 1);
        router.activateConfiguration(secondId);
        router.rollbackConfiguration();
        assertEq(router.activeConfigurationId(), firstId);
    }

    function testFeeRouterRejectsFeeOnTransferAndInvalidShares() public {
        FeeRouterV2 router = new FeeRouterV2(controller, GUARDIAN, PROTOCOL, 1 hours, 1 days);
        FeeRouterV2.Route[] memory invalid = _directRoutes(ALICE, BOB);
        invalid[1].shareBps = 4_999;
        vm.expectRevert(FeeRouterV2.InvalidConfiguration.selector);
        router.proposeConfiguration(invalid);

        uint256 id = router.proposeConfiguration(_directRoutes(ALICE, BOB));
        vm.warp(block.timestamp + 1 hours);
        router.activateConfiguration(id);
        token.setFeeBps(100);
        token.mint(address(router), 10_000);
        vm.expectPartialRevert(FeeRouterV2.InexactTransfer.selector);
        router.sync(address(token));
    }

    function testStakingAndAirdropEpochIntegration() public {
        StakingEngine.LockTier[] memory tiers = new StakingEngine.LockTier[](2);
        tiers[0] = StakingEngine.LockTier({
            duration: 1 days, rewardWeightBps: 10_000, governanceWeightBps: 10_000, enabled: true
        });
        tiers[1] = StakingEngine.LockTier({
            duration: 7 days, rewardWeightBps: 11_000, governanceWeightBps: 11_000, enabled: true
        });
        StakingEngine staking =
            new StakingEngine(controller, GUARDIAN, IERC20(address(token)), tiers);

        token.mint(ALICE, 1_000e18);
        vm.startPrank(ALICE);
        token.approve(address(staking), type(uint256).max);
        staking.stake(100e18, 1);
        vm.stopPrank();
        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);

        SinjohStakingEngine distributor =
            new SinjohStakingEngine(controller, GUARDIAN, staking, PROTOCOL);
        SinjohStakingEngine.ScheduleInput memory input = SinjohStakingEngine.ScheduleInput({
            rewardToken: address(token),
            interval: 30 minutes,
            claimPeriod: 7 days,
            permissionlessExecution: true,
            fixedExecutorReward: 0,
            executorRewardBps: 0,
            executorRewardCap: 0,
            unclaimedDestination: BOB
        });
        uint256 scheduleId = distributor.createSchedule(input);
        token.mint(address(this), 10_000e18);
        token.approve(address(distributor), type(uint256).max);
        distributor.fund(address(token), 10_000e18, abi.encode(scheduleId));
        assertEq(token.balanceOf(PROTOCOL), 100e18);

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 30 minutes);
        distributor.executeEpoch(scheduleId);
        uint64[] memory epochIds = new uint64[](1);
        epochIds[0] = 1;
        vm.prank(ALICE);
        distributor.claim(scheduleId, epochIds);
        assertEq(token.balanceOf(ALICE), 10_800e18);
    }

    function testStakeCheckpointsRecordWeightAndUnlockTime() public {
        StakingEngine.LockTier[] memory tiers = new StakingEngine.LockTier[](1);
        tiers[0] = StakingEngine.LockTier({
            duration: 1 days, rewardWeightBps: 10_000, governanceWeightBps: 10_000, enabled: true
        });
        StakingEngine staking =
            new StakingEngine(controller, GUARDIAN, IERC20(address(token)), tiers);
        token.mint(ALICE, 100e18);
        vm.startPrank(ALICE);
        token.approve(address(staking), 100e18);
        staking.stake(100e18, 0);
        vm.stopPrank();
        (,, uint48 unlockTime,,,) = staking.positions(ALICE);
        uint256 stakeTime = uint256(unlockTime) - 1 days;
        vm.warp(stakeTime + 1);
        assertEq(staking.getPastRewardWeight(ALICE, stakeTime), 100e18);
        assertEq(staking.getPastUnlockTime(ALICE, stakeTime), unlockTime);
    }

    function testYieldBasketEnforcesAllocationAndDistributesHarvestOnly() public {
        MockERC20 reward = new MockERC20();
        MockFundable sink = new MockFundable();
        MockYieldAdapter adapter = new MockYieldAdapter(address(token), reward);
        YieldBasket basket = new YieldBasket(controller, GUARDIAN, IERC20(address(token)));
        adapter.setBasket(address(basket));
        basket.configureAdapter(adapter, 5_000, 30 minutes);
        YieldBasket.RewardRouteInput[] memory routes = new YieldBasket.RewardRouteInput[](1);
        routes[0] = YieldBasket.RewardRouteInput({
            rewardToken: address(reward), distributor: address(sink), distributionConfig: ""
        });
        basket.setAdapterRewardRoutes(adapter, routes);

        token.mint(address(this), 1_000e18);
        token.approve(address(basket), type(uint256).max);
        basket.fund(address(token), 1_000e18, "");
        basket.allocate(adapter, 500e18);
        vm.expectRevert(YieldBasket.AllocationLimitExceeded.selector);
        basket.allocate(adapter, 1);

        adapter.setNextReward(50e18);
        vm.warp(block.timestamp + 30 minutes);
        basket.harvest(adapter);
        assertEq(sink.funded(address(reward)), 50e18);
        assertEq(basket.cumulativeRealizedYield(address(reward)), 50e18);
        assertEq(basket.totalPrincipalContributed(), 1_000e18);
    }

    function testDynamicBandPrefundingDelayConfirmationAndFee() public {
        MockERC20 subject = new MockERC20();
        MockTwapOracle oracle = new MockTwapOracle();
        DynamicFundingBands bands =
            new DynamicFundingBands(controller, GUARDIAN, oracle, 1 hours, PROTOCOL);
        token.mint(address(this), 10_000);
        token.approve(address(bands), type(uint256).max);
        DynamicFundingBands.BandInput memory input = DynamicFundingBands.BandInput({
            subject: address(subject),
            fundingAsset: address(token),
            amount: 10_000,
            lowerPriceE18: 110e18,
            upperPriceE18: 130e18,
            activationDelay: 1 hours,
            lifetime: 7 days,
            confirmationPeriod: 5 minutes,
            twapWindow: 5 minutes,
            minimumDistanceBps: 500,
            recipient: ALICE,
            refundRecipient: BOB
        });
        uint256 bandId = bands.createBand(input);
        assertEq(token.balanceOf(address(bands)), 10_000);
        vm.expectPartialRevert(DynamicFundingBands.ActivationPending.selector);
        bands.activate(bandId);
        vm.warp(block.timestamp + 1 hours);
        bands.activate(bandId);
        oracle.setPrice(120e18);
        bands.observe(bandId);
        vm.warp(block.timestamp + 5 minutes);
        oracle.setPrice(120e18);
        bands.redeem(bandId);
        assertEq(token.balanceOf(PROTOCOL), 100);
        assertEq(token.balanceOf(ALICE), 9_900);
        assertEq(bands.totalCommitted(), 0);
    }

    function testFuzzProtocolFeeCannotBeSplitAvoided(uint96 first, uint96 second) public {
        uint256 a = uint256(first) + 1;
        uint256 b = uint256(second) + 1;
        FeeRouterV2 router = new FeeRouterV2(controller, GUARDIAN, PROTOCOL, 1, 1 days);
        FeeRouterV2.Route[] memory routes = new FeeRouterV2.Route[](1);
        routes[0] = FeeRouterV2.Route({
            inputToken: address(token),
            recipient: ALICE,
            shareBps: 10_000,
            action: FeeRouterV2.Action.SEND,
            config: ""
        });
        uint256 id = router.proposeConfiguration(routes);
        vm.warp(block.timestamp + 1);
        router.activateConfiguration(id);
        token.mint(address(router), a);
        router.sync(address(token));
        token.mint(address(router), b);
        router.sync(address(token));
        assertEq(router.cumulativeProtocolFee(address(token)), (a + b) / 100);
    }

    function _directRoutes(address first, address second)
        private
        view
        returns (FeeRouterV2.Route[] memory routes)
    {
        routes = new FeeRouterV2.Route[](2);
        routes[0] = FeeRouterV2.Route({
            inputToken: address(token),
            recipient: first,
            shareBps: 5_000,
            action: FeeRouterV2.Action.SEND,
            config: ""
        });
        routes[1] = FeeRouterV2.Route({
            inputToken: address(token),
            recipient: second,
            shareBps: 5_000,
            action: FeeRouterV2.Action.SEND,
            config: ""
        });
    }
}
