// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ProjectTreasuryVaultV2 } from "../../src/treasury/ProjectTreasuryVaultV2.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { MockProjectController, MockRejectNative } from "../mocks/MockTreasuryIntegrations.sol";
import { TreasuryTestBase } from "../TreasuryTestBase.sol";

contract ProjectTreasuryVaultV2Test is TreasuryTestBase {
    function setUp() public {
        _setUpTreasury();
    }

    function testConstructorPublishesCompleteImmutableIdentity() public view {
        assertEq(vault.registry(), address(registry));
        assertEq(vault.subject(), address(token));
        assertEq(vault.creator(), CREATOR);
        assertEq(vault.projectId(), token.projectId());
        assertEq(vault.controller(), address(projectController));
        assertEq(vault.basketManager(), address(basketManager));
        assertEq(
            vault.integrationApprovalRoot(),
            _approvalLeaf(address(assetA), address(assetB), keccak256(ROUTE_DATA))
        );
    }

    function testConstructorRejectsControllerFromAnotherProject() public {
        MockProjectController wrong = MockProjectController(
            vm.deployCode(
                "MockTreasuryIntegrations.sol:MockProjectController",
                abi.encode(bytes32(uint256(123)))
            )
        );
        vm.expectPartialRevert(ProjectTreasuryVaultV2.InvalidController.selector);
        vm.deployCode(
            "ProjectTreasuryVaultV2.sol:ProjectTreasuryVaultV2",
            abi.encode(
                address(registry), address(token), CREATOR, address(wrong), bytes32(0), address(0)
            )
        );
    }

    function testConstructorAcceptsPredictedManagerAndRuntimeUseRequiresBytecode() public {
        address predictedManager = address(0xBEEF);
        ProjectTreasuryVaultV2 predictedVault = new ProjectTreasuryVaultV2(
            address(registry),
            address(token),
            CREATOR,
            address(projectController),
            bytes32(0),
            predictedManager
        );
        assertEq(predictedVault.basketManager(), predictedManager);
        vm.expectPartialRevert(ProjectTreasuryVaultV2.InvalidBasketManager.selector);
        projectController.execute(
            address(predictedVault), abi.encodeCall(predictedVault.syncBasketNft, (BASKET_ID))
        );
    }

    function testNativeReceiveAndExplicitDepositHavePredictableAccounting() public {
        vm.prank(DEPOSITOR);
        (bool sent,) = address(vault).call{ value: 2 ether }("");
        assertTrue(sent);
        assertEq(vault.accountedBalance(address(0)), 2 ether);

        vm.prank(DEPOSITOR);
        vault.depositNative{ value: 3 ether }(false);
        assertEq(vault.accountedBalance(address(0)), 5 ether);
        assertEq(vault.availableBalance(address(0)), 5 ether);
        assertTrue(vault.isAssetBacked(address(0)));
    }

    function testExactErc20DepositCreditsFullAmount() public {
        _deposit(address(assetA), 100e18, false);
        assertEq(vault.accountedBalance(address(assetA)), 100e18);
        assertEq(vault.measuredBalance(address(assetA)), 100e18);
        assertEq(vault.availableBalance(address(assetA)), 100e18);
    }

    function testFeeOnTransferDepositRevertsWithoutCrediting() public {
        assetA.setTransferFeeBps(100);
        assetA.mint(DEPOSITOR, 100e18);
        vm.startPrank(DEPOSITOR);
        assetA.approve(address(vault), 100e18);
        vm.expectPartialRevert(ProjectTreasuryVaultV2.InexactAssetReceipt.selector);
        vault.deposit(address(assetA), 100e18, false);
        vm.stopPrank();
        assertEq(vault.accountedBalance(address(assetA)), 0);
        assertEq(assetA.balanceOf(address(vault)), 0);
    }

    function testRawTransferBecomesAvailableOnlyAfterPermissionlessSync() public {
        assetA.mint(address(vault), 75e18);
        assertEq(vault.accountedBalance(address(assetA)), 0);
        vm.prank(OUTSIDER);
        assertEq(vault.syncAsset(address(assetA)), 75e18);
        assertEq(vault.availableBalance(address(assetA)), 75e18);
    }

    function testOnlyControllerCanSendAndRecipientGetsExactAmount() public {
        _deposit(address(assetA), 100e18, false);
        vm.prank(OUTSIDER);
        vm.expectPartialRevert(ProjectTreasuryVaultV2.OnlyController.selector);
        vault.send(address(assetA), 40e18, RECIPIENT);

        _controllerCall(abi.encodeCall(vault.send, (address(assetA), 40e18, RECIPIENT)));
        assertEq(assetA.balanceOf(RECIPIENT), 40e18);
        assertEq(vault.accountedBalance(address(assetA)), 60e18);
    }

    function testNativeSendFailureRollsBackAccounting() public {
        vm.prank(DEPOSITOR);
        vault.depositNative{ value: 2 ether }(false);
        MockRejectNative rejector = MockRejectNative(
            payable(vm.deployCode("MockTreasuryIntegrations.sol:MockRejectNative"))
        );
        vm.expectPartialRevert(ProjectTreasuryVaultV2.NativeTransferFailed.selector);
        _controllerCall(abi.encodeCall(vault.send, (address(0), 1 ether, address(rejector))));
        assertEq(vault.accountedBalance(address(0)), 2 ether);
        assertEq(address(vault).balance, 2 ether);
    }

    function testRouteConfigurationExposesSingleCallFrontendStatus() public {
        _configureSingleAssetRoute(address(assetA), 2_500);
        (bool enabled, bool eligible, uint256 basketId, uint16 bps, uint256 pending) =
            vault.basketRouteStatus(address(assetA));
        assertTrue(enabled);
        assertTrue(eligible);
        assertEq(basketId, BASKET_ID);
        assertEq(bps, 2_500);
        assertEq(pending, 0);
    }

    function testMarkedDepositReservesPolicyShareAndSendCannotSpendIt() public {
        _configureSingleAssetRoute(address(assetA), 2_500);
        _deposit(address(assetA), 100e18, true);
        assertEq(vault.reservedForBasket(address(assetA)), 25e18);
        assertEq(vault.availableBalance(address(assetA)), 75e18);
        vm.expectPartialRevert(ProjectTreasuryVaultV2.InsufficientAvailableBalance.selector);
        _controllerCall(abi.encodeCall(vault.send, (address(assetA), 76e18, RECIPIENT)));
    }

    function testUnrouteableMarkedDepositFailsBeforeMovingFunds() public {
        assetA.mint(DEPOSITOR, 10e18);
        vm.startPrank(DEPOSITOR);
        assetA.approve(address(vault), 10e18);
        vm.expectPartialRevert(ProjectTreasuryVaultV2.BasketRoutingUnavailable.selector);
        vault.deposit(address(assetA), 10e18, true);
        vm.stopPrank();
        assertEq(assetA.balanceOf(DEPOSITOR), 10e18);
    }

    function testPermissionlessSyncAndReserveUsesActivePolicy() public {
        _configureSingleAssetRoute(address(assetA), 4_000);
        assetA.mint(address(vault), 50e18);
        vm.prank(OUTSIDER);
        (uint256 surplus, uint256 reserved) = vault.syncAndReserve(address(assetA));
        assertEq(surplus, 50e18);
        assertEq(reserved, 20e18);
        assertEq(vault.reservedForBasket(address(assetA)), 20e18);
    }

    function testPermissionlessKeeperCanPartiallyExecuteReservation() public {
        _configureSingleAssetRoute(address(assetA), 5_000);
        _deposit(address(assetA), 100e18, true);
        vm.prank(OUTSIDER);
        assertEq(vault.executeBasketRoute(address(assetA), 30e18), 30e18);
        assertEq(vault.reservedForBasket(address(assetA)), 20e18);
        assertEq(vault.accountedBalance(address(assetA)), 70e18);
        assertEq(basketManager.funded(BASKET_ID, address(assetA)), 30e18);
        assertEq(assetA.allowance(address(vault), address(basketManager)), 0);
    }

    function testBasketFundingFailurePreservesExactReservationAndBalance() public {
        _configureSingleAssetRoute(address(assetA), 5_000);
        _deposit(address(assetA), 100e18, true);
        basketManager.setFundingBehavior(true, false);
        vm.expectRevert();
        vault.executeBasketRoute(address(assetA), 50e18);
        assertEq(vault.reservedForBasket(address(assetA)), 50e18);
        assertEq(vault.accountedBalance(address(assetA)), 100e18);
        assertEq(assetA.balanceOf(address(vault)), 100e18);
    }

    function testDisablingRouteReleasesOnlyPendingReservation() public {
        _configureSingleAssetRoute(address(assetA), 5_000);
        _deposit(address(assetA), 100e18, true);
        vault.executeBasketRoute(address(assetA), 20e18);
        _controllerCall(abi.encodeCall(vault.disableBasketRoute, ()));
        assertEq(vault.reservedForBasket(address(assetA)), 0);
        assertEq(vault.availableBalance(address(assetA)), 80e18);
        assertFalse(vault.basketRouteEnabled());
    }

    function testApprovalReadAPIAndCanonicalLeafMatch() public view {
        bytes32[] memory proof = new bytes32[](0);
        bytes32 routeHash = keccak256(ROUTE_DATA);
        assertEq(
            vault.swapApprovalLeaf(
                address(adapter), address(priceGuard), address(assetA), address(assetB), routeHash
            ),
            _approvalLeaf(address(assetA), address(assetB), routeHash)
        );
        assertTrue(
            vault.isSwapApproved(
                address(adapter),
                address(priceGuard),
                address(assetA),
                address(assetB),
                routeHash,
                proof
            )
        );
        assertFalse(
            vault.isSwapApproved(
                address(adapter),
                address(priceGuard),
                address(assetB),
                address(assetA),
                routeHash,
                proof
            )
        );
    }

    function testApprovedSwapEnforcesGuardAndExactAccounting() public {
        _deposit(address(assetA), 100e18, false);
        assetB.mint(address(adapter), 60e18);
        adapter.configure(60e18, type(uint256).max, false);
        priceGuard.setQuote(55e18, uint48(block.timestamp + 1 hours));
        bytes32[] memory proof = new bytes32[](0);
        bytes memory result = _controllerCall(
            abi.encodeCall(
                vault.swap,
                (
                    address(adapter),
                    address(priceGuard),
                    address(assetA),
                    address(assetB),
                    100e18,
                    58e18,
                    ROUTE_DATA,
                    bytes(""),
                    proof
                )
            )
        );
        assertEq(abi.decode(result, (uint256)), 60e18);
        assertEq(vault.accountedBalance(address(assetA)), 0);
        assertEq(vault.accountedBalance(address(assetB)), 60e18);
        assertEq(assetA.allowance(address(vault), address(adapter)), 0);
    }

    function testSwapRejectsUnapprovedRouteBeforeMovingFunds() public {
        _deposit(address(assetA), 100e18, false);
        bytes32[] memory proof = new bytes32[](0);
        vm.expectPartialRevert(ProjectTreasuryVaultV2.SwapNotApproved.selector);
        _controllerCall(
            abi.encodeCall(
                vault.swap,
                (
                    address(adapter),
                    address(priceGuard),
                    address(assetA),
                    address(assetB),
                    100e18,
                    1,
                    hex"99",
                    bytes(""),
                    proof
                )
            )
        );
        assertEq(assetA.balanceOf(address(vault)), 100e18);
    }

    function testSwapRejectsExpiredQuoteAndUnderOutputAtomically() public {
        _deposit(address(assetA), 100e18, false);
        assetB.mint(address(adapter), 100e18);
        bytes32[] memory proof = new bytes32[](0);
        priceGuard.setQuote(50e18, uint48(block.timestamp - 1));
        vm.expectPartialRevert(ProjectTreasuryVaultV2.GuardQuoteExpired.selector);
        _controllerCall(
            abi.encodeCall(
                vault.swap,
                (
                    address(adapter),
                    address(priceGuard),
                    address(assetA),
                    address(assetB),
                    100e18,
                    1,
                    ROUTE_DATA,
                    bytes(""),
                    proof
                )
            )
        );

        priceGuard.setQuote(50e18, uint48(block.timestamp + 1));
        adapter.configure(49e18, type(uint256).max, false);
        vm.expectPartialRevert(ProjectTreasuryVaultV2.InsufficientSwapOutput.selector);
        _controllerCall(
            abi.encodeCall(
                vault.swap,
                (
                    address(adapter),
                    address(priceGuard),
                    address(assetA),
                    address(assetB),
                    100e18,
                    1,
                    ROUTE_DATA,
                    bytes(""),
                    proof
                )
            )
        );
        assertEq(assetA.balanceOf(address(vault)), 100e18);
        assertEq(assetB.balanceOf(address(vault)), 0);
    }

    function testBasketNftIsAutomaticallyRegisteredAndCanBeUpdated() public {
        assertEq(vault.ownedBasketCount(), 1);
        assertEq(vault.ownedBasketAt(0), BASKET_ID);
        assertTrue(vault.isOwnedBasketRegistered(BASKET_ID));
        bytes memory config = hex"aabbcc";
        _controllerCall(abi.encodeCall(vault.updateOwnedBasket, (BASKET_ID, config)));
        assertEq(keccak256(basketManager.configuration(BASKET_ID)), keccak256(config));
    }

    function testBasketNftTransferUsesTypedPathAndClearsRegistration() public {
        _controllerCall(abi.encodeCall(vault.transferBasketNft, (BASKET_ID, RECIPIENT)));
        assertEq(basketManager.basketNFT().ownerOf(BASKET_ID), RECIPIENT);
        assertFalse(vault.isOwnedBasketRegistered(BASKET_ID));
    }

    function testTransferringActiveBasketReleasesPendingRouteAtomically() public {
        _configureSingleAssetRoute(address(assetA), 5_000);
        _deposit(address(assetA), 100e18, true);
        _controllerCall(abi.encodeCall(vault.transferBasketNft, (BASKET_ID, RECIPIENT)));
        assertFalse(vault.basketRouteEnabled());
        assertEq(vault.reservedForBasket(address(assetA)), 0);
        assertEq(vault.availableBalance(address(assetA)), 100e18);
    }

    function testBeginningActiveBasketBurnReleasesPendingRouteAtomically() public {
        _configureSingleAssetRoute(address(assetA), 5_000);
        _deposit(address(assetA), 100e18, true);
        _controllerCall(abi.encodeCall(vault.beginOwnedBasketBurn, (BASKET_ID)));
        assertTrue(basketManager.burnBegun(BASKET_ID));
        assertFalse(vault.basketRouteEnabled());
        assertEq(vault.reservedForBasket(address(assetA)), 0);
        assertEq(vault.availableBalance(address(assetA)), 100e18);
    }

    function testBasketBurnPaysSubjectPriceAndReturnsRedemptionToTreasury() public {
        address[] memory assets = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        assets[0] = address(assetA);
        amounts[0] = 30e18;
        assetA.mint(address(basketManager), 30e18);
        _createBasket(8, 10e18, assets, amounts);
        vm.startPrank(DEPOSITOR);
        token.approve(address(vault), 10e18);
        vault.deposit(address(token), 10e18, false);
        vm.stopPrank();
        _controllerCall(abi.encodeCall(vault.beginOwnedBasketBurn, (8)));
        _controllerCall(abi.encodeCall(vault.finalizeOwnedBasketBurn, (8)));
        assertEq(token.balanceOf(vault.BURN_ADDRESS()), 10e18);
        assertEq(vault.accountedBalance(address(token)), 0);
        assertEq(vault.accountedBalance(address(assetA)), 30e18);
        assertFalse(vault.isOwnedBasketRegistered(8));
        IERC721 basketNft = basketManager.basketNFT();
        vm.expectRevert();
        basketNft.ownerOf(8);
    }

    function testBasketBurnRejectsManagerThatLeavesNftAlive() public {
        address[] memory assets = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        assets[0] = address(assetA);
        _createBasket(8, 0, assets, amounts);
        _controllerCall(abi.encodeCall(vault.beginOwnedBasketBurn, (8)));
        basketManager.setKeepNftAfterFinalize(true);
        vm.expectPartialRevert(ProjectTreasuryVaultV2.BasketNftStillExists.selector);
        _controllerCall(abi.encodeCall(vault.finalizeOwnedBasketBurn, (8)));
        assertTrue(vault.isOwnedBasketRegistered(8));
    }
}
