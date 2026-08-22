// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AddressGovernanceController } from "../src/governance/AddressGovernanceController.sol";
import { ERC4626YieldAdapter } from "../src/adapters/ERC4626YieldAdapter.sol";
import { IGovernanceController } from "../src/interfaces/IGovernanceController.sol";
import { YieldBasket } from "../src/YieldBasket.sol";
import { TestBase } from "./TestBase.sol";
import { MockERC20, MockERC4626, MockFundable, MockNonCompliantERC4626 } from "./mocks/Mocks.sol";

contract ERC4626YieldAdapterTest is TestBase {
    address private constant GUARDIAN = address(0xBEEF);
    address private constant ALICE = address(0xA11CE);

    MockERC20 private asset;
    MockERC4626 private vault;
    MockFundable private treasury;
    YieldBasket private basket;
    ERC4626YieldAdapter private adapter;

    function setUp() public {
        asset = new MockERC20();
        vault = new MockERC4626(IERC20(address(asset)));
        treasury = new MockFundable();
        AddressGovernanceController controller =
            new AddressGovernanceController(address(this), IGovernanceController.Mode.INDIVIDUAL);
        basket = new YieldBasket(controller, GUARDIAN, IERC20(address(asset)), address(treasury));
        adapter = new ERC4626YieldAdapter(address(basket), vault);
        basket.configureAdapter(adapter, 10_000, 30 minutes);
    }

    function testERC4626GainIsRealizedAndForcedBackToTreasury() public {
        asset.mint(address(this), 1_000e18);
        asset.approve(address(basket), 1_000e18);
        basket.fund(address(asset), 1_000e18, "");
        uint256 shares = basket.allocate(adapter, 1_000e18);
        assertEq(shares, 1_000e18);
        assertEq(adapter.totalAssets(), 1_000e18);

        asset.mint(address(vault), 100e18);
        uint256 expectedAssets = adapter.totalAssets();
        (uint256 currentAssets, uint256 principal, uint256 gain, uint256 loss) =
            basket.basketValue();
        assertEq(currentAssets, expectedAssets);
        assertEq(principal, 1_000e18);
        assertEq(gain, expectedAssets - 1_000e18);
        assertEq(loss, 0);

        basket.withdrawFromAdapter(adapter, shares);
        assertEq(basket.idlePrincipal(), 1_000e18);
        assertEq(basket.realizedIdleValue(), expectedAssets - 1_000e18);
        basket.realizeIdleValue(expectedAssets - 1_000e18);
        basket.withdrawIdlePrincipal(1_000e18);
        assertEq(asset.balanceOf(address(treasury)), expectedAssets);
    }

    function testOnlyBoundBasketCanMoveAdapterAssets() public {
        vm.prank(ALICE);
        vm.expectRevert(ERC4626YieldAdapter.Unauthorized.selector);
        adapter.deposit(1e18);

        vm.prank(ALICE);
        vm.expectRevert(ERC4626YieldAdapter.Unauthorized.selector);
        adapter.withdraw(1e18);
    }

    function testFeeOnTransferDepositAssetIsRejected() public {
        asset.setFeeBps(100);
        asset.mint(address(this), 1_000e18);
        asset.approve(address(basket), 1_000e18);
        vm.expectPartialRevert(YieldBasket.InexactTransfer.selector);
        basket.fund(address(asset), 1_000e18, "");
    }

    function testWrittenOffPositionHasLossyExitWhenVaultUnderdeliversPreview() public {
        MockNonCompliantERC4626 badVault = new MockNonCompliantERC4626(IERC20(address(asset)));
        ERC4626YieldAdapter badAdapter = new ERC4626YieldAdapter(address(basket), badVault);
        basket.configureAdapter(badAdapter, 10_000, 30 minutes);

        asset.mint(address(this), 1_000e18);
        asset.approve(address(basket), 1_000e18);
        basket.fund(address(asset), 1_000e18, "");
        uint256 shares = basket.allocate(badAdapter, 1_000e18);
        uint256 previewedAssets = badVault.previewRedeem(shares);
        badVault.setRedeemBps(5_000);

        vm.expectPartialRevert(ERC4626YieldAdapter.NonCompliantPreview.selector);
        basket.withdrawFromAdapter(badAdapter, shares);
        assertEq(badVault.balanceOf(address(badAdapter)), shares);

        vm.prank(GUARDIAN);
        basket.setAdapterStatus(badAdapter, YieldBasket.AdapterStatus.FULLY_PAUSED);
        basket.writeOffAdapter(badAdapter);
        uint256 recovered = basket.recoverWrittenOffSharesLossy(badAdapter, shares);

        assertEq(recovered, previewedAssets / 2);
        assertEq(basket.writtenOffShares(address(badAdapter)), 0);
        assertEq(asset.balanceOf(address(treasury)), recovered);
        assertEq(badVault.balanceOf(address(badAdapter)), 0);
    }

    function testWrittenOffPositionCanBeClearedWhenVaultReturnsNothing() public {
        MockNonCompliantERC4626 badVault = new MockNonCompliantERC4626(IERC20(address(asset)));
        ERC4626YieldAdapter badAdapter = new ERC4626YieldAdapter(address(basket), badVault);
        basket.configureAdapter(badAdapter, 10_000, 30 minutes);

        asset.mint(address(this), 1_000e18);
        asset.approve(address(basket), 1_000e18);
        basket.fund(address(asset), 1_000e18, "");
        uint256 shares = basket.allocate(badAdapter, 1_000e18);
        badVault.setRedeemBps(0);

        vm.prank(GUARDIAN);
        basket.setAdapterStatus(badAdapter, YieldBasket.AdapterStatus.FULLY_PAUSED);
        basket.writeOffAdapter(badAdapter);
        uint256 recovered = basket.recoverWrittenOffSharesLossy(badAdapter, shares);

        assertEq(recovered, 0);
        assertEq(basket.writtenOffShares(address(badAdapter)), 0);
        assertEq(badVault.balanceOf(address(badAdapter)), 0);
    }
}
