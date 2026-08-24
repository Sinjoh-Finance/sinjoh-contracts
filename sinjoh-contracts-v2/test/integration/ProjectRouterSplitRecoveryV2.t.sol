// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ProjectRouterV2 } from "../../src/router/ProjectRouterV2.sol";
import { RouterAction, RouterActionType, RouterRouteInput } from "../../src/router/RouterTypes.sol";
import { RouterTestBase } from "../RouterTestBase.sol";

contract ProjectRouterSplitRecoveryV2IntegrationTest is RouterTestBase {
    function setUp() public {
        _setUpRouterDependencies();
    }

    function testE2EFiveWayRevenueSplitEscrowsOnlyFailureAndPermissionlesslyRetries() public {
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

        airdropSink.setBehavior(true, false, 0);
        _fund(router, address(assetA), 10_000);
        _execute(router, address(assetA), type(uint256).max);

        assertEq(assetA.balanceOf(CREATOR), 1_980);
        assertEq(treasury.accountedBalance(address(assetA)), 1_980);
        assertEq(airdropSink.funded(address(assetA)), 0);
        assertEq(raffleSink.funded(address(assetA)), 1_980);
        assertEq(liquiditySink.funded(address(assetA)), 1_980);
        assertEq(router.escrowed(address(assetA), 1, 2), 1_980);
        assertEq(router.totalEscrowed(address(assetA)), 1_980);
        assertEq(router.pending(address(assetA)), 0);

        airdropSink.setBehavior(false, false, 0);
        vm.prank(address(0xBEEF));
        (uint256 retried, bool succeeded) =
            router.retryEscrow(address(assetA), 1, 2, type(uint256).max, 0, "");

        assertTrue(succeeded);
        assertEq(retried, 1_980);
        assertEq(airdropSink.funded(address(assetA)), 1_980);
        assertEq(router.totalEscrowed(address(assetA)), 0);
        assertEq(assetA.balanceOf(address(router)), router.totalLiability(address(assetA)));
    }

    function _sinkAction(
        RouterActionType actionType,
        address recipient,
        uint16 bps,
        bytes memory config
    ) private pure returns (RouterAction memory) {
        return RouterAction(actionType, bps, recipient, address(0), address(0), config);
    }
}
