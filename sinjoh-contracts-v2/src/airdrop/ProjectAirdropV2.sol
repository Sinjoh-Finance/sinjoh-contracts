// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {
    AirdropAccountConfig,
    AirdropCadence,
    AirdropDustDestination,
    AirdropEligibilityMode,
    AirdropEpochCommitment,
    AirdropLeaf,
    AirdropProof,
    AirdropProofNode
} from "./AirdropTypes.sol";
import { IProjectEligibilitySource } from "../interfaces/IProjectEligibilitySource.sol";
import { IProjectFundable } from "../interfaces/IProjectFundable.sol";
import { IProjectModule } from "../interfaces/IProjectModule.sol";
import { IProjectStakedVoteSource } from "../interfaces/IProjectStakedVoteSource.sol";
import { IProjectTokenIdentity } from "../interfaces/IProjectTokenIdentity.sol";
import { ProjectIds } from "../libraries/ProjectIds.sol";
import { SinjohV2Constants } from "../libraries/SinjohV2Constants.sol";

/// @notice Automatic push-based proportional distributions from immutable project snapshots.
/// @dev Every leaf is checked against the checkpoint source and a two-sum, direction-aware proof.
contract ProjectAirdropV2 is IProjectModule, IProjectFundable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public constant NATIVE_ASSET = address(0);
    address public constant BURN_ADDRESS = SinjohV2Constants.BURN_ADDRESS;
    address public constant PONS_LOCKER = 0x1006fA85294A9c38AA4214d52c86CC970Ddc5647;
    address public constant PONS_POOL_MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    uint16 public constant BPS = 10_000;
    uint16 public constant PROTOCOL_FEE_BPS = 100;
    uint16 public constant MAX_PUSH_BATCH_SIZE = 64;
    uint16 public constant MAX_SNAPSHOT_CONFIRMATIONS = 255;
    uint256 public constant MAX_EXCLUSIONS = 68;
    uint256 public constant MAX_PROOF_DEPTH = 64;
    uint256 public constant PAYMENT_GAS_LIMIT = 200_000;
    uint48 public constant EPOCH_ABORT_DELAY = 30 days;
    bytes32 public constant ACCOUNT_DOMAIN = keccak256("SINJOH_V2_AIRDROP_ACCOUNT");
    bytes32 public constant ACCOUNT_CONFIG_DOMAIN = keccak256("SINJOH_V2_AIRDROP_ACCOUNT_CONFIG");
    bytes32 public constant LEAF_DOMAIN = keccak256("SINJOH_V2_AIRDROP_LEAF");
    bytes32 public constant NODE_DOMAIN = keccak256("SINJOH_V2_AIRDROP_NODE");
    bytes32 public constant COMMITMENT_TYPEHASH = keccak256(
        "AirdropEpochCommitment(bytes32 accountId,uint64 epochId,uint64 snapshotBlock,bytes32 snapshotBlockHash,uint48 snapshotTime,bytes32 rootHash,uint256 rootSum,uint256 epochAmount,uint256 totalEligibleWeight,uint32 leafCount,bytes32 artifactHash)"
    );
    bytes32 private constant EIP712_DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    bytes32 private constant NAME_HASH = keccak256("Sinjoh Project Airdrop");
    bytes32 private constant VERSION_HASH = keccak256("2");
    bytes32 private constant TIMESTAMP_CLOCK_MODE_HASH = keccak256("mode=timestamp");

    struct AccountState {
        address funder;
        address asset;
        bytes32 configHash;
        uint256 uncommittedFunding;
        uint256 committedUnpaid;
        uint64 lastEpochId;
        uint64 lastSnapshotBlock;
        uint48 lastSnapshotTime;
        uint16 feeRemainder;
        uint16 maxPushBatchSize;
        uint16 minimumSnapshotConfirmations;
        AirdropCadence cadence;
        AirdropDustDestination dustDestination;
        bool exists;
    }

    struct EpochState {
        uint64 snapshotBlock;
        uint48 snapshotTime;
        uint32 leafCount;
        uint32 settledLeafCount;
        uint48 committedAt;
        bytes32 snapshotBlockHash;
        bytes32 rootHash;
        bytes32 artifactHash;
        uint256 rootSum;
        uint256 epochAmount;
        uint256 totalEligibleWeight;
        uint256 settledEntitlement;
        bool finalized;
        bool aborted;
    }

    address public immutable override registry;
    address public immutable override subject;
    address public immutable creator;
    bytes32 public immutable override projectId;
    address public immutable treasury;
    address public immutable protocolFeeRecipient;
    address public immutable attestor;
    address public immutable eligibilitySource;
    AirdropEligibilityMode public immutable eligibilityMode;
    bytes32 public immutable exclusionHash;

    address[] private _exclusions;
    mapping(address account => bool excluded) private _excluded;
    mapping(bytes32 accountId => AccountState account) private _accounts;
    mapping(bytes32 accountId => mapping(uint64 epochId => EpochState epoch)) private _epochs;
    mapping(
        bytes32 accountId => mapping(uint64 epochId => mapping(address holder => bool done))
    ) public processed;

    mapping(address asset => uint256 amount) public totalUncommitted;
    mapping(address asset => uint256 amount) public totalCommittedUnpaid;
    mapping(address asset => uint256 amount) public totalRetryableCredits;
    mapping(address asset => uint256 amount) public protocolOwed;
    mapping(address recipient => mapping(address asset => uint256 amount)) public retryableCredit;

    error OnlySelf(address caller);
    error InvalidRegistry(address candidate);
    error InvalidSubject(address candidate);
    error InvalidCreator(address candidate);
    error InvalidTreasury(address candidate);
    error InvalidFeeRecipient(address candidate);
    error InvalidAttestor(address candidate);
    error InvalidEligibilitySource(address candidate);
    error ProjectIdentityMismatch(bytes32 expected, bytes32 actual);
    error StakedSourceSubjectMismatch(address expected, address actual);
    error UnsupportedClockMode(string supplied);
    error TooManyExclusions(uint256 supplied);
    error InvalidExclusion(uint256 index, address account);
    error UnsortedExclusions(uint256 index, address previous, address current);
    error ReservedExclusion(address account);
    error InvalidFundingIdentity(bytes32 projectId, address subject);
    error InvalidFunder(address funder);
    error InvalidAsset(address asset);
    error InvalidAmount(uint256 supplied);
    error NativeValueMismatch(uint256 expected, uint256 supplied);
    error InexactAssetReceipt(address asset, uint256 expected, uint256 measured);
    error InexactAssetSpend(address asset, uint256 expected, uint256 measured);
    error AssetUnderbacked(address asset, uint256 measured, uint256 liability);
    error MissingAccountConfig(bytes32 accountId);
    error NonCanonicalAccountConfig();
    error AccountConfigMismatch(bytes32 expected, bytes32 supplied);
    error InvalidPushBatchSize(uint16 supplied);
    error InvalidSnapshotConfirmations(uint16 supplied);
    error InvalidDustDestination(AirdropDustDestination supplied);
    error UnknownAccount(bytes32 accountId);
    error InvalidEpochId(uint64 expected, uint64 supplied);
    error InvalidSnapshotBlock(uint64 supplied, uint256 currentBlock);
    error SnapshotNotFinal(uint256 confirmations, uint256 required);
    error SnapshotOutsideHashWindow(uint256 confirmations);
    error SnapshotHashMismatch(bytes32 expected, bytes32 supplied);
    error InvalidSnapshotTime(uint48 previous, uint48 supplied, uint48 currentTime);
    error CadenceNotElapsed(uint48 earliest, uint48 supplied);
    error InvalidCommitment();
    error EligibleWeightMismatch(uint256 expected, uint256 supplied);
    error InsufficientAccountFunding(uint256 available, uint256 requested);
    error InvalidAttestation();
    error InputArrayLengthMismatch(uint256 leaves, uint256 proofs);
    error EmptyPushBatch();
    error PushBatchTooLarge(uint256 supplied, uint256 maximum);
    error UnknownEpoch(bytes32 accountId, uint64 epochId);
    error EpochAlreadyFinalized(bytes32 accountId, uint64 epochId);
    error UnauthorizedEpochAbort(address caller, address funder, address treasury);
    error EpochAbortNotReady(uint48 earliest, uint48 currentTime);
    error HolderAlreadyProcessed(address holder);
    error ExcludedHolder(address holder);
    error InvalidHolderWeight(address holder, uint256 expected, uint256 supplied);
    error InvalidEntitlement(address holder, uint256 expected, uint256 supplied);
    error ProofTooDeep(uint256 supplied);
    error InvalidMerkleSumProof(address holder);
    error EpochNotSettled(
        uint32 settledLeaves, uint32 totalLeaves, uint256 settled, uint256 rootSum
    );
    error NoRetryableCredit(address recipient, address asset);
    error NoProtocolFee(address asset);
    error NoSurplus(address asset);
    error NativeTransferFailed(address recipient, uint256 amount);

    event AirdropCreated(
        bytes32 indexed projectId,
        address indexed subject,
        address indexed eligibilitySource,
        AirdropEligibilityMode eligibilityMode,
        address attestor,
        bytes32 exclusionHash
    );
    event ExclusionConfigured(address indexed account, bool automatic);
    event AccountConfigured(
        bytes32 indexed accountId,
        address indexed funder,
        address indexed asset,
        AirdropEligibilityMode eligibilityMode,
        bytes32 configHash
    );
    event Funded(
        bytes32 indexed accountId,
        address indexed asset,
        uint256 gross,
        uint256 protocolFee,
        uint256 net
    );
    event EpochCommitted(
        bytes32 indexed accountId,
        uint64 indexed epochId,
        uint64 snapshotBlock,
        uint48 snapshotTime,
        bytes32 rootHash,
        uint256 rootSum,
        uint256 epochAmount,
        bytes32 artifactHash
    );
    event PaymentSucceeded(
        bytes32 indexed accountId,
        uint64 indexed epochId,
        address indexed holder,
        address asset,
        uint256 amount
    );
    event PaymentDeferred(
        bytes32 indexed accountId,
        uint64 indexed epochId,
        address indexed holder,
        address asset,
        uint256 amount,
        bytes32 reasonHash
    );
    event CreditDelivered(address indexed recipient, address indexed asset, uint256 amount);
    event CreditRetryFailed(
        address indexed recipient, address indexed asset, uint256 amount, bytes32 reasonHash
    );
    event DustDeferred(
        bytes32 indexed accountId,
        uint64 indexed epochId,
        address indexed recipient,
        address asset,
        uint256 amount,
        bytes32 reasonHash
    );
    event EpochFinalized(
        bytes32 indexed accountId, uint64 indexed epochId, uint256 divisionDust, address destination
    );
    event EpochAborted(bytes32 indexed accountId, uint64 indexed epochId, uint256 returnedFunding);
    event ProtocolFeeSent(address indexed asset, uint256 amount);
    event SurplusRecovered(address indexed asset, address indexed recipient, uint256 amount);

    modifier onlySelf() {
        if (msg.sender != address(this)) revert OnlySelf(msg.sender);
        _;
    }

    constructor(
        address registry_,
        address subject_,
        address creator_,
        address treasury_,
        address protocolFeeRecipient_,
        address attestor_,
        address eligibilitySource_,
        AirdropEligibilityMode eligibilityMode_,
        address[] memory additionalExclusions
    ) {
        if (registry_.code.length == 0) {
            revert InvalidRegistry(registry_);
        }
        if (subject_.code.length == 0) revert InvalidSubject(subject_);
        if (creator_ == address(0) || creator_ == BURN_ADDRESS || creator_ == address(this)) {
            revert InvalidCreator(creator_);
        }
        if (
            protocolFeeRecipient_ == address(0) || protocolFeeRecipient_ == BURN_ADDRESS
                || protocolFeeRecipient_ == address(this)
        ) revert InvalidFeeRecipient(protocolFeeRecipient_);
        if (attestor_ == address(0) || attestor_ == BURN_ADDRESS || attestor_ == address(this)) {
            revert InvalidAttestor(attestor_);
        }
        if (eligibilitySource_.code.length == 0) {
            revert InvalidEligibilitySource(eligibilitySource_);
        }

        bytes32 expectedProjectId = ProjectIds.derive(block.chainid, registry_, subject_);
        bytes32 subjectProjectId = IProjectTokenIdentity(subject_).projectId();
        if (
            IProjectTokenIdentity(subject_).registry() != registry_
                || subjectProjectId != expectedProjectId
        ) revert ProjectIdentityMismatch(expectedProjectId, subjectProjectId);
        bytes32 sourceProjectId = IProjectTokenIdentity(eligibilitySource_).projectId();
        if (
            IProjectTokenIdentity(eligibilitySource_).registry() != registry_
                || sourceProjectId != expectedProjectId
        ) revert ProjectIdentityMismatch(expectedProjectId, sourceProjectId);
        if (eligibilityMode_ == AirdropEligibilityMode.HOLDERS) {
            if (eligibilitySource_ != subject_) {
                revert InvalidEligibilitySource(eligibilitySource_);
            }
        } else {
            if (eligibilitySource_ == subject_) {
                revert InvalidEligibilitySource(eligibilitySource_);
            }
            address sourceSubject = address(IProjectStakedVoteSource(eligibilitySource_).subject());
            if (sourceSubject != subject_) {
                revert StakedSourceSubjectMismatch(subject_, sourceSubject);
            }
        }
        string memory clockMode;
        try IProjectEligibilitySource(eligibilitySource_).CLOCK_MODE() returns (
            string memory suppliedMode
        ) {
            clockMode = suppliedMode;
        } catch {
            revert InvalidEligibilitySource(eligibilitySource_);
        }
        if (keccak256(bytes(clockMode)) != TIMESTAMP_CLOCK_MODE_HASH) {
            revert UnsupportedClockMode(clockMode);
        }
        if (treasury_ != address(0)) {
            if (treasury_.code.length == 0) revert InvalidTreasury(treasury_);
            if (
                IProjectModule(treasury_).registry() != registry_
                    || IProjectModule(treasury_).subject() != subject_
                    || IProjectModule(treasury_).projectId() != expectedProjectId
            ) revert InvalidTreasury(treasury_);
        }

        registry = registry_;
        subject = subject_;
        creator = creator_;
        projectId = expectedProjectId;
        treasury = treasury_;
        protocolFeeRecipient = protocolFeeRecipient_;
        attestor = attestor_;
        eligibilitySource = eligibilitySource_;
        eligibilityMode = eligibilityMode_;

        _addAutomaticExclusion(address(0));
        _addAutomaticExclusion(address(this));
        _addAutomaticExclusion(subject_);
        _addAutomaticExclusion(BURN_ADDRESS);
        _addAutomaticExclusion(PONS_LOCKER);
        _addAutomaticExclusion(PONS_POOL_MANAGER);
        if (treasury_ != address(0)) _addAutomaticExclusion(treasury_);
        if (eligibilitySource_ != subject_) _addAutomaticExclusion(eligibilitySource_);
        _configureAdditionalExclusions(additionalExclusions);
        exclusionHash = keccak256(abi.encode(_exclusions));

        emit AirdropCreated(
            expectedProjectId,
            subject_,
            eligibilitySource_,
            eligibilityMode_,
            attestor_,
            exclusionHash
        );
    }

    function fund(
        bytes32 projectId_,
        address subject_,
        address asset,
        uint256 amount,
        bytes calldata config
    ) external payable nonReentrant returns (uint256 received) {
        if (projectId_ != projectId || subject_ != subject) {
            revert InvalidFundingIdentity(projectId_, subject_);
        }
        if (msg.sender == BURN_ADDRESS) revert InvalidFunder(msg.sender);
        if (amount == 0) revert InvalidAmount(amount);
        _validateAsset(asset);
        bytes32 id = accountId(msg.sender, asset);
        AccountState storage account = _accounts[id];
        _configureOrValidateAccount(id, account, msg.sender, asset, config);

        if (asset == NATIVE_ASSET) {
            if (msg.value != amount) revert NativeValueMismatch(amount, msg.value);
            uint256 measuredBefore = address(this).balance - msg.value;
            uint256 liabilityBefore = totalLiability(asset);
            if (measuredBefore < liabilityBefore) {
                revert AssetUnderbacked(asset, measuredBefore, liabilityBefore);
            }
            received = amount;
        } else {
            if (msg.value != 0) revert NativeValueMismatch(0, msg.value);
            _assertBacked(asset);
            uint256 beforeBalance = IERC20(asset).balanceOf(address(this));
            IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
            received = IERC20(asset).balanceOf(address(this)) - beforeBalance;
            if (received != amount) revert InexactAssetReceipt(asset, amount, received);
        }

        (uint256 fee, uint16 nextRemainder) = _accrueProtocolFee(amount, account.feeRemainder);
        account.feeRemainder = nextRemainder;
        account.uncommittedFunding += amount - fee;
        totalUncommitted[asset] += amount - fee;
        protocolOwed[asset] += fee;
        emit Funded(id, asset, amount, fee, amount - fee);
    }

    function commitEpoch(AirdropEpochCommitment calldata commitment, bytes calldata signature)
        external
        nonReentrant
    {
        AccountState storage account = _requireAccount(commitment.accountId);
        _assertBacked(account.asset);
        uint64 expectedEpochId = account.lastEpochId + 1;
        if (commitment.epochId != expectedEpochId) {
            revert InvalidEpochId(expectedEpochId, commitment.epochId);
        }
        _validateSnapshot(account, commitment);
        if (
            commitment.rootHash == bytes32(0) || commitment.rootSum == 0
                || commitment.epochAmount == 0 || commitment.totalEligibleWeight == 0
                || commitment.leafCount == 0 || commitment.artifactHash == bytes32(0)
                || commitment.rootSum > commitment.epochAmount
        ) revert InvalidCommitment();
        uint256 eligibleWeight = totalEligibleWeightAt(commitment.snapshotTime);
        if (eligibleWeight != commitment.totalEligibleWeight) {
            revert EligibleWeightMismatch(eligibleWeight, commitment.totalEligibleWeight);
        }
        if (commitment.epochAmount > account.uncommittedFunding) {
            revert InsufficientAccountFunding(account.uncommittedFunding, commitment.epochAmount);
        }
        bytes32 digest = commitmentDigest(commitment);
        if (!SignatureChecker.isValidSignatureNow(attestor, digest, signature)) {
            revert InvalidAttestation();
        }

        account.lastEpochId = commitment.epochId;
        account.lastSnapshotBlock = commitment.snapshotBlock;
        account.lastSnapshotTime = commitment.snapshotTime;
        account.uncommittedFunding -= commitment.epochAmount;
        account.committedUnpaid += commitment.epochAmount;
        totalUncommitted[account.asset] -= commitment.epochAmount;
        totalCommittedUnpaid[account.asset] += commitment.epochAmount;
        EpochState storage epoch = _epochs[commitment.accountId][commitment.epochId];
        epoch.snapshotBlock = commitment.snapshotBlock;
        epoch.snapshotTime = commitment.snapshotTime;
        epoch.leafCount = commitment.leafCount;
        epoch.committedAt = uint48(block.timestamp);
        epoch.snapshotBlockHash = commitment.snapshotBlockHash;
        epoch.rootHash = commitment.rootHash;
        epoch.artifactHash = commitment.artifactHash;
        epoch.rootSum = commitment.rootSum;
        epoch.epochAmount = commitment.epochAmount;
        epoch.totalEligibleWeight = commitment.totalEligibleWeight;
        emit EpochCommitted(
            commitment.accountId,
            commitment.epochId,
            commitment.snapshotBlock,
            commitment.snapshotTime,
            commitment.rootHash,
            commitment.rootSum,
            commitment.epochAmount,
            commitment.artifactHash
        );
    }

    function push(
        bytes32 accountId_,
        uint64 epochId,
        AirdropLeaf[] calldata leaves,
        AirdropProof[] calldata proofs
    ) external nonReentrant {
        uint256 count = leaves.length;
        if (count == 0) revert EmptyPushBatch();
        if (count != proofs.length) revert InputArrayLengthMismatch(count, proofs.length);
        AccountState storage account = _requireAccount(accountId_);
        _assertBacked(account.asset);
        if (count > account.maxPushBatchSize) {
            revert PushBatchTooLarge(count, account.maxPushBatchSize);
        }
        EpochState storage epoch = _requireEpoch(accountId_, epochId);
        if (epoch.finalized) revert EpochAlreadyFinalized(accountId_, epochId);
        for (uint256 i; i < count; ++i) {
            _processLeaf(accountId_, epochId, account, epoch, leaves[i], proofs[i]);
        }
    }

    function finalizeEpoch(bytes32 accountId_, uint64 epochId) external nonReentrant {
        AccountState storage account = _requireAccount(accountId_);
        _assertBacked(account.asset);
        EpochState storage epoch = _requireEpoch(accountId_, epochId);
        if (epoch.finalized) revert EpochAlreadyFinalized(accountId_, epochId);
        if (epoch.settledLeafCount != epoch.leafCount || epoch.settledEntitlement != epoch.rootSum)
        {
            revert EpochNotSettled(
                epoch.settledLeafCount, epoch.leafCount, epoch.settledEntitlement, epoch.rootSum
            );
        }
        epoch.finalized = true;
        uint256 dust = epoch.epochAmount - epoch.rootSum;
        address destination;
        if (dust != 0) {
            totalCommittedUnpaid[account.asset] -= dust;
            account.committedUnpaid -= dust;
            if (account.dustDestination == AirdropDustDestination.NEXT_EPOCH) {
                account.uncommittedFunding += dust;
                totalUncommitted[account.asset] += dust;
                destination = address(this);
            } else {
                destination = account.dustDestination == AirdropDustDestination.TREASURY
                    ? treasury
                    : account.funder;
                (bool success, bytes32 reasonHash) =
                    _isolatedPayment(account.asset, destination, dust);
                if (!success) {
                    _addCredit(destination, account.asset, dust);
                    emit DustDeferred(
                        accountId_, epochId, destination, account.asset, dust, reasonHash
                    );
                }
            }
        }
        emit EpochFinalized(accountId_, epochId, dust, destination);
    }

    function abortEpoch(bytes32 accountId_, uint64 epochId)
        external
        nonReentrant
        returns (uint256 returnedFunding)
    {
        AccountState storage account = _requireAccount(accountId_);
        if (msg.sender != account.funder && msg.sender != treasury) {
            revert UnauthorizedEpochAbort(msg.sender, account.funder, treasury);
        }
        _assertBacked(account.asset);
        EpochState storage epoch = _requireEpoch(accountId_, epochId);
        if (epoch.finalized) revert EpochAlreadyFinalized(accountId_, epochId);
        uint48 currentTime = uint48(block.timestamp);
        uint48 earliest = epoch.committedAt + EPOCH_ABORT_DELAY;
        if (currentTime < earliest) revert EpochAbortNotReady(earliest, currentTime);

        epoch.finalized = true;
        epoch.aborted = true;
        returnedFunding = epoch.epochAmount - epoch.settledEntitlement;
        account.committedUnpaid -= returnedFunding;
        account.uncommittedFunding += returnedFunding;
        totalCommittedUnpaid[account.asset] -= returnedFunding;
        totalUncommitted[account.asset] += returnedFunding;
        emit EpochAborted(accountId_, epochId, returnedFunding);
    }

    function retryCredit(address recipient, address asset, uint256 maxAmount)
        external
        nonReentrant
        returns (uint256 amount, bool succeeded)
    {
        if (maxAmount == 0) revert InvalidAmount(0);
        uint256 current = retryableCredit[recipient][asset];
        if (current == 0) revert NoRetryableCredit(recipient, asset);
        _assertBacked(asset);
        amount = Math.min(current, maxAmount);
        retryableCredit[recipient][asset] = current - amount;
        totalRetryableCredits[asset] -= amount;
        bytes32 reasonHash;
        (succeeded, reasonHash) = _isolatedPayment(asset, recipient, amount);
        if (succeeded) {
            emit CreditDelivered(recipient, asset, amount);
        } else {
            _addCredit(recipient, asset, amount);
            emit CreditRetryFailed(recipient, asset, amount, reasonHash);
        }
    }

    /// @notice Lets the credited holder redirect its own failed payment to a payable receiver.
    function claimCreditTo(address asset, uint256 maxAmount, address payoutRecipient)
        external
        nonReentrant
        returns (uint256 amount)
    {
        if (maxAmount == 0 || payoutRecipient == address(0) || payoutRecipient == address(this)) {
            revert InvalidAmount(maxAmount);
        }
        uint256 current = retryableCredit[msg.sender][asset];
        if (current == 0) revert NoRetryableCredit(msg.sender, asset);
        _assertBacked(asset);
        amount = Math.min(current, maxAmount);
        retryableCredit[msg.sender][asset] = current - amount;
        totalRetryableCredits[asset] -= amount;
        _sendExact(asset, payoutRecipient, amount);
        emit CreditDelivered(payoutRecipient, asset, amount);
    }

    function deliverPayment(address asset, address recipient, uint256 amount) external onlySelf {
        _sendExact(asset, recipient, amount);
    }

    function sendProtocolFee(address asset, uint256 maxAmount)
        external
        nonReentrant
        returns (uint256 amount)
    {
        if (maxAmount == 0) revert InvalidAmount(0);
        uint256 owed = protocolOwed[asset];
        if (owed == 0) revert NoProtocolFee(asset);
        _assertBacked(asset);
        amount = Math.min(owed, maxAmount);
        protocolOwed[asset] = owed - amount;
        _sendExact(asset, protocolFeeRecipient, amount);
        emit ProtocolFeeSent(asset, amount);
    }

    function recoverSurplus(address asset, uint256 maxAmount)
        external
        nonReentrant
        returns (uint256 amount)
    {
        if (maxAmount == 0) revert InvalidAmount(0);
        uint256 surplus = surplusBalance(asset);
        if (surplus == 0) revert NoSurplus(asset);
        amount = Math.min(surplus, maxAmount);
        address recipient = treasury == address(0) ? creator : treasury;
        _sendExact(asset, recipient, amount);
        emit SurplusRecovered(asset, recipient, amount);
    }

    function accountId(address funder, address asset) public view returns (bytes32) {
        return keccak256(abi.encode(ACCOUNT_DOMAIN, projectId, funder, asset, eligibilityMode));
    }

    function accountConfigHash(bytes32 accountId_, AirdropAccountConfig memory config)
        public
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                ACCOUNT_CONFIG_DOMAIN,
                block.chainid,
                address(this),
                accountId_,
                exclusionHash,
                config
            )
        );
    }

    function accountStatus(bytes32 accountId_)
        external
        view
        returns (
            AccountState memory account,
            uint256 committedUnpaid,
            uint256 assetRetryableCredits
        )
    {
        account = _requireAccount(accountId_);
        committedUnpaid = account.committedUnpaid;
        assetRetryableCredits = totalRetryableCredits[account.asset];
    }

    function epochStatus(bytes32 accountId_, uint64 epochId)
        external
        view
        returns (EpochState memory)
    {
        return _requireEpoch(accountId_, epochId);
    }

    function accountCommittedUnpaid(bytes32 accountId_) public view returns (uint256) {
        return _requireAccount(accountId_).committedUnpaid;
    }

    function totalLiability(address asset) public view returns (uint256) {
        return totalUncommitted[asset] + totalCommittedUnpaid[asset] + totalRetryableCredits[asset]
            + protocolOwed[asset];
    }

    function surplusBalance(address asset) public view returns (uint256) {
        _validateAsset(asset);
        uint256 measured = _measuredBalance(asset);
        uint256 liability = totalLiability(asset);
        return measured > liability ? measured - liability : 0;
    }

    function isAssetBacked(address asset) external view returns (bool) {
        _validateAsset(asset);
        return _measuredBalance(asset) >= totalLiability(asset);
    }

    function exclusionCount() external view returns (uint256) {
        return _exclusions.length;
    }

    function exclusionAt(uint256 index) external view returns (address) {
        return _exclusions[index];
    }

    function exclusions() external view returns (address[] memory) {
        return _exclusions;
    }

    function isExcluded(address account) public view returns (bool) {
        return _excluded[account];
    }

    function eligibilityAt(address holder, uint48 timepoint) public view returns (uint256) {
        if (isExcluded(holder)) return 0;
        return IProjectEligibilitySource(eligibilitySource).getPastVotes(holder, timepoint);
    }

    function totalEligibleWeightAt(uint48 timepoint) public view returns (uint256 eligible) {
        IProjectEligibilitySource source = IProjectEligibilitySource(eligibilitySource);
        eligible = source.getPastTotalSupply(timepoint);
        uint256 excludedWeight;
        uint256 count = _exclusions.length;
        for (uint256 i; i < count; ++i) {
            excludedWeight += source.getPastVotes(_exclusions[i], timepoint);
        }
        if (excludedWeight > eligible) {
            revert EligibleWeightMismatch(eligible, excludedWeight);
        }
        eligible -= excludedWeight;
    }

    function domainSeparator() public view returns (bytes32) {
        return keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH, NAME_HASH, VERSION_HASH, block.chainid, address(this)
            )
        );
    }

    function commitmentDigest(AirdropEpochCommitment calldata commitment)
        public
        view
        returns (bytes32)
    {
        bytes32 structHash = keccak256(
            abi.encode(
                COMMITMENT_TYPEHASH,
                commitment.accountId,
                commitment.epochId,
                commitment.snapshotBlock,
                commitment.snapshotBlockHash,
                commitment.snapshotTime,
                commitment.rootHash,
                commitment.rootSum,
                commitment.epochAmount,
                commitment.totalEligibleWeight,
                commitment.leafCount,
                commitment.artifactHash
            )
        );
        return MessageHashUtils.toTypedDataHash(domainSeparator(), structHash);
    }

    function leafHash(
        bytes32 accountId_,
        uint64 epochId,
        uint64 snapshotBlock,
        uint48 snapshotTime,
        AirdropLeaf calldata leaf
    ) public view returns (bytes32) {
        bytes32 inner = keccak256(
            abi.encode(
                LEAF_DOMAIN,
                block.chainid,
                address(this),
                accountId_,
                epochId,
                snapshotBlock,
                snapshotTime,
                leaf.holder,
                leaf.weight,
                leaf.amount
            )
        );
        return keccak256(bytes.concat(inner));
    }

    function nodeHash(
        bytes32 leftHash,
        uint256 leftWeightSum,
        uint256 leftAmountSum,
        uint32 leftLeafCount,
        bytes32 rightHash,
        uint256 rightWeightSum,
        uint256 rightAmountSum,
        uint32 rightLeafCount
    ) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                NODE_DOMAIN,
                leftHash,
                leftWeightSum,
                leftAmountSum,
                leftLeafCount,
                rightHash,
                rightWeightSum,
                rightAmountSum,
                rightLeafCount
            )
        );
    }

    function verifyProof(
        bytes32 accountId_,
        uint64 epochId,
        AirdropLeaf calldata leaf,
        AirdropProof calldata proof
    ) external view returns (bool) {
        EpochState storage epoch = _requireEpoch(accountId_, epochId);
        return _verifyProof(accountId_, epochId, epoch, leaf, proof);
    }

    function cadenceSeconds(AirdropCadence cadence) public pure returns (uint48) {
        if (cadence == AirdropCadence.DAILY) return 1 days;
        if (cadence == AirdropCadence.WEEKLY) return 7 days;
        return 0;
    }

    function _configureOrValidateAccount(
        bytes32 id,
        AccountState storage account,
        address funder,
        address asset,
        bytes calldata configData
    ) private {
        if (!account.exists) {
            if (configData.length == 0) revert MissingAccountConfig(id);
            AirdropAccountConfig memory config = abi.decode(configData, (AirdropAccountConfig));
            if (keccak256(configData) != keccak256(abi.encode(config))) {
                revert NonCanonicalAccountConfig();
            }
            _validateAccountConfig(config);
            bytes32 configHash = accountConfigHash(id, config);
            account.funder = funder;
            account.asset = asset;
            account.configHash = configHash;
            account.maxPushBatchSize = config.maxPushBatchSize;
            account.minimumSnapshotConfirmations = config.minimumSnapshotConfirmations;
            account.cadence = config.cadence;
            account.dustDestination = config.dustDestination;
            account.exists = true;
            emit AccountConfigured(id, funder, asset, eligibilityMode, configHash);
            return;
        }
        if (configData.length == 0) return;
        AirdropAccountConfig memory supplied = abi.decode(configData, (AirdropAccountConfig));
        if (keccak256(configData) != keccak256(abi.encode(supplied))) {
            revert NonCanonicalAccountConfig();
        }
        bytes32 suppliedHash = accountConfigHash(id, supplied);
        if (suppliedHash != account.configHash) {
            revert AccountConfigMismatch(account.configHash, suppliedHash);
        }
    }

    function _validateAccountConfig(AirdropAccountConfig memory config) private view {
        if (config.maxPushBatchSize == 0 || config.maxPushBatchSize > MAX_PUSH_BATCH_SIZE) {
            revert InvalidPushBatchSize(config.maxPushBatchSize);
        }
        if (
            config.minimumSnapshotConfirmations == 0
                || config.minimumSnapshotConfirmations > MAX_SNAPSHOT_CONFIRMATIONS
        ) revert InvalidSnapshotConfirmations(config.minimumSnapshotConfirmations);
        if (config.dustDestination == AirdropDustDestination.TREASURY && treasury == address(0)) {
            revert InvalidDustDestination(config.dustDestination);
        }
    }

    function _validateSnapshot(
        AccountState storage account,
        AirdropEpochCommitment calldata commitment
    ) private view {
        uint256 snapshotBlock = commitment.snapshotBlock;
        if (snapshotBlock >= block.number || snapshotBlock <= account.lastSnapshotBlock) {
            revert InvalidSnapshotBlock(commitment.snapshotBlock, block.number);
        }
        uint256 confirmations = block.number - snapshotBlock;
        if (confirmations < account.minimumSnapshotConfirmations) {
            revert SnapshotNotFinal(confirmations, account.minimumSnapshotConfirmations);
        }
        // The attestor signature binds the block hash. Do not use EVM `blockhash` here: it only
        // exposes the latest 256 blocks, while Robinhood's finalized head can lag farther than
        // that. Workers must reconcile the finalized block/hash/time through two providers
        // before the attestor signs; the contract verifies that exact signed commitment.
        if (commitment.snapshotBlockHash == bytes32(0)) {
            revert SnapshotHashMismatch(bytes32(0), commitment.snapshotBlockHash);
        }
        uint48 currentTime = IProjectEligibilitySource(eligibilitySource).clock();
        if (
            commitment.snapshotTime <= account.lastSnapshotTime
                || commitment.snapshotTime >= currentTime
        ) {
            revert InvalidSnapshotTime(
                account.lastSnapshotTime, commitment.snapshotTime, currentTime
            );
        }
        if (account.lastSnapshotTime != 0) {
            uint48 earliest = account.lastSnapshotTime + cadenceSeconds(account.cadence);
            if (commitment.snapshotTime < earliest) {
                revert CadenceNotElapsed(earliest, commitment.snapshotTime);
            }
        }
    }

    function _processLeaf(
        bytes32 accountId_,
        uint64 epochId,
        AccountState storage account,
        EpochState storage epoch,
        AirdropLeaf calldata leaf,
        AirdropProof calldata proof
    ) private {
        if (processed[accountId_][epochId][leaf.holder]) {
            revert HolderAlreadyProcessed(leaf.holder);
        }
        if (isExcluded(leaf.holder)) revert ExcludedHolder(leaf.holder);
        uint256 expectedWeight = IProjectEligibilitySource(eligibilitySource)
            .getPastVotes(leaf.holder, epoch.snapshotTime);
        if (expectedWeight == 0 || leaf.weight != expectedWeight) {
            revert InvalidHolderWeight(leaf.holder, expectedWeight, leaf.weight);
        }
        uint256 expectedAmount =
            Math.mulDiv(epoch.epochAmount, expectedWeight, epoch.totalEligibleWeight);
        if (leaf.amount != expectedAmount) {
            revert InvalidEntitlement(leaf.holder, expectedAmount, leaf.amount);
        }
        if (!_verifyProof(accountId_, epochId, epoch, leaf, proof)) {
            revert InvalidMerkleSumProof(leaf.holder);
        }

        processed[accountId_][epochId][leaf.holder] = true;
        epoch.settledLeafCount += 1;
        epoch.settledEntitlement += leaf.amount;
        if (leaf.amount == 0) {
            emit PaymentSucceeded(accountId_, epochId, leaf.holder, account.asset, 0);
            return;
        }
        totalCommittedUnpaid[account.asset] -= leaf.amount;
        account.committedUnpaid -= leaf.amount;
        (bool success, bytes32 reasonHash) =
            _isolatedPayment(account.asset, leaf.holder, leaf.amount);
        if (success) {
            emit PaymentSucceeded(accountId_, epochId, leaf.holder, account.asset, leaf.amount);
        } else {
            _addCredit(leaf.holder, account.asset, leaf.amount);
            emit PaymentDeferred(
                accountId_, epochId, leaf.holder, account.asset, leaf.amount, reasonHash
            );
        }
    }

    function _verifyProof(
        bytes32 accountId_,
        uint64 epochId,
        EpochState storage epoch,
        AirdropLeaf calldata leaf,
        AirdropProof calldata proof
    ) private view returns (bool) {
        uint256 depth = proof.nodes.length;
        if (depth > MAX_PROOF_DEPTH) revert ProofTooDeep(depth);
        bytes32 currentHash =
            leafHash(accountId_, epochId, epoch.snapshotBlock, epoch.snapshotTime, leaf);
        uint256 currentWeight = leaf.weight;
        uint256 currentAmount = leaf.amount;
        uint32 currentLeafCount = 1;
        for (uint256 i; i < depth; ++i) {
            AirdropProofNode calldata sibling = proof.nodes[i];
            if (
                type(uint256).max - currentWeight < sibling.siblingWeightSum
                    || type(uint256).max - currentAmount < sibling.siblingAmountSum
                    || sibling.siblingLeafCount == 0
                    || type(uint32).max - currentLeafCount < sibling.siblingLeafCount
            ) return false;
            uint256 combinedWeight = currentWeight + sibling.siblingWeightSum;
            uint256 combinedAmount = currentAmount + sibling.siblingAmountSum;
            uint32 combinedLeafCount = currentLeafCount + sibling.siblingLeafCount;
            if (sibling.siblingOnLeft) {
                currentHash = nodeHash(
                    sibling.siblingHash,
                    sibling.siblingWeightSum,
                    sibling.siblingAmountSum,
                    sibling.siblingLeafCount,
                    currentHash,
                    currentWeight,
                    currentAmount,
                    currentLeafCount
                );
            } else {
                currentHash = nodeHash(
                    currentHash,
                    currentWeight,
                    currentAmount,
                    currentLeafCount,
                    sibling.siblingHash,
                    sibling.siblingWeightSum,
                    sibling.siblingAmountSum,
                    sibling.siblingLeafCount
                );
            }
            currentWeight = combinedWeight;
            currentAmount = combinedAmount;
            currentLeafCount = combinedLeafCount;
        }
        return currentHash == epoch.rootHash && currentWeight == epoch.totalEligibleWeight
            && currentAmount == epoch.rootSum && currentLeafCount == epoch.leafCount;
    }

    function _isolatedPayment(address asset, address recipient, uint256 amount)
        private
        returns (bool succeeded, bytes32 reasonHash)
    {
        bytes memory callData = abi.encodeCall(this.deliverPayment, (asset, recipient, amount));
        uint256 returnSize;
        assembly ("memory-safe") {
            succeeded := call(
                PAYMENT_GAS_LIMIT,
                address(),
                0,
                add(callData, 0x20),
                mload(callData),
                0,
                0
            )
            returnSize := returndatasize()
        }
        if (succeeded) return (true, bytes32(0));
        uint256 copySize = Math.min(returnSize, 256);
        bytes memory boundedReason = new bytes(copySize + 32);
        assembly ("memory-safe") {
            returndatacopy(add(boundedReason, 0x20), 0, copySize)
            mstore(add(add(boundedReason, 0x20), copySize), returnSize)
        }
        return (false, keccak256(boundedReason));
    }

    function _sendExact(address asset, address recipient, uint256 amount) private {
        uint256 beforeRouter = _measuredBalance(asset);
        if (asset == NATIVE_ASSET) {
            (bool success,) = recipient.call{ value: amount }("");
            if (!success) revert NativeTransferFailed(recipient, amount);
        } else {
            uint256 beforeRecipient = IERC20(asset).balanceOf(recipient);
            IERC20(asset).safeTransfer(recipient, amount);
            uint256 received = IERC20(asset).balanceOf(recipient) - beforeRecipient;
            if (received != amount) revert InexactAssetReceipt(asset, amount, received);
        }
        uint256 afterRouter = _measuredBalance(asset);
        uint256 spent = beforeRouter >= afterRouter ? beforeRouter - afterRouter : 0;
        if (spent != amount) revert InexactAssetSpend(asset, amount, spent);
    }

    function _addCredit(address recipient, address asset, uint256 amount) private {
        retryableCredit[recipient][asset] += amount;
        totalRetryableCredits[asset] += amount;
    }

    function _accrueProtocolFee(uint256 amount, uint16 remainder)
        private
        pure
        returns (uint256 fee, uint16 nextRemainder)
    {
        uint256 scaledRemainder = (amount % BPS) * PROTOCOL_FEE_BPS + remainder;
        // forge-lint: disable-next-line(divide-before-multiply)
        fee = (amount / BPS) * PROTOCOL_FEE_BPS + scaledRemainder / BPS;
        // forge-lint: disable-next-line(unsafe-typecast)
        nextRemainder = uint16(scaledRemainder % BPS);
    }

    function _addAutomaticExclusion(address account) private {
        if (_excluded[account]) return;
        _excluded[account] = true;
        _exclusions.push(account);
        emit ExclusionConfigured(account, true);
    }

    function _configureAdditionalExclusions(address[] memory exclusions_) private {
        uint256 existing = _exclusions.length;
        uint256 supplied = exclusions_.length;
        if (existing + supplied > MAX_EXCLUSIONS) {
            revert TooManyExclusions(existing + supplied);
        }
        address previous;
        for (uint256 i; i < supplied; ++i) {
            address account = exclusions_[i];
            if (account == address(0)) revert InvalidExclusion(i, account);
            if (account == creator) revert ReservedExclusion(account);
            if (i != 0 && account <= previous) {
                revert UnsortedExclusions(i, previous, account);
            }
            if (_excluded[account]) revert ReservedExclusion(account);
            previous = account;
            _excluded[account] = true;
            _exclusions.push(account);
            emit ExclusionConfigured(account, false);
        }
    }

    function _requireAccount(bytes32 accountId_)
        private
        view
        returns (AccountState storage account)
    {
        account = _accounts[accountId_];
        if (!account.exists) revert UnknownAccount(accountId_);
    }

    function _requireEpoch(bytes32 accountId_, uint64 epochId)
        private
        view
        returns (EpochState storage epoch)
    {
        epoch = _epochs[accountId_][epochId];
        if (epoch.snapshotBlock == 0) revert UnknownEpoch(accountId_, epochId);
    }

    function _assertBacked(address asset) private view {
        uint256 measured = _measuredBalance(asset);
        uint256 liability = totalLiability(asset);
        if (measured < liability) revert AssetUnderbacked(asset, measured, liability);
    }

    function _measuredBalance(address asset) private view returns (uint256) {
        return
            asset == NATIVE_ASSET ? address(this).balance : IERC20(asset).balanceOf(address(this));
    }

    function _validateAsset(address asset) private view {
        if (asset != NATIVE_ASSET && asset.code.length == 0) revert InvalidAsset(asset);
    }
}
