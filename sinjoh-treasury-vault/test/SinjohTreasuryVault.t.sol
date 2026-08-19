// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { SinjohTreasuryVault } from "../src/SinjohTreasuryVault.sol";
import { TestBase } from "./TestBase.sol";
import { FeeOnTransferToken, MockERC20 } from "./mocks/MockERC20.sol";
import { ReentrantRecipient, RejectingRecipient } from "./mocks/MockRecipients.sol";

contract SinjohTreasuryVaultTest is TestBase {
    address internal constant GOVERNOR = address(0xA11CE);
    address internal constant RECIPIENT = address(0xBEEF);
    address internal constant OUTSIDER = address(0xBAD);
    address internal constant RECOVERY = address(0x5AFE);
    uint256 internal constant HANDOFF_DELAY = 3 days;
    uint256 internal constant INACTIVITY_PERIOD = 180 days;
    uint256 internal constant START = 1_000_000;

    SinjohTreasuryVault internal vault;
    SinjohTreasuryVault internal recoverableVault;
    MockERC20 internal token;

    receive() external payable { }

    function setUp() public {
        vm.warp(START);
        vault = new SinjohTreasuryVault(GOVERNOR, HANDOFF_DELAY, address(0), 0);
        recoverableVault =
            new SinjohTreasuryVault(GOVERNOR, HANDOFF_DELAY, RECOVERY, INACTIVITY_PERIOD);
        token = new MockERC20();
    }

    function _fundNative(SinjohTreasuryVault target, uint256 amount) internal {
        vm.deal(address(this), amount);
        (bool success,) = address(target).call{ value: amount }("");
        assertTrue(success);
    }

    function testInitialConfiguration() public view {
        assertEq(vault.governor(), GOVERNOR);
        assertEq(vault.GOVERNOR_HANDOFF_DELAY(), HANDOFF_DELAY);
        assertEq(vault.RECOVERY_ADDRESS(), address(0));
        assertEq(vault.RECOVERY_INACTIVITY_PERIOD(), 0);
        assertEq(vault.pendingGovernor(), address(0));
        assertEq(vault.lastGovernorActionAt(), START);
        assertEq(vault.NATIVE_ASSET(), address(0));
    }

    function testConstructorRejectsZeroGovernor() public {
        vm.expectPartialRevert(SinjohTreasuryVault.InvalidGovernor.selector);
        new SinjohTreasuryVault(address(0), HANDOFF_DELAY, address(0), 0);
    }

    function testConstructorRejectsZeroHandoffDelay() public {
        vm.expectRevert(SinjohTreasuryVault.InvalidHandoffDelay.selector);
        new SinjohTreasuryVault(GOVERNOR, 0, address(0), 0);
    }

    function testConstructorRejectsInconsistentRecoveryConfiguration() public {
        vm.expectPartialRevert(SinjohTreasuryVault.InvalidRecoveryConfiguration.selector);
        new SinjohTreasuryVault(GOVERNOR, HANDOFF_DELAY, RECOVERY, 0);

        vm.expectPartialRevert(SinjohTreasuryVault.InvalidRecoveryConfiguration.selector);
        new SinjohTreasuryVault(GOVERNOR, HANDOFF_DELAY, address(0), INACTIVITY_PERIOD);

        vm.expectPartialRevert(SinjohTreasuryVault.InvalidRecoveryConfiguration.selector);
        new SinjohTreasuryVault(GOVERNOR, HANDOFF_DELAY, GOVERNOR, INACTIVITY_PERIOD);
    }

    function testReceivesNativeCurrency() public {
        _fundNative(vault, 5 ether);
        assertEq(address(vault).balance, 5 ether);
    }

    function testOnlyGovernorCanTransfer() public {
        _fundNative(vault, 1 ether);
        vm.prank(OUTSIDER);
        vm.expectPartialRevert(SinjohTreasuryVault.NotGovernor.selector);
        vault.transfer(address(0), 1 ether, RECIPIENT);
    }

    function testTransfersNativeCurrency() public {
        _fundNative(vault, 5 ether);

        vm.prank(GOVERNOR);
        vault.transfer(address(0), 2 ether, RECIPIENT);

        assertEq(address(vault).balance, 3 ether);
        assertEq(RECIPIENT.balance, 2 ether);
    }

    function testTransfersToken() public {
        token.mint(address(vault), 100);

        vm.prank(GOVERNOR);
        vault.transfer(address(token), 60, RECIPIENT);

        assertEq(token.balanceOf(address(vault)), 40);
        assertEq(token.balanceOf(RECIPIENT), 60);
    }

    function testTransferRejectsZeroAmount() public {
        vm.prank(GOVERNOR);
        vm.expectRevert(SinjohTreasuryVault.ZeroAmount.selector);
        vault.transfer(address(0), 0, RECIPIENT);
    }

    function testTransferRejectsInvalidRecipient() public {
        vm.prank(GOVERNOR);
        vm.expectPartialRevert(SinjohTreasuryVault.InvalidRecipient.selector);
        vault.transfer(address(0), 1, address(0));

        vm.prank(GOVERNOR);
        vm.expectPartialRevert(SinjohTreasuryVault.InvalidRecipient.selector);
        vault.transfer(address(0), 1, address(vault));
    }

    function testTransferRejectsInsufficientNativeBalance() public {
        _fundNative(vault, 1 ether);
        vm.prank(GOVERNOR);
        vm.expectPartialRevert(SinjohTreasuryVault.InsufficientBalance.selector);
        vault.transfer(address(0), 2 ether, RECIPIENT);
    }

    function testTransferRejectsInsufficientTokenBalance() public {
        token.mint(address(vault), 10);
        vm.prank(GOVERNOR);
        vm.expectPartialRevert(SinjohTreasuryVault.InsufficientBalance.selector);
        vault.transfer(address(token), 11, RECIPIENT);
    }

    function testTransferRejectsFeeOnTransferToken() public {
        FeeOnTransferToken feeToken = new FeeOnTransferToken();
        feeToken.mint(address(vault), 100);

        vm.prank(GOVERNOR);
        vm.expectPartialRevert(SinjohTreasuryVault.InexactTransfer.selector);
        vault.transfer(address(feeToken), 100, RECIPIENT);
    }

    function testTransferRejectsRejectingNativeRecipient() public {
        RejectingRecipient rejecting = new RejectingRecipient();
        _fundNative(vault, 1 ether);

        vm.prank(GOVERNOR);
        vm.expectRevert(SinjohTreasuryVault.NativeTransferFailed.selector);
        vault.transfer(address(0), 1 ether, address(rejecting));
    }

    function testTransferBlocksReentrantNativeRecipient() public {
        ReentrantRecipient reentrant = new ReentrantRecipient(address(vault));
        _fundNative(vault, 1 ether);

        vm.prank(GOVERNOR);
        vm.expectRevert(SinjohTreasuryVault.NativeTransferFailed.selector);
        vault.transfer(address(0), 1 ether, address(reentrant));
    }

    function testNominationRequiresGovernor() public {
        vm.prank(OUTSIDER);
        vm.expectPartialRevert(SinjohTreasuryVault.NotGovernor.selector);
        vault.nominateGovernor(OUTSIDER);
    }

    function testNominationRejectsInvalidSuccessor() public {
        vm.prank(GOVERNOR);
        vm.expectPartialRevert(SinjohTreasuryVault.InvalidGovernor.selector);
        vault.nominateGovernor(address(0));

        vm.prank(GOVERNOR);
        vm.expectPartialRevert(SinjohTreasuryVault.InvalidGovernor.selector);
        vault.nominateGovernor(address(vault));
    }

    function testHandoffRequiresDelay() public {
        address successor = address(0xCAFE);

        vm.prank(GOVERNOR);
        vault.nominateGovernor(successor);
        assertEq(vault.pendingGovernor(), successor);
        assertEq(vault.pendingGovernorAcceptableAt(), START + HANDOFF_DELAY);

        vm.prank(successor);
        vm.expectPartialRevert(SinjohTreasuryVault.HandoffDelayNotElapsed.selector);
        vault.acceptGovernorship();

        vm.warp(START + HANDOFF_DELAY);
        vm.prank(successor);
        vault.acceptGovernorship();

        assertEq(vault.governor(), successor);
        assertEq(vault.pendingGovernor(), address(0));
        assertEq(vault.pendingGovernorAcceptableAt(), 0);
        assertEq(vault.lastGovernorActionAt(), START + HANDOFF_DELAY);
    }

    function testAcceptRequiresNomination() public {
        vm.prank(OUTSIDER);
        vm.expectRevert(SinjohTreasuryVault.NoPendingGovernor.selector);
        vault.acceptGovernorship();
    }

    function testAcceptRequiresNominatedCaller() public {
        vm.prank(GOVERNOR);
        vault.nominateGovernor(address(0xCAFE));

        vm.warp(START + HANDOFF_DELAY);
        vm.prank(OUTSIDER);
        vm.expectPartialRevert(SinjohTreasuryVault.NotPendingGovernor.selector);
        vault.acceptGovernorship();
    }

    function testGovernorCanCancelNomination() public {
        vm.prank(GOVERNOR);
        vault.nominateGovernor(address(0xCAFE));

        vm.prank(GOVERNOR);
        vault.cancelGovernorNomination();

        assertEq(vault.pendingGovernor(), address(0));
        assertEq(vault.pendingGovernorAcceptableAt(), 0);

        vm.prank(GOVERNOR);
        vm.expectRevert(SinjohTreasuryVault.NoPendingGovernor.selector);
        vault.cancelGovernorNomination();
    }

    function testNominationOverwritesPending() public {
        vm.prank(GOVERNOR);
        vault.nominateGovernor(address(0xCAFE));

        vm.prank(GOVERNOR);
        vault.nominateGovernor(address(0xFACE));

        assertEq(vault.pendingGovernor(), address(0xFACE));

        vm.warp(START + HANDOFF_DELAY);
        vm.prank(address(0xCAFE));
        vm.expectPartialRevert(SinjohTreasuryVault.NotPendingGovernor.selector);
        vault.acceptGovernorship();
    }

    function testTransferUpdatesLivenessClock() public {
        token.mint(address(vault), 10);

        vm.warp(START + 42 days);
        vm.prank(GOVERNOR);
        vault.transfer(address(token), 10, RECIPIENT);

        assertEq(vault.lastGovernorActionAt(), START + 42 days);
    }

    function testRecoveryDisabledReverts() public {
        vm.warp(START + INACTIVITY_PERIOD + 1);
        vm.prank(RECOVERY);
        vm.expectRevert(SinjohTreasuryVault.RecoveryDisabled.selector);
        vault.beginRecovery();
    }

    function testRecoveryRequiresRecoveryAddress() public {
        vm.warp(START + INACTIVITY_PERIOD);
        vm.prank(OUTSIDER);
        vm.expectPartialRevert(SinjohTreasuryVault.NotRecoveryAddress.selector);
        recoverableVault.beginRecovery();
    }

    function testRecoveryRequiresInactivity() public {
        vm.warp(START + INACTIVITY_PERIOD - 1);
        vm.prank(RECOVERY);
        vm.expectPartialRevert(SinjohTreasuryVault.GovernorStillActive.selector);
        recoverableVault.beginRecovery();
    }

    function testRecoveryClaimsSlotAfterInactivityAndDelay() public {
        vm.warp(START + INACTIVITY_PERIOD);
        vm.prank(RECOVERY);
        recoverableVault.beginRecovery();

        assertEq(recoverableVault.pendingGovernor(), RECOVERY);

        vm.warp(START + INACTIVITY_PERIOD + HANDOFF_DELAY);
        vm.prank(RECOVERY);
        recoverableVault.acceptGovernorship();

        assertEq(recoverableVault.governor(), RECOVERY);
    }

    function testLiveGovernorCancelsRecoveryAndResetsClock() public {
        vm.warp(START + INACTIVITY_PERIOD);
        vm.prank(RECOVERY);
        recoverableVault.beginRecovery();

        vm.prank(GOVERNOR);
        recoverableVault.cancelGovernorNomination();

        assertEq(recoverableVault.pendingGovernor(), address(0));
        assertEq(recoverableVault.lastGovernorActionAt(), START + INACTIVITY_PERIOD);

        vm.prank(RECOVERY);
        vm.expectPartialRevert(SinjohTreasuryVault.GovernorStillActive.selector);
        recoverableVault.beginRecovery();
    }

    function testGovernorActionDefersRecovery() public {
        token.mint(address(recoverableVault), 10);

        vm.warp(START + INACTIVITY_PERIOD - 1);
        vm.prank(GOVERNOR);
        recoverableVault.transfer(address(token), 10, RECIPIENT);

        vm.warp(START + INACTIVITY_PERIOD + 1);
        vm.prank(RECOVERY);
        vm.expectPartialRevert(SinjohTreasuryVault.GovernorStillActive.selector);
        recoverableVault.beginRecovery();
    }
}
