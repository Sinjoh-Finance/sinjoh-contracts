// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { YieldBankAccount } from "../../src/yield-banks/YieldBankAccount.sol";
import {
    MockYieldBankAsset,
    MockYieldBankDistributorHarness
} from "../mocks/MockYieldBankIntegrations.sol";

contract RetryableDistributionAsset is ERC20 {
    address public rejectedRecipient;

    constructor() ERC20("Retryable distribution asset", "RETRY") { }

    function mint(address recipient, uint256 amount) external {
        _mint(recipient, amount);
    }

    function setRejectedRecipient(address recipient) external {
        rejectedRecipient = recipient;
    }

    function _update(address from, address to, uint256 value) internal override {
        require(to == address(0) || to != rejectedRecipient, "recipient rejected");
        super._update(from, to, value);
    }
}

contract YieldBankDistributorCapacityTest is Test {
    function testMaximumAssetSettlementRemainsBoundedAndTracksEveryNonzeroAsset() external {
        MockYieldBankDistributorHarness harness = new MockYieldBankDistributorHarness();
        for (uint256 i; i < 64; ++i) {
            MockYieldBankAsset asset = new MockYieldBankAsset("Distribution asset", "DIST");
            harness.registerAsset(address(asset));
            asset.mint(address(harness), 1 ether);
            harness.accrue(address(asset), 1 ether, 1);
        }
        address account = harness.createAccount(1);

        uint256 gasBefore = gasleft();
        harness.settle(1, account, true);
        uint256 gasUsed = gasBefore - gasleft();

        assertEq(YieldBankAccount(account).trackedAssets().length, 64);
        assertLt(gasUsed, 12_000_000);
    }

    function testMaximumSettlementAlsoSucceedsWithActiveDynamicDeltaSleeve() external {
        MockYieldBankDistributorHarness harness = new MockYieldBankDistributorHarness();
        address account = harness.createAccount(1);
        MockYieldBankAsset dynamicSleeve =
            new MockYieldBankAsset("Dynamic Delta sleeve", "DELTA-SHARE");
        harness.trackAccountAsset(account, address(dynamicSleeve));

        for (uint256 i; i < 64; ++i) {
            MockYieldBankAsset asset = new MockYieldBankAsset("Distribution asset", "DIST");
            harness.registerAsset(address(asset));
            asset.mint(address(harness), 1 ether);
            harness.accrue(address(asset), 1 ether, 1);
        }

        harness.settle(1, account, true);

        assertEq(YieldBankAccount(account).trackedAssets().length, 65);
    }

    function testSettlementIsIdempotentAndPreservesFractionalDebt() external {
        MockYieldBankDistributorHarness harness = new MockYieldBankDistributorHarness();
        MockYieldBankAsset asset = new MockYieldBankAsset("Distribution asset", "DIST");
        harness.registerAsset(address(asset));
        address account = harness.createAccount(1);

        asset.mint(address(harness), 10 ether + 3);
        harness.accrue(address(asset), 10 ether, 3);
        harness.settle(1, account, false);
        uint256 firstSettlement = asset.balanceOf(account);
        assertEq(firstSettlement, 3_333_333_333_333_333_333);

        harness.settle(1, account, false);
        assertEq(asset.balanceOf(account), firstSettlement);

        harness.accrue(address(asset), 3, 3);
        harness.settle(1, account, false);
        assertEq(asset.balanceOf(account), firstSettlement + 1);
    }

    function testTokenCreatedAfterAccrualCannotClaimEarlierYield() external {
        MockYieldBankDistributorHarness harness = new MockYieldBankDistributorHarness();
        MockYieldBankAsset asset = new MockYieldBankAsset("Distribution asset", "DIST");
        harness.registerAsset(address(asset));
        harness.createAccount(1);

        asset.mint(address(harness), 14 ether);
        harness.accrue(address(asset), 10 ether, 1);
        address laterAccount = harness.createAccount(2);
        harness.settle(2, laterAccount, false);
        assertEq(asset.balanceOf(laterAccount), 0);

        harness.accrue(address(asset), 4 ether, 2);
        harness.settle(2, laterAccount, false);
        assertEq(asset.balanceOf(laterAccount), 2 ether);
    }

    function testFinalTokenReceivesAllRoundingDustAndDrainsLiability() external {
        MockYieldBankDistributorHarness harness = new MockYieldBankDistributorHarness();
        MockYieldBankAsset asset = new MockYieldBankAsset("Distribution asset", "DIST");
        harness.registerAsset(address(asset));
        address first = harness.createAccount(1);
        address second = harness.createAccount(2);
        address finalAccount = harness.createAccount(3);

        asset.mint(address(harness), 10);
        harness.accrue(address(asset), 10, 3);
        harness.settle(1, first, false);
        harness.settle(2, second, false);
        harness.settle(3, finalAccount, true);

        assertEq(asset.balanceOf(first), 3);
        assertEq(asset.balanceOf(second), 3);
        assertEq(asset.balanceOf(finalAccount), 4);
        assertEq(harness.distributor().accountedBalance(address(asset)), 0);
        assertEq(harness.distributor().totalSettled(address(asset)), 10);
        assertTrue(harness.distributor().solvent(address(asset)));
    }

    function testSettlementFailureRollsBackAndCanBeRetriedWithoutLosingYield() external {
        MockYieldBankDistributorHarness harness = new MockYieldBankDistributorHarness();
        RetryableDistributionAsset asset = new RetryableDistributionAsset();
        harness.registerAsset(address(asset));
        address account = harness.createAccount(1);
        asset.mint(address(harness), 7 ether);
        harness.accrue(address(asset), 7 ether, 1);
        asset.setRejectedRecipient(account);

        vm.expectRevert("recipient rejected");
        harness.settle(1, account, false);
        assertEq(harness.distributor().pending(1, address(asset)), 7 ether);
        assertEq(harness.distributor().accountedBalance(address(asset)), 7 ether);
        assertEq(harness.distributor().totalSettled(address(asset)), 0);

        asset.setRejectedRecipient(address(0));
        harness.settle(1, account, false);
        assertEq(asset.balanceOf(account), 7 ether);
        assertEq(harness.distributor().pending(1, address(asset)), 0);
        assertEq(harness.distributor().accountedBalance(address(asset)), 0);
        assertEq(harness.distributor().totalSettled(address(asset)), 7 ether);
    }
}
