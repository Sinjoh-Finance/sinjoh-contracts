// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { YieldBankAccount } from "../../src/yield-banks/YieldBankAccount.sol";
import {
    MockYieldBankAsset,
    MockYieldBankDistributorHarness
} from "../mocks/MockYieldBankIntegrations.sol";

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
}
