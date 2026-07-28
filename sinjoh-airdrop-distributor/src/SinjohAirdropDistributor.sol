// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { SafeTransferLib } from "./libraries/SafeTransferLib.sol";

interface IArbSys {
    function arbBlockNumber() external view returns (uint256);
    function arbBlockHash(uint256 arbBlockNum) external view returns (bytes32);
}

contract SinjohAirdropDistributor {
    using SafeTransferLib for address;

    uint16 public constant BPS = 10_000;
    uint16 public constant PROTOCOL_FEE_BPS = 100;
    address public constant ARBSYS = address(0x64);
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    uint16 public constant MAX_BATCH_SIZE = 64;
    uint8 public constant MAX_EXCLUSIONS = 32;
    uint8 public constant MAX_PROOF_LENGTH = 64;
    bytes32 public constant LEAF_DOMAIN = keccak256("SINJOH_AIRDROP_LEAF_V1");
    bytes32 public constant NODE_DOMAIN = keccak256("SINJOH_AIRDROP_NODE_V1");

    error Unauthorized();
    error OnlySelf();
    error Reentrancy();
    error InvalidAddress();
    error InvalidAmount();
    error InvalidValue();
    error InvalidConfiguration();
    error ConfigurationMismatch();
    error NonCanonicalConfiguration();
    error AccountNotFound();
    error InvalidEpoch();
    error InvalidSnapshot();
    error InvalidRoot();
    error InvalidBatch();
    error InvalidProof();
    error ExcludedHolder();
    error Insolvent(address asset);
    error UnexpectedBalanceDelta(address asset, uint256 expected, uint256 actual);
    error InvariantViolation();

    struct Config {
        uint128 minPayout;
        uint16 maxBatchSize;
        uint16 minConfirmations;
        address[] exclusions;
    }

    struct Account {
        address funder;
        address subject;
        address asset;
        bytes32 configHash;
        uint128 minPayout;
        uint16 maxBatchSize;
        uint16 minConfirmations;
        uint64 latestEpochId;
        uint64 latestSnapshotBlock;
        uint256 totalFunded;
        uint256 totalPaid;
        uint256 latestRootSum;
        bool configured;
    }

    struct EpochCommitment {
        bytes32 rootHash;
        uint256 rootSum;
        uint64 snapshotBlock;
        bytes32 snapshotBlockHash;
    }

    struct ProofElement {
        bytes32 siblingHash;
        uint256 siblingSum;
        bool siblingIsLeft;
    }

    struct Leaf {
        address holder;
        uint256 cumulativeAmount;
    }

    event AccountConfigured(
        bytes32 indexed accountId,
        address indexed funder,
        address indexed subject,
        address asset,
        bytes32 configHash,
        uint128 minPayout,
        uint16 maxBatchSize,
        uint16 minConfirmations,
        address[] exclusions
    );
    event Funded(
        bytes32 indexed accountId,
        address indexed funder,
        address indexed asset,
        uint256 amount,
        uint256 totalFunded
    );
    event ProtocolFeeAccrued(
        bytes32 indexed accountId, address indexed asset, uint256 gross, uint256 fee
    );
    event ProtocolFeeSent(
        address indexed asset, address indexed recipient, uint256 amount, address indexed caller
    );
    event EpochCommitted(
        bytes32 indexed accountId,
        uint64 indexed epochId,
        uint64 snapshotBlock,
        bytes32 snapshotBlockHash,
        bytes32 rootHash,
        uint256 rootSum
    );
    event PaymentSucceeded(
        bytes32 indexed accountId,
        uint64 indexed epochId,
        address indexed holder,
        address asset,
        uint256 amount,
        uint256 cumulativePaid
    );
    event PaymentFailed(
        bytes32 indexed accountId,
        uint64 indexed epochId,
        address indexed holder,
        uint256 cumulativeAmount,
        bytes reason
    );

    address public immutable attestor;
    address public immutable protocolFeeRecipient;

    mapping(bytes32 accountId => Account account) public accounts;
    mapping(bytes32 accountId => mapping(uint64 epochId => EpochCommitment commitment)) public
        commitments;
    mapping(bytes32 accountId => mapping(address holder => bool excluded)) public isExcluded;
    mapping(bytes32 accountId => mapping(address holder => uint256 amount)) public paid;
    mapping(address asset => uint16 remainder) public protocolFeeRemainder;
    mapping(address asset => uint256 amount) public protocolOwed;
    mapping(address asset => uint256 amount) public totalLiability;

    uint256 private _reentrancyState = 1;

    constructor(address attestor_, address protocolFeeRecipient_) {
        if (attestor_ == address(0) || protocolFeeRecipient_ == address(0)) {
            revert InvalidAddress();
        }
        attestor = attestor_;
        protocolFeeRecipient = protocolFeeRecipient_;
    }

    modifier onlyAttestor() {
        if (msg.sender != attestor) revert Unauthorized();
        _;
    }

    modifier nonReentrant() {
        if (_reentrancyState == 2) revert Reentrancy();
        _reentrancyState = 2;
        _;
        _reentrancyState = 1;
    }

    receive() external payable { }

    function accountId(address funder, address subject, address asset)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(funder, subject, asset));
    }

    function fund(address subject, address asset, uint256 amount, bytes calldata configData)
        external
        payable
        nonReentrant
        returns (uint256 received)
    {
        if (subject == address(0) || subject == address(this) || subject.code.length == 0) {
            revert InvalidAddress();
        }
        if (amount == 0) revert InvalidAmount();

        bytes32 id = accountId(msg.sender, subject, asset);
        Account storage account = accounts[id];
        bytes32 suppliedConfigHash = keccak256(configData);
        if (!account.configured) {
            Config memory config = abi.decode(configData, (Config));
            if (keccak256(abi.encode(config)) != suppliedConfigHash) {
                revert NonCanonicalConfiguration();
            }
            _configure(id, account, msg.sender, subject, asset, suppliedConfigHash, config);
        } else if (suppliedConfigHash != account.configHash) {
            revert ConfigurationMismatch();
        }

        if (asset == address(0)) {
            if (msg.value != amount) revert InvalidValue();
            received = amount;
        } else {
            if (msg.value != 0) revert InvalidValue();
            uint256 beforeBalance = asset.safeBalanceOf(address(this));
            asset.safeTransferFrom(msg.sender, address(this), amount);
            uint256 afterBalance = asset.safeBalanceOf(address(this));
            received = afterBalance >= beforeBalance ? afterBalance - beforeBalance : 0;
            if (received != amount) {
                revert UnexpectedBalanceDelta(asset, amount, received);
            }
        }

        (uint256 fee, uint16 nextFeeRemainder) =
            _accrueProtocolFee(received, protocolFeeRemainder[asset]);
        protocolFeeRemainder[asset] = nextFeeRemainder;
        uint256 net = received - fee;
        account.totalFunded += net;
        protocolOwed[asset] += fee;
        totalLiability[asset] += received;
        _assertSolvent(asset);
        emit ProtocolFeeAccrued(id, asset, received, fee);
        emit Funded(id, msg.sender, asset, net, account.totalFunded);
    }

    function _accrueProtocolFee(uint256 amount, uint16 remainder)
        private
        pure
        returns (uint256 fee, uint16 nextRemainder)
    {
        uint256 scaledRemainder = (amount % BPS) * PROTOCOL_FEE_BPS + remainder;
        // Quotient/remainder decomposition avoids overflow without losing precision.
        // forge-lint: disable-next-line(divide-before-multiply)
        fee = (amount / BPS) * PROTOCOL_FEE_BPS + scaledRemainder / BPS;
        // The modulo result is strictly below BPS and therefore fits uint16.
        // forge-lint: disable-next-line(unsafe-typecast)
        nextRemainder = uint16(scaledRemainder % BPS);
    }

    function sendProtocolFee(address asset, uint256 amount) external nonReentrant {
        if (amount == 0 || amount > protocolOwed[asset]) revert InvalidAmount();

        protocolOwed[asset] -= amount;
        totalLiability[asset] -= amount;
        _sendExact(asset, protocolFeeRecipient, amount);
        _assertSolvent(asset);

        emit ProtocolFeeSent(asset, protocolFeeRecipient, amount, msg.sender);
    }

    function commitEpoch(
        address funder,
        address subject,
        address asset,
        uint64 epochId,
        uint64 snapshotBlock,
        bytes32 snapshotBlockHash,
        bytes32 rootHash,
        uint256 rootSum
    ) external onlyAttestor nonReentrant {
        bytes32 id = accountId(funder, subject, asset);
        Account storage account = accounts[id];
        if (!account.configured) revert AccountNotFound();
        if (epochId != account.latestEpochId + 1) revert InvalidEpoch();
        if (snapshotBlock <= account.latestSnapshotBlock) revert InvalidSnapshot();
        if (rootHash == bytes32(0) || rootSum == 0) revert InvalidRoot();
        if (rootSum < account.latestRootSum || rootSum > account.totalFunded) {
            revert InvalidRoot();
        }

        uint256 currentL2Block = IArbSys(ARBSYS).arbBlockNumber();
        if (currentL2Block < uint256(snapshotBlock) + account.minConfirmations) {
            revert InvalidSnapshot();
        }
        if (currentL2Block > uint256(snapshotBlock) + 255) revert InvalidSnapshot();
        if (IArbSys(ARBSYS).arbBlockHash(snapshotBlock) != snapshotBlockHash) {
            revert InvalidSnapshot();
        }

        commitments[id][epochId] = EpochCommitment({
            rootHash: rootHash,
            rootSum: rootSum,
            snapshotBlock: snapshotBlock,
            snapshotBlockHash: snapshotBlockHash
        });
        account.latestEpochId = epochId;
        account.latestSnapshotBlock = snapshotBlock;
        account.latestRootSum = rootSum;

        emit EpochCommitted(id, epochId, snapshotBlock, snapshotBlockHash, rootHash, rootSum);
    }

    function push(
        address funder,
        address subject,
        address asset,
        uint64 epochId,
        Leaf[] calldata leaves,
        ProofElement[][] calldata proofs
    ) external nonReentrant {
        bytes32 id = accountId(funder, subject, asset);
        Account storage account = accounts[id];
        if (!account.configured) revert AccountNotFound();
        EpochCommitment storage commitment = commitments[id][epochId];
        if (commitment.rootHash == bytes32(0)) revert InvalidEpoch();

        uint256 length = leaves.length;
        if (length == 0 || length > account.maxBatchSize || length != proofs.length) {
            revert InvalidBatch();
        }

        address previousHolder;
        for (uint256 i; i < length; ++i) {
            Leaf calldata leaf = leaves[i];
            if (leaf.holder <= previousHolder) revert InvalidBatch();
            if (isExcluded[id][leaf.holder]) revert ExcludedHolder();
            if (proofs[i].length > MAX_PROOF_LENGTH) revert InvalidProof();
            if (!_verify(id, epochId, commitment, leaf, proofs[i])) revert InvalidProof();
            previousHolder = leaf.holder;
        }

        for (uint256 i; i < length; ++i) {
            Leaf calldata leaf = leaves[i];
            uint256 alreadyPaid = paid[id][leaf.holder];
            if (leaf.cumulativeAmount <= alreadyPaid) continue;
            if (leaf.cumulativeAmount - alreadyPaid < account.minPayout) continue;

            try this.pay(id, epochId, leaf.holder, leaf.cumulativeAmount) { }
            catch (bytes memory reason) {
                emit PaymentFailed(id, epochId, leaf.holder, leaf.cumulativeAmount, reason);
            }
        }
    }

    function pay(bytes32 id, uint64 epochId, address holder, uint256 cumulativeAmount) external {
        if (msg.sender != address(this)) revert OnlySelf();
        Account storage account = accounts[id];
        if (!account.configured) revert AccountNotFound();
        if (isExcluded[id][holder]) revert ExcludedHolder();

        uint256 alreadyPaid = paid[id][holder];
        if (cumulativeAmount <= alreadyPaid) return;
        uint256 amount = cumulativeAmount - alreadyPaid;
        if (amount < account.minPayout) return;

        paid[id][holder] = cumulativeAmount;
        account.totalPaid += amount;
        totalLiability[account.asset] -= amount;
        if (
            account.totalPaid > account.latestRootSum || account.latestRootSum > account.totalFunded
        ) revert InvariantViolation();

        address asset = account.asset;
        _sendExact(asset, holder, amount);
        _assertSolvent(asset);

        emit PaymentSucceeded(id, epochId, holder, asset, amount, cumulativeAmount);
    }

    function leafHash(
        bytes32 id,
        uint64 epochId,
        uint64 snapshotBlock,
        address holder,
        uint256 cumulativeAmount
    ) public view returns (bytes32) {
        return keccak256(
            abi.encode(
                LEAF_DOMAIN,
                block.chainid,
                address(this),
                id,
                epochId,
                snapshotBlock,
                holder,
                cumulativeAmount
            )
        );
    }

    function nodeHash(bytes32 leftHash, uint256 leftSum, bytes32 rightHash, uint256 rightSum)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(NODE_DOMAIN, leftHash, leftSum, rightHash, rightSum));
    }

    function accountFinancials(bytes32 id)
        external
        view
        returns (
            uint256 totalFunded,
            uint256 totalPaid,
            uint256 latestRootSum,
            uint64 latestEpochId,
            uint64 latestSnapshotBlock
        )
    {
        Account storage account = accounts[id];
        return (
            account.totalFunded,
            account.totalPaid,
            account.latestRootSum,
            account.latestEpochId,
            account.latestSnapshotBlock
        );
    }

    function _configure(
        bytes32 id,
        Account storage account,
        address funder,
        address subject,
        address asset,
        bytes32 configHash,
        Config memory config
    ) private {
        if (
            config.minPayout == 0 || config.maxBatchSize == 0
                || config.maxBatchSize > MAX_BATCH_SIZE || config.minConfirmations == 0
                || config.minConfirmations > 255 || config.exclusions.length > MAX_EXCLUSIONS
        ) revert InvalidConfiguration();

        address previous;
        for (uint256 i; i < config.exclusions.length; ++i) {
            address excluded = config.exclusions[i];
            if (excluded == address(0) || excluded <= previous) {
                revert InvalidConfiguration();
            }
            isExcluded[id][excluded] = true;
            previous = excluded;
        }
        isExcluded[id][address(0)] = true;
        isExcluded[id][BURN_ADDRESS] = true;
        isExcluded[id][address(this)] = true;
        isExcluded[id][funder] = true;

        account.funder = funder;
        account.subject = subject;
        account.asset = asset;
        account.configHash = configHash;
        account.minPayout = config.minPayout;
        account.maxBatchSize = config.maxBatchSize;
        account.minConfirmations = config.minConfirmations;
        account.configured = true;

        emit AccountConfigured(
            id,
            funder,
            subject,
            asset,
            configHash,
            config.minPayout,
            config.maxBatchSize,
            config.minConfirmations,
            config.exclusions
        );
    }

    function _verify(
        bytes32 id,
        uint64 epochId,
        EpochCommitment storage commitment,
        Leaf calldata leaf,
        ProofElement[] calldata proof
    ) private view returns (bool) {
        bytes32 hash = leafHash(
            id, epochId, commitment.snapshotBlock, leaf.holder, leaf.cumulativeAmount
        );
        uint256 sum = leaf.cumulativeAmount;
        for (uint256 i; i < proof.length; ++i) {
            ProofElement calldata element = proof[i];
            if (element.siblingIsLeft) {
                hash = nodeHash(element.siblingHash, element.siblingSum, hash, sum);
            } else {
                hash = nodeHash(hash, sum, element.siblingHash, element.siblingSum);
            }
            sum += element.siblingSum;
        }
        return hash == commitment.rootHash && sum == commitment.rootSum;
    }

    function _balance(address asset) private view returns (uint256) {
        return asset == address(0) ? address(this).balance : asset.safeBalanceOf(address(this));
    }

    function _sendExact(address asset, address recipient, uint256 amount) private {
        uint256 beforeBalance = _balance(asset);
        if (asset == address(0)) {
            SafeTransferLib.safeTransferETH(recipient, amount);
        } else {
            uint256 recipientBefore = asset.safeBalanceOf(recipient);
            asset.safeTransfer(recipient, amount);
            uint256 recipientAfter = asset.safeBalanceOf(recipient);
            uint256 received =
                recipientAfter >= recipientBefore ? recipientAfter - recipientBefore : 0;
            if (received != amount) {
                revert UnexpectedBalanceDelta(asset, amount, received);
            }
        }
        uint256 afterBalance = _balance(asset);
        uint256 spent = beforeBalance >= afterBalance ? beforeBalance - afterBalance : 0;
        if (spent != amount) revert UnexpectedBalanceDelta(asset, amount, spent);
    }

    function _assertSolvent(address asset) private view {
        uint256 balance = _balance(asset);
        if (balance < totalLiability[asset]) revert Insolvent(asset);
    }
}
