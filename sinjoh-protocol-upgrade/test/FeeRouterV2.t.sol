// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AddressGovernanceController } from "../src/governance/AddressGovernanceController.sol";
import { IGovernanceController } from "../src/interfaces/IGovernanceController.sol";
import { FeeRouterV2 } from "../src/FeeRouterV2.sol";
import { DynamicFundingBands } from "../src/DynamicFundingBands.sol";
import { SinjohStakingEngine } from "../src/SinjohStakingEngine.sol";
import { StakingEngine } from "../src/StakingEngine.sol";
import { TestBase } from "./TestBase.sol";
import { MockERC20, MockFundable, MockTwapOracle } from "./mocks/Mocks.sol";

contract FeeRouterV2Test is TestBase {
    address private constant GUARDIAN = address(0xBEEF);
    address private constant PROTOCOL = address(0xFEE);
    address private constant ALICE = address(0xA11CE);

    MockERC20 private token;
    FeeRouterV2 private router;
    AddressGovernanceController private controller;

    function setUp() public {
        controller =
            new AddressGovernanceController(address(this), IGovernanceController.Mode.INDIVIDUAL);
        token = new MockERC20();
        router = new FeeRouterV2(controller, GUARDIAN, PROTOCOL, 1 hours, 1 days);
    }

    function testSwapAndLiquidityRoutesUseExplicitFundableAdapters() public {
        MockFundable swapAdapter = new MockFundable();
        MockFundable liquidityAdapter = new MockFundable();
        FeeRouterV2.Route[] memory routes = new FeeRouterV2.Route[](2);
        routes[0] = FeeRouterV2.Route({
            inputToken: address(token),
            recipient: address(swapAdapter),
            shareBps: 6_000,
            action: FeeRouterV2.Action.SWAP_AND_SEND,
            config: abi.encode(uint256(123))
        });
        routes[1] = FeeRouterV2.Route({
            inputToken: address(token),
            recipient: address(liquidityAdapter),
            shareBps: 4_000,
            action: FeeRouterV2.Action.ADD_LIQUIDITY,
            config: abi.encode(uint256(456))
        });
        _activate(routes);
        token.mint(address(router), 10_000);
        router.sync(address(token));
        assertEq(swapAdapter.funded(address(token)), 5_940);
        assertEq(liquidityAdapter.funded(address(token)), 3_960);
        assertEq(token.balanceOf(PROTOCOL), 100);
    }

    function testFundableRouteMustActuallyConsumeApprovedFunds() public {
        MockFundable dishonestAdapter = new MockFundable();
        dishonestAdapter.setPullFunds(false);
        FeeRouterV2.Route[] memory routes = new FeeRouterV2.Route[](1);
        routes[0] = FeeRouterV2.Route({
            inputToken: address(token),
            recipient: address(dishonestAdapter),
            shareBps: 10_000,
            action: FeeRouterV2.Action.FUND_BASKET,
            config: ""
        });
        _activate(routes);
        token.mint(address(router), 10_000);
        vm.expectPartialRevert(FeeRouterV2.InexactTransfer.selector);
        router.sync(address(token));
        assertEq(token.balanceOf(address(router)), 10_000);
        assertEq(token.balanceOf(PROTOCOL), 0);
    }

    function testFundBandRouteUsesRuntimeAmountAsFullPrefunding() public {
        MockERC20 subject = new MockERC20();
        MockTwapOracle oracle = new MockTwapOracle();
        DynamicFundingBands bands =
            new DynamicFundingBands(controller, GUARDIAN, oracle, 1 hours, PROTOCOL);
        DynamicFundingBands.BandInput memory template = DynamicFundingBands.BandInput({
            subject: address(subject),
            fundingAsset: address(token),
            amount: 0,
            lowerPriceE18: 110e18,
            upperPriceE18: 120e18,
            activationDelay: 1 hours,
            lifetime: 7 days,
            confirmationPeriod: 5 minutes,
            twapWindow: 5 minutes,
            minimumDistanceBps: 500,
            recipient: ALICE,
            refundRecipient: address(router)
        });
        FeeRouterV2.Route[] memory routes = new FeeRouterV2.Route[](1);
        routes[0] = FeeRouterV2.Route({
            inputToken: address(token),
            recipient: address(bands),
            shareBps: 10_000,
            action: FeeRouterV2.Action.FUND_BAND,
            config: abi.encode(template)
        });
        _activate(routes);
        token.mint(address(router), 10_000);
        router.sync(address(token));
        DynamicFundingBands.FundingBand memory band = bands.getBand(1);
        assertEq(band.amount, 9_900);
        assertEq(token.balanceOf(address(bands)), 9_900);
        assertEq(bands.committedByAsset(address(token)), 9_900);
    }

    function testFundStakingRouteAppliesBothFeesAndFundsClaims() public {
        StakingEngine.LockTier[] memory tiers = new StakingEngine.LockTier[](1);
        tiers[0] = StakingEngine.LockTier({
            duration: 30 days, rewardWeightBps: 10_000, governanceWeightBps: 10_000, enabled: true
        });
        StakingEngine staking =
            new StakingEngine(controller, GUARDIAN, IERC20(address(token)), tiers);
        token.mint(ALICE, 100e18);
        vm.startPrank(ALICE);
        token.approve(address(staking), 100e18);
        staking.stake(100e18, 0);
        vm.stopPrank();
        vm.roll(block.number + 1);

        SinjohStakingEngine rewards =
            new SinjohStakingEngine(controller, GUARDIAN, staking, PROTOCOL);
        uint256 scheduleId = rewards.createSchedule(
            SinjohStakingEngine.ScheduleInput({
                rewardToken: address(token),
                interval: 30 minutes,
                claimPeriod: 1 days,
                permissionlessExecution: true,
                fixedExecutorReward: 0,
                executorRewardBps: 0,
                executorRewardCap: 0,
                unclaimedDestination: address(0xB0B)
            })
        );
        FeeRouterV2.Route[] memory routes = new FeeRouterV2.Route[](1);
        routes[0] = FeeRouterV2.Route({
            inputToken: address(token),
            recipient: address(rewards),
            shareBps: 10_000,
            action: FeeRouterV2.Action.FUND_AIRDROP,
            config: abi.encode(scheduleId)
        });
        _activate(routes);
        token.mint(address(router), 10_000);
        router.sync(address(token));

        SinjohStakingEngine.DistributionSchedule memory schedule = rewards.getSchedule(scheduleId);
        assertEq(token.balanceOf(PROTOCOL), 199);
        assertEq(schedule.pendingRewards, 9_801);
        assertEq(rewards.totalLiability(address(token)), 9_801);

        vm.warp(block.timestamp + 30 minutes);
        vm.roll(block.number + 1);
        rewards.executeEpoch(scheduleId);
        uint64[] memory epochIds = new uint64[](1);
        epochIds[0] = 1;
        vm.prank(ALICE);
        rewards.claim(scheduleId, epochIds);
        assertEq(token.balanceOf(ALICE), 9_801);
        assertEq(rewards.totalLiability(address(token)), 0);
    }

    function testGovernanceCanPauseAndResumeIndividualRoute() public {
        _activate(_directRoute());
        router.pauseRoute(0);
        token.mint(address(router), 10_000);
        vm.expectPartialRevert(FeeRouterV2.RoutePaused.selector);
        router.sync(address(token));
        assertEq(token.balanceOf(PROTOCOL), 0);
        assertEq(token.balanceOf(address(router)), 10_000);
        router.resumeRoute(0);
        router.sync(address(token));
        assertEq(token.balanceOf(ALICE), 9_900);
    }

    function testDirectRoutesRejectOpaqueConfigurationBytes() public {
        FeeRouterV2.Route[] memory routes = _directRoute();
        routes[0].config = hex"01";
        vm.expectRevert(FeeRouterV2.InvalidConfiguration.selector);
        router.proposeConfiguration(routes);
    }

    function testRollbackWindowExpires() public {
        uint256 firstId = _activate(_directRoute());
        FeeRouterV2.Route[] memory replacement = _directRoute();
        replacement[0].recipient = address(0xCAFE);
        uint256 secondId = router.proposeConfiguration(replacement);
        vm.warp(block.timestamp + 1 hours);
        router.activateConfiguration(secondId);
        vm.warp(block.timestamp + 1 days + 1);
        vm.expectRevert(FeeRouterV2.RollbackUnavailable.selector);
        router.rollbackConfiguration();
        assertEq(router.activeConfigurationId(), secondId);
        assertTrue(firstId != secondId);
    }

    function testAtomicConfigurationSupportsIndependentTokenShareSets() public {
        MockERC20 secondToken = new MockERC20();
        FeeRouterV2.Route[] memory routes = new FeeRouterV2.Route[](2);
        routes[0] = FeeRouterV2.Route({
            inputToken: address(token),
            recipient: ALICE,
            shareBps: 10_000,
            action: FeeRouterV2.Action.SEND,
            config: ""
        });
        routes[1] = FeeRouterV2.Route({
            inputToken: address(secondToken),
            recipient: ALICE,
            shareBps: 10_000,
            action: FeeRouterV2.Action.SEND,
            config: ""
        });
        _activate(routes);
        token.mint(address(router), 10_000);
        secondToken.mint(address(router), 20_000);
        router.sync(address(token));
        router.sync(address(secondToken));
        assertEq(token.balanceOf(ALICE), 9_900);
        assertEq(secondToken.balanceOf(ALICE), 19_800);
    }

    function _activate(FeeRouterV2.Route[] memory routes) private returns (uint256 configId) {
        configId = router.proposeConfiguration(routes);
        vm.warp(block.timestamp + 1 hours);
        router.activateConfiguration(configId);
    }

    function _directRoute() private view returns (FeeRouterV2.Route[] memory routes) {
        routes = new FeeRouterV2.Route[](1);
        routes[0] = FeeRouterV2.Route({
            inputToken: address(token),
            recipient: ALICE,
            shareBps: 10_000,
            action: FeeRouterV2.Action.SEND,
            config: ""
        });
    }
}
