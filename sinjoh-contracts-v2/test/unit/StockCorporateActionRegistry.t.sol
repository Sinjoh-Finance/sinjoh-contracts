// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import {
    StockCorporateActionRegistry as Registry
} from "../../src/yield-banks/stock/StockCorporateActionRegistry.sol";
import {
    StockDividendAccounting as Accounting
} from "../../src/yield-banks/stock/StockDividendAccounting.sol";

contract StockMultiplierMock {
    uint256 public uiMultiplier = 100;
    bool public oraclePaused;

    function set(uint256 multiplier, bool paused) external {
        uiMultiplier = multiplier;
        oraclePaused = paused;
    }
}

contract StockCorporateActionRegistryTest is Test {
    Registry r;
    StockMultiplierMock stock;

    function setUp() public {
        vm.warp(1000);
        r = new Registry(address(this));
        stock = new StockMultiplierMock();
        r.register(address(stock), keccak256("reviewed manifest"));
    }

    function action(uint256 m0, uint256 m1, Accounting.ActionKind kind, bytes32 id)
        private
        view
        returns (Registry.Action memory)
    {
        return Registry.Action(
            m0,
            m1,
            uint48(block.timestamp),
            kind,
            keccak256("issuer and canonical log evidence"),
            id
        );
    }

    function testUnknownChangeBlocksUntilGovernanceClassification() public {
        (uint64 sequence, uint256 multiplier) = r.requireCurrent(address(stock), true);
        assertEq(sequence, 0);
        assertEq(multiplier, 100);
        stock.set(102, false);
        vm.expectRevert(Registry.AssetNotCurrent.selector);
        r.requireCurrent(address(stock), true);
        Registry.Action memory a =
            action(100, 102, Accounting.ActionKind.CashDividend, bytes32(uint256(1)));
        vm.prank(address(0xBAD));
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(0xBAD))
        );
        r.publish(address(stock), a);
        r.publish(address(stock), a);
        (sequence, multiplier) = r.requireCurrent(address(stock), true);
        assertEq(sequence, 1);
        assertEq(multiplier, 102);
        assertEq(r.actionAt(address(stock), 1).evidenceHash, a.evidenceHash);
        vm.expectRevert(Registry.InvalidEvidence.selector);
        r.publish(address(stock), a);
    }

    function testFutureOrUnobservedChangeCannotAuthorizeDividend() public {
        Registry.Action memory a =
            action(100, 102, Accounting.ActionKind.CashDividend, bytes32(uint256(1)));
        vm.expectRevert(Registry.AssetNotCurrent.selector);
        r.publish(address(stock), a);
        stock.set(102, false);
        a.effectiveAt = uint48(block.timestamp + 1);
        vm.expectRevert(Registry.InvalidAction.selector);
        r.publish(address(stock), a);
        a.effectiveAt = uint48(block.timestamp);
        a.evidenceHash = bytes32(0);
        vm.expectRevert(Registry.InvalidEvidence.selector);
        r.publish(address(stock), a);
    }

    function testReverseSplitClassifiedButOraclePauseStillBlocks() public {
        stock.set(10, true);
        Registry.Action memory a =
            action(100, 10, Accounting.ActionKind.CashDividend, bytes32(uint256(1)));
        vm.expectRevert(Registry.InvalidAction.selector);
        r.publish(address(stock), a);
        a.kind = Accounting.ActionKind.NonDividend;
        r.publish(address(stock), a);
        vm.expectRevert(Registry.AssetNotCurrent.selector);
        r.requireCurrent(address(stock), false);
        stock.set(10, false);
        (, uint256 multiplier) = r.requireCurrent(address(stock), false);
        assertEq(multiplier, 10);
    }

    function testAdmissionRevocationAllowsExistingExitButNotNewFunds() public {
        r.setEnabled(address(stock), false);
        vm.expectRevert(Registry.InvalidAsset.selector);
        r.requireCurrent(address(stock), true);
        r.requireCurrent(address(stock), false);
        stock.set(102, false);
        r.publish(
            address(stock),
            action(100, 102, Accounting.ActionKind.CashDividend, bytes32(uint256(1)))
        );
        r.requireCurrent(address(stock), false);
        r.pause();
        vm.expectRevert(Pausable.EnforcedPause.selector);
        r.requireCurrent(address(stock), false);
        r.unpause();
        r.requireCurrent(address(stock), false);
    }

    function testCannotResetCheckpointOrRewriteFinalizedHistory() public {
        vm.expectRevert(Registry.InvalidAsset.selector);
        r.register(address(stock), bytes32(uint256(2)));
        stock.set(102, false);
        r.publish(
            address(stock),
            action(100, 102, Accounting.ActionKind.CashDividend, bytes32(uint256(1)))
        );
        stock.set(104, false);
        vm.expectRevert(Registry.InvalidAction.selector);
        r.publish(
            address(stock),
            action(100, 104, Accounting.ActionKind.CashDividend, bytes32(uint256(2)))
        );
        r.publish(
            address(stock),
            action(102, 104, Accounting.ActionKind.CashDividend, bytes32(uint256(2)))
        );
        assertEq(r.actionAt(address(stock), 1).afterMultiplier, 102);
        assertEq(r.actionAt(address(stock), 2).beforeMultiplier, 102);
    }

    function testQueuedDividendAndSplitHistoryCanBePublishedAtomically() public {
        stock.set(1020, false);
        Registry.Action[] memory actions = new Registry.Action[](2);
        actions[0] = action(100, 102, Accounting.ActionKind.CashDividend, bytes32(uint256(11)));
        actions[1] = action(102, 1020, Accounting.ActionKind.NonDividend, bytes32(uint256(12)));
        vm.expectRevert(Registry.AssetNotCurrent.selector);
        r.publish(address(stock), actions[0]);
        r.publishBatch(address(stock), actions);
        (uint64 sequence, uint256 multiplier) = r.requireCurrent(address(stock), false);
        assertEq(sequence, 2);
        assertEq(multiplier, 1020);
        assertEq(
            uint8(r.actionAt(address(stock), 1).kind), uint8(Accounting.ActionKind.CashDividend)
        );
        assertEq(
            uint8(r.actionAt(address(stock), 2).kind), uint8(Accounting.ActionKind.NonDividend)
        );
    }

    function testIncompleteOrReorderedBatchCannotPartiallyAdvanceRegistry() public {
        stock.set(104, false);
        Registry.Action[] memory actions = new Registry.Action[](2);
        actions[0] = action(100, 102, Accounting.ActionKind.CashDividend, bytes32(uint256(11)));
        actions[1] = action(103, 104, Accounting.ActionKind.CashDividend, bytes32(uint256(12)));
        vm.expectRevert(Registry.InvalidAction.selector);
        r.publishBatch(address(stock), actions);
        (, uint64 sequence,,,) = r.assets(address(stock));
        assertEq(sequence, 0);
        assertFalse(r.usedSource(bytes32(uint256(11))));
        actions[1].beforeMultiplier = 102;
        actions[1].afterMultiplier = 103;
        vm.expectRevert(Registry.AssetNotCurrent.selector);
        r.publishBatch(address(stock), actions);
        (, sequence,,,) = r.assets(address(stock));
        assertEq(sequence, 0);
    }
}
