// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ProjectLiquidityManagerV2 } from "../../src/liquidity/ProjectLiquidityManagerV2.sol";
import { ProjectRouterV2 } from "../../src/router/ProjectRouterV2.sol";
import {
    RouterAction,
    RouterActionType,
    RouterRouteInput,
    RouterSwapConfig,
    RouterSwapAndFundConfig
} from "../../src/router/RouterTypes.sol";
import { RouterTestBase } from "../RouterTestBase.sol";
import { MockReentrantController } from "../mocks/MockRouterIntegrations.sol";

contract ProjectRouterV2Test is RouterTestBase {
    function setUp() public {
        _setUpRouterDependencies();
    }

    function testConstructorPublishesIdentityAndInitialRouteForImmediateUse() public {
        ProjectRouterV2 router = _deployRouter(
            _singleRoute(address(assetA), _sendAction(RECIPIENT, 10_000)), bytes32(0)
        );
        assertEq(router.registry(), address(registry));
        assertEq(router.subject(), address(token));
        assertEq(router.projectId(), token.projectId());
        assertEq(router.controller(), address(projectController));
        assertEq(router.protocolFeeRecipient(), FEE_RECIPIENT);
        assertEq(router.activeRouteVersion(address(assetA)), 1);
        (ProjectRouterV2.RouteHeader memory header, RouterAction[] memory actions) =
            router.activeRoute(address(assetA));
        assertEq(header.version, 1);
        assertEq(header.activatedAt, START);
        assertEq(actions.length, 1);
        assertEq(actions[0].recipient, RECIPIENT);
    }

    function testConstructorBoundsInitialRouteSets() public {
        RouterRouteInput[] memory routes = new RouterRouteInput[](17);
        vm.expectPartialRevert(ProjectRouterV2.InvalidActionCount.selector);
        _deployRouter(routes, bytes32(0));
    }

    function testConstructorRejectsInitcodeRiskBeforeDeployment() public {
        RouterAction memory action = _sendAction(RECIPIENT, 10_000);
        action.actionConfig = new bytes(132_000);
        vm.expectPartialRevert(ProjectRouterV2.InitialRouteDataTooLarge.selector);
        _deployRouter(_singleRoute(address(assetA), action), bytes32(0));
    }

    function testRouteSupportsEveryUiBucketRecipientCombination() public {
        RouterRouteInput[] memory routes = new RouterRouteInput[](1);
        routes[0].inputAsset = address(assetA);
        routes[0].actions = new RouterAction[](80);
        for (uint256 i; i < 80; ++i) {
            routes[0].actions[i] = _sendAction(address(uint160(0x1000 + i)), 125);
        }
        ProjectRouterV2 router = _deployRouter(routes, bytes32(0));
        (, RouterAction[] memory actions) = router.activeRoute(address(assetA));
        assertEq(actions.length, 80);
    }

    function testExecutionCallbackCannotReenterGovernanceConfiguration() public {
        MockReentrantController reentrantController = new MockReentrantController(token.projectId());
        RouterAction memory action = _sendAction(address(reentrantController), 10_000);
        ProjectRouterV2 router = new ProjectRouterV2(
            address(registry),
            address(token),
            CREATOR,
            address(reentrantController),
            FEE_RECIPIENT,
            address(0),
            address(0),
            address(0),
            address(0),
            bytes32(0),
            _singleRoute(address(0), action)
        );
        reentrantController.configureReentry(
            address(router), abi.encodeCall(router.pauseAction, (address(0), 1, 0))
        );
        router.fund{ value: 1 ether }(token.projectId(), address(token), address(0), 1 ether, "");
        _execute(router, address(0), type(uint256).max);
        assertFalse(reentrantController.lastReentrySucceeded());
        assertFalse(router.actionPaused(address(0), 1, 0));
        assertEq(address(reentrantController).balance, 0.99 ether);
    }

    function testAttributedFundingChargesOnePercentAndExposesOneCallWorkStatus() public {
        ProjectRouterV2 router = _deployRouter(
            _singleRoute(address(assetA), _sendAction(RECIPIENT, 10_000)), bytes32(0)
        );
        _fund(router, address(assetA), 10_000);
        assertEq(router.pending(address(assetA)), 9_900);
        assertEq(router.protocolOwed(address(assetA)), 100);
        assertEq(router.totalLiability(address(assetA)), 10_000);
        (uint64 version, uint256 pendingAmount, uint256 escrowAmount, uint256 feeAmount) =
            router.workStatus(address(assetA));
        assertEq(version, 1);
        assertEq(pendingAmount, 9_900);
        assertEq(escrowAmount, 0);
        assertEq(feeAmount, 100);
    }

    function testNativeFundingAndExecutionAreExact() public {
        ProjectRouterV2 router =
            _deployRouter(_singleRoute(address(0), _sendAction(RECIPIENT, 10_000)), bytes32(0));
        vm.prank(HOLDER);
        router.fund{ value: 1 ether }(token.projectId(), address(token), address(0), 1 ether, "");
        uint256 beforeRecipient = RECIPIENT.balance;
        _execute(router, address(0), type(uint256).max);
        assertEq(RECIPIENT.balance - beforeRecipient, 0.99 ether);
        assertEq(router.protocolOwed(address(0)), 0.01 ether);
        assertEq(address(router).balance, 0.01 ether);
    }

    function testFeeRemainderMakesSplitFundingEqualSingleFunding() public {
        ProjectRouterV2 router = _deployRouter(
            _singleRoute(address(assetA), _sendAction(RECIPIENT, 10_000)), bytes32(0)
        );
        assetA.mint(HOLDER, 100);
        vm.startPrank(HOLDER);
        assetA.approve(address(router), 100);
        for (uint256 i; i < 100; ++i) {
            router.fund(token.projectId(), address(token), address(assetA), 1, "");
        }
        vm.stopPrank();
        assertEq(router.protocolOwed(address(assetA)), 1);
        assertEq(router.pending(address(assetA)), 99);
        assertEq(router.protocolFeeRemainder(address(assetA)), 0);
    }

    function testRawTransferSyncCreditsSurplusExactlyOnce() public {
        ProjectRouterV2 router = _deployRouter(
            _singleRoute(address(assetA), _sendAction(RECIPIENT, 10_000)), bytes32(0)
        );
        assetA.mint(address(router), 10_000);
        (uint256 surplus, uint256 net) = router.sync(address(assetA));
        assertEq(surplus, 10_000);
        assertEq(net, 9_900);
        vm.expectPartialRevert(ProjectRouterV2.NoSurplus.selector);
        router.sync(address(assetA));
    }

    function testFeeOnTransferFundingRevertsBeforeAccounting() public {
        ProjectRouterV2 router = _deployRouter(
            _singleRoute(address(assetA), _sendAction(RECIPIENT, 10_000)), bytes32(0)
        );
        assetA.setTransferFeeBps(100);
        assetA.mint(HOLDER, 10_000);
        vm.startPrank(HOLDER);
        assetA.approve(address(router), 10_000);
        bytes32 projectId = token.projectId();
        vm.expectPartialRevert(ProjectRouterV2.InexactAssetReceipt.selector);
        router.fund(projectId, address(token), address(assetA), 10_000, "");
        vm.stopPrank();
        assertEq(router.totalLiability(address(assetA)), 0);
        assertEq(assetA.balanceOf(address(router)), 0);
    }

    function testProtocolFeeDeliveryIsPermissionlessAndFixedRecipient() public {
        ProjectRouterV2 router = _deployRouter(
            _singleRoute(address(assetA), _sendAction(RECIPIENT, 10_000)), bytes32(0)
        );
        _fund(router, address(assetA), 10_000);
        vm.prank(address(0xBAD));
        assertEq(router.sendProtocolFee(address(assetA), 40), 40);
        assertEq(assetA.balanceOf(FEE_RECIPIENT), 40);
        assertEq(router.protocolOwed(address(assetA)), 60);
    }

    function testOnlyControllerCanActivatePauseAndResume() public {
        ProjectRouterV2 router = _deployRouter(
            _singleRoute(address(assetA), _sendAction(RECIPIENT, 10_000)), bytes32(0)
        );
        RouterRouteInput memory next =
            _singleRoute(address(assetA), _sendAction(CREATOR, 10_000))[0];
        vm.expectPartialRevert(ProjectRouterV2.OnlyController.selector);
        router.activateRoute(next);
        _controllerCall(router, abi.encodeCall(router.activateRoute, (next)));
        assertEq(router.activeRouteVersion(address(assetA)), 2);

        vm.expectPartialRevert(ProjectRouterV2.OnlyController.selector);
        router.pauseAction(address(assetA), 2, 0);
        _controllerCall(router, abi.encodeCall(router.pauseAction, (address(assetA), 2, 0)));
        assertTrue(router.actionPaused(address(assetA), 2, 0));
        _controllerCall(router, abi.encodeCall(router.resumeAction, (address(assetA), 2, 0)));
        assertFalse(router.actionPaused(address(assetA), 2, 0));
    }

    function testCumulativeAllocationCannotBeBiasedByTinyExecutions() public {
        RouterAction[] memory actions = new RouterAction[](2);
        actions[0] = _sendAction(CREATOR, 5_000);
        actions[1] = _sendAction(RECIPIENT, 5_000);
        RouterRouteInput[] memory routes = new RouterRouteInput[](1);
        routes[0] = RouterRouteInput({ inputAsset: address(assetA), actions: actions });
        ProjectRouterV2 router = _deployRouter(routes, bytes32(0));
        _fund(router, address(assetA), 101);
        for (uint256 i; i < 100; ++i) {
            _execute(router, address(assetA), 1);
        }
        assertEq(assetA.balanceOf(CREATOR), 50);
        assertEq(assetA.balanceOf(RECIPIENT), 50);
        assertEq(_allocated(router, address(assetA), 1, 0), 50);
        assertEq(_allocated(router, address(assetA), 1, 1), 50);
    }

    function testThreeActionCumulativeAllocationDoesNotUnderflowAcrossBatches() public {
        RouterAction[] memory actions = new RouterAction[](3);
        actions[0] = _sendAction(CREATOR, 3_000);
        actions[1] = _sendAction(RECIPIENT, 3_300);
        actions[2] = _sendAction(address(0xCAFE), 3_700);
        ProjectRouterV2 router = _deployRouter(_route(address(assetA), actions), bytes32(0));

        _fund(router, address(assetA), 13);
        _execute(router, address(assetA), 13);
        _fund(router, address(assetA), 1);

        uint256[] memory projected = router.projectedAllocations(address(assetA), 1, 1);
        assertEq(projected[0], 1);
        assertEq(projected[1], 0);
        assertEq(projected[2], 0);
        _execute(router, address(assetA), 1);
        assertEq(_allocated(router, address(assetA), 1, 0), 4);
        assertEq(_allocated(router, address(assetA), 1, 1), 5);
        assertEq(_allocated(router, address(assetA), 1, 2), 5);
    }

    function testOneRoutePaysCreatorTreasuryAirdropRaffleAndLiquidity() public {
        RouterAction[] memory actions = new RouterAction[](5);
        actions[0] = _sendAction(CREATOR, 2_000);
        actions[1] = _sinkAction(
            RouterActionType.FUND_TREASURY, address(treasury), 2_000, abi.encode(false)
        );
        actions[2] = _sinkAction(RouterActionType.FUND_AIRDROP, address(airdropSink), 2_000, "");
        actions[3] = _sinkAction(RouterActionType.FUND_RAFFLE, address(raffleSink), 2_000, "");
        actions[4] = _sinkAction(RouterActionType.ADD_LIQUIDITY, address(liquiditySink), 2_000, "");
        RouterRouteInput[] memory routes = new RouterRouteInput[](1);
        routes[0] = RouterRouteInput({ inputAsset: address(assetA), actions: actions });
        ProjectRouterV2 router = _deployRouter(routes, bytes32(0));
        _fund(router, address(assetA), 10_000);
        _execute(router, address(assetA), type(uint256).max);
        assertEq(assetA.balanceOf(CREATOR), 1_980);
        assertEq(treasury.accountedBalance(address(assetA)), 1_980);
        assertEq(airdropSink.funded(address(assetA)), 1_980);
        assertEq(raffleSink.funded(address(assetA)), 1_980);
        assertEq(liquiditySink.funded(address(assetA)), 1_980);
        assertEq(router.pending(address(assetA)), 0);
        assertEq(router.totalEscrowed(address(assetA)), 0);
    }

    function testLiquidityFeeDestinationsMaterializeWithoutRawProjectAddresses() public {
        ProjectLiquidityManagerV2.Config memory config = ProjectLiquidityManagerV2.Config({
            venue: ProjectLiquidityManagerV2.Venue.UNISWAP_V3,
            quoteAsset: address(assetA),
            poolFee: 3_000,
            tickSpacing: 60,
            hooks: address(0),
            swapAdapter: address(adapter),
            priceGuard: address(priceGuard),
            swapRouteData: hex"01",
            quoteSwapBps: 5_000,
            maxMintSlippageBps: 100,
            minNotionalPerMint: 1,
            maxNotionalPerMint: type(uint128).max,
            minMintInterval: 0,
            feeMode: ProjectLiquidityManagerV2.FeeMode.CREATOR,
            feeRecipient: address(0)
        });
        ProjectLiquidityManagerV2.FundingConfig memory funding =
            ProjectLiquidityManagerV2.FundingConfig({
                config: config, integrationApprovalProof: new bytes32[](0)
            });
        RouterAction memory action = _sinkAction(
            RouterActionType.ADD_LIQUIDITY, address(liquiditySink), 10_000, abi.encode(funding)
        );
        ProjectRouterV2 router = _deployRouter(_singleRoute(address(assetA), action), bytes32(0));
        funding = abi.decode(
            _action(router, address(assetA), 1, 0).actionConfig,
            (ProjectLiquidityManagerV2.FundingConfig)
        );
        assertEq(funding.config.feeRecipient, CREATOR);

        funding.config.feeMode = ProjectLiquidityManagerV2.FeeMode.TREASURY;
        funding.config.feeRecipient = address(0);
        action.actionConfig = abi.encode(funding);
        RouterRouteInput memory next = _singleRoute(address(assetA), action)[0];
        _controllerCall(router, abi.encodeCall(router.activateRoute, (next)));
        funding = abi.decode(
            _action(router, address(assetA), 2, 0).actionConfig,
            (ProjectLiquidityManagerV2.FundingConfig)
        );
        assertEq(funding.config.feeRecipient, address(treasury));
    }

    function testRevertingActionEscrowsOnlyItsShareAndOtherActionSettles() public {
        RouterAction[] memory actions = new RouterAction[](2);
        actions[0] = _sinkAction(RouterActionType.FUND_AIRDROP, address(airdropSink), 5_000, "");
        actions[1] = _sendAction(RECIPIENT, 5_000);
        ProjectRouterV2 router = _deployRouter(_route(address(assetA), actions), bytes32(0));
        airdropSink.setBehavior(true, false, 0);
        _fund(router, address(assetA), 10_000);
        _execute(router, address(assetA), type(uint256).max);
        assertEq(router.escrowed(address(assetA), 1, 0), 4_950);
        assertEq(router.totalEscrowed(address(assetA)), 4_950);
        assertEq(assetA.balanceOf(RECIPIENT), 4_950);
        assertEq(router.totalLiability(address(assetA)), 5_050);
    }

    function testPermissionlessRetryPreservesFailureThenSettlesExactEscrow() public {
        ProjectRouterV2 router = _failingAirdropRouter();
        _fund(router, address(assetA), 10_000);
        _execute(router, address(assetA), type(uint256).max);
        (, bool firstSucceeded) = router.retryEscrow(address(assetA), 1, 0, 4_000, 0, "");
        assertFalse(firstSucceeded);
        assertEq(router.escrowed(address(assetA), 1, 0), 9_900);
        airdropSink.setBehavior(false, false, 0);
        vm.prank(address(0xBAD));
        (uint256 amount, bool succeeded) =
            router.retryEscrow(address(assetA), 1, 0, type(uint256).max, 0, "");
        assertTrue(succeeded);
        assertEq(amount, 9_900);
        assertEq(airdropSink.funded(address(assetA)), 9_900);
        assertEq(router.totalEscrowed(address(assetA)), 0);
    }

    function testHugeRevertPayloadCannotBreakBatchFailureIsolation() public {
        RouterAction[] memory actions = new RouterAction[](2);
        actions[0] = _sinkAction(RouterActionType.FUND_AIRDROP, address(airdropSink), 5_000, "");
        actions[1] = _sendAction(RECIPIENT, 5_000);
        ProjectRouterV2 router = _deployRouter(_route(address(assetA), actions), bytes32(0));
        airdropSink.setBehavior(true, false, 32_768);
        _fund(router, address(assetA), 10_000);
        _execute(router, address(assetA), type(uint256).max);
        assertEq(router.escrowed(address(assetA), 1, 0), 4_950);
        assertEq(assetA.balanceOf(RECIPIENT), 4_950);
    }

    function testPausedActionEscrowsNewShareAndHistoricalPauseBlocksRetry() public {
        ProjectRouterV2 router = _failingAirdropRouter();
        _controllerCall(router, abi.encodeCall(router.pauseAction, (address(assetA), 1, 0)));
        _fund(router, address(assetA), 10_000);
        _execute(router, address(assetA), type(uint256).max);
        assertEq(router.escrowed(address(assetA), 1, 0), 9_900);
        RouterRouteInput memory next =
            _singleRoute(address(assetA), _sendAction(RECIPIENT, 10_000))[0];
        _controllerCall(router, abi.encodeCall(router.activateRoute, (next)));
        vm.expectPartialRevert(ProjectRouterV2.ActionIsPaused.selector);
        router.retryEscrow(address(assetA), 1, 0, 1, 0, "");
    }

    function testRouteReplacementCannotChangeOldEscrowAndRecoveryRekeysToActiveAction() public {
        ProjectRouterV2 router = _failingAirdropRouter();
        _fund(router, address(assetA), 10_000);
        _execute(router, address(assetA), type(uint256).max);
        RouterRouteInput memory next =
            _singleRoute(address(assetA), _sendAction(RECIPIENT, 10_000))[0];
        _controllerCall(router, abi.encodeCall(router.activateRoute, (next)));
        assertEq(router.escrowed(address(assetA), 1, 0), 9_900);
        vm.expectPartialRevert(ProjectRouterV2.StaleRouteEscrow.selector);
        router.retryEscrow(address(assetA), 1, 0, type(uint256).max, 0, "");
        _controllerCall(
            router, abi.encodeCall(router.recoverEscrow, (address(assetA), 1, 0, 4_000, 0))
        );
        assertEq(router.escrowed(address(assetA), 1, 0), 5_900);
        assertEq(router.escrowed(address(assetA), 2, 0), 4_000);
        router.retryEscrow(address(assetA), 2, 0, type(uint256).max, 0, "");
        assertEq(assetA.balanceOf(RECIPIENT), 4_000);
    }

    function testApprovedSwapUsesStrongerCallerMinimumAndSendsMeasuredOutput() public {
        bytes32 root = _swapLeaf(address(assetA), address(assetB));
        RouterSwapConfig memory config = RouterSwapConfig({
            outputAsset: address(assetB),
            maxAmountInPerCall: type(uint128).max,
            routeData: ROUTE_DATA,
            approvalProof: new bytes32[](0)
        });
        RouterAction memory action = RouterAction({
            actionType: RouterActionType.SWAP_AND_SEND,
            allocationBps: 10_000,
            recipient: RECIPIENT,
            adapter: address(adapter),
            priceGuard: address(priceGuard),
            actionConfig: abi.encode(config)
        });
        ProjectRouterV2 router = _deployRouter(_singleRoute(address(assetA), action), root);
        assertTrue(router.isSwapApproved(address(adapter), address(priceGuard), new bytes32[](0)));
        assertFalse(router.isSwapApproved(address(token), address(priceGuard), new bytes32[](0)));
        assetB.mint(address(adapter), 5_000);
        adapter.configure(5_000, type(uint256).max, false);
        priceGuard.setQuote(4_000, 2_000_000);
        _fund(router, address(assetA), 10_000);
        uint256[] memory minima = new uint256[](1);
        minima[0] = 4_500;
        router.execute(address(assetA), type(uint256).max, minima, new bytes[](1));
        assertEq(assetB.balanceOf(RECIPIENT), 5_000);
        assertEq(assetA.allowance(address(router), address(adapter)), 0);
    }

    function testExecuteAutomaticallyChunksAtTheImmutableSwapCap() public {
        bytes32 root = _swapLeaf(address(assetA), address(assetB));
        RouterSwapConfig memory config = RouterSwapConfig({
            outputAsset: address(assetB),
            maxAmountInPerCall: 1_000,
            routeData: ROUTE_DATA,
            approvalProof: new bytes32[](0)
        });
        RouterAction memory action = RouterAction({
            actionType: RouterActionType.SWAP_AND_SEND,
            allocationBps: 10_000,
            recipient: RECIPIENT,
            adapter: address(adapter),
            priceGuard: address(priceGuard),
            actionConfig: abi.encode(config)
        });
        ProjectRouterV2 router = _deployRouter(_singleRoute(address(assetA), action), root);
        assetB.mint(address(adapter), 1_000);
        adapter.configure(1_000, 1_000, false);
        priceGuard.setQuote(1, 2_000_000);
        _fund(router, address(assetA), 10_000);

        assertEq(router.maximumExecutableAmount(address(assetA), 1), 1_000);
        uint256 executed =
            router.execute(address(assetA), type(uint256).max, new uint256[](1), new bytes[](1));
        assertEq(executed, 1_000);
        assertEq(router.pending(address(assetA)), 8_900);
        assertEq(assetB.balanceOf(RECIPIENT), 1_000);
    }

    function testZeroSenderCanQuoteExactActionOutputButOnchainCallerCannot() public {
        bytes32 root = _swapLeaf(address(assetA), address(assetB));
        RouterSwapConfig memory config = RouterSwapConfig({
            outputAsset: address(assetB),
            maxAmountInPerCall: type(uint128).max,
            routeData: ROUTE_DATA,
            approvalProof: new bytes32[](0)
        });
        RouterAction memory action = RouterAction({
            actionType: RouterActionType.SWAP_AND_SEND,
            allocationBps: 10_000,
            recipient: RECIPIENT,
            adapter: address(adapter),
            priceGuard: address(priceGuard),
            actionConfig: abi.encode(config)
        });
        ProjectRouterV2 router = _deployRouter(_singleRoute(address(assetA), action), root);
        assetB.mint(address(adapter), 5_000);
        adapter.configure(5_000, type(uint256).max, false);
        priceGuard.setQuote(1, 2_000_000);
        _fund(router, address(assetA), 10_000);

        vm.expectPartialRevert(ProjectRouterV2.OnlyQuoteSimulation.selector);
        router.quoteAction(address(assetA), 1, 0, 9_900, 0, "");

        vm.prank(address(0));
        (address outputAsset, uint256 amountOut) =
            router.quoteAction(address(assetA), 1, 0, 9_900, 0, "");
        assertEq(outputAsset, address(assetB));
        assertEq(amountOut, 5_000);
    }

    function testQuoteCannotSpendMoreThanPendingAndActionEscrow() public {
        ProjectRouterV2 router = _deployRouter(
            _singleRoute(address(assetA), _sendAction(RECIPIENT, 10_000)), bytes32(0)
        );
        _fund(router, address(assetA), 10_000);
        vm.prank(address(0));
        vm.expectPartialRevert(ProjectRouterV2.InvalidAmount.selector);
        router.quoteAction(address(assetA), 1, 0, 9_901, 0, "");

        _controllerCall(router, abi.encodeCall(router.pauseAction, (address(assetA), 1, 0)));
        router.execute(address(assetA), type(uint256).max, new uint256[](1), new bytes[](1));
        _controllerCall(router, abi.encodeCall(router.resumeAction, (address(assetA), 1, 0)));

        vm.prank(address(0));
        (address outputAsset, uint256 amountOut) =
            router.quoteAction(address(assetA), 1, 0, 9_900, 0, "");
        assertEq(outputAsset, address(assetA));
        assertEq(amountOut, 9_900);

        vm.prank(address(0));
        vm.expectPartialRevert(ProjectRouterV2.InvalidAmount.selector);
        router.quoteAction(address(assetA), 1, 0, 9_901, 0, "");
    }

    function testApprovedNormalizationCreditsExistingOutputRouteWithoutSecondProtocolFee() public {
        bytes32 root = _swapLeaf(address(assetA), address(assetB));
        RouterSwapConfig memory config = RouterSwapConfig({
            outputAsset: address(assetB),
            maxAmountInPerCall: type(uint128).max,
            routeData: ROUTE_DATA,
            approvalProof: new bytes32[](0)
        });
        RouterAction memory normalize = RouterAction({
            actionType: RouterActionType.NORMALIZE_TO_ROUTE,
            allocationBps: 10_000,
            recipient: address(0),
            adapter: address(adapter),
            priceGuard: address(priceGuard),
            actionConfig: abi.encode(config)
        });
        RouterRouteInput[] memory routes = new RouterRouteInput[](2);
        routes[0] = _singleRoute(address(assetB), _sendAction(RECIPIENT, 10_000))[0];
        routes[1] = _singleRoute(address(assetA), normalize)[0];
        ProjectRouterV2 router = _deployRouter(routes, root);

        assetB.mint(address(adapter), 5_000);
        adapter.configure(5_000, type(uint256).max, false);
        priceGuard.setQuote(4_000, 2_000_000);
        _fund(router, address(assetA), 10_000);
        _execute(router, address(assetA), type(uint256).max);

        assertEq(router.pending(address(assetA)), 0);
        assertEq(router.protocolOwed(address(assetA)), 100);
        assertEq(router.pending(address(assetB)), 5_000);
        assertEq(router.protocolOwed(address(assetB)), 0);
        assertTrue(router.isAssetBacked(address(assetA)));
        assertTrue(router.isAssetBacked(address(assetB)));

        _execute(router, address(assetB), type(uint256).max);
        assertEq(assetB.balanceOf(RECIPIENT), 5_000);
        assertEq(router.pending(address(assetB)), 0);
    }

    function testNormalizationRejectsAnOutputWithoutAnExistingRoute() public {
        bytes32 root = _swapLeaf(address(assetA), address(assetB));
        RouterSwapConfig memory config = RouterSwapConfig({
            outputAsset: address(assetB),
            maxAmountInPerCall: type(uint128).max,
            routeData: ROUTE_DATA,
            approvalProof: new bytes32[](0)
        });
        RouterAction memory normalize = RouterAction({
            actionType: RouterActionType.NORMALIZE_TO_ROUTE,
            allocationBps: 10_000,
            recipient: address(0),
            adapter: address(adapter),
            priceGuard: address(priceGuard),
            actionConfig: abi.encode(config)
        });
        vm.expectPartialRevert(ProjectRouterV2.NoActiveRoute.selector);
        _deployRouter(_singleRoute(address(assetA), normalize), root);
    }

    function testApprovedSwapCanFundTreasuryWithConvertedAsset() public {
        bytes32 root = _swapLeaf(address(assetA), address(assetB));
        RouterSwapAndFundConfig memory config = RouterSwapAndFundConfig({
            outputAsset: address(assetB),
            maxAmountInPerCall: type(uint128).max,
            routeData: ROUTE_DATA,
            approvalProof: new bytes32[](0),
            fundingConfig: abi.encode(false)
        });
        RouterAction memory action = RouterAction({
            actionType: RouterActionType.SWAP_AND_FUND_TREASURY,
            allocationBps: 10_000,
            recipient: address(treasury),
            adapter: address(adapter),
            priceGuard: address(priceGuard),
            actionConfig: abi.encode(config)
        });
        ProjectRouterV2 router = _deployRouter(_singleRoute(address(assetA), action), root);
        assetB.mint(address(adapter), 5_000);
        adapter.configure(5_000, type(uint256).max, false);
        priceGuard.setExpectedSubject(address(token));
        priceGuard.setQuote(4_000, 2_000_000);
        _fund(router, address(assetA), 10_000);
        _execute(router, address(assetA), type(uint256).max);
        assertEq(treasury.accountedBalance(address(assetB)), 5_000);
        assertEq(assetA.allowance(address(router), address(adapter)), 0);
        assertEq(assetB.allowance(address(router), address(treasury)), 0);
    }

    function testApprovedSwapCanFundAirdropWithConvertedAsset() public {
        bytes32 root = _swapLeaf(address(assetA), address(assetB));
        RouterSwapAndFundConfig memory config = RouterSwapAndFundConfig({
            outputAsset: address(assetB),
            maxAmountInPerCall: type(uint128).max,
            routeData: ROUTE_DATA,
            approvalProof: new bytes32[](0),
            fundingConfig: hex"aabb"
        });
        RouterAction memory action = RouterAction({
            actionType: RouterActionType.SWAP_AND_FUND_AIRDROP,
            allocationBps: 10_000,
            recipient: address(airdropSink),
            adapter: address(adapter),
            priceGuard: address(priceGuard),
            actionConfig: abi.encode(config)
        });
        ProjectRouterV2 router = _deployRouter(_singleRoute(address(assetA), action), root);
        assetB.mint(address(adapter), 7_000);
        adapter.configure(7_000, type(uint256).max, false);
        priceGuard.setExpectedSubject(address(token));
        priceGuard.setQuote(6_000, 2_000_000);
        _fund(router, address(assetA), 10_000);
        _execute(router, address(assetA), type(uint256).max);
        assertEq(airdropSink.funded(address(assetB)), 7_000);
        assertEq(assetA.allowance(address(router), address(adapter)), 0);
        assertEq(assetB.allowance(address(router), address(airdropSink)), 0);
    }

    function testUnderOutputSwapEscrowsInputInsteadOfLosingIt() public {
        bytes32 root = _swapLeaf(address(assetA), address(assetB));
        RouterSwapConfig memory config =
            RouterSwapConfig(address(assetB), type(uint128).max, ROUTE_DATA, new bytes32[](0));
        RouterAction memory action = RouterAction(
            RouterActionType.SWAP_AND_SEND,
            10_000,
            RECIPIENT,
            address(adapter),
            address(priceGuard),
            abi.encode(config)
        );
        ProjectRouterV2 router = _deployRouter(_singleRoute(address(assetA), action), root);
        assetB.mint(address(adapter), 3_000);
        adapter.configure(3_000, type(uint256).max, false);
        priceGuard.setQuote(4_000, 2_000_000);
        _fund(router, address(assetA), 10_000);
        _execute(router, address(assetA), type(uint256).max);
        assertEq(router.escrowed(address(assetA), 1, 0), 9_900);
        assertEq(assetA.balanceOf(address(router)), 10_000);
        assertEq(assetB.balanceOf(address(router)), 0);
    }

    function testDirectBurnRouteReducesTrueProjectSupply() public {
        RouterAction memory action = RouterAction(
            RouterActionType.BURN_PROJECT_TOKEN, 10_000, address(0), address(0), address(0), ""
        );
        ProjectRouterV2 router = _deployRouter(_singleRoute(address(token), action), bytes32(0));
        uint256 supplyBefore = token.totalSupply();
        _fund(router, address(token), 1_000e18);
        _execute(router, address(token), type(uint256).max);
        assertEq(supplyBefore - token.totalSupply(), 990e18);
        assertEq(token.balanceOf(token.BURN_ADDRESS()), 0);
    }

    function testTreasuryActionUsesTypedDepositAndLeavesNoAllowance() public {
        RouterAction memory action = _sinkAction(
            RouterActionType.FUND_TREASURY, address(treasury), 10_000, abi.encode(false)
        );
        ProjectRouterV2 router = _deployRouter(_singleRoute(address(assetA), action), bytes32(0));
        _fund(router, address(assetA), 10_000);
        _execute(router, address(assetA), type(uint256).max);
        assertEq(treasury.accountedBalance(address(assetA)), 9_900);
        assertEq(assetA.allowance(address(router), address(treasury)), 0);
    }

    function testApprovedRegisteredProjectSinkUsesOnlyTypedFundSelector() public {
        RouterAction memory action = _sinkAction(
            RouterActionType.FUND_PROJECT_SINK, address(airdropSink), 10_000, hex"aabb"
        );
        ProjectRouterV2 router = _deployRouter(_singleRoute(address(assetA), action), bytes32(0));
        assertFalse(router.isSinkApproved(address(airdropSink)));
        _registerRouterAndAirdrop(router);
        assertTrue(router.isSinkApproved(address(airdropSink)));
        assertFalse(router.isSinkApproved(address(raffleSink)));
        _fund(router, address(assetA), 10_000);
        _execute(router, address(assetA), type(uint256).max);
        assertEq(airdropSink.funded(address(assetA)), 9_900);
    }

    function testActionStatusReturnsAllFrontendWorkFieldsInOneCall() public {
        ProjectRouterV2 router = _failingAirdropRouter();
        _fund(router, address(assetA), 10_000);
        _execute(router, address(assetA), type(uint256).max);
        (
            RouterAction memory action,
            bool paused,
            uint256 cumulativeAllocation,
            uint256 retryableEscrow
        ) = router.actionStatus(address(assetA), 1, 0);
        assertEq(uint256(action.actionType), uint256(RouterActionType.FUND_AIRDROP));
        assertFalse(paused);
        assertEq(cumulativeAllocation, 9_900);
        assertEq(retryableEscrow, 9_900);
    }

    function testInvalidRoutesRejectBadTotalsBurnRecipientAndUnapprovedSwap() public {
        RouterAction[] memory actions = new RouterAction[](1);
        actions[0] = _sendAction(RECIPIENT, 9_999);
        vm.expectPartialRevert(ProjectRouterV2.InvalidAllocationTotal.selector);
        _deployRouter(_route(address(assetA), actions), bytes32(0));

        actions[0] = RouterAction(
            RouterActionType.BURN_PROJECT_TOKEN, 10_000, RECIPIENT, address(0), address(0), ""
        );
        vm.expectPartialRevert(ProjectRouterV2.InvalidRecipient.selector);
        _deployRouter(_route(address(token), actions), bytes32(0));

        RouterSwapConfig memory config =
            RouterSwapConfig(address(assetB), type(uint128).max, ROUTE_DATA, new bytes32[](0));
        actions[0] = RouterAction(
            RouterActionType.SWAP_AND_SEND,
            10_000,
            RECIPIENT,
            address(adapter),
            address(priceGuard),
            abi.encode(config)
        );
        vm.expectPartialRevert(ProjectRouterV2.IntegrationNotApproved.selector);
        _deployRouter(_route(address(assetA), actions), bytes32(uint256(123)));
    }

    function testFundingRejectsWrongProjectSubjectAndNonemptyConfig() public {
        ProjectRouterV2 router = _deployRouter(
            _singleRoute(address(assetA), _sendAction(RECIPIENT, 10_000)), bytes32(0)
        );
        assetA.mint(HOLDER, 100);
        vm.startPrank(HOLDER);
        assetA.approve(address(router), 100);
        vm.expectPartialRevert(ProjectRouterV2.InvalidFundingIdentity.selector);
        router.fund(bytes32(uint256(123)), address(token), address(assetA), 100, "");
        bytes32 projectId = token.projectId();
        vm.expectPartialRevert(ProjectRouterV2.InvalidFundingConfig.selector);
        router.fund(projectId, address(token), address(assetA), 100, hex"01");
        vm.stopPrank();
    }

    function _failingAirdropRouter() private returns (ProjectRouterV2 router) {
        RouterAction memory action =
            _sinkAction(RouterActionType.FUND_AIRDROP, address(airdropSink), 10_000, "");
        router = _deployRouter(_singleRoute(address(assetA), action), bytes32(0));
        airdropSink.setBehavior(true, false, 0);
    }

    function _sinkAction(
        RouterActionType actionType,
        address recipient,
        uint16 bps,
        bytes memory config
    ) private pure returns (RouterAction memory) {
        return RouterAction(actionType, bps, recipient, address(0), address(0), config);
    }

    function _action(ProjectRouterV2 router, address asset, uint64 version, uint256 index)
        private
        view
        returns (RouterAction memory action)
    {
        (action,,,) = router.actionStatus(asset, version, index);
    }

    function _allocated(ProjectRouterV2 router, address asset, uint64 version, uint256 index)
        private
        view
        returns (uint256 cumulativeAllocation)
    {
        (,, cumulativeAllocation,) = router.actionStatus(asset, version, index);
    }

    function _route(address asset, RouterAction[] memory actions)
        private
        pure
        returns (RouterRouteInput[] memory routes)
    {
        routes = new RouterRouteInput[](1);
        routes[0] = RouterRouteInput({ inputAsset: asset, actions: actions });
    }
}
