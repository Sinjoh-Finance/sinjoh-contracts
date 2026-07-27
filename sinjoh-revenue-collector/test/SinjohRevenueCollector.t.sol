// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SinjohRevenueCollector } from "../src/SinjohRevenueCollector.sol";
import { TestBase } from "./TestBase.sol";
import { FeeOnTransferToken, MockERC20 } from "./mocks/MockERC20.sol";
import { ReentrantProcessor, RejectingProcessor } from "./mocks/MockProcessors.sol";

contract SinjohRevenueCollectorTest is TestBase {
    address internal constant GOVERNANCE = address(0xA11CE);
    address internal constant PROCESSOR = address(0xBEEF);
    address internal constant OUTSIDER = address(0xBAD);

    SinjohRevenueCollector internal collector;
    MockERC20 internal token;

    receive() external payable { }

    function setUp() public {
        collector = new SinjohRevenueCollector(GOVERNANCE, PROCESSOR);
        token = new MockERC20();
    }

    function testInitialConfiguration() public view {
        assertEq(collector.owner(), GOVERNANCE);
        assertEq(collector.processor(), PROCESSOR);
        assertEq(collector.NATIVE_ASSET(), address(0));
    }

    function testConstructorRejectsInvalidProcessor() public {
        vm.expectPartialRevert(SinjohRevenueCollector.InvalidProcessor.selector);
        new SinjohRevenueCollector(GOVERNANCE, address(0));
    }

    function testOnlyGovernanceCanSetProcessor() public {
        vm.prank(OUTSIDER);
        vm.expectPartialRevert(Ownable.OwnableUnauthorizedAccount.selector);
        collector.setProcessor(address(0xCAFE));
    }

    function testGovernanceCanSetProcessor() public {
        vm.prank(GOVERNANCE);
        collector.setProcessor(address(0xCAFE));
        assertEq(collector.processor(), address(0xCAFE));
    }

    function testProcessorCannotBeZeroOrCollector() public {
        vm.prank(GOVERNANCE);
        vm.expectPartialRevert(SinjohRevenueCollector.InvalidProcessor.selector);
        collector.setProcessor(address(0));

        vm.prank(GOVERNANCE);
        vm.expectPartialRevert(SinjohRevenueCollector.InvalidProcessor.selector);
        collector.setProcessor(address(collector));
    }

    function testOwnershipTransferRequiresAcceptance() public {
        address nextGovernance = address(0xCAFE);

        vm.prank(GOVERNANCE);
        collector.transferOwnership(nextGovernance);

        assertEq(collector.owner(), GOVERNANCE);
        assertEq(collector.pendingOwner(), nextGovernance);

        vm.prank(nextGovernance);
        collector.acceptOwnership();

        assertEq(collector.owner(), nextGovernance);
        assertEq(collector.pendingOwner(), address(0));
    }

    function testOwnershipCannotBeRenounced() public {
        vm.prank(GOVERNANCE);
        vm.expectRevert(SinjohRevenueCollector.OwnershipRenunciationDisabled.selector);
        collector.renounceOwnership();

        assertEq(collector.owner(), GOVERNANCE);
    }

    function testAnyoneCanForwardExactNativeAmount() public {
        uint256 amount = 3 ether;
        vm.deal(address(collector), amount);

        vm.prank(OUTSIDER);
        collector.forward(address(0), 1 ether);

        assertEq(PROCESSOR.balance, 1 ether);
        assertEq(address(collector).balance, 2 ether);
    }

    function testFuzzForwardAllNative(uint256 rawAmount) public {
        uint256 amount = (rawAmount % 1_000_000 ether) + 1;
        vm.deal(address(collector), amount);

        vm.prank(OUTSIDER);
        collector.forwardAll(address(0));

        assertEq(PROCESSOR.balance, amount);
        assertEq(address(collector).balance, 0);
    }

    function testAnyoneCanForwardExactERC20Amount() public {
        token.mint(address(collector), 100 ether);

        vm.prank(OUTSIDER);
        collector.forward(address(token), 40 ether);

        assertEq(token.balanceOf(PROCESSOR), 40 ether);
        assertEq(token.balanceOf(address(collector)), 60 ether);
    }

    function testFuzzForwardAllERC20(uint256 rawAmount) public {
        uint256 amount = (rawAmount % 1_000_000 ether) + 1;
        token.mint(address(collector), amount);

        vm.prank(OUTSIDER);
        collector.forwardAll(address(token));

        assertEq(token.balanceOf(PROCESSOR), amount);
        assertEq(token.balanceOf(address(collector)), 0);
    }

    function testProcessorChangeOnlyAffectsFutureForwarding() public {
        address nextProcessor = address(0xCAFE);
        token.mint(address(collector), 2 ether);
        collector.forward(address(token), 1 ether);

        vm.prank(GOVERNANCE);
        collector.setProcessor(nextProcessor);
        collector.forwardAll(address(token));

        assertEq(token.balanceOf(PROCESSOR), 1 ether);
        assertEq(token.balanceOf(nextProcessor), 1 ether);
    }

    function testRejectsZeroAmountAndInsufficientBalance() public {
        vm.expectRevert(SinjohRevenueCollector.ZeroAmount.selector);
        collector.forward(address(token), 0);

        vm.expectPartialRevert(SinjohRevenueCollector.InsufficientBalance.selector);
        collector.forward(address(token), 1);
    }

    function testFeeOnTransferTokenRevertsWithoutLosingFunds() public {
        FeeOnTransferToken feeToken = new FeeOnTransferToken();
        feeToken.mint(address(collector), 100 ether);

        vm.expectPartialRevert(SinjohRevenueCollector.InexactTransfer.selector);
        collector.forwardAll(address(feeToken));

        assertEq(feeToken.balanceOf(address(collector)), 100 ether);
        assertEq(feeToken.balanceOf(PROCESSOR), 0);
    }

    function testRejectingNativeProcessorCannotDrainCollector() public {
        RejectingProcessor rejectingProcessor = new RejectingProcessor();
        vm.prank(GOVERNANCE);
        collector.setProcessor(address(rejectingProcessor));
        vm.deal(address(collector), 1 ether);

        vm.expectRevert(SinjohRevenueCollector.NativeTransferFailed.selector);
        collector.forwardAll(address(0));

        assertEq(address(collector).balance, 1 ether);
        assertEq(address(rejectingProcessor).balance, 0);
    }

    function testNativeReentrancyRevertsWithoutLosingFunds() public {
        ReentrantProcessor reentrantProcessor = new ReentrantProcessor(address(collector));
        vm.prank(GOVERNANCE);
        collector.setProcessor(address(reentrantProcessor));
        vm.deal(address(collector), 2 ether);

        vm.expectRevert(SinjohRevenueCollector.NativeTransferFailed.selector);
        collector.forwardAll(address(0));

        assertEq(address(collector).balance, 2 ether);
        assertEq(address(reentrantProcessor).balance, 0);
    }
}
