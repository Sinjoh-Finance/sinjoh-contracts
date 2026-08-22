// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title SinjohJoint
/// @notice Immutable 2-of-3 joint-account control system: the Standard governor module for
///         `SinjohTreasuryVault` and the reusable owner primitive for other Sinjoh protocols.
/// @dev Exactly three distinct signers; any two must confirm before a proposal executes. Signer
///      rotation happens only through an executed proposal that targets this contract, so a
///      compromised key is replaced at the same 2-of-3 quorum without touching owned protocols.
///      Confirmations are counted against the signer set at execution time, so a rotated-out
///      signer's stale confirmations never count. Proposals expire after a fixed lifetime frozen
///      at deployment. With two of three keys lost the module is dead by design; treasuries
///      wanting an escape from that state elect the vault's dead-man recovery rail at deployment.
contract SinjohJoint is ReentrancyGuard {
    uint256 public constant SIGNER_COUNT = 3;
    uint256 public constant EXECUTION_THRESHOLD = 2;

    /// @notice Seconds a proposal remains confirmable and executable after creation.
    uint256 public immutable PROPOSAL_TTL;

    struct Proposal {
        address target;
        uint256 value;
        bytes data;
        uint256 expiresAt;
        bool executed;
    }

    address[SIGNER_COUNT] internal _signers;
    mapping(address account => bool isSigner) public isSigner;

    uint256 public proposalCount;
    mapping(uint256 proposalId => Proposal proposal) internal _proposals;
    mapping(uint256 proposalId => mapping(address signer => bool confirmed)) public confirmedBy;

    error NotSigner(address caller);
    error NotSelf(address caller);
    error InvalidSigner(address candidate);
    error DuplicateSigner(address candidate);
    error InvalidProposalTtl();
    error InvalidTarget(address target);
    error UnknownProposal(uint256 proposalId);
    error ProposalExpired(uint256 proposalId, uint256 expiresAt);
    error ProposalAlreadyExecuted(uint256 proposalId);
    error AlreadyConfirmed(uint256 proposalId, address signer);
    error NotConfirmed(uint256 proposalId, address signer);
    error ThresholdNotMet(uint256 proposalId, uint256 confirmations);
    error ExecutionFailed(uint256 proposalId);
    error InvalidBatch();
    error BatchCallFailed(uint256 index);

    event Deposited(address indexed sender, uint256 amount);
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        address indexed target,
        uint256 value,
        bytes data,
        uint256 expiresAt
    );
    event ProposalConfirmed(uint256 indexed proposalId, address indexed signer);
    event ConfirmationRevoked(uint256 indexed proposalId, address indexed signer);
    event ProposalExecuted(uint256 indexed proposalId, address indexed executor);
    event BatchCallExecuted(uint256 indexed index, address indexed target, uint256 value);
    event SignerReplaced(address indexed previousSigner, address indexed newSigner);

    modifier onlySigner() {
        if (!isSigner[msg.sender]) revert NotSigner(msg.sender);
        _;
    }

    constructor(address[SIGNER_COUNT] memory initialSigners, uint256 proposalTtl) {
        if (proposalTtl == 0) revert InvalidProposalTtl();
        PROPOSAL_TTL = proposalTtl;

        for (uint256 i = 0; i < SIGNER_COUNT; i++) {
            address signer = initialSigners[i];
            if (signer == address(0) || signer == address(this)) revert InvalidSigner(signer);
            if (isSigner[signer]) revert DuplicateSigner(signer);
            isSigner[signer] = true;
            _signers[i] = signer;
        }
    }

    receive() external payable {
        emit Deposited(msg.sender, msg.value);
    }

    /// @notice Returns the current signer set.
    function signers() external view returns (address[SIGNER_COUNT] memory) {
        return _signers;
    }

    /// @notice Returns one proposal in full.
    function getProposal(uint256 proposalId) external view returns (Proposal memory) {
        _requireKnown(proposalId);
        return _proposals[proposalId];
    }

    /// @notice Counts confirmations from the current signer set only.
    function confirmations(uint256 proposalId) public view returns (uint256 count) {
        _requireKnown(proposalId);
        for (uint256 i = 0; i < SIGNER_COUNT; i++) {
            if (confirmedBy[proposalId][_signers[i]]) count++;
        }
    }

    /// @notice Creates a proposal and records the proposer's confirmation.
    function propose(address target, uint256 value, bytes calldata data)
        external
        onlySigner
        returns (uint256 proposalId)
    {
        if (target == address(0)) revert InvalidTarget(target);

        proposalId = ++proposalCount;
        uint256 expiresAt = block.timestamp + PROPOSAL_TTL;
        _proposals[proposalId] = Proposal({
            target: target, value: value, data: data, expiresAt: expiresAt, executed: false
        });
        confirmedBy[proposalId][msg.sender] = true;

        emit ProposalCreated(proposalId, msg.sender, target, value, data, expiresAt);
        emit ProposalConfirmed(proposalId, msg.sender);
    }

    /// @notice Adds the caller's confirmation to a live proposal.
    function confirm(uint256 proposalId) external onlySigner {
        _requireLive(proposalId);
        if (confirmedBy[proposalId][msg.sender]) {
            revert AlreadyConfirmed(proposalId, msg.sender);
        }

        confirmedBy[proposalId][msg.sender] = true;
        emit ProposalConfirmed(proposalId, msg.sender);
    }

    /// @notice Withdraws the caller's confirmation from a live proposal.
    function revokeConfirmation(uint256 proposalId) external onlySigner {
        _requireLive(proposalId);
        if (!confirmedBy[proposalId][msg.sender]) {
            revert NotConfirmed(proposalId, msg.sender);
        }

        confirmedBy[proposalId][msg.sender] = false;
        emit ConfirmationRevoked(proposalId, msg.sender);
    }

    /// @notice Executes a live proposal once two current signers have confirmed it.
    function execute(uint256 proposalId) external onlySigner nonReentrant {
        _requireLive(proposalId);
        uint256 confirmed = confirmations(proposalId);
        if (confirmed < EXECUTION_THRESHOLD) {
            revert ThresholdNotMet(proposalId, confirmed);
        }

        Proposal storage proposal = _proposals[proposalId];
        proposal.executed = true;

        (bool success,) = proposal.target.call{ value: proposal.value }(proposal.data);
        if (!success) revert ExecutionFailed(proposalId);

        emit ProposalExecuted(proposalId, msg.sender);
    }

    /// @notice Atomically executes multiple calls through one approved proposal.
    /// @dev Callable only by proposing a call from this Joint to itself. Any failed call reverts
    /// the entire batch, including every earlier call in the same transaction.
    function executeBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata data
    ) external {
        if (msg.sender != address(this)) revert NotSelf(msg.sender);
        uint256 length = targets.length;
        if (length == 0 || length != values.length || length != data.length) {
            revert InvalidBatch();
        }

        for (uint256 i; i < length; ++i) {
            address target = targets[i];
            if (target == address(0)) revert InvalidTarget(target);
            (bool success,) = target.call{ value: values[i] }(data[i]);
            if (!success) revert BatchCallFailed(i);
            emit BatchCallExecuted(i, target, values[i]);
        }
    }

    /// @notice Swaps one signer for another; callable only through an executed proposal.
    function replaceSigner(address currentSigner, address newSigner) external {
        if (msg.sender != address(this)) revert NotSelf(msg.sender);
        if (!isSigner[currentSigner]) revert InvalidSigner(currentSigner);
        if (newSigner == address(0) || newSigner == address(this)) revert InvalidSigner(newSigner);
        if (isSigner[newSigner]) revert DuplicateSigner(newSigner);

        for (uint256 i = 0; i < SIGNER_COUNT; i++) {
            if (_signers[i] == currentSigner) {
                _signers[i] = newSigner;
                break;
            }
        }
        isSigner[currentSigner] = false;
        isSigner[newSigner] = true;

        emit SignerReplaced(currentSigner, newSigner);
    }

    function _requireKnown(uint256 proposalId) internal view {
        if (proposalId == 0 || proposalId > proposalCount) revert UnknownProposal(proposalId);
    }

    function _requireLive(uint256 proposalId) internal view {
        _requireKnown(proposalId);
        Proposal storage proposal = _proposals[proposalId];
        if (proposal.executed) revert ProposalAlreadyExecuted(proposalId);
        if (block.timestamp > proposal.expiresAt) {
            revert ProposalExpired(proposalId, proposal.expiresAt);
        }
    }
}
