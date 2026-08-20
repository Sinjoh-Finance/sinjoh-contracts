// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Governed } from "./governance/Governed.sol";
import { IGovernanceController } from "./interfaces/IGovernanceController.sol";
import { IStakingSnapshot } from "./interfaces/IStakingSnapshot.sol";
import { ISinjohFundable } from "./interfaces/ISinjohFundable.sol";

/// @notice Permissionless epoch closing and batched start-of-epoch checkpoint claims for stakers.
contract SinjohStakingEngine is Governed, ReentrancyGuard, ISinjohFundable {
    using SafeERC20 for IERC20;

    uint16 public constant BPS = 10_000;
    uint16 public constant PROTOCOL_FEE_BPS = 100;
    uint32 public constant MIN_INTERVAL = 30 minutes;
    uint16 public constant MAX_EXECUTOR_REWARD_BPS = 100;
    uint16 public constant MAX_BATCH_CLAIMS = 64;

    struct ScheduleInput {
        address rewardToken;
        uint32 interval;
        uint32 claimPeriod;
        bool permissionlessExecution;
        uint128 fixedExecutorReward;
        uint16 executorRewardBps;
        uint128 executorRewardCap;
        address unclaimedDestination;
    }

    struct DistributionSchedule {
        address rewardToken;
        uint32 interval;
        uint32 claimPeriod;
        uint48 nextEpoch;
        uint48 epochStartTime;
        uint64 epochStartBlock;
        uint64 latestEpochId;
        bool permissionlessExecution;
        uint128 fixedExecutorReward;
        uint16 executorRewardBps;
        uint128 executorRewardCap;
        address unclaimedDestination;
        uint256 pendingRewards;
    }

    struct Epoch {
        uint64 snapshotBlock;
        uint48 startTime;
        uint48 endTime;
        uint48 claimDeadline;
        address unclaimedDestination;
        uint256 fundedAmount;
        uint256 eligibleWeight;
        uint256 claimedAmount;
    }

    error InvalidAddress();
    error InvalidConfiguration();
    error InvalidSchedule();
    error EpochNotDue(uint256 dueAt);
    error EpochNotFunded();
    error InvalidEpoch();
    error AlreadyClaimed();
    error Ineligible();
    error ClaimExpired();
    error ClaimStillOpen();
    error InvalidAmount();
    error InexactTransfer(uint256 expected, uint256 received);

    event ScheduleCreated(
        uint256 indexed scheduleId, address indexed rewardToken, uint48 nextEpoch
    );
    event ScheduleUpdated(uint256 indexed scheduleId);
    event Funded(uint256 indexed scheduleId, address indexed funder, uint256 gross, uint256 fee);
    event EpochExecuted(
        uint256 indexed scheduleId,
        uint64 indexed epochId,
        uint64 snapshotBlock,
        uint256 fundedAmount,
        uint256 eligibleWeight,
        uint256 executorReward
    );
    event EmptyEpochSkipped(
        uint256 indexed scheduleId, uint64 snapshotBlock, uint256 pendingRewards, uint48 nextEpoch
    );
    event Claimed(
        uint256 indexed scheduleId, uint64 indexed epochId, address indexed account, uint256 amount
    );
    event UnclaimedSwept(uint256 indexed scheduleId, uint64 indexed epochId, uint256 amount);

    IStakingSnapshot public immutable staking;
    address public immutable protocolFeeRecipient;
    uint256 public scheduleCount;
    mapping(uint256 scheduleId => DistributionSchedule) public schedules;
    mapping(uint256 scheduleId => mapping(uint64 epochId => Epoch)) public epochs;
    mapping(uint256 scheduleId => mapping(uint64 epochId => mapping(address => bool))) public
        claimed;
    mapping(address token => uint16 remainder) public protocolFeeRemainder;
    mapping(address token => uint256 amount) public cumulativeGrossFunding;
    mapping(address token => uint256 amount) public cumulativeProtocolFee;
    mapping(address token => uint256 amount) public totalLiability;

    constructor(
        IGovernanceController controller,
        address guardian,
        IStakingSnapshot staking_,
        address protocolFeeRecipient_
    ) Governed(controller, guardian) {
        if (
            address(staking_).code.length == 0 || protocolFeeRecipient_ == address(0)
                || protocolFeeRecipient_ == address(this)
        ) revert InvalidAddress();
        staking = staking_;
        protocolFeeRecipient = protocolFeeRecipient_;
    }

    function createSchedule(ScheduleInput calldata input)
        external
        onlyGovernance
        returns (uint256 scheduleId)
    {
        _validate(input);
        scheduleId = ++scheduleCount;
        uint48 nextEpoch = uint48(block.timestamp) + input.interval;
        schedules[scheduleId] = DistributionSchedule({
            rewardToken: input.rewardToken,
            interval: input.interval,
            claimPeriod: input.claimPeriod,
            nextEpoch: nextEpoch,
            epochStartTime: uint48(block.timestamp),
            epochStartBlock: _snapshotBlock(),
            latestEpochId: 0,
            permissionlessExecution: input.permissionlessExecution,
            fixedExecutorReward: input.fixedExecutorReward,
            executorRewardBps: input.executorRewardBps,
            executorRewardCap: input.executorRewardCap,
            unclaimedDestination: input.unclaimedDestination,
            pendingRewards: 0
        });
        emit ScheduleCreated(scheduleId, input.rewardToken, nextEpoch);
    }

    function updateSchedule(uint256 scheduleId, ScheduleInput calldata input)
        external
        onlyGovernance
    {
        DistributionSchedule storage schedule = schedules[scheduleId];
        if (schedule.rewardToken == address(0) || input.rewardToken != schedule.rewardToken) {
            revert InvalidSchedule();
        }
        _validate(input);
        schedule.interval = input.interval;
        schedule.claimPeriod = input.claimPeriod;
        schedule.permissionlessExecution = input.permissionlessExecution;
        schedule.fixedExecutorReward = input.fixedExecutorReward;
        schedule.executorRewardBps = input.executorRewardBps;
        schedule.executorRewardCap = input.executorRewardCap;
        schedule.unclaimedDestination = input.unclaimedDestination;
        emit ScheduleUpdated(scheduleId);
    }

    /// @inheritdoc ISinjohFundable
    /// @dev `config` is canonical `abi.encode(scheduleId)`.
    function fund(address asset, uint256 amount, bytes calldata config)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 received)
    {
        if (config.length != 32 || amount == 0) revert InvalidConfiguration();
        uint256 scheduleId = abi.decode(config, (uint256));
        DistributionSchedule storage schedule = schedules[scheduleId];
        if (schedule.rewardToken != asset) revert InvalidSchedule();

        IERC20 token = IERC20(asset);
        uint256 beforeBalance = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), amount);
        received = token.balanceOf(address(this)) - beforeBalance;
        if (received != amount) revert InexactTransfer(amount, received);

        (uint256 fee, uint16 nextRemainder) = _protocolFee(amount, protocolFeeRemainder[asset]);
        protocolFeeRemainder[asset] = nextRemainder;
        cumulativeGrossFunding[asset] += amount;
        cumulativeProtocolFee[asset] += fee;
        schedule.pendingRewards += amount - fee;
        totalLiability[asset] += amount - fee;
        _sendExact(token, protocolFeeRecipient, fee);
        emit Funded(scheduleId, msg.sender, amount, fee);
    }

    function executeEpoch(uint256 scheduleId) external nonReentrant whenNotPaused {
        DistributionSchedule storage schedule = schedules[scheduleId];
        if (schedule.rewardToken == address(0)) revert InvalidSchedule();
        if (
            !schedule.permissionlessExecution
                && !governanceController.canCall(msg.sender, address(this), msg.sig)
        ) revert Unauthorized();
        uint48 scheduledEnd = schedule.nextEpoch;
        if (block.timestamp < scheduledEnd) revert EpochNotDue(scheduledEnd);
        uint256 funded = schedule.pendingRewards;
        if (funded == 0) revert EpochNotFunded();
        uint64 snapshotBlock = schedule.epochStartBlock;
        uint256 totalWeight = staking.getPastTotalRewardWeight(snapshotBlock);
        if (totalWeight == 0) {
            schedule.epochStartTime = uint48(block.timestamp);
            schedule.epochStartBlock = _snapshotBlock();
            schedule.nextEpoch = uint48(block.timestamp) + schedule.interval;
            emit EmptyEpochSkipped(scheduleId, snapshotBlock, funded, schedule.nextEpoch);
            return;
        }

        uint256 executorReward = schedule.fixedExecutorReward;
        uint256 variableReward = funded * schedule.executorRewardBps / BPS;
        if (variableReward > schedule.executorRewardCap) {
            variableReward = schedule.executorRewardCap;
        }
        executorReward += variableReward;
        if (executorReward >= funded) revert InvalidConfiguration();
        uint256 distributable = funded - executorReward;

        uint64 epochId = ++schedule.latestEpochId;
        uint48 startTime = schedule.epochStartTime;
        epochs[scheduleId][epochId] = Epoch({
            snapshotBlock: snapshotBlock,
            startTime: startTime,
            endTime: scheduledEnd,
            claimDeadline: uint48(block.timestamp) + schedule.claimPeriod,
            unclaimedDestination: schedule.unclaimedDestination,
            fundedAmount: distributable,
            eligibleWeight: totalWeight,
            claimedAmount: 0
        });
        schedule.pendingRewards = 0;
        schedule.epochStartTime = uint48(block.timestamp);
        schedule.epochStartBlock = _snapshotBlock();
        schedule.nextEpoch = uint48(block.timestamp) + schedule.interval;
        if (executorReward != 0) {
            totalLiability[schedule.rewardToken] -= executorReward;
            _sendExact(IERC20(schedule.rewardToken), msg.sender, executorReward);
        }
        emit EpochExecuted(
            scheduleId, epochId, snapshotBlock, distributable, totalWeight, executorReward
        );
    }

    function claim(uint256 scheduleId, uint64[] calldata epochIds)
        external
        nonReentrant
        returns (uint256 total)
    {
        if (epochIds.length == 0 || epochIds.length > MAX_BATCH_CLAIMS) {
            revert InvalidConfiguration();
        }
        DistributionSchedule storage schedule = schedules[scheduleId];
        uint64 previous;
        for (uint256 i; i < epochIds.length; ++i) {
            uint64 epochId = epochIds[i];
            if (epochId <= previous) revert InvalidEpoch();
            previous = epochId;
            Epoch storage epoch = epochs[scheduleId][epochId];
            if (epoch.snapshotBlock == 0) revert InvalidEpoch();
            if (block.timestamp > epoch.claimDeadline) revert ClaimExpired();
            if (claimed[scheduleId][epochId][msg.sender]) revert AlreadyClaimed();
            uint256 weight = staking.getPastRewardWeight(msg.sender, epoch.snapshotBlock);
            if (weight == 0) revert Ineligible();
            uint256 amount = Math.mulDiv(weight, epoch.fundedAmount, epoch.eligibleWeight);
            if (amount == 0) revert InvalidAmount();
            claimed[scheduleId][epochId][msg.sender] = true;
            epoch.claimedAmount += amount;
            total += amount;
            emit Claimed(scheduleId, epochId, msg.sender, amount);
        }
        totalLiability[schedule.rewardToken] -= total;
        _sendExact(IERC20(schedule.rewardToken), msg.sender, total);
    }

    function sweepUnclaimed(uint256 scheduleId, uint64 epochId) external nonReentrant {
        DistributionSchedule storage schedule = schedules[scheduleId];
        Epoch storage epoch = epochs[scheduleId][epochId];
        if (epoch.snapshotBlock == 0) revert InvalidEpoch();
        if (block.timestamp <= epoch.claimDeadline) revert ClaimStillOpen();
        uint256 amount = epoch.fundedAmount - epoch.claimedAmount;
        if (amount == 0) revert InvalidAmount();
        epoch.claimedAmount = epoch.fundedAmount;
        totalLiability[schedule.rewardToken] -= amount;
        _sendExact(IERC20(schedule.rewardToken), epoch.unclaimedDestination, amount);
        emit UnclaimedSwept(scheduleId, epochId, amount);
    }

    function claimable(uint256 scheduleId, uint64 epochId, address account)
        external
        view
        returns (uint256)
    {
        Epoch storage epoch = epochs[scheduleId][epochId];
        if (
            epoch.snapshotBlock == 0 || block.timestamp > epoch.claimDeadline
                || claimed[scheduleId][epochId][account]
        ) return 0;
        uint256 weight = staking.getPastRewardWeight(account, epoch.snapshotBlock);
        if (weight == 0) return 0;
        return Math.mulDiv(weight, epoch.fundedAmount, epoch.eligibleWeight);
    }

    function getSchedule(uint256 scheduleId) external view returns (DistributionSchedule memory) {
        return schedules[scheduleId];
    }

    function getEpoch(uint256 scheduleId, uint64 epochId) external view returns (Epoch memory) {
        return epochs[scheduleId][epochId];
    }

    function _validate(ScheduleInput calldata input) private view {
        if (
            input.rewardToken.code.length == 0 || input.interval < MIN_INTERVAL
                || input.claimPeriod < input.interval || input.unclaimedDestination == address(0)
                || input.unclaimedDestination == address(this)
                || input.executorRewardBps > MAX_EXECUTOR_REWARD_BPS
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

    function _snapshotBlock() private view returns (uint64) {
        return block.number == 0 ? 0 : uint64(block.number - 1);
    }

    function _sendExact(IERC20 token, address recipient, uint256 amount) private {
        if (amount == 0) return;
        uint256 beforeBalance = token.balanceOf(recipient);
        token.safeTransfer(recipient, amount);
        uint256 afterBalance = token.balanceOf(recipient);
        uint256 received = afterBalance >= beforeBalance ? afterBalance - beforeBalance : 0;
        if (received != amount) revert InexactTransfer(amount, received);
    }
}
