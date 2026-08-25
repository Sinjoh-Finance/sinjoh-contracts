// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Vm } from "forge-std/Vm.sol";
import { ProjectRouterV2 } from "../../src/router/ProjectRouterV2.sol";
import { RouterAction, RouterActionType, RouterRouteInput } from "../../src/router/RouterTypes.sol";
import { MockRouterSink } from "../mocks/MockRouterIntegrations.sol";
import { MockProjectController, MockTreasuryERC20 } from "../mocks/MockTreasuryIntegrations.sol";
import { RouterTestBase } from "../RouterTestBase.sol";

contract ProjectRouterV2Handler {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    ProjectRouterV2 public immutable router;
    MockProjectController public immutable projectController;
    MockTreasuryERC20 public immutable asset;
    MockRouterSink public immutable sink;
    bytes32 public immutable projectId;
    address public immutable subject;

    constructor(
        ProjectRouterV2 router_,
        MockProjectController projectController_,
        MockTreasuryERC20 asset_,
        MockRouterSink sink_,
        bytes32 projectId_,
        address subject_
    ) {
        router = router_;
        projectController = projectController_;
        asset = asset_;
        sink = sink_;
        projectId = projectId_;
        subject = subject_;
    }

    function fund(uint128 rawAmount) external {
        uint256 amount = uint256(rawAmount % 1_000_000e18) + 1;
        asset.mint(address(this), amount);
        asset.approve(address(router), amount);
        router.fund(projectId, subject, address(asset), amount, "");
    }

    function rawTransferAndSync(uint128 rawAmount) external {
        uint256 amount = uint256(rawAmount % 1_000_000e18) + 1;
        asset.mint(address(router), amount);
        router.sync(address(asset));
    }

    function execute(uint128 rawMaximum) external {
        uint256 current = router.pending(address(asset));
        if (current == 0) return;
        uint256 maximum = uint256(rawMaximum % current) + 1;
        router.execute(address(asset), maximum, new uint256[](2), new bytes[](2));
    }

    function retry(uint128 rawMaximum) external {
        uint256 current = router.escrowed(address(asset), 1, 0);
        if (current == 0 || router.actionPaused(address(asset), 1, 0)) return;
        uint256 maximum = uint256(rawMaximum % current) + 1;
        router.retryEscrow(address(asset), 1, 0, maximum, 0, "");
    }

    function sendFee(uint128 rawMaximum) external {
        uint256 current = router.protocolOwed(address(asset));
        if (current == 0) return;
        uint256 maximum = uint256(rawMaximum % current) + 1;
        router.sendProtocolFee(address(asset), maximum);
    }

    function setSinkFailure(bool fail) external {
        sink.setBehavior(fail, false, 0);
    }

    function setPause(bool pause) external {
        bool current = router.actionPaused(address(asset), 1, 0);
        if (pause == current) return;
        bytes memory data = pause
            ? abi.encodeCall(router.pauseAction, (address(asset), 1, 0))
            : abi.encodeCall(router.resumeAction, (address(asset), 1, 0));
        projectController.execute(address(router), data);
    }
}

contract ProjectRouterV2InvariantTest is RouterTestBase {
    ProjectRouterV2 private router;
    ProjectRouterV2Handler private handler;

    function setUp() public {
        _setUpRouterDependencies();
        RouterAction[] memory actions = new RouterAction[](2);
        actions[0] = RouterAction(
            RouterActionType.FUND_AIRDROP, 4_000, address(airdropSink), address(0), address(0), ""
        );
        actions[1] = _sendAction(RECIPIENT, 6_000);
        RouterRouteInput[] memory routes = new RouterRouteInput[](1);
        routes[0] = RouterRouteInput(address(assetA), actions);
        router = _deployRouter(routes, bytes32(0));
        handler = new ProjectRouterV2Handler(
            router, projectController, assetA, airdropSink, token.projectId(), address(token)
        );
        targetContract(address(handler));
    }

    function invariantAllLiabilitiesAreExactlyBacked() public view {
        assertEq(assetA.balanceOf(address(router)), router.totalLiability(address(assetA)));
        assertTrue(router.isAssetBacked(address(assetA)));
    }

    function invariantLiabilityBucketsRemainDisjointAndReconcile() public view {
        assertEq(
            router.totalLiability(address(assetA)),
            router.pending(address(assetA)) + router.totalEscrowed(address(assetA))
                + router.protocolOwed(address(assetA))
        );
        assertEq(router.totalEscrowed(address(assetA)), router.escrowed(address(assetA), 1, 0));
    }

    function invariantCumulativeAllocationsEqualEveryRoutedUnit() public view {
        (ProjectRouterV2.RouteHeader memory header,) = router.activeRoute(address(assetA));
        (,, uint256 allocated0,) = router.actionStatus(address(assetA), 1, 0);
        (,, uint256 allocated1,) = router.actionStatus(address(assetA), 1, 1);
        assertEq(allocated0 + allocated1, header.totalRouted);
    }

    function invariantExternalAllowancesAreAlwaysCleared() public view {
        assertEq(assetA.allowance(address(router), address(airdropSink)), 0);
        assertEq(assetA.allowance(address(router), address(treasury)), 0);
        assertEq(assetA.allowance(address(router), address(adapter)), 0);
    }

    function invariantIdentityRouteAndDestinationsNeverChange() public view {
        assertEq(router.projectId(), token.projectId());
        assertEq(router.controller(), address(projectController));
        assertEq(router.activeRouteVersion(address(assetA)), 1);
        assertEq(router.airdrop(), address(airdropSink));
        assertEq(router.protocolFeeRecipient(), FEE_RECIPIENT);
    }

    function invariantFeeRemainderAlwaysStaysBelowDenominator() public view {
        assertLt(router.protocolFeeRemainder(address(assetA)), router.BPS());
    }
}
