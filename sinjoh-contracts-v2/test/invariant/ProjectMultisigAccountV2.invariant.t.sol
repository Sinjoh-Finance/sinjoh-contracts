// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Vm } from "forge-std/Vm.sol";
import { ProjectMultisigAccountV2 } from "../../src/multisig/ProjectMultisigAccountV2.sol";
import { ProjectVotesToken } from "../../src/token/ProjectVotesToken.sol";
import { MockControlledModule } from "../mocks/MockControlledModule.sol";
import { MockRegistry } from "../mocks/MockRegistry.sol";
import { InvariantTestBase } from "../TestBase.sol";

contract ProjectMultisigAccountV2Handler {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 private constant MAX_TRANSACTIONS = 64;
    address private constant SIGNER_A = address(0xA1);
    address private constant SIGNER_B = address(0xB2);
    address private constant SIGNER_C = address(0xC3);
    address private constant SIGNER_D = address(0xD4);

    ProjectMultisigAccountV2 public immutable account;
    MockControlledModule public immutable module;
    bytes32[] private _transactionIds;

    constructor(ProjectMultisigAccountV2 account_, MockControlledModule module_) {
        account = account_;
        module = module_;
    }

    function submit(uint256 newValue, uint256 rawSigner) external {
        if (_transactionIds.length >= MAX_TRANSACTIONS) return;
        address signer = _signer(rawSigner);
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(module);
        calldatas[0] = abi.encodeCall(module.setValue, (newValue));
        vm.prank(signer);
        try account.submit(targets, values, calldatas) returns (bytes32 transactionId) {
            _transactionIds.push(transactionId);
        } catch { }
    }

    function confirm(uint256 rawTransaction, uint256 rawSigner) external {
        if (_transactionIds.length == 0) return;
        bytes32 transactionId = _transactionIds[rawTransaction % _transactionIds.length];
        address signer = _signer(rawSigner);
        vm.prank(signer);
        try account.confirm(transactionId) { } catch { }
    }

    function revoke(uint256 rawTransaction, uint256 rawSigner) external {
        if (_transactionIds.length == 0) return;
        bytes32 transactionId = _transactionIds[rawTransaction % _transactionIds.length];
        address signer = _signer(rawSigner);
        vm.prank(signer);
        try account.revokeConfirmation(transactionId) { } catch { }
    }

    function execute(uint256 rawTransaction) external {
        if (_transactionIds.length == 0) return;
        bytes32 transactionId = _transactionIds[rawTransaction % _transactionIds.length];
        try account.execute(transactionId) { } catch { }
    }

    function replaceFirstSigner() external {
        if (!account.isSigner(SIGNER_A) || _transactionIds.length >= MAX_TRANSACTIONS) return;
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(account);
        calldatas[0] = abi.encodeCall(account.replaceSigner, (SIGNER_A, SIGNER_D));
        vm.prank(SIGNER_A);
        bytes32 transactionId = account.submit(targets, values, calldatas);
        _transactionIds.push(transactionId);
        vm.prank(SIGNER_B);
        account.confirm(transactionId);
        account.execute(transactionId);
    }

    function advanceTime(uint32 rawDelay) external {
        vm.warp(block.timestamp + uint256(rawDelay % uint32(8 days)));
    }

    function transactionCount() external view returns (uint256) {
        return _transactionIds.length;
    }

    function transactionIdAt(uint256 index) external view returns (bytes32) {
        return _transactionIds[index];
    }

    function _signer(uint256 rawSigner) private view returns (address) {
        address[3] memory current = account.signers();
        return current[rawSigner % 3];
    }
}

contract ProjectMultisigAccountV2InvariantTest is InvariantTestBase {
    address private constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    address private constant SIGNER_A = address(0xA1);
    address private constant SIGNER_B = address(0xB2);
    address private constant SIGNER_C = address(0xC3);

    ProjectMultisigAccountV2 private account;
    MockControlledModule private module;
    ProjectMultisigAccountV2Handler private handler;

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
        handler = new ProjectMultisigAccountV2Handler(account, module);
        targetContract(address(handler));
    }

    function invariantSignerSetAlwaysHasThreeUniqueEligibleAddresses() public view {
        address[3] memory current = account.signers();
        assertLt(uint160(current[0]), uint160(current[1]));
        assertLt(uint160(current[1]), uint160(current[2]));
        for (uint256 i; i < 3; ++i) {
            assertNotEq(current[i], address(0));
            assertNotEq(current[i], BURN_ADDRESS);
            assertTrue(account.isSigner(current[i]));
        }
    }

    function invariantExecutionAlwaysRecordedThresholdApproval() public view {
        uint256 count = handler.transactionCount();
        for (uint256 i; i < count; ++i) {
            bytes32 transactionId = handler.transactionIdAt(i);
            ProjectMultisigAccountV2.Transaction memory current =
                account.transactionDetails(transactionId);
            if (current.executed) {
                assertGe(current.executionConfirmationCount, account.EXECUTION_THRESHOLD());
                assertFalse(account.isReady(transactionId));
            } else {
                assertEq(current.executionConfirmationCount, 0);
            }
        }
    }

    function invariantConfirmationCountNeverExceedsSignerCount() public view {
        uint256 count = handler.transactionCount();
        for (uint256 i; i < count; ++i) {
            assertLe(account.confirmationCount(handler.transactionIdAt(i)), account.SIGNER_COUNT());
        }
    }

    function invariantEveryStoredTransactionMatchesItsCommittedActions() public view {
        uint256 count = handler.transactionCount();
        for (uint256 i; i < count; ++i) {
            bytes32 transactionId = handler.transactionIdAt(i);
            ProjectMultisigAccountV2.Transaction memory current =
                account.transactionDetails(transactionId);
            (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) =
                account.transactionActions(transactionId);
            assertEq(current.actionCount, targets.length);
            assertEq(targets.length, values.length);
            assertEq(targets.length, calldatas.length);
            assertEq(current.actionsHash, keccak256(abi.encode(targets, values, calldatas)));
        }
    }

    function invariantControllerIsAlwaysAccountItself() public view {
        assertEq(account.controller(), address(account));
        assertEq(module.controller(), address(account));
    }
}
