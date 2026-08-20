// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Checkpoints } from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";

/// @notice Opt-in, multi-token staking and snapshot rewards for Sinjoh launches.
/// @dev The fee router calls `fund` with the launched token as `subject`. One staked subject token
/// is one reward unit. Unstaking is immediate and does not change a completed snapshot.
contract SinjohLaunchStakingEngine is ReentrancyGuard {
    using Checkpoints for Checkpoints.Trace256;
    using SafeERC20 for IERC20;

    uint16 public constant BPS = 10_000;
    uint16 public constant PROTOCOL_FEE_BPS = 100;
    uint32 public constant MIN_INTERVAL = 1 hours;
    uint32 public constant MAX_INTERVAL = 30 days;
    uint32 public constant MIN_CLAIM_PERIOD = 1 days;
    uint32 public constant MAX_CLAIM_PERIOD = 365 days;
    uint16 public constant MAX_BATCH_CLAIMS = 64;

    struct Config {
        uint32 interval;
        uint32 claimPeriod;
        address unclaimedDestination;
    }

    struct Account {
        address funder;
        address subject;
        address asset;
        bytes32 configHash;
        uint32 interval;
        uint32 claimPeriod;
        uint48 nextEpoch;
        uint64 latestEpochId;
        address unclaimedDestination;
        uint256 pendingRewards;
        uint256 totalFunded;
        uint256 totalClaimed;
        bool configured;
    }

    struct Epoch {
        uint48 snapshotTime;
        uint48 executedAt;
        uint48 claimDeadline;
        address unclaimedDestination;
        uint256 fundedAmount;
        uint256 eligibleStake;
        uint256 claimedAmount;
    }

    error InvalidAddress();
    error InvalidAmount();
    error InvalidConfiguration();
    error ConfigurationMismatch();
    error NonCanonicalConfiguration();
    error AccountNotFound();
    error EpochNotDue(uint256 dueAt);
    error EpochNotFunded();
    error InvalidEpoch();
    error AlreadyClaimed();
    error Ineligible();
    error ClaimExpired();
    error ClaimStillOpen();
    error InsufficientStake(uint256 available, uint256 requested);
    error FutureLookup();
    error InexactTransfer(uint256 expected, uint256 received);
    error NativeTransferFailed();
    error Insolvent(address asset);

    event Staked(
        address indexed subject, address indexed account, uint256 amount, uint256 newBalance
    );
    event Unstaked(
        address indexed subject, address indexed account, uint256 amount, uint256 newBalance
    );
    event AccountConfigured(
        bytes32 indexed accountId,
        address indexed funder,
        address indexed subject,
        address asset,
        uint32 interval,
        uint32 claimPeriod,
        address unclaimedDestination
    );
    event Funded(
        bytes32 indexed accountId,
        address indexed funder,
        address indexed asset,
        uint256 gross,
        uint256 fee
    );
    event EpochExecuted(
        bytes32 indexed accountId,
        uint64 indexed epochId,
        uint48 snapshotTime,
        uint256 fundedAmount,
        uint256 eligibleStake
    );
    event EmptyEpochSkipped(
        bytes32 indexed accountId, uint48 snapshotTime, uint256 pendingRewards, uint48 nextEpoch
    );
    event Claimed(
        bytes32 indexed accountId, uint64 indexed epochId, address indexed account, uint256 amount
    );
    event UnclaimedSwept(bytes32 indexed accountId, uint64 indexed epochId, uint256 amount);

    address public immutable protocolFeeRecipient;

    mapping(address subject => mapping(address account => uint256 amount)) public balanceOf;
    mapping(address subject => uint256 amount) public totalStaked;
    mapping(address subject => mapping(address account => Checkpoints.Trace256)) private
        _balanceCheckpoints;
    mapping(address subject => Checkpoints.Trace256) private _totalStakedCheckpoints;

    mapping(bytes32 accountId => Account account) public accounts;
    mapping(bytes32 accountId => mapping(uint64 epochId => Epoch epoch)) public epochs;
    mapping(bytes32 accountId => mapping(uint64 epochId => mapping(address account => bool))) public
        claimed;
    mapping(address asset => uint16 remainder) public protocolFeeRemainder;
    mapping(address asset => uint256 amount) public rewardLiability;
    mapping(address asset => uint256 amount) public stakingLiability;

    constructor(address protocolFeeRecipient_) {
        if (protocolFeeRecipient_ == address(0) || protocolFeeRecipient_ == address(this)) {
            revert InvalidAddress();
        }
        protocolFeeRecipient = protocolFeeRecipient_;
    }

    receive() external payable { }

    function accountId(address funder, address subject, address asset)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(funder, subject, asset));
    }

    function stake(address subject, uint256 amount) external nonReentrant {
        if (subject.code.length == 0 || subject == address(this)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();
        IERC20 token = IERC20(subject);
        uint256 beforeBalance = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = token.balanceOf(address(this)) - beforeBalance;
        if (received != amount) revert InexactTransfer(amount, received);

        uint256 newBalance = balanceOf[subject][msg.sender] + amount;
        uint256 newTotal = totalStaked[subject] + amount;
        balanceOf[subject][msg.sender] = newBalance;
        totalStaked[subject] = newTotal;
        stakingLiability[subject] += amount;
        _writeCheckpoints(subject, msg.sender, newBalance, newTotal);
        _assertSolvent(subject);
        emit Staked(subject, msg.sender, amount, newBalance);
    }

    function unstake(address subject, uint256 amount) external nonReentrant {
        if (amount == 0) revert InvalidAmount();
        uint256 oldBalance = balanceOf[subject][msg.sender];
        if (amount > oldBalance) revert InsufficientStake(oldBalance, amount);

        uint256 newBalance = oldBalance - amount;
        uint256 newTotal = totalStaked[subject] - amount;
        balanceOf[subject][msg.sender] = newBalance;
        totalStaked[subject] = newTotal;
        stakingLiability[subject] -= amount;
        _writeCheckpoints(subject, msg.sender, newBalance, newTotal);
        _sendExact(subject, msg.sender, amount);
        _assertSolvent(subject);
        emit Unstaked(subject, msg.sender, amount, newBalance);
    }

    /// @notice Funds one router/subject/asset reward account.
    /// @dev `configData` is canonical `abi.encode(Config)` and is immutable for the account.
    function fund(address subject, address asset, uint256 amount, bytes calldata configData)
        external
        payable
        nonReentrant
        returns (uint256 received)
    {
        if (subject.code.length == 0 || subject == address(this)) revert InvalidAddress();
        if (asset != address(0) && (asset.code.length == 0 || asset == address(this))) {
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
            _validateConfig(config);
            account.funder = msg.sender;
            account.subject = subject;
            account.asset = asset;
            account.configHash = suppliedConfigHash;
            account.interval = config.interval;
            account.claimPeriod = config.claimPeriod;
            account.nextEpoch = uint48(block.timestamp) + config.interval;
            account.unclaimedDestination = config.unclaimedDestination;
            account.configured = true;
            emit AccountConfigured(
                id,
                msg.sender,
                subject,
                asset,
                config.interval,
                config.claimPeriod,
                config.unclaimedDestination
            );
        } else if (account.configHash != suppliedConfigHash) {
            revert ConfigurationMismatch();
        }

        if (asset == address(0)) {
            if (msg.value != amount) revert InexactTransfer(amount, msg.value);
            received = amount;
        } else {
            if (msg.value != 0) revert InvalidAmount();
            IERC20 token = IERC20(asset);
            uint256 beforeBalance = token.balanceOf(address(this));
            token.safeTransferFrom(msg.sender, address(this), amount);
            received = token.balanceOf(address(this)) - beforeBalance;
            if (received != amount) revert InexactTransfer(amount, received);
        }

        (uint256 fee, uint16 nextRemainder) = _protocolFee(amount, protocolFeeRemainder[asset]);
        protocolFeeRemainder[asset] = nextRemainder;
        uint256 net = amount - fee;
        account.pendingRewards += net;
        account.totalFunded += net;
        rewardLiability[asset] += net;
        _sendExact(asset, protocolFeeRecipient, fee);
        _assertSolvent(asset);
        emit Funded(id, msg.sender, asset, amount, fee);
    }

    function executeEpoch(address funder, address subject, address asset) external nonReentrant {
        bytes32 id = accountId(funder, subject, asset);
        Account storage account = accounts[id];
        if (!account.configured) revert AccountNotFound();
        if (block.timestamp < account.nextEpoch) revert EpochNotDue(account.nextEpoch);
        uint256 funded = account.pendingRewards;
        if (funded == 0) revert EpochNotFunded();

        uint48 snapshotTime = uint48(block.timestamp - 1);
        uint256 eligibleStake = _pastTotalStaked(subject, snapshotTime);
        if (eligibleStake == 0) {
            account.nextEpoch = uint48(block.timestamp) + account.interval;
            emit EmptyEpochSkipped(id, snapshotTime, funded, account.nextEpoch);
            return;
        }

        uint64 epochId = ++account.latestEpochId;
        epochs[id][epochId] = Epoch({
            snapshotTime: snapshotTime,
            executedAt: uint48(block.timestamp),
            claimDeadline: uint48(block.timestamp) + account.claimPeriod,
            unclaimedDestination: account.unclaimedDestination,
            fundedAmount: funded,
            eligibleStake: eligibleStake,
            claimedAmount: 0
        });
        account.pendingRewards = 0;
        account.nextEpoch = uint48(block.timestamp) + account.interval;
        emit EpochExecuted(id, epochId, snapshotTime, funded, eligibleStake);
    }

    function claim(bytes32 id, uint64[] calldata epochIds)
        external
        nonReentrant
        returns (uint256 total)
    {
        if (epochIds.length == 0 || epochIds.length > MAX_BATCH_CLAIMS) {
            revert InvalidConfiguration();
        }
        Account storage account = accounts[id];
        if (!account.configured) revert AccountNotFound();
        uint64 previous;
        for (uint256 i; i < epochIds.length; ++i) {
            uint64 epochId = epochIds[i];
            if (epochId <= previous) revert InvalidEpoch();
            previous = epochId;
            Epoch storage epoch = epochs[id][epochId];
            if (epoch.executedAt == 0) revert InvalidEpoch();
            if (block.timestamp > epoch.claimDeadline) revert ClaimExpired();
            if (claimed[id][epochId][msg.sender]) revert AlreadyClaimed();
            uint256 stakedBalance = _pastBalance(account.subject, msg.sender, epoch.snapshotTime);
            if (stakedBalance == 0) revert Ineligible();
            uint256 amount = Math.mulDiv(stakedBalance, epoch.fundedAmount, epoch.eligibleStake);
            if (amount == 0) revert InvalidAmount();
            claimed[id][epochId][msg.sender] = true;
            epoch.claimedAmount += amount;
            total += amount;
            emit Claimed(id, epochId, msg.sender, amount);
        }
        account.totalClaimed += total;
        rewardLiability[account.asset] -= total;
        _sendExact(account.asset, msg.sender, total);
        _assertSolvent(account.asset);
    }

    function sweepUnclaimed(bytes32 id, uint64 epochId) external nonReentrant {
        Account storage account = accounts[id];
        if (!account.configured) revert AccountNotFound();
        Epoch storage epoch = epochs[id][epochId];
        if (epoch.executedAt == 0) revert InvalidEpoch();
        if (block.timestamp <= epoch.claimDeadline) revert ClaimStillOpen();
        uint256 amount = epoch.fundedAmount - epoch.claimedAmount;
        if (amount == 0) revert InvalidAmount();
        epoch.claimedAmount = epoch.fundedAmount;
        rewardLiability[account.asset] -= amount;
        _sendExact(account.asset, epoch.unclaimedDestination, amount);
        _assertSolvent(account.asset);
        emit UnclaimedSwept(id, epochId, amount);
    }

    function claimable(bytes32 id, uint64 epochId, address accountAddress)
        external
        view
        returns (uint256)
    {
        Account storage account = accounts[id];
        Epoch storage epoch = epochs[id][epochId];
        if (
            !account.configured || epoch.executedAt == 0 || block.timestamp > epoch.claimDeadline
                || claimed[id][epochId][accountAddress]
        ) return 0;
        uint256 stakedBalance = _pastBalance(account.subject, accountAddress, epoch.snapshotTime);
        if (stakedBalance == 0) return 0;
        return Math.mulDiv(stakedBalance, epoch.fundedAmount, epoch.eligibleStake);
    }

    function getPastBalance(address subject, address account, uint256 timepoint)
        external
        view
        returns (uint256)
    {
        return _pastBalance(subject, account, timepoint);
    }

    function getPastTotalStaked(address subject, uint256 timepoint)
        external
        view
        returns (uint256)
    {
        return _pastTotalStaked(subject, timepoint);
    }

    function _writeCheckpoints(
        address subject,
        address account,
        uint256 accountBalance,
        uint256 total
    ) private {
        uint256 timepoint = block.timestamp;
        _balanceCheckpoints[subject][account].push(timepoint, accountBalance);
        _totalStakedCheckpoints[subject].push(timepoint, total);
    }

    function _pastBalance(address subject, address account, uint256 timepoint)
        private
        view
        returns (uint256)
    {
        if (timepoint >= block.timestamp) revert FutureLookup();
        return _balanceCheckpoints[subject][account].upperLookupRecent(timepoint);
    }

    function _pastTotalStaked(address subject, uint256 timepoint) private view returns (uint256) {
        if (timepoint >= block.timestamp) revert FutureLookup();
        return _totalStakedCheckpoints[subject].upperLookupRecent(timepoint);
    }

    function _validateConfig(Config memory config) private view {
        if (
            config.interval < MIN_INTERVAL || config.interval > MAX_INTERVAL
                || config.claimPeriod < MIN_CLAIM_PERIOD || config.claimPeriod > MAX_CLAIM_PERIOD
                || config.unclaimedDestination == address(0)
                || config.unclaimedDestination == address(this)
        ) revert InvalidConfiguration();
    }

    function _protocolFee(uint256 amount, uint16 remainder)
        private
        pure
        returns (uint256 fee, uint16 nextRemainder)
    {
        uint256 scaledRemainder = (amount % BPS) * PROTOCOL_FEE_BPS + remainder;
        fee = (amount / BPS) * PROTOCOL_FEE_BPS + scaledRemainder / BPS;
        nextRemainder = uint16(scaledRemainder % BPS);
    }

    function _sendExact(address asset, address recipient, uint256 amount) private {
        if (amount == 0) return;
        if (asset == address(0)) {
            (bool ok,) = recipient.call{ value: amount }("");
            if (!ok) revert NativeTransferFailed();
            return;
        }
        IERC20 token = IERC20(asset);
        uint256 beforeBalance = token.balanceOf(recipient);
        token.safeTransfer(recipient, amount);
        uint256 received = token.balanceOf(recipient) - beforeBalance;
        if (received != amount) revert InexactTransfer(amount, received);
    }

    function _assertSolvent(address asset) private view {
        uint256 balance =
            asset == address(0) ? address(this).balance : IERC20(asset).balanceOf(address(this));
        uint256 liabilities = rewardLiability[asset] + stakingLiability[asset];
        if (balance < liabilities) revert Insolvent(asset);
    }
}
