// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    CollectionPortfolioAllocator
} from "../../src/yield-banks/CollectionPortfolioAllocator.sol";
import { CollectionRevenueRouter } from "../../src/yield-banks/CollectionRevenueRouter.sol";
import { DeltaV3LPAdapter } from "../../src/yield-banks/adapters/DeltaV3LPAdapter.sol";
import {
    YieldBankSelfServiceExecutionRouter
} from "../../src/yield-banks/YieldBankSelfServiceExecutionRouter.sol";
import { CollectionTimelock } from "../../src/yield-banks/CollectionTimelock.sol";
import { YieldBankProceedsVault } from "../../src/yield-banks/YieldBankProceedsVault.sol";

contract PiggyBanksSelfServiceExecutionRouterForkTest is Test {
    uint256 private constant CHAIN_ID = 4663;
    address private constant ALLOCATOR = 0x42e14eA9f926ad7b530ce49d433CB6f748f8D0a1;
    address private constant PROCEEDS_VAULT = 0xa9653463ffdE4e2352b4659334f785159d7525FD;
    address private constant TIMELOCK = 0x7C15804A2d7F5981035895CAb953e5E76393E1B8;
    address private constant DELTA_POOL = 0xB09fa4f04032b9d9e690ac4a1d29523b5f9A72DC;
    address private constant REVENUE_ROUTER = 0x9e4E01d2C3c939d870c040192AA143cB139bcc9F;
    address private constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    address private constant USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;
    address private constant USDG_SLEEVE = 0x9e02f4E267fcEf8c1DC89f148529D20F1aD040A1;
    bytes32 private constant PREDECESSOR = bytes32(0);
    address private constant EXPECTED_PROPOSER = 0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49;

    function testLiveSuccessorCutoverPreservesTheImmutableDelayForGovernanceOnly() external {
        string memory rpcUrl = vm.envOr("ROBINHOOD_MAINNET_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) vm.skip(true);
        vm.createSelectFork(rpcUrl);
        assertEq(block.chainid, CHAIN_ID);

        TimelockController timelock = TimelockController(payable(TIMELOCK));
        vm.expectRevert(CollectionTimelock.TimelockConfigurationImmutable.selector);
        vm.prank(TIMELOCK);
        timelock.updateDelay(0);

        YieldBankProceedsVault vault = YieldBankProceedsVault(payable(PROCEEDS_VAULT));
        YieldBankSelfServiceExecutionRouter successor =
            new YieldBankSelfServiceExecutionRouter(ALLOCATOR);
        bytes memory activation =
            abi.encodeCall(YieldBankProceedsVault.setAllocationOperator, (address(successor)));
        bytes32 salt = keccak256(
            abi.encode(
                "PIGGY_BANKS_SELF_SERVICE_EXECUTION_ROUTER_V2", address(successor), block.chainid
            )
        );
        bytes32 operationId =
            timelock.hashOperation(PROCEEDS_VAULT, 0, activation, PREDECESSOR, salt);

        uint256 minimumDelay = timelock.getMinDelay();
        vm.prank(EXPECTED_PROPOSER);
        timelock.schedule(PROCEEDS_VAULT, 0, activation, PREDECESSOR, salt, minimumDelay);
        assertTrue(timelock.isOperationPending(operationId));
        vm.warp(timelock.getTimestamp(operationId));
        vm.prank(EXPECTED_PROPOSER);
        timelock.execute(PROCEEDS_VAULT, 0, activation, PREDECESSOR, salt);

        assertEq(vault.allocationOperator(), address(successor));
        assertEq(CollectionPortfolioAllocator(ALLOCATOR).allocationOperator(), address(successor));
    }

    function testLiveRouterCanAtomicallyPlaceTheCurrentIdleDeltaCapital() external {
        string memory rpcUrl = vm.envOr("ROBINHOOD_MAINNET_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) vm.skip(true);
        vm.createSelectFork(rpcUrl);
        assertEq(block.chainid, CHAIN_ID);

        CollectionPortfolioAllocator allocator = CollectionPortfolioAllocator(ALLOCATOR);
        YieldBankProceedsVault vault = YieldBankProceedsVault(payable(PROCEEDS_VAULT));
        YieldBankSelfServiceExecutionRouter router =
            new YieldBankSelfServiceExecutionRouter(ALLOCATOR);
        vm.prank(TIMELOCK);
        vault.setAllocationOperator(address(router));
        assertEq(allocator.allocationOperator(), address(router));

        CollectionPortfolioAllocator.DeltaPoolBinding memory binding =
            allocator.deltaPoolBinding(DELTA_POOL);
        DeltaV3LPAdapter adapter = DeltaV3LPAdapter(binding.adapter);
        uint256 idleBefore = IERC20(router.weth()).balanceOf(binding.sleeve);
        uint256 positionsBefore = adapter.positionIds().length;
        YieldBankSelfServiceExecutionRouter.DeltaDeploymentPreview memory preview =
            router.previewDeltaDeployment(DELTA_POOL);
        assertEq(preview.idleAssets, idleBefore);
        assertEq(preview.assets, idleBefore * router.IDLE_UTILIZATION_BPS() / 10_000);
        assertEq(preview.sleeve, binding.sleeve);
        assertEq(preview.adapter, binding.adapter);

        if (!preview.ready) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    YieldBankSelfServiceExecutionRouter.DeltaDeploymentNotReady.selector,
                    preview.idleAssets,
                    preview.managedAssets,
                    preview.positionCount
                )
            );
            vm.prank(address(0xBEEF));
            router.deployIdleDelta(DELTA_POOL);
            return;
        }

        vm.prank(address(0xBEEF));
        uint256 units = router.deployIdleDelta(DELTA_POOL);
        assertGt(units, 0);
        assertEq(adapter.positionIds().length, positionsBefore + 1);
        assertGt(adapter.totalManagedAssets(), 0);
        assertEq(IERC20(router.weth()).balanceOf(binding.sleeve), idleBefore - preview.assets);
    }

    function testSuccessorSynchronizesAllCurrentRoyaltyBackingWithFreshBounds() external {
        string memory rpcUrl = vm.envOr("ROBINHOOD_MAINNET_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) vm.skip(true);
        vm.createSelectFork(rpcUrl);
        assertEq(block.chainid, CHAIN_ID);

        YieldBankProceedsVault vault = YieldBankProceedsVault(payable(PROCEEDS_VAULT));
        YieldBankSelfServiceExecutionRouter successor =
            new YieldBankSelfServiceExecutionRouter(ALLOCATOR);
        vm.prank(TIMELOCK);
        vault.setAllocationOperator(address(successor));

        CollectionRevenueRouter revenueRouter = CollectionRevenueRouter(payable(REVENUE_ROUTER));
        uint256 nativeBefore = REVENUE_ROUTER.balance;
        uint256 wethBefore = IERC20(WETH).balanceOf(REVENUE_ROUTER);
        uint256 usdgBefore = IERC20(USDG).balanceOf(USDG_SLEEVE);
        uint256 sleeveSupplyBefore = IERC20(USDG_SLEEVE).totalSupply();
        assertGt(nativeBefore, 0);
        assertGt(wethBefore, 0);
        assertEq(revenueRouter.accountedEscrow(address(0)), 0);
        assertEq(revenueRouter.accountedEscrow(WETH), 0);

        (uint256 minimumUsdgOut, uint256 minimumShares) =
            successor.previewRoyaltyBacking(nativeBefore);
        assertGt(minimumUsdgOut, 0);
        assertGt(minimumShares, 0);

        vm.prank(address(0xBEEF));
        (uint256 nativeSynced, uint256 wethSynced) = successor.syncRoyaltyBacking();
        assertEq(nativeSynced, nativeBefore);
        assertEq(wethSynced, wethBefore);
        assertEq(REVENUE_ROUTER.balance, 0);
        assertEq(IERC20(WETH).balanceOf(REVENUE_ROUTER), 0);
        assertEq(revenueRouter.accountedEscrow(address(0)), 0);
        assertEq(revenueRouter.accountedEscrow(WETH), 0);
        assertGt(IERC20(USDG).balanceOf(USDG_SLEEVE), usdgBefore);
        assertGt(IERC20(USDG_SLEEVE).totalSupply(), sleeveSupplyBefore);
        assertEq(IERC20(WETH).balanceOf(ALLOCATOR), 0);
        assertEq(IERC20(USDG).balanceOf(ALLOCATOR), 0);

        vm.expectRevert(YieldBankSelfServiceExecutionRouter.NoRoyaltiesToSync.selector);
        successor.syncRoyaltyBacking();
    }
}
