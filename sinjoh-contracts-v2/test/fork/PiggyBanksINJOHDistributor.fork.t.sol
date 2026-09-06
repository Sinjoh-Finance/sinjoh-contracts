// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    PiggyBanksINJOHDistributor,
    IPiggyBanksDistributionCollection
} from "../../src/yield-banks/PiggyBanksINJOHDistributor.sol";

contract PiggyBanksINJOHDistributorForkTest is Test {
    address private constant OPERATOR = 0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49;
    address private constant COLLECTION = 0xc275fa302Cd53DFa42D41b1C5b770661d923ba43;
    address private constant INJOH = 0x2cC0FAC44B8252f6B10208B091aFf2c94B4da77D;
    uint256 private constant TOKEN_COUNT = 3_333;
    uint256 private constant TOTAL_WEIGHT = 8_130;
    uint256 private constant TARGET_AMOUNT = 6_000_000 ether;

    PiggyBanksINJOHDistributor private distributor;
    IPiggyBanksDistributionCollection private collection;
    IERC20 private injoh;

    function setUp() external {
        vm.createSelectFork(vm.envString("YIELD_BANK_RPC_URL"));
        distributor = new PiggyBanksINJOHDistributor();
        collection = IPiggyBanksDistributionCollection(COLLECTION);
        injoh = IERC20(INJOH);
    }

    function testConstructorBindsExactProductionSystem() external view {
        assertEq(distributor.COLLECTION(), COLLECTION);
        assertEq(distributor.INJOH(), INJOH);
        assertEq(distributor.OPERATOR(), OPERATOR);
        assertEq(distributor.TARGET_AMOUNT(), TARGET_AMOUNT);
        assertEq(distributor.TOKEN_COUNT(), TOKEN_COUNT);
        assertEq(distributor.TOTAL_WEIGHT(), TOTAL_WEIGHT);
        assertEq(distributor.remainingFunding(), TARGET_AMOUNT);
        assertEq(distributor.nextTokenId(), 1);
    }

    function testDistributionCannotStartUntilFullyFunded() external {
        uint256 partialAmount = TARGET_AMOUNT - 1;
        vm.prank(OPERATOR);
        injoh.transfer(address(distributor), partialAmount);

        vm.expectRevert(
            abi.encodeWithSelector(
                PiggyBanksINJOHDistributor.FundingIncomplete.selector, TARGET_AMOUNT, partialAmount
            )
        );
        distributor.distribute(64);
    }

    function testExcessRecoveryCannotRemoveContributionPrincipal() external {
        uint256 excess = 17 ether;
        uint256 operatorBalanceBefore = injoh.balanceOf(OPERATOR);
        vm.prank(OPERATOR);
        injoh.transfer(address(distributor), TARGET_AMOUNT + excess);

        vm.prank(OPERATOR);
        assertEq(distributor.recoverExcess(), excess);
        assertEq(injoh.balanceOf(address(distributor)), TARGET_AMOUNT);
        assertEq(injoh.balanceOf(OPERATOR), operatorBalanceBefore - TARGET_AMOUNT);
    }

    function testDistributesExactWeightedAmountsToEveryBankWithoutResidue() external {
        uint256[] memory balancesBefore = new uint256[](TOKEN_COUNT);
        for (uint256 tokenId = 1; tokenId <= TOKEN_COUNT; ++tokenId) {
            address account = collection.accountOf(tokenId);
            assertNotEq(account, address(0), "missing production bank account");
            balancesBefore[tokenId - 1] = injoh.balanceOf(account);
        }

        uint256 operatorBalanceBefore = injoh.balanceOf(OPERATOR);
        vm.prank(OPERATOR);
        injoh.transfer(address(distributor), TARGET_AMOUNT);
        assertEq(injoh.balanceOf(OPERATOR), operatorBalanceBefore - TARGET_AMOUNT);
        assertEq(distributor.remainingFunding(), 0);

        while (distributor.nextTokenId() <= TOKEN_COUNT) {
            distributor.distribute(64);
        }

        uint256 runningWeight;
        uint256 runningEntitlement;
        uint256 receivedTotal;
        for (uint256 tokenId = 1; tokenId <= TOKEN_COUNT; ++tokenId) {
            uint256 weight = collection.feeWeightOf(tokenId);
            runningWeight += weight;
            uint256 cumulativeEntitlement = TARGET_AMOUNT * runningWeight / TOTAL_WEIGHT;
            uint256 expectedAmount = cumulativeEntitlement - runningEntitlement;
            runningEntitlement = cumulativeEntitlement;

            address account = collection.accountOf(tokenId);
            uint256 received = injoh.balanceOf(account) - balancesBefore[tokenId - 1];
            assertEq(received, expectedAmount, "incorrect bank allocation");
            receivedTotal += received;
        }

        assertEq(runningWeight, TOTAL_WEIGHT);
        assertEq(receivedTotal, TARGET_AMOUNT);
        assertEq(distributor.totalDistributed(), TARGET_AMOUNT);
        assertEq(distributor.cumulativeWeight(), TOTAL_WEIGHT);
        assertEq(distributor.nextTokenId(), TOKEN_COUNT + 1);
        assertEq(injoh.balanceOf(address(distributor)), 0);
        assertEq(distributor.remainingFunding(), 0);

        vm.expectRevert(PiggyBanksINJOHDistributor.DistributionAlreadyComplete.selector);
        distributor.distribute(1);
    }
}
