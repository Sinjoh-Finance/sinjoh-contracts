// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ProjectMultisigAccountV2 } from "../../src/multisig/ProjectMultisigAccountV2.sol";
import { ProjectVotesToken } from "../../src/token/ProjectVotesToken.sol";
import { MockBatchTarget, MockControlledModule } from "../mocks/MockControlledModule.sol";
import { MockERC721 } from "../mocks/MockERC721.sol";
import { MockRegistry } from "../mocks/MockRegistry.sol";
import { TestBase } from "../TestBase.sol";

contract ProjectMultisigAccountV2Test is TestBase {
    uint256 private constant START = 1_000_000;
    address private constant SIGNER_A = address(0xA1);
    address private constant SIGNER_B = address(0xB2);
    address private constant SIGNER_C = address(0xC3);
    address private constant SIGNER_D = address(0xD4);
    address private constant OUTSIDER = address(0xBAD);
    address private constant RECIPIENT = address(0xBEEF);

    MockRegistry private registry;
    ProjectVotesToken private token;
    ProjectMultisigAccountV2 private account;
    MockControlledModule private module;

    function setUp() public {
        vm.warp(START);
        registry = new MockRegistry();
        ProjectVotesToken.TokenAllocation[] memory allocations =
            new ProjectVotesToken.TokenAllocation[](1);
        allocations[0] =
            ProjectVotesToken.TokenAllocation({ recipient: SIGNER_A, amount: 1_000e18 });
        token = new ProjectVotesToken(
            "Project", "PRJ", address(registry), SIGNER_A, allocations, new address[](0)
        );
        account = _deployAccount([SIGNER_A, SIGNER_B, SIGNER_C]);
        module = new MockControlledModule(address(account));
    }

    function testConstructorPublishesIdentityControllerAndCanonicalSigners() public view {
        assertEq(account.registry(), address(registry));
        assertEq(account.subject(), address(token));
        assertEq(account.projectId(), token.projectId());
        assertEq(account.controller(), address(account));
        assertEq(account.SIGNER_COUNT(), 3);
        assertEq(account.EXECUTION_THRESHOLD(), 2);
        assertEq(account.TRANSACTION_TTL(), 7 days);
        address[3] memory current = account.signers();
        assertEq(current[0], SIGNER_A);
        assertEq(current[1], SIGNER_B);
        assertEq(current[2], SIGNER_C);
    }

    function testConstructorRejectsUnsortedSigners() public {
        vm.expectPartialRevert(ProjectMultisigAccountV2.UnsortedSigners.selector);
        _deployAccount([SIGNER_B, SIGNER_A, SIGNER_C]);
    }

    function testConstructorRejectsDuplicateSigner() public {
        vm.expectPartialRevert(ProjectMultisigAccountV2.UnsortedSigners.selector);
        _deployAccount([SIGNER_A, SIGNER_A, SIGNER_C]);
    }

    function testConstructorRejectsZeroAndBurnSigners() public {
        vm.expectPartialRevert(ProjectMultisigAccountV2.InvalidSigner.selector);
        _deployAccount([address(0), SIGNER_B, SIGNER_C]);

        address burnAddress = account.BURN_ADDRESS();
        vm.expectPartialRevert(ProjectMultisigAccountV2.InvalidSigner.selector);
        _deployAccount([SIGNER_A, SIGNER_B, burnAddress]);
    }

    function testConstructorRejectsMismatchedProjectRegistry() public {
        MockRegistry otherRegistry = new MockRegistry();
        vm.expectPartialRevert(ProjectMultisigAccountV2.ProjectIdentityMismatch.selector);
        new ProjectMultisigAccountV2(
            address(otherRegistry), address(token), [SIGNER_A, SIGNER_B, SIGNER_C]
        );
    }

    function testSubmitStoresActionsAndAutoConfirmsSubmitter() public {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) =
            _singleSetValue(42);
        vm.prank(SIGNER_A);
        bytes32 transactionId = account.submit(targets, values, calldatas);

        bytes32 actionsHash = keccak256(abi.encode(targets, values, calldatas));
        assertEq(
            transactionId, keccak256(abi.encode(block.chainid, address(account), 0, actionsHash))
        );
        ProjectMultisigAccountV2.Transaction memory current =
            account.transactionDetails(transactionId);
        assertEq(current.nonce, 0);
        assertEq(current.actionsHash, actionsHash);
        assertEq(current.submittedAt, START);
        assertEq(current.expiresAt, START + 7 days);
        assertEq(current.actionCount, 1);
        assertTrue(current.exists);
        assertTrue(account.confirmedBy(transactionId, SIGNER_A));
        assertEq(account.confirmationCount(transactionId), 1);

        (address target, uint256 value, bytes memory data) = account.actionAt(transactionId, 0);
        assertEq(target, address(module));
        assertEq(value, 0);
        assertEq(keccak256(data), keccak256(calldatas[0]));
    }

    function testSubmitRequiresCurrentSigner() public {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) =
            _singleSetValue(1);
        vm.prank(OUTSIDER);
        vm.expectPartialRevert(ProjectMultisigAccountV2.NotSigner.selector);
        account.submit(targets, values, calldatas);
    }

    function testSubmitRejectsEmptyAndMismatchedBatches() public {
        vm.prank(SIGNER_A);
        vm.expectPartialRevert(ProjectMultisigAccountV2.InvalidActionCount.selector);
        account.submit(new address[](0), new uint256[](0), new bytes[](0));

        address[] memory targets = new address[](1);
        targets[0] = address(module);
        vm.prank(SIGNER_A);
        vm.expectPartialRevert(ProjectMultisigAccountV2.InvalidBatchLengths.selector);
        account.submit(targets, new uint256[](0), new bytes[](1));
    }

    function testSubmitRejectsTooManyActionsAndZeroTarget() public {
        address[] memory targets = new address[](11);
        uint256[] memory values = new uint256[](11);
        bytes[] memory calldatas = new bytes[](11);
        for (uint256 i; i < 11; ++i) {
            targets[i] = address(module);
        }
        vm.prank(SIGNER_A);
        vm.expectPartialRevert(ProjectMultisigAccountV2.InvalidActionCount.selector);
        account.submit(targets, values, calldatas);

        targets = new address[](1);
        values = new uint256[](1);
        calldatas = new bytes[](1);
        vm.prank(SIGNER_A);
        vm.expectPartialRevert(ProjectMultisigAccountV2.InvalidTarget.selector);
        account.submit(targets, values, calldatas);
    }

    function testSubmitRejectsOversizedCalldata() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(module);
        calldatas[0] = new bytes(account.MAX_TOTAL_CALLDATA() + 1);
        vm.prank(SIGNER_A);
        vm.expectPartialRevert(ProjectMultisigAccountV2.CalldataLimitExceeded.selector);
        account.submit(targets, values, calldatas);
    }

    function testSecondCurrentSignerMakesTransactionReady() public {
        bytes32 transactionId = _submitSetValue(SIGNER_A, 42);
        vm.prank(SIGNER_B);
        account.confirm(transactionId);
        assertEq(account.confirmationCount(transactionId), 2);
        assertTrue(account.isReady(transactionId));
    }

    function testConfirmationRejectsNonSignerAndDuplicate() public {
        bytes32 transactionId = _submitSetValue(SIGNER_A, 42);
        vm.prank(OUTSIDER);
        vm.expectPartialRevert(ProjectMultisigAccountV2.NotSigner.selector);
        account.confirm(transactionId);
        vm.prank(SIGNER_A);
        vm.expectPartialRevert(ProjectMultisigAccountV2.AlreadyConfirmed.selector);
        account.confirm(transactionId);
    }

    function testRevocationRemovesReadiness() public {
        bytes32 transactionId = _submitSetValue(SIGNER_A, 42);
        vm.prank(SIGNER_B);
        account.confirm(transactionId);
        vm.prank(SIGNER_B);
        account.revokeConfirmation(transactionId);
        assertEq(account.confirmationCount(transactionId), 1);
        assertFalse(account.isReady(transactionId));
        vm.expectPartialRevert(ProjectMultisigAccountV2.ThresholdNotMet.selector);
        account.execute(transactionId);
    }

    function testPermissionlessExecutionOperatesControlledModule() public {
        bytes32 transactionId = _submitSetValue(SIGNER_A, 42);
        vm.prank(SIGNER_B);
        account.confirm(transactionId);
        vm.prank(OUTSIDER);
        account.execute(transactionId);

        assertEq(module.value(), 42);
        ProjectMultisigAccountV2.Transaction memory current =
            account.transactionDetails(transactionId);
        assertTrue(current.executed);
        assertEq(current.executionConfirmationCount, 2);
    }

    function testSignerCannotBypassAccountToCallControlledModule() public {
        vm.prank(SIGNER_A);
        vm.expectPartialRevert(MockControlledModule.OnlyController.selector);
        module.setValue(42);
    }

    function testExecutionRequiresTwoConfirmationsAndCannotRepeat() public {
        bytes32 transactionId = _submitSetValue(SIGNER_A, 42);
        vm.expectPartialRevert(ProjectMultisigAccountV2.ThresholdNotMet.selector);
        account.execute(transactionId);

        vm.prank(SIGNER_B);
        account.confirm(transactionId);
        account.execute(transactionId);
        vm.expectPartialRevert(ProjectMultisigAccountV2.TransactionAlreadyExecuted.selector);
        account.execute(transactionId);
    }

    function testExecutionAllowedAtExactExpiryButNotAfter() public {
        bytes32 executableAtBoundary = _submitSetValue(SIGNER_A, 1);
        vm.prank(SIGNER_B);
        account.confirm(executableAtBoundary);
        vm.warp(START + 7 days);
        account.execute(executableAtBoundary);
        assertEq(module.value(), 1);

        vm.warp(START + 7 days + 1);
        bytes32 expired = _submitAtCurrentTime(SIGNER_A, 2);
        vm.warp(block.timestamp + 7 days + 1);
        vm.prank(SIGNER_B);
        vm.expectPartialRevert(ProjectMultisigAccountV2.TransactionExpired.selector);
        account.confirm(expired);
        assertTrue(account.isExpired(expired));
    }

    function testBatchFailureRollsBackAndCanBeRetried() public {
        MockBatchTarget reverter = new MockBatchTarget();
        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory calldatas = new bytes[](2);
        targets[0] = address(module);
        targets[1] = address(reverter);
        calldatas[0] = abi.encodeCall(module.setValue, (77));
        calldatas[1] = abi.encodeCall(reverter.run, ());

        vm.prank(SIGNER_A);
        bytes32 transactionId = account.submit(targets, values, calldatas);
        vm.prank(SIGNER_B);
        account.confirm(transactionId);
        vm.expectRevert(MockBatchTarget.ForcedFailure.selector);
        account.execute(transactionId);

        assertEq(module.value(), 0);
        assertFalse(account.transactionDetails(transactionId).executed);
        reverter.setShouldRevert(false);
        account.execute(transactionId);
        assertEq(module.value(), 77);
        assertEq(reverter.calls(), 1);
    }

    function testApprovedBatchPreservesActionOrder() public {
        address[] memory targets = new address[](3);
        uint256[] memory values = new uint256[](3);
        bytes[] memory calldatas = new bytes[](3);
        for (uint256 i; i < 3; ++i) {
            targets[i] = address(module);
        }
        calldatas[0] = abi.encodeCall(module.setValue, (10));
        calldatas[1] = abi.encodeCall(module.increment, (5));
        calldatas[2] = abi.encodeCall(module.increment, (8));
        bytes32 transactionId = _submitConfirmExecute(targets, values, calldatas);
        assertEq(module.value(), 23);
        assertTrue(account.transactionDetails(transactionId).executed);
    }

    function testAccountForwardsNativeValueToContractAndEOA() public {
        vm.deal(address(account), 2 ether);
        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory calldatas = new bytes[](2);
        targets[0] = address(module);
        values[0] = 1 ether;
        calldatas[0] = abi.encodeCall(module.setValuePayable, (9));
        targets[1] = RECIPIENT;
        values[1] = 0.5 ether;

        _submitConfirmExecute(targets, values, calldatas);
        assertEq(module.nativeReceived(), 1 ether);
        assertEq(RECIPIENT.balance, 0.5 ether);
        assertEq(address(account).balance, 0.5 ether);
    }

    function testEOAActionRejectsNonemptyCalldataAtExecution() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = RECIPIENT;
        calldatas[0] = hex"01";
        vm.prank(SIGNER_A);
        bytes32 transactionId = account.submit(targets, values, calldatas);
        vm.prank(SIGNER_B);
        account.confirm(transactionId);
        vm.expectPartialRevert(ProjectMultisigAccountV2.InvalidEOACall.selector);
        account.execute(transactionId);
        assertFalse(account.transactionDetails(transactionId).executed);
    }

    function testThresholdApprovedSelfCallReplacesSigner() public {
        bytes32 pending = _submitSetValue(SIGNER_A, 5);
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(account);
        calldatas[0] = abi.encodeCall(account.replaceSigner, (SIGNER_A, SIGNER_D));
        _submitConfirmExecute(targets, values, calldatas);

        assertFalse(account.isSigner(SIGNER_A));
        assertTrue(account.isSigner(SIGNER_D));
        assertEq(account.confirmationCount(pending), 0);
        vm.prank(SIGNER_D);
        account.confirm(pending);
        vm.prank(SIGNER_B);
        account.confirm(pending);
        account.execute(pending);
        assertEq(module.value(), 5);
    }

    function testReplaceSignerCannotBeCalledDirectly() public {
        vm.prank(SIGNER_A);
        vm.expectPartialRevert(ProjectMultisigAccountV2.NotSelf.selector);
        account.replaceSigner(SIGNER_A, SIGNER_D);
    }

    function testOneTransactionCannotReplaceMultipleSigners() public {
        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory calldatas = new bytes[](2);
        targets[0] = address(account);
        targets[1] = address(account);
        calldatas[0] = abi.encodeCall(account.replaceSigner, (SIGNER_A, SIGNER_D));
        calldatas[1] = abi.encodeCall(account.replaceSigner, (SIGNER_B, address(0xE5)));

        vm.prank(SIGNER_A);
        bytes32 transactionId = account.submit(targets, values, calldatas);
        vm.prank(SIGNER_B);
        account.confirm(transactionId);
        vm.expectPartialRevert(ProjectMultisigAccountV2.SignerReplacementAlreadyPerformed.selector);
        account.execute(transactionId);

        assertTrue(account.isSigner(SIGNER_A));
        assertTrue(account.isSigner(SIGNER_B));
        assertFalse(account.isSigner(SIGNER_D));
        assertFalse(account.transactionDetails(transactionId).executed);
    }

    function testAccountSafelyReceivesERC721() public {
        MockERC721 nft = new MockERC721();
        nft.safeMint(address(account), 1);
        assertEq(nft.ownerOf(1), address(account));
    }

    function _deployAccount(address[3] memory signers)
        private
        returns (ProjectMultisigAccountV2 deployed)
    {
        deployed = new ProjectMultisigAccountV2(address(registry), address(token), signers);
    }

    function _singleSetValue(uint256 newValue)
        private
        view
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas)
    {
        targets = new address[](1);
        values = new uint256[](1);
        calldatas = new bytes[](1);
        targets[0] = address(module);
        calldatas[0] = abi.encodeCall(module.setValue, (newValue));
    }

    function _submitSetValue(address signer, uint256 newValue)
        private
        returns (bytes32 transactionId)
    {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) =
            _singleSetValue(newValue);
        vm.prank(signer);
        transactionId = account.submit(targets, values, calldatas);
    }

    function _submitAtCurrentTime(address signer, uint256 newValue)
        private
        returns (bytes32 transactionId)
    {
        return _submitSetValue(signer, newValue);
    }

    function _submitConfirmExecute(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas
    ) private returns (bytes32 transactionId) {
        vm.prank(SIGNER_A);
        transactionId = account.submit(targets, values, calldatas);
        vm.prank(SIGNER_B);
        account.confirm(transactionId);
        account.execute(transactionId);
    }
}
