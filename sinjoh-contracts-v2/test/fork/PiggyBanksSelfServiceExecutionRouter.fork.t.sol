// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    CollectionPortfolioAllocator
} from "../../src/yield-banks/CollectionPortfolioAllocator.sol";
import { DeltaV3LPAdapter } from "../../src/yield-banks/adapters/DeltaV3LPAdapter.sol";
import {
    YieldBankSelfServiceExecutionRouter
} from "../../src/yield-banks/YieldBankSelfServiceExecutionRouter.sol";
import { YieldBankProceedsVault } from "../../src/yield-banks/YieldBankProceedsVault.sol";

contract PiggyBanksSelfServiceExecutionRouterForkTest is Test {
    uint256 private constant CHAIN_ID = 4663;
    address private constant ALLOCATOR = 0x42e14eA9f926ad7b530ce49d433CB6f748f8D0a1;
    address private constant PROCEEDS_VAULT = 0xa9653463ffdE4e2352b4659334f785159d7525FD;
    address private constant TIMELOCK = 0x7C15804A2d7F5981035895CAb953e5E76393E1B8;
    address private constant DELTA_POOL = 0xB09fa4f04032b9d9e690ac4a1d29523b5f9A72DC;

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

        vm.prank(address(0xBEEF));
        uint256 units = router.deployIdleDelta(DELTA_POOL);
        assertGt(units, 0);
        assertEq(adapter.positionIds().length, positionsBefore + 1);
        assertGt(adapter.totalManagedAssets(), 0);
        assertEq(IERC20(router.weth()).balanceOf(binding.sleeve), idleBefore - preview.assets);
    }
}
