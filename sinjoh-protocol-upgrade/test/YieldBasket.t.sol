// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AddressGovernanceController } from "../src/governance/AddressGovernanceController.sol";
import { IGovernanceController } from "../src/interfaces/IGovernanceController.sol";
import { Governed } from "../src/governance/Governed.sol";
import { YieldBasket } from "../src/YieldBasket.sol";
import { SinjohTreasuryVault } from "@sinjoh-treasury/SinjohTreasuryVault.sol";
import { TestBase } from "./TestBase.sol";
import { MockERC20, MockFundable, MockRebasingERC20, MockYieldAdapter } from "./mocks/Mocks.sol";

contract YieldBasketTest is TestBase {
    address private constant GUARDIAN = address(0xBEEF);
    address private constant ALICE = address(0xA11CE);

    AddressGovernanceController private controller;
    MockERC20 private asset;
    MockERC20 private reward;
    MockFundable private sink;
    MockYieldAdapter private adapter;
    YieldBasket private basket;

    function setUp() public {
        controller =
            new AddressGovernanceController(address(this), IGovernanceController.Mode.INDIVIDUAL);
        asset = new MockERC20();
        reward = new MockERC20();
        sink = new MockFundable();
        adapter = new MockYieldAdapter(address(asset), reward);
        basket = new YieldBasket(controller, GUARDIAN, IERC20(address(asset)), address(sink));
        adapter.setBasket(address(basket));
        basket.configureAdapter(adapter, 5_000, 30 minutes);
        _setRoute(adapter, reward, sink, "");
    }

    function testHarvestDistributesOnlyFreshAllowlistedRewards() public {
        _fundAndAllocate(1_000e18, 500e18);
        adapter.setNextReward(50e18);
        vm.warp(block.timestamp + 30 minutes);
        basket.harvest(adapter);
        assertEq(sink.funded(address(reward)), 50e18);
        assertEq(basket.cumulativeRealizedYield(address(reward)), 50e18);
        assertEq(basket.managedPrincipal(), 1_000e18);
    }

    function testAdapterMustActuallyPullAllocatedPrincipal() public {
        asset.mint(address(this), 1_000e18);
        asset.approve(address(basket), 1_000e18);
        basket.fund(address(asset), 1_000e18, "");
        adapter.setPullFunds(false);
        vm.expectPartialRevert(YieldBasket.InexactTransfer.selector);
        basket.allocate(adapter, 500e18);
        assertEq(asset.balanceOf(address(basket)), 1_000e18);
        assertEq(basket.idlePrincipal(), 1_000e18);
    }

    function testDistributorMustActuallyPullHarvestedRewards() public {
        _fundAndAllocate(1_000e18, 500e18);
        sink.setPullFunds(false);
        adapter.setNextReward(50e18);
        vm.warp(block.timestamp + 30 minutes);
        vm.expectPartialRevert(YieldBasket.InexactTransfer.selector);
        basket.harvest(adapter);
        assertEq(reward.balanceOf(address(basket)), 0);
        assertEq(sink.funded(address(reward)), 0);
        assertEq(basket.cumulativeRealizedYield(address(reward)), 0);
    }

    function testRevertingAdapterAndDistributorCannotCorruptAccounting() public {
        _fundAndAllocate(1_000e18, 500e18);
        adapter.setReverts(false, true, false);
        vm.expectRevert();
        basket.withdrawFromAdapter(adapter, 500e18);
        YieldBasket.AdapterConfig memory config = basket.getAdapterConfig(address(adapter));
        assertEq(config.principalAllocated, 500e18);
        assertEq(basket.managedPrincipal(), 1_000e18);

        adapter.setReverts(false, false, false);
        sink.setShouldRevert(true);
        adapter.setNextReward(50e18);
        vm.warp(block.timestamp + 30 minutes);
        vm.expectRevert();
        basket.harvest(adapter);
        assertEq(basket.cumulativeRealizedYield(address(reward)), 0);
        assertEq(sink.funded(address(reward)), 0);
    }

    function testAdapterCapCannotBeReducedBelowExistingExposure() public {
        _fundAndAllocate(1_000e18, 500e18);
        vm.expectRevert(YieldBasket.AllocationLimitExceeded.selector);
        basket.configureAdapter(adapter, 4_999, 30 minutes);
    }

    function testAdapterCannotMislabelExistingBasketAssetsAsYield() public {
        _fundAndAllocate(1_000e18, 500e18);
        reward.mint(address(basket), 50e18);
        adapter.setMintReward(false);
        adapter.setNextReward(50e18);
        vm.warp(block.timestamp + 30 minutes);
        vm.expectPartialRevert(YieldBasket.InexactTransfer.selector);
        basket.harvest(adapter);
        assertEq(reward.balanceOf(address(basket)), 50e18);
        assertEq(sink.funded(address(reward)), 0);

        basket.recoverNonDepositAsset(IERC20(address(reward)), 50e18);
        assertEq(reward.balanceOf(address(basket)), 0);
        assertEq(reward.balanceOf(address(sink)), 50e18);
    }

    function testOnlyGovernanceCanRecoverNonDepositAssets() public {
        reward.mint(address(basket), 50e18);
        vm.prank(ALICE);
        vm.expectRevert(Governed.Unauthorized.selector);
        basket.recoverNonDepositAsset(IERC20(address(reward)), 50e18);
        assertEq(reward.balanceOf(address(basket)), 50e18);
    }

    function testDepositAssetCannotBeRecoveredThroughTokenEscapeHatch() public {
        asset.mint(address(basket), 50e18);
        vm.expectRevert(YieldBasket.InvalidConfiguration.selector);
        basket.recoverNonDepositAsset(IERC20(address(asset)), 50e18);
        assertEq(asset.balanceOf(address(basket)), 50e18);
    }

    function testDepositAssetCanNeverBeConfiguredAsHarvestedReward() public {
        YieldBasket.RewardRouteInput[] memory routes = new YieldBasket.RewardRouteInput[](1);
        routes[0] = YieldBasket.RewardRouteInput({
            rewardToken: address(asset), distributor: address(sink), distributionConfig: ""
        });
        vm.expectRevert(YieldBasket.InvalidConfiguration.selector);
        basket.setAdapterRewardRoutes(adapter, routes);
    }

    function testConfigureAdapterPreservesGuardianPause() public {
        vm.prank(GUARDIAN);
        basket.setAdapterStatus(adapter, YieldBasket.AdapterStatus.FULLY_PAUSED);
        basket.configureAdapter(adapter, 6_000, 1 hours);
        YieldBasket.AdapterConfig memory config = basket.getAdapterConfig(address(adapter));
        assertTrue(config.status == YieldBasket.AdapterStatus.FULLY_PAUSED);
        vm.expectRevert(YieldBasket.AdapterNotApproved.selector);
        basket.allocate(adapter, 1);
    }

    function testMultiRewardAdapterUsesTokenSpecificRoutes() public {
        MockERC20 secondReward = new MockERC20();
        MockFundable secondSink = new MockFundable();
        YieldBasket.RewardRouteInput[] memory routes = new YieldBasket.RewardRouteInput[](2);
        routes[0] = YieldBasket.RewardRouteInput({
            rewardToken: address(reward), distributor: address(sink), distributionConfig: hex"01"
        });
        routes[1] = YieldBasket.RewardRouteInput({
            rewardToken: address(secondReward),
            distributor: address(secondSink),
            distributionConfig: hex"02"
        });
        basket.setAdapterRewardRoutes(adapter, routes);
        YieldBasket.RewardRoute memory firstRoute =
            basket.getAdapterRewardRoute(address(adapter), address(reward));
        YieldBasket.RewardRoute memory secondRoute =
            basket.getAdapterRewardRoute(address(adapter), address(secondReward));
        assertEq(firstRoute.distributor, address(sink));
        assertEq(secondRoute.distributor, address(secondSink));
        assertTrue(keccak256(firstRoute.distributionConfig) == keccak256(hex"01"));
        assertTrue(keccak256(secondRoute.distributionConfig) == keccak256(hex"02"));
        _fundAndAllocate(1_000e18, 500e18);
        adapter.setNextReward(50e18);
        adapter.setSecondReward(secondReward, 25e18);
        vm.warp(block.timestamp + 30 minutes);
        basket.harvest(adapter);
        assertEq(sink.funded(address(reward)), 50e18);
        assertEq(secondSink.funded(address(secondReward)), 25e18);
        assertEq(sink.funded(address(secondReward)), 0);
        assertEq(secondSink.funded(address(reward)), 0);
    }

    function testFullyLostAdapterCanBeWrittenOffAndIdlePrincipalWithdrawn() public {
        _fundAndAllocate(1_000e18, 500e18);
        adapter.setWithdrawBps(0);
        vm.prank(GUARDIAN);
        basket.setAdapterStatus(adapter, YieldBasket.AdapterStatus.FULLY_PAUSED);
        basket.writeOffAdapter(adapter);

        YieldBasket.AdapterConfig memory config = basket.getAdapterConfig(address(adapter));
        assertEq(config.principalAllocated, 0);
        assertEq(config.sharesHeld, 0);
        assertEq(basket.writtenOffShares(address(adapter)), 500e18);
        assertEq(basket.managedPrincipal(), 500e18);
        assertEq(basket.cumulativeRealizedLoss(), 500e18);

        basket.removeAdapter(adapter);
        basket.withdrawIdlePrincipal(500e18);
        assertEq(asset.balanceOf(address(sink)), 500e18);
        assertEq(basket.managedPrincipal(), 0);

        vm.expectRevert(YieldBasket.InvalidConfiguration.selector);
        basket.configureAdapter(adapter, 5_000, 30 minutes);
        adapter.setWithdrawBps(10_000);
        basket.recoverWrittenOffShares(adapter, 500e18);
        assertEq(basket.writtenOffShares(address(adapter)), 0);
        assertEq(basket.idleUnrealizedValue(), 0);
        assertEq(asset.balanceOf(address(sink)), 1_000e18);
        basket.configureAdapter(adapter, 5_000, 30 minutes);
    }

    function testRemoveAdapterClearsRewardRoutesBeforeReapproval() public {
        basket.removeAdapter(adapter);
        assertEq(basket.getAdapterRewardTokens(address(adapter)).length, 0);
        assertEq(
            basket.getAdapterRewardRoute(address(adapter), address(reward)).distributor, address(0)
        );

        basket.configureAdapter(adapter, 5_000, 30 minutes);
        adapter.setNextReward(1e18);
        vm.warp(block.timestamp + 30 minutes);
        vm.expectRevert(YieldBasket.InvalidConfiguration.selector);
        basket.harvest(adapter);
    }

    function testLossReducesManagedPrincipalWithoutCreatingPhantomIdleFunds() public {
        _fundAndAllocate(1_000e18, 500e18);
        adapter.setWithdrawBps(5_000);
        basket.withdrawFromAdapter(adapter, 500e18);
        assertEq(basket.idlePrincipal(), 750e18);
        assertEq(basket.managedPrincipal(), 750e18);
        assertEq(basket.cumulativeRealizedLoss(), 250e18);
        assertEq(asset.balanceOf(address(basket)), 750e18);
        YieldBasket.AdapterConfig memory config = basket.getAdapterConfig(address(adapter));
        assertEq(config.principalAllocated, 0);
        assertEq(config.sharesHeld, 0);
    }

    function testGainStaysNonDistributableUntilGovernanceRealizesIt() public {
        _fundAndAllocate(1_000e18, 500e18);
        adapter.setWithdrawBps(12_000);
        basket.withdrawFromAdapter(adapter, 500e18);
        assertEq(basket.idlePrincipal(), 1_000e18);
        assertEq(basket.idleUnrealizedValue(), 100e18);
        basket.realizeIdleValue(100e18);
        assertEq(asset.balanceOf(address(sink)), 100e18);
        assertEq(basket.idleUnrealizedValue(), 0);
    }

    function testBasketValueReportsPrincipalAndUnrealizedChange() public {
        _fundAndAllocate(1_000e18, 500e18);
        (uint256 currentAssets, uint256 principal, uint256 gain, uint256 loss) =
            basket.basketValue();
        assertEq(currentAssets, 1_000e18);
        assertEq(principal, 1_000e18);
        assertEq(gain, 0);
        assertEq(loss, 0);

        adapter.setTotalAssets(400e18);
        (currentAssets, principal, gain, loss) = basket.basketValue();
        assertEq(currentAssets, 900e18);
        assertEq(principal, 1_000e18);
        assertEq(gain, 0);
        assertEq(loss, 100e18);
    }

    function testIdleWithdrawalCannotSilentlyBreakAllocationCap() public {
        _fundAndAllocate(1_000e18, 500e18);
        vm.expectRevert(YieldBasket.AllocationLimitExceeded.selector);
        basket.withdrawIdlePrincipal(1);
        basket.withdrawFromAdapter(adapter, 500e18);
        basket.withdrawIdlePrincipal(1_000e18);
        assertEq(asset.balanceOf(address(sink)), 1_000e18);
        assertEq(basket.managedPrincipal(), 0);
    }

    function testTreasuryTransferRegistersThenAllocatesWithoutAllowance() public {
        SinjohTreasuryVault vault = new SinjohTreasuryVault(address(this), 1 days, address(0), 0);
        YieldBasket treasuryBasket =
            new YieldBasket(controller, GUARDIAN, IERC20(address(asset)), address(vault));
        MockYieldAdapter treasuryAdapter = new MockYieldAdapter(address(asset), reward);
        treasuryAdapter.setBasket(address(treasuryBasket));
        treasuryBasket.configureAdapter(treasuryAdapter, 10_000, 30 minutes);

        asset.mint(address(vault), 1_000e18);
        treasuryBasket.prepareTreasuryFunding(1_000e18);
        vault.transfer(address(asset), 1_000e18, address(treasuryBasket));
        treasuryBasket.completeTreasuryFunding();
        treasuryBasket.allocate(treasuryAdapter, 1_000e18);

        assertEq(asset.allowance(address(vault), address(treasuryBasket)), 0);
        assertEq(treasuryBasket.managedPrincipal(), 1_000e18);
        assertEq(treasuryBasket.idlePrincipal(), 0);
    }

    function testUnsolicitedDepositCannotSatisfyTreasuryFundingSnapshot() public {
        SinjohTreasuryVault vault = new SinjohTreasuryVault(address(this), 1 days, address(0), 0);
        YieldBasket treasuryBasket =
            new YieldBasket(controller, GUARDIAN, IERC20(address(asset)), address(vault));
        asset.mint(address(vault), 1_000e18);
        asset.mint(ALICE, 1_000e18);

        treasuryBasket.prepareTreasuryFunding(1_000e18);
        vm.prank(ALICE);
        assertTrue(asset.transfer(address(treasuryBasket), 1_000e18));
        vm.expectPartialRevert(YieldBasket.TreasuryFundingMismatch.selector);
        treasuryBasket.completeTreasuryFunding();
        treasuryBasket.cancelTreasuryFunding();

        assertEq(treasuryBasket.managedPrincipal(), 0);
        assertEq(treasuryBasket.unregisteredDepositAssets(), 1_000e18);
        treasuryBasket.sweepUnregisteredDepositAsset(1_000e18);
        assertEq(asset.balanceOf(address(vault)), 2_000e18);
    }

    function testRebasingBalanceDriftRejectsTreasuryRegistration() public {
        MockRebasingERC20 rebasingAsset = new MockRebasingERC20();
        SinjohTreasuryVault vault = new SinjohTreasuryVault(address(this), 1 days, address(0), 0);
        YieldBasket treasuryBasket =
            new YieldBasket(controller, GUARDIAN, IERC20(address(rebasingAsset)), address(vault));
        rebasingAsset.mint(address(vault), 1_000e18);
        treasuryBasket.prepareTreasuryFunding(500e18);
        rebasingAsset.rebaseUp(address(vault), 1);
        vault.transfer(address(rebasingAsset), 500e18, address(treasuryBasket));
        vm.expectPartialRevert(YieldBasket.TreasuryFundingMismatch.selector);
        treasuryBasket.completeTreasuryFunding();
        assertEq(treasuryBasket.managedPrincipal(), 0);
    }

    function _fundAndAllocate(uint256 funded, uint128 allocated) private {
        asset.mint(address(this), funded);
        asset.approve(address(basket), funded);
        basket.fund(address(asset), funded, "");
        basket.allocate(adapter, allocated);
    }

    function _setRoute(
        MockYieldAdapter routeAdapter,
        MockERC20 routeReward,
        MockFundable distributor,
        bytes memory config
    ) private {
        YieldBasket.RewardRouteInput[] memory routes = new YieldBasket.RewardRouteInput[](1);
        routes[0] = YieldBasket.RewardRouteInput({
            rewardToken: address(routeReward),
            distributor: address(distributor),
            distributionConfig: config
        });
        basket.setAdapterRewardRoutes(routeAdapter, routes);
    }
}
