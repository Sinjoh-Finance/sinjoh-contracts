// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ERC721Holder } from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Time } from "@openzeppelin/contracts/utils/types/Time.sol";
import { IProjectControlled } from "../interfaces/IProjectControlled.sol";
import { ProjectIds } from "../libraries/ProjectIds.sol";
import { SinjohV2Constants } from "../libraries/SinjohV2Constants.sol";

/// @notice Independent project controller account requiring two of three current signers.
/// @dev Every submitted transaction expires after seven days. Confirmation counts are derived from
/// the current signer set, so replaced signers immediately lose influence over pending actions.
contract ProjectMultisigAccountV2 is IProjectControlled, ERC721Holder, ReentrancyGuard {
    using Address for address;

    uint256 public constant SIGNER_COUNT = 3;
    uint256 public constant EXECUTION_THRESHOLD = 2;
    uint64 public constant TRANSACTION_TTL = 7 days;
    uint256 public constant MAX_ACTIONS = 10;
    uint256 public constant MAX_TOTAL_CALLDATA = 24_576;
    address public constant BURN_ADDRESS = SinjohV2Constants.BURN_ADDRESS;

    struct Transaction {
        uint256 nonce;
        bytes32 actionsHash;
        uint64 submittedAt;
        uint64 expiresAt;
        uint8 actionCount;
        uint8 executionConfirmationCount;
        bool executed;
        bool exists;
    }

    address public immutable registry;
    address public immutable subject;
    bytes32 public immutable override projectId;
    address public immutable override controller;

    address[SIGNER_COUNT] private _signers;
    mapping(address signer => bool active) public isSigner;

    uint256 public nextNonce;
    bytes32 private _executingTransactionId;
    bool private _signerReplacedDuringExecution;
    mapping(bytes32 transactionId => Transaction transaction) private _transactions;
    mapping(bytes32 transactionId => address[] targets) private _targets;
    mapping(bytes32 transactionId => uint256[] values) private _values;
    mapping(bytes32 transactionId => bytes[] calldatas) private _calldatas;
    mapping(bytes32 transactionId => mapping(address signer => bool confirmed)) public confirmedBy;

    error InvalidRegistry(address candidate);
    error InvalidSubject(address candidate);
    error ProjectIdentityMismatch(bytes32 expected, bytes32 actual);
    error InvalidSigner(uint256 index, address candidate);
    error UnsortedSigners(uint256 index, address previous, address current);
    error NotSigner(address caller);
    error NotSelf(address caller);
    error InvalidBatchLengths(uint256 targets, uint256 values, uint256 calldatas);
    error InvalidActionCount(uint256 supplied);
    error InvalidTarget(uint256 index, address target);
    error CalldataLimitExceeded(uint256 supplied, uint256 maximum);
    error UnknownTransaction(bytes32 transactionId);
    error TransactionExpired(bytes32 transactionId, uint64 expiresAt);
    error TransactionAlreadyExecuted(bytes32 transactionId);
    error AlreadyConfirmed(bytes32 transactionId, address signer);
    error NotConfirmed(bytes32 transactionId, address signer);
    error ThresholdNotMet(bytes32 transactionId, uint256 confirmations);
    error InvalidEOACall(bytes32 transactionId, uint256 index, address target);
    error InvalidReplacement(address oldSigner, address newSigner);
    error SignerReplacementAlreadyPerformed(bytes32 transactionId);

    event MultisigAccountCreated(
        bytes32 indexed projectId,
        address indexed account,
        address indexed signer0,
        address signer1,
        address signer2
    );
    event NativeReceived(address indexed sender, uint256 amount);
    event TransactionSubmitted(
        bytes32 indexed transactionId,
        uint256 indexed nonce,
        address indexed submitter,
        uint64 expiresAt,
        bytes32 actionsHash
    );
    event TransactionConfirmed(bytes32 indexed transactionId, address indexed signer);
    event ConfirmationRevoked(bytes32 indexed transactionId, address indexed signer);
    event ActionExecuted(
        bytes32 indexed transactionId,
        uint256 indexed index,
        address indexed target,
        uint256 value,
        bytes32 returnDataHash
    );
    event TransactionExecuted(bytes32 indexed transactionId, address indexed executor);
    event SignerReplaced(address indexed oldSigner, address indexed newSigner);

    modifier onlySigner() {
        if (!isSigner[msg.sender]) revert NotSigner(msg.sender);
        _;
    }

    modifier onlySelf() {
        if (msg.sender != address(this)) revert NotSelf(msg.sender);
        _;
    }

    constructor(address registry_, address subject_, address[3] memory initialSigners) {
        if (registry_.code.length == 0) revert InvalidRegistry(registry_);
        if (subject_.code.length == 0) revert InvalidSubject(subject_);

        bytes32 expectedProjectId = ProjectIds.derive(block.chainid, registry_, subject_);
        (bool declaresIdentity, address subjectRegistry, bytes32 subjectProjectId) =
            ProjectIds.declaredIdentity(subject_);
        if (
            declaresIdentity
                && (subjectRegistry != registry_ || subjectProjectId != expectedProjectId)
        ) revert ProjectIdentityMismatch(expectedProjectId, subjectProjectId);

        address previous;
        for (uint256 i; i < SIGNER_COUNT; ++i) {
            address signer = initialSigners[i];
            if (signer == address(0) || signer == BURN_ADDRESS || signer == address(this)) {
                revert InvalidSigner(i, signer);
            }
            if (i != 0 && signer <= previous) {
                revert UnsortedSigners(i, previous, signer);
            }
            previous = signer;
            _signers[i] = signer;
            isSigner[signer] = true;
        }

        registry = registry_;
        subject = subject_;
        projectId = expectedProjectId;
        controller = address(this);

        emit MultisigAccountCreated(
            expectedProjectId,
            address(this),
            initialSigners[0],
            initialSigners[1],
            initialSigners[2]
        );
    }

    receive() external payable {
        emit NativeReceived(msg.sender, msg.value);
    }

    function signers() external view returns (address[SIGNER_COUNT] memory) {
        return _signers;
    }

    /// @notice Submits one atomic action batch and records the submitter's first confirmation.
    function submit(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas
    ) external onlySigner returns (bytes32 transactionId) {
        _validateBatch(targets, values, calldatas);

        uint256 nonce = nextNonce++;
        bytes32 actionsHash = keccak256(abi.encode(targets, values, calldatas));
        transactionId = keccak256(abi.encode(block.chainid, address(this), nonce, actionsHash));
        uint64 submittedAt = uint64(Time.timestamp());
        uint64 expiresAt = submittedAt + TRANSACTION_TTL;

        Transaction storage current = _transactions[transactionId];
        current.nonce = nonce;
        current.actionsHash = actionsHash;
        current.submittedAt = submittedAt;
        current.expiresAt = expiresAt;
        current.actionCount = uint8(targets.length);
        current.exists = true;

        for (uint256 i; i < targets.length; ++i) {
            _targets[transactionId].push(targets[i]);
            _values[transactionId].push(values[i]);
            _calldatas[transactionId].push(calldatas[i]);
        }
        confirmedBy[transactionId][msg.sender] = true;

        emit TransactionSubmitted(transactionId, nonce, msg.sender, expiresAt, actionsHash);
        emit TransactionConfirmed(transactionId, msg.sender);
    }

    function confirm(bytes32 transactionId) external onlySigner {
        _requireLive(transactionId);
        if (confirmedBy[transactionId][msg.sender]) {
            revert AlreadyConfirmed(transactionId, msg.sender);
        }
        confirmedBy[transactionId][msg.sender] = true;
        emit TransactionConfirmed(transactionId, msg.sender);
    }

    function revokeConfirmation(bytes32 transactionId) external onlySigner {
        _requireLive(transactionId);
        if (!confirmedBy[transactionId][msg.sender]) {
            revert NotConfirmed(transactionId, msg.sender);
        }
        confirmedBy[transactionId][msg.sender] = false;
        emit ConfirmationRevoked(transactionId, msg.sender);
    }

    /// @notice Permissionlessly executes a ready transaction before its expiry.
    function execute(bytes32 transactionId) external nonReentrant {
        _requireLive(transactionId);
        uint256 confirmations = confirmationCount(transactionId);
        if (confirmations < EXECUTION_THRESHOLD) {
            revert ThresholdNotMet(transactionId, confirmations);
        }

        Transaction storage current = _transactions[transactionId];
        current.executed = true;
        // The count is bounded by the fixed three-signer set.
        // forge-lint: disable-next-line(unsafe-typecast)
        current.executionConfirmationCount = uint8(confirmations);
        _executingTransactionId = transactionId;
        _signerReplacedDuringExecution = false;

        uint256 length = current.actionCount;
        for (uint256 i; i < length; ++i) {
            address target = _targets[transactionId][i];
            uint256 value = _values[transactionId][i];
            bytes memory data = _calldatas[transactionId][i];
            bytes memory returnData;

            if (target.code.length == 0) {
                if (data.length != 0) revert InvalidEOACall(transactionId, i, target);
                Address.sendValue(payable(target), value);
            } else {
                returnData = target.functionCallWithValue(data, value);
            }

            emit ActionExecuted(transactionId, i, target, value, keccak256(returnData));
        }
        _executingTransactionId = bytes32(0);

        emit TransactionExecuted(transactionId, msg.sender);
    }

    /// @notice Replaces one signer through a normal threshold-approved self-call.
    function replaceSigner(address oldSigner, address newSigner) external onlySelf {
        if (_signerReplacedDuringExecution) {
            revert SignerReplacementAlreadyPerformed(_executingTransactionId);
        }
        if (
            !isSigner[oldSigner] || newSigner == address(0) || newSigner == BURN_ADDRESS
                || newSigner == address(this) || isSigner[newSigner]
        ) {
            revert InvalidReplacement(oldSigner, newSigner);
        }

        for (uint256 i; i < SIGNER_COUNT; ++i) {
            if (_signers[i] == oldSigner) {
                _signers[i] = newSigner;
                break;
            }
        }
        isSigner[oldSigner] = false;
        isSigner[newSigner] = true;
        _signerReplacedDuringExecution = true;
        _sortSigners();
        emit SignerReplaced(oldSigner, newSigner);
    }

    function transactionDetails(bytes32 transactionId) external view returns (Transaction memory) {
        _requireKnown(transactionId);
        return _transactions[transactionId];
    }

    function transactionActions(bytes32 transactionId)
        external
        view
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas)
    {
        _requireKnown(transactionId);
        return (_targets[transactionId], _values[transactionId], _calldatas[transactionId]);
    }

    function actionAt(bytes32 transactionId, uint256 index)
        external
        view
        returns (address target, uint256 value, bytes memory data)
    {
        _requireKnown(transactionId);
        return (
            _targets[transactionId][index],
            _values[transactionId][index],
            _calldatas[transactionId][index]
        );
    }

    function confirmationCount(bytes32 transactionId) public view returns (uint256 count) {
        _requireKnown(transactionId);
        for (uint256 i; i < SIGNER_COUNT; ++i) {
            if (confirmedBy[transactionId][_signers[i]]) ++count;
        }
    }

    function isReady(bytes32 transactionId) external view returns (bool) {
        Transaction storage current = _transactions[transactionId];
        return current.exists && !current.executed && Time.timestamp() <= current.expiresAt
            && confirmationCount(transactionId) >= EXECUTION_THRESHOLD;
    }

    function isExpired(bytes32 transactionId) external view returns (bool) {
        _requireKnown(transactionId);
        return Time.timestamp() > _transactions[transactionId].expiresAt;
    }

    function _validateBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas
    ) private pure {
        uint256 length = targets.length;
        if (length != values.length || length != calldatas.length) {
            revert InvalidBatchLengths(length, values.length, calldatas.length);
        }
        if (length == 0 || length > MAX_ACTIONS) revert InvalidActionCount(length);

        uint256 totalCalldata;
        for (uint256 i; i < length; ++i) {
            if (targets[i] == address(0)) revert InvalidTarget(i, targets[i]);
            totalCalldata += calldatas[i].length;
        }
        if (totalCalldata > MAX_TOTAL_CALLDATA) {
            revert CalldataLimitExceeded(totalCalldata, MAX_TOTAL_CALLDATA);
        }
    }

    function _requireKnown(bytes32 transactionId) private view {
        if (!_transactions[transactionId].exists) revert UnknownTransaction(transactionId);
    }

    function _requireLive(bytes32 transactionId) private view {
        _requireKnown(transactionId);
        Transaction storage current = _transactions[transactionId];
        if (current.executed) revert TransactionAlreadyExecuted(transactionId);
        if (Time.timestamp() > current.expiresAt) {
            revert TransactionExpired(transactionId, current.expiresAt);
        }
    }

    function _sortSigners() private {
        for (uint256 i = 1; i < SIGNER_COUNT; ++i) {
            address candidate = _signers[i];
            uint256 j = i;
            while (j != 0 && _signers[j - 1] > candidate) {
                _signers[j] = _signers[j - 1];
                --j;
            }
            _signers[j] = candidate;
        }
    }
}
