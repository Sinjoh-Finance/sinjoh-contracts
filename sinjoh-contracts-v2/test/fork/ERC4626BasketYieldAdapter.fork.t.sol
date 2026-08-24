// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { ERC4626BasketYieldAdapter } from "../../src/adapters/ERC4626BasketYieldAdapter.sol";

/// @notice Explicitly skipped unless a reviewed Robinhood mainnet ERC-4626 canary is configured.
contract ERC4626BasketYieldAdapterForkTest is Test {
    uint256 private constant ROBINHOOD_MAINNET_CHAIN_ID = 4_663;

    function testForkSelectedVaultDepositHarvestAndFullExit() public {
        string memory rpcUrl = vm.envOr("ROBINHOOD_MAINNET_RPC_URL", string(""));
        address vaultAddress = vm.envOr("YIELD_CANARY_ERC4626_VAULT", address(0));
        address funder = vm.envOr("YIELD_CANARY_FUNDER", address(0));
        uint256 amount = vm.envOr("YIELD_CANARY_AMOUNT", uint256(0));
        if (
            bytes(rpcUrl).length == 0 || vaultAddress == address(0) || funder == address(0)
                || amount == 0
        ) {
            vm.skip(true);
        }

        vm.createSelectFork(rpcUrl);
        assertEq(block.chainid, ROBINHOOD_MAINNET_CHAIN_ID);
        IERC4626 vault = IERC4626(vaultAddress);
        IERC20 asset = IERC20(vault.asset());
        assertGt(vaultAddress.code.length, 0);
        assertGt(address(asset).code.length, 0);
        assertGe(asset.balanceOf(funder), amount);

        ERC4626BasketYieldAdapter adapter = new ERC4626BasketYieldAdapter(funder, vaultAddress);
        vm.startPrank(funder);
        asset.approve(address(adapter), amount);
        uint256 shares = adapter.deposit(amount);
        assertGt(shares, 0);
        assertGe(adapter.totalAssets(), amount);
        (address[] memory harvestAssets,) = adapter.harvest(funder);
        assertEq(harvestAssets[0], address(asset));
        adapter.exitAll(funder);
        vm.stopPrank();

        assertEq(adapter.totalAssets(), 0);
        assertEq(vault.balanceOf(address(adapter)), 0);
    }
}
