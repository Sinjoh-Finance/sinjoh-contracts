// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { SinjohJoint } from "../src/SinjohJoint.sol";
import { SinjohTreasuryVault } from "../src/SinjohTreasuryVault.sol";
import { TestBase } from "./TestBase.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";

contract SinjohJointTest is TestBase {
    address internal constant SIGNER_A = address(0xA1);
    address internal constant SIGNER_B = address(0xB2);
    address internal constant SIGNER_C = address(0xC3);
    address internal constant OUTSIDER = address(0xBAD);
    address internal constant RECIPIENT = address(0xBEEF);
    uint256 internal constant PROPOSAL_TTL = 30 days;
    uint256 internal constant HANDOFF_DELAY = 3 days;
    uint256 internal constant START = 1_000_000;

    SinjohJoint internal joint;
    SinjohTreasuryVault internal vault;
    MockERC20 internal token;

    function setUp() public {
        vm.warp(START);
        joint = new SinjohJoint([SIGNER_A, SIGNER_B, SIGNER_C], PROPOSAL_TTL);
        vault = new SinjohTreasuryVault(address(joint), HANDOFF_DELAY, address(0), 0);
        token = new MockERC20();
    }

    function _transferCall(uint256 amount) internal view returns (bytes memory) {
        return abi.encodeCall(SinjohTreasuryVault.transfer, (address(token), amount, RECIPIENT));
    }

    function _proposeVaultTransfer(uint256 amount) internal returns (uint256 proposalId) {
        vm.prank(SIGNER_A);
        proposalId = joint.propose(address(vault), 0, _transferCall(amount));
    }

    function testInitialConfiguration() public view {
        assertEq(joint.SIGNER_COUNT(), 3);
        assertEq(joint.EXECUTION_THRESHOLD(), 2);
        assertEq(joint.PROPOSAL_TTL(), PROPOSAL_TTL);
        assertEq(joint.proposalCount(), 0);

        address[3] memory currentSigners = joint.signers();
        assertEq(currentSigners[0], SIGNER_A);
        assertEq(currentSigners[1], SIGNER_B);
        assertEq(currentSigners[2], SIGNER_C);
        assertTrue(joint.isSigner(SIGNER_A));
        assertTrue(joint.isSigner(SIGNER_B));
        assertTrue(joint.isSigner(SIGNER_C));
        assertTrue(!joint.isSigner(OUTSIDER));
    }

    function testConstructorRejectsZeroSigner() public {
        vm.expectPartialRevert(SinjohJoint.InvalidSigner.selector);
        new SinjohJoint([SIGNER_A, address(0), SIGNER_C], PROPOSAL_TTL);
    }

    function testConstructorRejectsDuplicateSigner() public {
        vm.expectPartialRevert(SinjohJoint.DuplicateSigner.selector);
        new SinjohJoint([SIGNER_A, SIGNER_A, SIGNER_C], PROPOSAL_TTL);
    }

    function testConstructorRejectsZeroTtl() public {
        vm.expectRevert(SinjohJoint.InvalidProposalTtl.selector);
        new SinjohJoint([SIGNER_A, SIGNER_B, SIGNER_C], 0);
    }

    function testProposeRequiresSigner() public {
        vm.prank(OUTSIDER);
        vm.expectPartialRevert(SinjohJoint.NotSigner.selector);
        joint.propose(address(vault), 0, "");
    }

    function testProposeRejectsZeroTarget() public {
        vm.prank(SIGNER_A);
        vm.expectPartialRevert(SinjohJoint.InvalidTarget.selector);
        joint.propose(address(0), 0, "");
    }

    function testProposeAutoConfirms() public {
        uint256 proposalId = _proposeVaultTransfer(10);

        assertEq(proposalId, 1);
        assertEq(joint.proposalCount(), 1);
        assertTrue(joint.confirmedBy(proposalId, SIGNER_A));
        assertEq(joint.confirmations(proposalId), 1);

        SinjohJoint.Proposal memory proposal = joint.getProposal(proposalId);
        assertEq(proposal.target, address(vault));
        assertEq(proposal.value, 0);
        assertEq(proposal.expiresAt, START + PROPOSAL_TTL);
        assertTrue(!proposal.executed);
    }

    function testConfirmRequiresSigner() public {
        uint256 proposalId = _proposeVaultTransfer(10);
        vm.prank(OUTSIDER);
        vm.expectPartialRevert(SinjohJoint.NotSigner.selector);
        joint.confirm(proposalId);
    }

    function testConfirmRejectsUnknownProposal() public {
        vm.prank(SIGNER_A);
        vm.expectPartialRevert(SinjohJoint.UnknownProposal.selector);
        joint.confirm(1);
    }

    function testConfirmRejectsDoubleConfirmation() public {
        uint256 proposalId = _proposeVaultTransfer(10);
        vm.prank(SIGNER_A);
        vm.expectPartialRevert(SinjohJoint.AlreadyConfirmed.selector);
        joint.confirm(proposalId);
    }

    function testExecuteRequiresThreshold() public {
        token.mint(address(vault), 10);
        uint256 proposalId = _proposeVaultTransfer(10);

        vm.prank(SIGNER_A);
        vm.expectPartialRevert(SinjohJoint.ThresholdNotMet.selector);
        joint.execute(proposalId);
    }

    function testTwoOfThreeExecutesVaultTransfer() public {
        token.mint(address(vault), 100);
        uint256 proposalId = _proposeVaultTransfer(60);

        vm.prank(SIGNER_B);
        joint.confirm(proposalId);
        assertEq(joint.confirmations(proposalId), 2);

        vm.prank(SIGNER_C);
        joint.execute(proposalId);

        assertEq(token.balanceOf(RECIPIENT), 60);
        assertEq(token.balanceOf(address(vault)), 40);
        assertTrue(joint.getProposal(proposalId).executed);
    }

    function testExecuteRejectsDoubleExecution() public {
        token.mint(address(vault), 100);
        uint256 proposalId = _proposeVaultTransfer(60);

        vm.prank(SIGNER_B);
        joint.confirm(proposalId);
        vm.prank(SIGNER_A);
        joint.execute(proposalId);

        vm.prank(SIGNER_A);
        vm.expectPartialRevert(SinjohJoint.ProposalAlreadyExecuted.selector);
        joint.execute(proposalId);
    }

    function testExecuteBubblesFailureAsExecutionFailed() public {
        uint256 proposalId = _proposeVaultTransfer(10);

        vm.prank(SIGNER_B);
        joint.confirm(proposalId);

        vm.prank(SIGNER_A);
        vm.expectPartialRevert(SinjohJoint.ExecutionFailed.selector);
        joint.execute(proposalId);

        assertTrue(!joint.getProposal(proposalId).executed);
    }

    function testExpiredProposalCannotBeConfirmedOrExecuted() public {
        token.mint(address(vault), 10);
        uint256 proposalId = _proposeVaultTransfer(10);

        vm.warp(START + PROPOSAL_TTL + 1);

        vm.prank(SIGNER_B);
        vm.expectPartialRevert(SinjohJoint.ProposalExpired.selector);
        joint.confirm(proposalId);

        vm.prank(SIGNER_A);
        vm.expectPartialRevert(SinjohJoint.ProposalExpired.selector);
        joint.execute(proposalId);
    }

    function testRevokeConfirmationLowersCount() public {
        token.mint(address(vault), 10);
        uint256 proposalId = _proposeVaultTransfer(10);

        vm.prank(SIGNER_B);
        joint.confirm(proposalId);
        assertEq(joint.confirmations(proposalId), 2);

        vm.prank(SIGNER_B);
        joint.revokeConfirmation(proposalId);
        assertEq(joint.confirmations(proposalId), 1);

        vm.prank(SIGNER_A);
        vm.expectPartialRevert(SinjohJoint.ThresholdNotMet.selector);
        joint.execute(proposalId);
    }

    function testRevokeRequiresExistingConfirmation() public {
        uint256 proposalId = _proposeVaultTransfer(10);
        vm.prank(SIGNER_B);
        vm.expectPartialRevert(SinjohJoint.NotConfirmed.selector);
        joint.revokeConfirmation(proposalId);
    }

    function testReplaceSignerRequiresSelf() public {
        vm.prank(SIGNER_A);
        vm.expectPartialRevert(SinjohJoint.NotSelf.selector);
        joint.replaceSigner(SIGNER_C, OUTSIDER);
    }

    function testReplaceSignerThroughProposal() public {
        address newSigner = address(0xD4);
        bytes memory data = abi.encodeCall(SinjohJoint.replaceSigner, (SIGNER_C, newSigner));

        vm.prank(SIGNER_A);
        uint256 proposalId = joint.propose(address(joint), 0, data);
        vm.prank(SIGNER_B);
        joint.confirm(proposalId);
        vm.prank(SIGNER_A);
        joint.execute(proposalId);

        assertTrue(!joint.isSigner(SIGNER_C));
        assertTrue(joint.isSigner(newSigner));
        address[3] memory currentSigners = joint.signers();
        assertEq(currentSigners[2], newSigner);
    }

    function testReplacedSignerConfirmationsStopCounting() public {
        token.mint(address(vault), 10);

        uint256 transferId = _proposeVaultTransfer(10);
        vm.prank(SIGNER_C);
        joint.confirm(transferId);
        assertEq(joint.confirmations(transferId), 2);

        bytes memory data = abi.encodeCall(SinjohJoint.replaceSigner, (SIGNER_C, address(0xD4)));
        vm.prank(SIGNER_A);
        uint256 rotationId = joint.propose(address(joint), 0, data);
        vm.prank(SIGNER_B);
        joint.confirm(rotationId);
        vm.prank(SIGNER_A);
        joint.execute(rotationId);

        assertEq(joint.confirmations(transferId), 1);
        vm.prank(SIGNER_A);
        vm.expectPartialRevert(SinjohJoint.ThresholdNotMet.selector);
        joint.execute(transferId);
    }

    function testReplacedSignerLosesAccess() public {
        bytes memory data = abi.encodeCall(SinjohJoint.replaceSigner, (SIGNER_C, address(0xD4)));
        vm.prank(SIGNER_A);
        uint256 proposalId = joint.propose(address(joint), 0, data);
        vm.prank(SIGNER_B);
        joint.confirm(proposalId);
        vm.prank(SIGNER_A);
        joint.execute(proposalId);

        vm.prank(SIGNER_C);
        vm.expectPartialRevert(SinjohJoint.NotSigner.selector);
        joint.propose(address(vault), 0, "");
    }

    function testJointGovernsVaultHandoff() public {
        address successor = address(0xCAFE);

        vm.prank(SIGNER_A);
        uint256 proposalId = joint.propose(
            address(vault), 0, abi.encodeCall(SinjohTreasuryVault.nominateGovernor, (successor))
        );
        vm.prank(SIGNER_B);
        joint.confirm(proposalId);
        vm.prank(SIGNER_B);
        joint.execute(proposalId);

        assertEq(vault.pendingGovernor(), successor);

        vm.warp(START + HANDOFF_DELAY);
        vm.prank(successor);
        vault.acceptGovernorship();
        assertEq(vault.governor(), successor);
    }

    function testExecuteSendsValueFromJointBalance() public {
        vm.deal(address(this), 1 ether);
        (bool funded,) = address(joint).call{ value: 1 ether }("");
        assertTrue(funded);

        vm.prank(SIGNER_A);
        uint256 proposalId = joint.propose(RECIPIENT, 1 ether, "");
        vm.prank(SIGNER_B);
        joint.confirm(proposalId);
        vm.prank(SIGNER_A);
        joint.execute(proposalId);

        assertEq(RECIPIENT.balance, 1 ether);
        assertEq(address(joint).balance, 0);
    }
}
