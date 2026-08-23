// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ProjectRouterV2 } from "../../src/router/ProjectRouterV2.sol";
import { RouterAction, RouterActionType, RouterRouteInput } from "../../src/router/RouterTypes.sol";
import { ProjectTreasuryVaultV2 } from "../../src/treasury/ProjectTreasuryVaultV2.sol";
import { MockProjectController, MockTreasuryERC20 } from "../mocks/MockTreasuryIntegrations.sol";
import { RouterTestBase } from "../RouterTestBase.sol";

contract SystemRevenueFlowV2Handler {
    ProjectRouterV2 public immutable router;
    ProjectTreasuryVaultV2 public immutable treasury;
    MockProjectController public immutable projectController;
    MockTreasuryERC20 public immutable asset;
    bytes32 public immutable projectId;
    address public immutable subject;
    address public immutable recipient;

    uint256 public totalMinted;

    constructor(
        ProjectRouterV2 router_,
        ProjectTreasuryVaultV2 treasury_,
        MockProjectController projectController_,
        MockTreasuryERC20 asset_,
        bytes32 projectId_,
        address subject_,
        address recipient_
    ) {
        router = router_;
        treasury = treasury_;
        projectController = projectController_;
        asset = asset_;
        projectId = projectId_;
        subject = subject_;
        recipient = recipient_;
    }

    function fundRouter(uint128 rawAmount) external {
        uint256 amount = uint256(rawAmount % 1_000_000e18) + 1;
        totalMinted += amount;
        asset.mint(address(this), amount);
        asset.approve(address(router), amount);
        router.fund(projectId, subject, address(asset), amount, "");
    }

    function executeRouter(uint128 rawMaximum) external {
        uint256 current = router.pending(address(asset));
        if (current == 0) return;
        uint256 maximum = uint256(rawMaximum % current) + 1;
        try router.execute(address(asset), maximum, new uint256[](2), new bytes[](2)) { } catch { }
    }

    function sendTreasury(uint128 rawMaximum) external {
        uint256 current = treasury.availableBalance(address(asset));
        if (current == 0) return;
        uint256 amount = uint256(rawMaximum % current) + 1;
        try projectController.execute(
            address(treasury), abi.encodeCall(treasury.send, (address(asset), amount, recipient))
        ) { }
            catch { }
    }

    function sendProtocolFee(uint128 rawMaximum) external {
        uint256 current = router.protocolOwed(address(asset));
        if (current == 0) return;
        uint256 amount = uint256(rawMaximum % current) + 1;
        try router.sendProtocolFee(address(asset), amount) { } catch { }
    }
}

contract SystemRevenueFlowV2InvariantTest is RouterTestBase {
    ProjectRouterV2 private router;
    SystemRevenueFlowV2Handler private handler;

    function setUp() public {
        _setUpRouterDependencies();
        RouterAction[] memory actions = new RouterAction[](2);
        actions[0] = RouterAction({
            actionType: RouterActionType.FUND_TREASURY,
            allocationBps: 7_000,
            recipient: address(treasury),
            adapter: address(0),
            priceGuard: address(0),
            actionConfig: abi.encode(false)
        });
        actions[1] = _sendAction(RECIPIENT, 3_000);
        RouterRouteInput[] memory routes = new RouterRouteInput[](1);
        routes[0] = RouterRouteInput({ inputAsset: address(assetA), actions: actions });
        router = _deployRouter(routes, bytes32(0));
        handler = new SystemRevenueFlowV2Handler(
            router,
            treasury,
            projectController,
            assetA,
            token.projectId(),
            address(token),
            RECIPIENT
        );
        targetContract(address(handler));
    }

    function invariantEveryMintedUnitRemainsAccountedAcrossModulesAndRecipients() public view {
        assertEq(
            handler.totalMinted(),
            assetA.balanceOf(address(router)) + assetA.balanceOf(address(treasury))
                + assetA.balanceOf(RECIPIENT) + assetA.balanceOf(FEE_RECIPIENT)
        );
    }

    function invariantBothCustodyModulesRemainExactlyBacked() public view {
        assertEq(assetA.balanceOf(address(router)), router.totalLiability(address(assetA)));
        assertEq(assetA.balanceOf(address(treasury)), treasury.accountedBalance(address(assetA)));
        assertTrue(router.isAssetBacked(address(assetA)));
        assertTrue(treasury.isAssetBacked(address(assetA)));
    }

    function invariantCrossModuleIdentityAndControlNeverDrift() public view {
        assertEq(router.projectId(), treasury.projectId());
        assertEq(router.subject(), treasury.subject());
        assertEq(router.controller(), treasury.controller());
        assertEq(router.treasury(), address(treasury));
    }

    function invariantCrossModuleAllowancesAreClearedAfterEveryAttempt() public view {
        assertEq(assetA.allowance(address(router), address(treasury)), 0);
    }
}
