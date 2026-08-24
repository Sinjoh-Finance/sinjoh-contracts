// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Vm } from "forge-std/Vm.sol";
import { ProjectTreasuryVaultV2 } from "../../src/treasury/ProjectTreasuryVaultV2.sol";
import {
    MockProjectBasketManager,
    MockProjectController,
    MockTreasuryERC20
} from "../mocks/MockTreasuryIntegrations.sol";
import { TreasuryTestBase } from "../TreasuryTestBase.sol";

contract ProjectTreasuryVaultV2Handler {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    ProjectTreasuryVaultV2 public immutable vault;
    MockProjectController public immutable projectController;
    MockProjectBasketManager public immutable basketManager;
    MockTreasuryERC20 public immutable assetA;
    MockTreasuryERC20 public immutable assetB;
    address public immutable recipient;

    constructor(
        ProjectTreasuryVaultV2 vault_,
        MockProjectController projectController_,
        MockProjectBasketManager basketManager_,
        MockTreasuryERC20 assetA_,
        MockTreasuryERC20 assetB_,
        address recipient_
    ) {
        vault = vault_;
        projectController = projectController_;
        basketManager = basketManager_;
        assetA = assetA_;
        assetB = assetB_;
        recipient = recipient_;
    }

    receive() external payable { }

    function deposit(uint128 rawAmount, bool secondAsset, bool route) external {
        uint256 amount = uint256(rawAmount % 1_000_000e18) + 1;
        MockTreasuryERC20 asset = secondAsset ? assetB : assetA;
        asset.mint(address(this), amount);
        asset.approve(address(vault), amount);
        try vault.deposit(address(asset), amount, route) { } catch { }
    }

    function rawTransferAndSync(uint128 rawAmount, bool route) external {
        uint256 amount = uint256(rawAmount % 1_000_000e18) + 1;
        assetA.mint(address(vault), amount);
        if (route) {
            try vault.syncAndReserve(address(assetA)) { } catch { }
        } else {
            try vault.syncAsset(address(assetA)) { } catch { }
        }
    }

    function sendAvailable(uint128 rawAmount, bool secondAsset) external {
        MockTreasuryERC20 asset = secondAsset ? assetB : assetA;
        uint256 available = vault.availableBalance(address(asset));
        if (available == 0) return;
        uint256 amount = uint256(rawAmount % available) + 1;
        try projectController.execute(
            address(vault), abi.encodeCall(vault.send, (address(asset), amount, recipient))
        ) { }
            catch { }
    }

    function executeRoute(uint128 rawMaximum) external {
        uint256 pending = vault.reservedForBasket(address(assetA));
        if (pending == 0) return;
        uint256 maximum = uint256(rawMaximum % pending) + 1;
        try vault.executeBasketRoute(address(assetA), maximum) { } catch { }
    }

    function nativeDeposit(uint96 rawAmount, bool route) external {
        uint256 amount = uint256(rawAmount % 100 ether) + 1;
        vm.deal(address(this), amount);
        try vault.depositNative{ value: amount }(route) { } catch { }
    }
}

contract ProjectTreasuryVaultV2InvariantTest is TreasuryTestBase {
    ProjectTreasuryVaultV2Handler private handler;

    function setUp() public {
        _setUpTreasury();
        address[] memory assets = new address[](2);
        if (address(assetA) < address(assetB)) {
            assets[0] = address(assetA);
            assets[1] = address(assetB);
        } else {
            assets[0] = address(assetB);
            assets[1] = address(assetA);
        }
        _controllerCall(abi.encodeCall(vault.configureBasketRoute, (BASKET_ID, 3_000, assets)));
        handler = new ProjectTreasuryVaultV2Handler(
            vault, projectController, basketManager, assetA, assetB, RECIPIENT
        );
        targetContract(address(handler));
    }

    function invariantEveryAccountedAssetIsBacked() public view {
        assertTrue(vault.isAssetBacked(address(assetA)));
        assertTrue(vault.isAssetBacked(address(assetB)));
        assertTrue(vault.isAssetBacked(address(0)));
    }

    function invariantReservationsNeverExceedAccounting() public view {
        assertLe(vault.reservedForBasket(address(assetA)), vault.accountedBalance(address(assetA)));
        assertLe(vault.reservedForBasket(address(assetB)), vault.accountedBalance(address(assetB)));
        assertLe(vault.reservedForBasket(address(0)), vault.accountedBalance(address(0)));
    }

    function invariantAccountingEqualsMeasuredStandardAssetBalances() public view {
        assertEq(vault.accountedBalance(address(assetA)), assetA.balanceOf(address(vault)));
        assertEq(vault.accountedBalance(address(assetB)), assetB.balanceOf(address(vault)));
        assertEq(vault.accountedBalance(address(0)), address(vault).balance);
    }

    function invariantExternalAllowancesAreAlwaysZeroAfterCalls() public view {
        assertEq(assetA.allowance(address(vault), address(basketManager)), 0);
        assertEq(assetB.allowance(address(vault), address(basketManager)), 0);
    }

    function invariantControllerAndProjectIdentityNeverChange() public view {
        assertEq(vault.controller(), address(projectController));
        assertEq(vault.projectId(), token.projectId());
        assertEq(vault.subject(), address(token));
        assertEq(vault.registry(), address(registry));
    }

    function invariantPrimaryBasketRemainsRegisteredAndTreasuryOwned() public view {
        assertTrue(vault.isOwnedBasketRegistered(BASKET_ID));
        assertEq(basketManager.basketNFT().ownerOf(BASKET_ID), address(vault));
    }
}
