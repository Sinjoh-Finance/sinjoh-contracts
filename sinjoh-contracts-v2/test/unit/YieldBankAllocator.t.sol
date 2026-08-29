// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import {
    CollectionPortfolioAllocator
} from "../../src/yield-banks/CollectionPortfolioAllocator.sol";
import {
    MockYieldBankAsset,
    MockYieldBankCollectionPointer,
    MockYieldBankSleeve
} from "../mocks/MockYieldBankIntegrations.sol";

contract YieldBankAllocatorTest is Test {
    MockYieldBankAsset private input;
    MockYieldBankCollectionPointer private collection;
    MockYieldBankSleeve private core;
    MockYieldBankSleeve private market;
    MockYieldBankSleeve private yieldSleeve;
    CollectionPortfolioAllocator private allocator;

    function setUp() public {
        input = new MockYieldBankAsset("Wrapped Ether", "WETH");
        collection = new MockYieldBankCollectionPointer();
        core = new MockYieldBankSleeve(address(input), "CORE");
        market = new MockYieldBankSleeve(address(input), "MARKET");
        yieldSleeve = new MockYieldBankSleeve(address(input), "YIELD");
        allocator = new CollectionPortfolioAllocator(
            address(collection),
            address(this),
            address(this),
            address(this),
            address(core),
            address(market),
            address(yieldSleeve),
            4_000,
            3_750,
            2_250
        );
        collection.setProceedsVault(address(this));
        input.mint(address(this), 1_000 ether);
        input.approve(address(allocator), type(uint256).max);
    }

    function allocationOperator() external view returns (address) {
        return address(this);
    }

    function testPrimaryAllocationUsesConfiguredImmutableWeights() public {
        CollectionPortfolioAllocator.AllocationCall[3] memory calls;
        calls[0].minimumOutput = 400 ether;
        calls[0].minimumShares = 400 ether;
        calls[1].minimumOutput = 375 ether;
        calls[1].minimumShares = 375 ether;
        calls[2].minimumOutput = 225 ether;
        calls[2].minimumShares = 225 ether;
        (address[] memory assets, uint256[] memory shares) =
            allocator.allocatePrimary(address(input), 1_000 ether, address(this), calls);
        assertEq(assets[0], address(core));
        assertEq(shares[0], 400 ether);
        assertEq(assets[1], address(market));
        assertEq(shares[1], 375 ether);
        assertEq(assets[2], address(yieldSleeve));
        assertEq(shares[2], 225 ether);
        assertEq(allocator.coreWeightBps(), 4_000);
        assertEq(allocator.marketMakingWeightBps(), 3_750);
        assertEq(allocator.usdgWeightBps(), 2_250);
        assertEq(input.balanceOf(address(allocator)), 0);
        assertEq(input.allowance(address(allocator), address(core)), 0);
        assertEq(input.allowance(address(allocator), address(market)), 0);
        assertEq(input.allowance(address(allocator), address(yieldSleeve)), 0);
    }

    function testPrimaryAllocationRequiresExplicitOutputAndShareFloors() public {
        CollectionPortfolioAllocator.AllocationCall[3] memory calls;
        vm.expectRevert(CollectionPortfolioAllocator.InvalidConfiguration.selector);
        allocator.allocatePrimary(address(input), 1_000 ether, address(this), calls);
    }

    function testConstructorRejectsWeightsThatDoNotSumToOneHundredPercent() public {
        vm.expectRevert(CollectionPortfolioAllocator.InvalidConfiguration.selector);
        new CollectionPortfolioAllocator(
            address(collection),
            address(this),
            address(this),
            address(this),
            address(core),
            address(market),
            address(yieldSleeve),
            4_000,
            3_750,
            2_000
        );
    }

    function testOnlyCollectionProceedsVaultCanAllocatePrimary() public {
        collection.setProceedsVault(address(0xBEEF));
        CollectionPortfolioAllocator.AllocationCall[3] memory calls;
        vm.expectRevert(
            abi.encodeWithSelector(
                CollectionPortfolioAllocator.OnlyProceedsVault.selector, address(this)
            )
        );
        allocator.allocatePrimary(address(input), 1_000 ether, address(this), calls);
    }

    function testAllocationOperatorCanReachSleeveAdapterActions() public {
        address adapter = address(0xADA7);
        uint256 positionUnits =
            allocator.depositToAdapter(address(market), adapter, 25 ether, 25 ether, "");
        assertEq(positionUnits, 25 ether);
        assertEq(market.lastAdapter(), adapter);
        assertEq(market.lastAdapterAssets(), 25 ether);

        address caller = address(0xBAD);
        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                CollectionPortfolioAllocator.OnlyAllocationOperator.selector, caller
            )
        );
        allocator.depositToAdapter(address(market), adapter, 1 ether, 1 ether, "");
    }
}
