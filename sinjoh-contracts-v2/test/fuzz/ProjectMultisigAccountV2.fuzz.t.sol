// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ProjectMultisigAccountV2 } from "../../src/multisig/ProjectMultisigAccountV2.sol";
import { ProjectVotesToken } from "../../src/token/ProjectVotesToken.sol";
import { MockControlledModule } from "../mocks/MockControlledModule.sol";
import { MockRegistry } from "../mocks/MockRegistry.sol";
import { TestBase } from "../TestBase.sol";

contract ProjectMultisigAccountV2FuzzTest is TestBase {
    address private constant SIGNER_A = address(0xA1);
    address private constant SIGNER_B = address(0xB2);
    address private constant SIGNER_C = address(0xC3);
    address private constant SIGNER_D = address(0xD4);

    ProjectMultisigAccountV2 private account;
    MockControlledModule private module;

    function setUp() public {
        vm.warp(1_000_000);
        MockRegistry registry = new MockRegistry();
        ProjectVotesToken.TokenAllocation[] memory allocations =
            new ProjectVotesToken.TokenAllocation[](1);
        allocations[0] =
            ProjectVotesToken.TokenAllocation({ recipient: SIGNER_A, amount: 1_000e18 });
        ProjectVotesToken token = new ProjectVotesToken(
            "Project", "PRJ", address(registry), SIGNER_A, allocations, new address[](0)
        );
        account = new ProjectMultisigAccountV2(
            address(registry), address(token), [SIGNER_A, SIGNER_B, SIGNER_C]
        );
        module = new MockControlledModule(address(account));
    }

    function testFuzzAnyTwoDistinctCurrentSignersExecute(uint256 newValue, bool useSignerC) public {
        bytes32 transactionId = _submitSetValue(SIGNER_A, newValue);
        vm.prank(useSignerC ? SIGNER_C : SIGNER_B);
        account.confirm(transactionId);
        account.execute(transactionId);
        assertEq(module.value(), newValue);
        assertEq(account.transactionDetails(transactionId).executionConfirmationCount, 2);
    }

    function testFuzzOneSignerNeverMakesTransactionReady(uint256 newValue) public {
        bytes32 transactionId = _submitSetValue(SIGNER_A, newValue);
        assertFalse(account.isReady(transactionId));
        vm.expectPartialRevert(ProjectMultisigAccountV2.ThresholdNotMet.selector);
        account.execute(transactionId);
        assertEq(module.value(), 0);
    }

    function testFuzzRevocationRemovesThreshold(uint256 newValue, bool revokeSubmitter) public {
        bytes32 transactionId = _submitSetValue(SIGNER_A, newValue);
        vm.prank(SIGNER_B);
        account.confirm(transactionId);
        vm.prank(revokeSubmitter ? SIGNER_A : SIGNER_B);
        account.revokeConfirmation(transactionId);
        assertEq(account.confirmationCount(transactionId), 1);
        assertFalse(account.isReady(transactionId));
    }

    function testFuzzOrderedBatchExecutesEveryAction(uint8 rawLength, uint128 rawIncrement) public {
        uint256 length = bound(rawLength, 1, account.MAX_ACTIONS());
        uint256 increment = bound(rawIncrement, 1, type(uint64).max);
        address[] memory targets = new address[](length);
        uint256[] memory values = new uint256[](length);
        bytes[] memory calldatas = new bytes[](length);
        for (uint256 i; i < length; ++i) {
            targets[i] = address(module);
            calldatas[i] = abi.encodeCall(module.increment, (increment));
        }
        bytes32 transactionId = _submit(SIGNER_A, targets, values, calldatas);
        vm.prank(SIGNER_B);
        account.confirm(transactionId);
        account.execute(transactionId);
        assertEq(module.value(), increment * length);
        assertEq(module.calls(), length);
    }

    function testFuzzNonceProducesDistinctCommittedTransactionIds(
        uint256 firstValue,
        uint256 secondValue
    ) public {
        bytes32 first = _submitSetValue(SIGNER_A, firstValue);
        bytes32 second = _submitSetValue(SIGNER_A, secondValue);
        assertNotEq(first, second);
        assertEq(account.transactionDetails(first).nonce, 0);
        assertEq(account.transactionDetails(second).nonce, 1);
    }

    function testFuzzSignerReplacementInvalidatesOldConfirmation(uint256 newValue) public {
        bytes32 pending = _submitSetValue(SIGNER_A, newValue);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(account);
        calldatas[0] = abi.encodeCall(account.replaceSigner, (SIGNER_A, SIGNER_D));
        bytes32 replacement = _submit(SIGNER_A, targets, values, calldatas);
        vm.prank(SIGNER_B);
        account.confirm(replacement);
        account.execute(replacement);

        assertEq(account.confirmationCount(pending), 0);
        vm.prank(SIGNER_D);
        account.confirm(pending);
        vm.prank(SIGNER_C);
        account.confirm(pending);
        account.execute(pending);
        assertEq(module.value(), newValue);
    }

    function _submitSetValue(address signer, uint256 newValue)
        private
        returns (bytes32 transactionId)
    {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(module);
        calldatas[0] = abi.encodeCall(module.setValue, (newValue));
        return _submit(signer, targets, values, calldatas);
    }

    function _submit(
        address signer,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas
    ) private returns (bytes32 transactionId) {
        vm.prank(signer);
        return account.submit(targets, values, calldatas);
    }
}
