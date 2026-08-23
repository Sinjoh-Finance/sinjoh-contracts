// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ProjectRouterV2 } from "../../src/router/ProjectRouterV2.sol";
import { RouterAction, RouterActionType, RouterRouteInput } from "../../src/router/RouterTypes.sol";
import { RouterTestBase } from "../RouterTestBase.sol";

contract ProjectRouterV2FuzzTest is RouterTestBase {
    function setUp() public {
        _setUpRouterDependencies();
    }

    function testFuzzCumulativeFeeEqualsOnePercentOfTotal(uint128 rawFirst, uint128 rawSecond)
        public
    {
        uint256 first = bound(uint256(rawFirst), 1, 1_000_000e18);
        uint256 second = bound(uint256(rawSecond), 1, 1_000_000e18);
        ProjectRouterV2 router = _deployRouter(
            _singleRoute(address(assetA), _sendAction(RECIPIENT, 10_000)), bytes32(0)
        );
        assetA.mint(HOLDER, first + second);
        vm.startPrank(HOLDER);
        assetA.approve(address(router), first + second);
        router.fund(token.projectId(), address(token), address(assetA), first, "");
        router.fund(token.projectId(), address(token), address(assetA), second, "");
        vm.stopPrank();
        uint256 expectedFee = (first + second) / 100;
        assertEq(router.protocolOwed(address(assetA)), expectedFee);
        assertEq(router.pending(address(assetA)), first + second - expectedFee);
    }

    function testFuzzProjectedAllocationsAlwaysSumToExactBatch(
        uint16 rawFirstBps,
        uint16 rawSecondBps,
        uint128 rawAmount
    ) public {
        uint16 firstBps = uint16(bound(uint256(rawFirstBps), 1, 9_998));
        uint16 secondBps = uint16(bound(uint256(rawSecondBps), 1, 9_999 - firstBps));
        uint16 thirdBps = 10_000 - firstBps - secondBps;
        RouterAction[] memory actions = new RouterAction[](3);
        actions[0] = _sendAction(CREATOR, firstBps);
        actions[1] = _sendAction(RECIPIENT, secondBps);
        actions[2] = _sendAction(address(0xCAFE), thirdBps);
        RouterRouteInput[] memory routes = new RouterRouteInput[](1);
        routes[0] = RouterRouteInput(address(assetA), actions);
        ProjectRouterV2 router = _deployRouter(routes, bytes32(0));
        uint256 amount = bound(uint256(rawAmount), 1, 1_000_000e18);
        uint256[] memory projected = router.projectedAllocations(address(assetA), 1, amount);
        assertEq(projected[0] + projected[1] + projected[2], amount);
    }

    function testFuzzThreeActionMultiBatchAllocationsStayLiveAndExact(
        uint16 rawFirstBps,
        uint16 rawSecondBps,
        uint64 rawFirstGross,
        uint64 rawSecondGross
    ) public {
        uint16 firstBps = uint16(bound(uint256(rawFirstBps), 1, 9_998));
        uint16 secondBps = uint16(bound(uint256(rawSecondBps), 1, 9_999 - firstBps));
        RouterAction[] memory actions = new RouterAction[](3);
        actions[0] = _sendAction(CREATOR, firstBps);
        actions[1] = _sendAction(RECIPIENT, secondBps);
        actions[2] = _sendAction(address(0xCAFE), 10_000 - firstBps - secondBps);
        RouterRouteInput[] memory routes = new RouterRouteInput[](1);
        routes[0] = RouterRouteInput(address(assetA), actions);
        ProjectRouterV2 router = _deployRouter(routes, bytes32(0));

        _fund(router, address(assetA), bound(uint256(rawFirstGross), 1, 1e18));
        _execute(router, address(assetA), type(uint256).max);
        _fund(router, address(assetA), bound(uint256(rawSecondGross), 2, 1e18));
        uint256 secondBatch = router.pending(address(assetA));
        uint256[] memory projected = router.projectedAllocations(address(assetA), 1, secondBatch);
        assertEq(projected[0] + projected[1] + projected[2], secondBatch);
        _execute(router, address(assetA), type(uint256).max);

        ProjectRouterV2.RouteHeader memory header = router.routeHeader(address(assetA), 1);
        assertEq(
            router.allocatedToAction(address(assetA), 1, 0)
                + router.allocatedToAction(address(assetA), 1, 1)
                + router.allocatedToAction(address(assetA), 1, 2),
            header.totalRouted
        );
    }

    function testFuzzExactSendConservesNetAndFee(uint128 rawGross) public {
        uint256 gross = bound(uint256(rawGross), 1, 1_000_000e18);
        ProjectRouterV2 router = _deployRouter(
            _singleRoute(address(assetA), _sendAction(RECIPIENT, 10_000)), bytes32(0)
        );
        _fund(router, address(assetA), gross);
        uint256 net = gross - gross / 100;
        _execute(router, address(assetA), type(uint256).max);
        assertEq(assetA.balanceOf(RECIPIENT), net);
        assertEq(assetA.balanceOf(address(router)), gross / 100);
        assertEq(router.protocolOwed(address(assetA)), gross / 100);
    }

    function testFuzzFailedActionEscrowsItsExactNetShare(uint128 rawGross, uint16 rawBps) public {
        uint256 gross = bound(uint256(rawGross), 100, 1_000_000e18);
        uint16 failedBps = uint16(bound(uint256(rawBps), 1, 9_999));
        RouterAction[] memory actions = new RouterAction[](2);
        actions[0] = RouterAction(
            RouterActionType.FUND_AIRDROP,
            failedBps,
            address(airdropSink),
            address(0),
            address(0),
            ""
        );
        actions[1] = _sendAction(RECIPIENT, 10_000 - failedBps);
        RouterRouteInput[] memory routes = new RouterRouteInput[](1);
        routes[0] = RouterRouteInput(address(assetA), actions);
        ProjectRouterV2 router = _deployRouter(routes, bytes32(0));
        airdropSink.setBehavior(true, false, 0);
        _fund(router, address(assetA), gross);
        uint256 net = gross - gross / 100;
        uint256 expectedFailed = net * failedBps / 10_000;
        _execute(router, address(assetA), type(uint256).max);
        assertEq(router.escrowed(address(assetA), 1, 0), expectedFailed);
        assertEq(assetA.balanceOf(RECIPIENT), net - expectedFailed);
    }

    function testFuzzPartialRetrySettlesOnlyRequestedEscrow(uint128 rawGross, uint128 rawRetry)
        public
    {
        uint256 gross = bound(uint256(rawGross), 100, 1_000_000e18);
        RouterAction memory action = RouterAction(
            RouterActionType.FUND_AIRDROP, 10_000, address(airdropSink), address(0), address(0), ""
        );
        ProjectRouterV2 router = _deployRouter(_singleRoute(address(assetA), action), bytes32(0));
        airdropSink.setBehavior(true, false, 0);
        _fund(router, address(assetA), gross);
        _execute(router, address(assetA), type(uint256).max);
        uint256 net = gross - gross / 100;
        uint256 retryAmount = bound(uint256(rawRetry), 1, net);
        airdropSink.setBehavior(false, false, 0);
        router.retryEscrow(address(assetA), 1, 0, retryAmount, 0, "");
        assertEq(airdropSink.funded(address(assetA)), retryAmount);
        assertEq(router.escrowed(address(assetA), 1, 0), net - retryAmount);
    }

    function testFuzzRawSyncCreditsOnlyUnaccountedAmount(uint128 rawFirst, uint128 rawSecond)
        public
    {
        uint256 first = bound(uint256(rawFirst), 1, 1_000_000e18);
        uint256 second = bound(uint256(rawSecond), 1, 1_000_000e18);
        ProjectRouterV2 router = _deployRouter(
            _singleRoute(address(assetA), _sendAction(RECIPIENT, 10_000)), bytes32(0)
        );
        assetA.mint(address(router), first);
        (uint256 firstSurplus,) = router.sync(address(assetA));
        assetA.mint(address(router), second);
        (uint256 secondSurplus,) = router.sync(address(assetA));
        assertEq(firstSurplus, first);
        assertEq(secondSurplus, second);
        assertEq(router.totalLiability(address(assetA)), first + second);
    }
}
