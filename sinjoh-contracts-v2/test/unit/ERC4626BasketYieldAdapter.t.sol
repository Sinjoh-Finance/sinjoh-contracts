// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC4626BasketYieldAdapter } from "../../src/adapters/ERC4626BasketYieldAdapter.sol";
import { MockBasketAsset } from "../mocks/MockBasketIntegrations.sol";
import { MockERC4626 } from "../mocks/MockERC4626.sol";

contract ERC4626BasketYieldAdapterTest is Test {
    address private constant OUTSIDER = address(0xBAD);

    MockBasketAsset private asset;
    MockERC4626 private vault;
    ERC4626BasketYieldAdapter private adapter;

    function setUp() public {
        asset = new MockBasketAsset("Yield Asset", "YIELD");
        vault = new MockERC4626(IERC20(address(asset)));
        adapter = new ERC4626BasketYieldAdapter(address(this), address(vault));
        asset.mint(address(this), 10_000e18);
        asset.approve(address(adapter), type(uint256).max);
    }

    function testConstructorPublishesPermanentBindingsAndStableRuntimeHash() public {
        ERC4626BasketYieldAdapter second = new ERC4626BasketYieldAdapter(OUTSIDER, address(vault));
        assertEq(adapter.basketVault(), address(this));
        assertEq(adapter.depositAsset(), address(asset));
        assertEq(address(adapter.vault()), address(vault));
        assertEq(address(adapter).codehash, address(second).codehash);
    }

    function testDepositHarvestAndFullExitPreservePrincipal() public {
        uint256 shares = adapter.deposit(1_000e18);
        assertGt(shares, 0);
        assertEq(adapter.managedPrincipal(), 1_000e18);
        assertEq(asset.allowance(address(adapter), address(vault)), 0);

        asset.mint(address(vault), 100e18);
        uint256 positionBefore = adapter.totalAssets();
        uint256 walletBefore = asset.balanceOf(address(this));
        (address[] memory harvestAssets, uint256[] memory harvestAmounts) =
            adapter.harvest(address(this));
        assertEq(harvestAssets.length, 1);
        assertEq(harvestAssets[0], address(asset));
        assertEq(asset.balanceOf(address(this)) - walletBefore, harvestAmounts[0]);
        assertGt(harvestAmounts[0], 0);
        assertGe(adapter.totalAssets(), adapter.managedPrincipal());
        assertLe(adapter.totalAssets() + harvestAmounts[0], positionBefore);

        walletBefore = asset.balanceOf(address(this));
        (, uint256[] memory exitAmounts) = adapter.exitAll(address(this));
        assertEq(asset.balanceOf(address(this)) - walletBefore, exitAmounts[0]);
        assertEq(adapter.totalAssets(), 0);
        assertEq(adapter.managedPrincipal(), 0);
        assertEq(vault.balanceOf(address(adapter)), 0);
    }

    function testDirectUnderlyingDonationIsHarvestedAsYield() public {
        adapter.deposit(1_000e18);
        assertTrue(asset.transfer(address(adapter), 25e18));
        (, uint256[] memory amounts) = adapter.harvest(address(this));
        assertEq(amounts[0], 25e18);
        assertGe(adapter.totalAssets(), 1_000e18);
    }

    function testNoGainReturnsCanonicalZeroOutput() public {
        adapter.deposit(1_000e18);
        (address[] memory assets, uint256[] memory amounts) = adapter.harvest(address(this));
        assertEq(assets.length, 1);
        assertEq(assets[0], address(asset));
        assertEq(amounts[0], 0);
    }

    function testOnlyBoundBasketCanMoveAssetsAndRecipientCannotBeRedirected() public {
        vm.prank(OUTSIDER);
        vm.expectRevert(
            abi.encodeWithSelector(ERC4626BasketYieldAdapter.OnlyBasketVault.selector, OUTSIDER)
        );
        adapter.deposit(1e18);

        vm.expectRevert(
            abi.encodeWithSelector(ERC4626BasketYieldAdapter.InvalidRecipient.selector, OUTSIDER)
        );
        adapter.harvest(OUTSIDER);

        vm.expectRevert(
            abi.encodeWithSelector(ERC4626BasketYieldAdapter.InvalidRecipient.selector, OUTSIDER)
        );
        adapter.exitAll(OUTSIDER);
    }

    function testZeroDepositRevertsWithoutMovingAssets() public {
        vm.expectRevert(abi.encodeWithSelector(ERC4626BasketYieldAdapter.InvalidAmount.selector, 0));
        adapter.deposit(0);
        assertEq(adapter.totalAssets(), 0);
    }

    function testFuzzHarvestNeverReducesPositionBelowPrincipal(uint96 rawPrincipal, uint96 rawYield)
        public
    {
        uint256 principal = bound(uint256(rawPrincipal), 1e6, 1e30);
        uint256 yield = bound(uint256(rawYield), 1, 1e30);
        asset.mint(address(this), principal);
        adapter.deposit(principal);
        asset.mint(address(vault), yield);

        uint256 beforePosition = adapter.totalAssets();
        uint256 walletBefore = asset.balanceOf(address(this));
        (, uint256[] memory harvested) = adapter.harvest(address(this));
        uint256 received = asset.balanceOf(address(this)) - walletBefore;

        assertEq(received, harvested[0]);
        assertGe(adapter.totalAssets(), principal);
        assertLe(adapter.totalAssets() + received, beforePosition);
    }
}
