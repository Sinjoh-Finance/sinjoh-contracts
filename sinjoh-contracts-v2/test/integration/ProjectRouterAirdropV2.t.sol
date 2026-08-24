// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {
    AirdropAccountConfig,
    AirdropCadence,
    AirdropDustDestination,
    AirdropEligibilityMode
} from "../../src/airdrop/AirdropTypes.sol";
import { ProjectAirdropV2 } from "../../src/airdrop/ProjectAirdropV2.sol";
import { ProjectRouterV2 } from "../../src/router/ProjectRouterV2.sol";
import { RouterAction, RouterActionType, RouterRouteInput } from "../../src/router/RouterTypes.sol";
import { RouterTestBase } from "../RouterTestBase.sol";

contract ProjectRouterAirdropV2IntegrationTest is RouterTestBase {
    function setUp() public {
        _setUpRouterDependencies();
    }

    function testRouterFundsCanonicalAirdropAccountWithoutPostLaunchWiring() public {
        ProjectAirdropV2 projectAirdrop = new ProjectAirdropV2(
            address(registry),
            address(token),
            CREATOR,
            address(treasury),
            FEE_RECIPIENT,
            address(0xA773570),
            address(token),
            AirdropEligibilityMode.HOLDERS,
            new address[](0)
        );
        AirdropAccountConfig memory accountConfig = AirdropAccountConfig({
            maxPushBatchSize: 16,
            minimumSnapshotConfirmations: 5,
            cadence: AirdropCadence.DAILY,
            dustDestination: AirdropDustDestination.NEXT_EPOCH
        });
        RouterAction[] memory actions = new RouterAction[](1);
        actions[0] = RouterAction({
            actionType: RouterActionType.FUND_AIRDROP,
            allocationBps: 10_000,
            recipient: address(projectAirdrop),
            adapter: address(0),
            priceGuard: address(0),
            actionConfig: abi.encode(accountConfig)
        });
        RouterRouteInput[] memory routes = new RouterRouteInput[](1);
        routes[0] = RouterRouteInput({ inputAsset: address(assetA), actions: actions });
        ProjectRouterV2 router = new ProjectRouterV2(
            address(registry),
            address(token),
            CREATOR,
            address(projectController),
            FEE_RECIPIENT,
            address(treasury),
            address(projectAirdrop),
            address(raffleSink),
            address(liquiditySink),
            bytes32(0),
            routes
        );

        _fund(router, address(assetA), 10_000);
        _execute(router, address(assetA), type(uint256).max);

        bytes32 id = projectAirdrop.accountId(address(router), address(assetA));
        (ProjectAirdropV2.AccountState memory account,,) = projectAirdrop.accountStatus(id);
        assertEq(account.funder, address(router));
        assertEq(account.uncommittedFunding, 9_801);
        assertEq(projectAirdrop.protocolOwed(address(assetA)), 99);
        assertEq(assetA.balanceOf(address(projectAirdrop)), 9_900);
        assertEq(router.pending(address(assetA)), 0);
        assertEq(router.totalEscrowed(address(assetA)), 0);
    }
}
