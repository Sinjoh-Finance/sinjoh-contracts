// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { YieldBankCollection } from "../../src/yield-banks/YieldBankCollection.sol";
import {
    CollectionPortfolioAllocator
} from "../../src/yield-banks/CollectionPortfolioAllocator.sol";
import { DeltaPoolController } from "../../src/yield-banks/DeltaPoolController.sol";
import {
    YieldBankSelfServiceExecutionRouter
} from "../../src/yield-banks/YieldBankSelfServiceExecutionRouter.sol";
import { DeltaV3SinglePoolRoute } from "../../src/yield-banks/adapters/DeltaV3SinglePoolRoute.sol";
import { DeltaV3LPAdapter } from "../../src/yield-banks/adapters/DeltaV3LPAdapter.sol";
import { MarketMakingSleeve } from "../../src/yield-banks/sleeves/MarketMakingSleeve.sol";

/// @notice Positive control for the actual dynamic-sleeve extension, using unchanged mainnet code.
/// @dev Local fork only. Proves registration and custody integration, not Stock/dividend support.
contract PiggyBanksDynamicSleeveExtensionForkTest is Test {
    YieldBankCollection private constant COLLECTION =
        YieldBankCollection(0xc275fa302Cd53DFa42D41b1C5b770661d923ba43);
    CollectionPortfolioAllocator private constant ALLOCATOR =
        CollectionPortfolioAllocator(0x42e14eA9f926ad7b530ce49d433CB6f748f8D0a1);
    address private constant NEW_POOL = 0x52e65B17fB6E5BA00Ed806f37Afcd2DaA50271Ca;
    address private constant USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;
    uint256 private constant TOKEN_ID = 334;

    function testRegisteredSleeveReceivesAndReturnsExistingBankBackingWithoutMigration() public {
        string memory rpc = vm.envOr("ROBINHOOD_MAINNET_RPC_URL", string(""));
        if (bytes(rpc).length == 0) vm.skip(true);
        vm.createSelectFork(rpc, 62_565_708);
        assertEq(block.chainid, 4663);

        DeltaPoolController controller =
            DeltaPoolController(address(ALLOCATOR.deltaPoolController()));
        YieldBankSelfServiceExecutionRouter router =
            YieldBankSelfServiceExecutionRouter(ALLOCATOR.allocationOperator());
        address account = COLLECTION.accountOf(TOKEN_ID);
        address owner = COLLECTION.nft().ownerOf(TOKEN_ID);
        uint96 feeWeight = COLLECTION.feeWeightOf(TOKEN_ID);
        uint256 supply = COLLECTION.liveSupply();
        uint256 ownerInjoh = COLLECTION.redemptionToken().balanceOf(owner);
        uint256 bankInjoh = COLLECTION.redemptionToken().balanceOf(account);
        address usdgSleeve = ALLOCATOR.sleeves(2);
        assertGt(IERC20(usdgSleeve).balanceOf(account), 0);
        assertEq(ALLOCATOR.activeDeltaPoolOf(TOKEN_ID), address(0));
        (address previous,,,,) = controller.foundationOf(NEW_POOL);
        assertEq(previous, address(0));
        assertTrue(controller.isAllocationPool(NEW_POOL));

        // This is the existing governance -> operator -> materializer path. No storage writes,
        // bytecode replacement, fabricated token balances, or implementation changes are used.
        bytes memory materialize = abi.encodeCall(
            DeltaPoolController.materializePool,
            (
                NEW_POOL,
                DeltaPoolController.MaterializationConfig({
                    maximumPositions: 1,
                    adapterCapBps: controller.maximumAdapterCapBps(),
                    maximumOperatorLossBps: controller.maximumOperatorLossBps()
                }),
                type(DeltaV3SinglePoolRoute).creationCode,
                type(MarketMakingSleeve).creationCode,
                type(DeltaV3LPAdapter).creationCode
            )
        );
        vm.prank(COLLECTION.collectionTimelock());
        bytes memory result = router.executeGovernanceCall(address(controller), materialize);
        (address newSleeve, address adapter) = abi.decode(result, (address, address));
        assertTrue(COLLECTION.isSleeveAsset(newSleeve));
        assertTrue(ALLOCATOR.isDeltaPoolSleeve(newSleeve));
        assertEq(controller.poolOfSleeve(newSleeve), NEW_POOL);
        assertGt(adapter.code.length, 0);

        uint16[3] memory target = [uint16(0), uint16(4000), uint16(6000)];
        vm.prank(owner);
        uint64 revision = ALLOCATOR.setTargetAllocation(
            TOKEN_ID, target, NEW_POOL, 100, uint48(block.timestamp + 1 hours)
        );
        CollectionPortfolioAllocator.RebalanceExecution memory execution = _execution(false);
        execution.allocations[1].minimumOutput = 1;
        execution.allocations[1].minimumShares = 1;
        vm.prank(owner);
        router.executeOwnerAllocation(TOKEN_ID, revision, execution);
        assertGt(IERC20(newSleeve).balanceOf(account), 0);
        assertGt(IERC20(usdgSleeve).balanceOf(account), 0);
        assertEq(ALLOCATOR.activeDeltaPoolOf(TOKEN_ID), NEW_POOL);

        // Return to USDG through the same allocator, exercising dynamic sleeve discovery/exit.
        target = [uint16(0), uint16(0), uint16(10000)];
        vm.prank(owner);
        revision = ALLOCATOR.setTargetAllocation(
            TOKEN_ID, target, address(0), 100, uint48(block.timestamp + 1 hours)
        );
        execution = _execution(true);
        vm.prank(owner);
        router.executeOwnerAllocation(TOKEN_ID, revision, execution);
        assertEq(IERC20(newSleeve).balanceOf(account), 0);
        assertGt(IERC20(usdgSleeve).balanceOf(account), 0);
        assertEq(ALLOCATOR.activeDeltaPoolOf(TOKEN_ID), address(0));
        assertEq(COLLECTION.accountOf(TOKEN_ID), account);
        assertEq(COLLECTION.nft().ownerOf(TOKEN_ID), owner);
        assertEq(COLLECTION.feeWeightOf(TOKEN_ID), feeWeight);
        assertEq(COLLECTION.liveSupply(), supply);
        assertEq(COLLECTION.redemptionToken().balanceOf(owner), ownerInjoh);
        assertEq(COLLECTION.redemptionToken().balanceOf(account), bankInjoh);
    }

    function _execution(bool unwindDynamic)
        private
        view
        returns (CollectionPortfolioAllocator.RebalanceExecution memory execution)
    {
        // Deliberately broad leg minima for a fork capability test. The deployed allocator's
        // separately specified 1% end-to-end owner loss limit is still enforced on both legs.
        execution.redemptions[2].minimumOutputs = new uint256[](1);
        execution.redemptions[2].minimumOutputs[0] = 1;
        if (unwindDynamic) {
            CollectionPortfolioAllocator.DeltaPoolBinding memory binding =
                ALLOCATOR.deltaPoolBinding(NEW_POOL);
            execution.deltaPoolRedemption.minimumOutputs =
                new uint256[](MarketMakingSleeve(binding.sleeve).inventoryAssets().length);
            execution.deltaPoolRedemption.minimumOutputs[0] = 1;
        }
        execution.conversions = new CollectionPortfolioAllocator.ConversionCall[](1);
        execution.conversions[0] = CollectionPortfolioAllocator.ConversionCall(USDG, 1, "");
        execution.allocations[2].minimumOutput = 1;
        execution.allocations[2].minimumShares = 1;
        execution.minimumWethRecovered = 1;
        execution.deadline = block.timestamp + 1 hours;
    }
}
