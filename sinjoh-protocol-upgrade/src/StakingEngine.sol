// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Checkpoints } from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import { Governed } from "./governance/Governed.sol";
import { IGovernanceController } from "./interfaces/IGovernanceController.sol";
import { IStakingSnapshot } from "./interfaces/IStakingSnapshot.sol";
import { ProtocolAccounting } from "./libraries/ProtocolAccounting.sol";

/// @notice Single-position fixed-tier staking with separate voting and reward checkpoints.
/// @dev Checkpoints use timestamp timepoints. Weight is active only while `timepoint < unlockTime`.
contract StakingEngine is Governed, ReentrancyGuard, IStakingSnapshot {
    using SafeERC20 for IERC20;
    using Checkpoints for Checkpoints.Trace256;

    uint16 public constant BPS = 10_000;
    uint8 public constant MAX_TIERS = 8;
    uint16 public constant MAX_WEIGHT_BPS = 20_000;
    // Exclusive upper bound for a sparse Fenwick tree keyed by every uint48 timestamp.
    uint256 private constant EXPIRY_TREE_SIZE = 1 << 48;

    struct LockTier {
        uint32 duration;
        uint16 rewardWeightBps;
        uint16 governanceWeightBps;
        bool enabled;
    }

    struct Position {
        uint128 amount;
        uint48 lockStart;
        uint48 unlockTime;
        uint16 rewardWeightBps;
        uint16 governanceWeightBps;
        uint8 tierId;
    }

    error InvalidAddress();
    error InvalidTier();
    error InvalidAmount();
    error PositionExists();
    error PositionNotFound();
    error PositionLocked(uint256 unlockTime);
    error PositionExpired(uint256 unlockTime);
    error FutureLookup();
    error InvalidExpiryAccounting();
    error InexactTransfer(uint256 expected, uint256 received);

    event TierSet(
        uint8 indexed tierId,
        uint32 duration,
        uint16 rewardWeightBps,
        uint16 governanceWeightBps,
        bool enabled
    );
    event Staked(address indexed account, uint256 amount, uint8 indexed tierId, uint48 unlockTime);
    event StakeIncreased(address indexed account, uint256 amount, uint256 newAmount);
    event LockExtended(address indexed account, uint8 indexed tierId, uint48 unlockTime);
    event Withdrawn(address indexed account, uint256 amount);

    IERC20 public immutable stakingToken;
    uint8 public immutable tierCount;
    uint256 public totalStaked;
    mapping(uint8 tierId => LockTier) public lockTiers;
    mapping(address account => Position) public positions;

    mapping(address account => Checkpoints.Trace256) private _votes;
    mapping(address account => Checkpoints.Trace256) private _rewardWeights;
    mapping(address account => Checkpoints.Trace256) private _unlockTimes;
    Checkpoints.Trace256 private _totalVotes;
    Checkpoints.Trace256 private _totalRewardWeights;
    mapping(uint256 node => int256 delta) private _voteExpiries;
    mapping(uint256 node => int256 delta) private _rewardExpiries;

    constructor(
        IGovernanceController controller,
        address guardian,
        IERC20 stakingToken_,
        LockTier[] memory tiers
    ) Governed(controller, guardian) {
        if (address(stakingToken_).code.length == 0) revert InvalidAddress();
        if (tiers.length == 0 || tiers.length > MAX_TIERS) revert InvalidTier();
        stakingToken = stakingToken_;
        tierCount = uint8(tiers.length);
        for (uint8 i; i < tiers.length; ++i) {
            _validateTier(tiers[i]);
            lockTiers[i] = tiers[i];
            emit TierSet(
                i,
                tiers[i].duration,
                tiers[i].rewardWeightBps,
                tiers[i].governanceWeightBps,
                tiers[i].enabled
            );
        }
    }

    function setTier(uint8 tierId, LockTier calldata tier) external onlyGovernance {
        if (tierId >= tierCount) revert InvalidTier();
        _validateTier(tier);
        lockTiers[tierId] = tier;
        emit TierSet(
            tierId, tier.duration, tier.rewardWeightBps, tier.governanceWeightBps, tier.enabled
        );
    }

    function stake(uint128 amount, uint8 tierId) external nonReentrant whenNotPaused {
        if (positions[msg.sender].amount != 0) revert PositionExists();
        if (amount == 0) revert InvalidAmount();
        LockTier memory tier = _activeTier(tierId);
        uint256 beforeBalance = stakingToken.balanceOf(address(this));
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = stakingToken.balanceOf(address(this)) - beforeBalance;
        if (received != amount) revert InexactTransfer(amount, received);

        uint48 now48 = uint48(block.timestamp);
        uint48 unlockTime = now48 + tier.duration;
        positions[msg.sender] = Position({
            amount: amount,
            lockStart: now48,
            unlockTime: unlockTime,
            rewardWeightBps: tier.rewardWeightBps,
            governanceWeightBps: tier.governanceWeightBps,
            tierId: tierId
        });
        totalStaked += amount;
        _writePosition(
            msg.sender, amount, unlockTime, tier.rewardWeightBps, tier.governanceWeightBps
        );
        emit Staked(msg.sender, amount, tierId, unlockTime);
    }

    function increaseStake(uint128 amount) external nonReentrant whenNotPaused {
        Position storage position = positions[msg.sender];
        if (position.amount == 0) revert PositionNotFound();
        if (amount == 0) revert InvalidAmount();
        if (block.timestamp >= position.unlockTime) revert PositionExpired(position.unlockTime);
        uint256 beforeBalance = stakingToken.balanceOf(address(this));
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = stakingToken.balanceOf(address(this)) - beforeBalance;
        if (received != amount) revert InexactTransfer(amount, received);

        uint256 newAmount = uint256(position.amount) + amount;
        if (newAmount > type(uint128).max) revert InvalidAmount();
        position.amount = uint128(newAmount);
        totalStaked += amount;
        _writePosition(
            msg.sender,
            newAmount,
            position.unlockTime,
            position.rewardWeightBps,
            position.governanceWeightBps
        );
        emit StakeIncreased(msg.sender, amount, newAmount);
    }

    function extendLock(uint8 tierId) external whenNotPaused {
        Position storage position = positions[msg.sender];
        if (position.amount == 0) revert PositionNotFound();
        LockTier memory tier = _activeTier(tierId);
        uint48 unlockTime = uint48(block.timestamp) + tier.duration;
        if (unlockTime <= position.unlockTime) revert InvalidTier();
        position.tierId = tierId;
        position.unlockTime = unlockTime;
        position.rewardWeightBps = tier.rewardWeightBps;
        position.governanceWeightBps = tier.governanceWeightBps;
        _writePosition(
            msg.sender, position.amount, unlockTime, tier.rewardWeightBps, tier.governanceWeightBps
        );
        emit LockExtended(msg.sender, tierId, unlockTime);
    }

    function withdraw() external nonReentrant {
        Position memory position = positions[msg.sender];
        if (position.amount == 0) revert PositionNotFound();
        if (block.timestamp < position.unlockTime) revert PositionLocked(position.unlockTime);
        delete positions[msg.sender];
        totalStaked -= position.amount;
        _writePosition(msg.sender, 0, 0, 0, 0);
        ProtocolAccounting.sendExact(stakingToken, msg.sender, position.amount);
        emit Withdrawn(msg.sender, position.amount);
    }

    function getPastVotes(address account, uint256 timepoint) external view returns (uint256) {
        _validatePastTimepoint(timepoint);
        return _activeAt(_votes[account], _unlockTimes[account], timepoint);
    }

    function getPastTotalSupply(uint256 timepoint) external view returns (uint256) {
        _validatePastTimepoint(timepoint);
        return _activeTotalAt(_totalVotes, _voteExpiries, timepoint);
    }

    function getPastRewardWeight(address account, uint256 timepoint)
        external
        view
        returns (uint256)
    {
        _validatePastTimepoint(timepoint);
        return _activeAt(_rewardWeights[account], _unlockTimes[account], timepoint);
    }

    function getPastTotalRewardWeight(uint256 timepoint) external view returns (uint256) {
        _validatePastTimepoint(timepoint);
        return _activeTotalAt(_totalRewardWeights, _rewardExpiries, timepoint);
    }

    function getPastEligibleRewardWeight(
        address account,
        uint256 checkpointTimepoint,
        uint256 eligibilityTimepoint
    ) external view returns (uint256) {
        _validateEligibilityTimepoints(checkpointTimepoint, eligibilityTimepoint);
        return _activeAt(
            _rewardWeights[account],
            _unlockTimes[account],
            checkpointTimepoint,
            eligibilityTimepoint
        );
    }

    function getPastEligibleTotalRewardWeight(
        uint256 checkpointTimepoint,
        uint256 eligibilityTimepoint
    ) external view returns (uint256) {
        _validateEligibilityTimepoints(checkpointTimepoint, eligibilityTimepoint);
        return _activeTotalAt(
            _totalRewardWeights, _rewardExpiries, checkpointTimepoint, eligibilityTimepoint
        );
    }

    function getPastUnlockTime(address account, uint256 timepoint) external view returns (uint256) {
        _validatePastTimepoint(timepoint);
        return _unlockTimes[account].upperLookupRecent(timepoint);
    }

    function currentVotes(address account) external view returns (uint256) {
        return _activeAt(_votes[account], _unlockTimes[account], block.timestamp);
    }

    function currentTotalVotes() external view returns (uint256) {
        return _activeTotalAt(_totalVotes, _voteExpiries, block.timestamp);
    }

    function currentRewardWeight(address account) external view returns (uint256) {
        return _activeAt(_rewardWeights[account], _unlockTimes[account], block.timestamp);
    }

    function _writePosition(
        address account,
        uint256 amount,
        uint256 unlockTime,
        uint16 rewardWeightBps,
        uint16 governanceWeightBps
    ) private {
        uint256 timepoint = block.timestamp;
        uint256 oldVotes = _votes[account].latest();
        uint256 oldRewards = _rewardWeights[account].latest();
        uint256 oldUnlockTime = _unlockTimes[account].latest();
        bool oldActive = oldUnlockTime > timepoint;
        uint256 newVotes = amount * governanceWeightBps / BPS;
        uint256 newRewards = amount * rewardWeightBps / BPS;

        if (oldActive) {
            _scheduleExpiry(oldUnlockTime, -_signedWeight(oldVotes), -_signedWeight(oldRewards));
        }
        if (unlockTime > timepoint) {
            _scheduleExpiry(unlockTime, _signedWeight(newVotes), _signedWeight(newRewards));
        }

        _votes[account].push(timepoint, newVotes);
        _rewardWeights[account].push(timepoint, newRewards);
        _unlockTimes[account].push(timepoint, unlockTime);
        _totalVotes.push(timepoint, _totalVotes.latest() + newVotes - (oldActive ? oldVotes : 0));
        _totalRewardWeights.push(
            timepoint, _totalRewardWeights.latest() + newRewards - (oldActive ? oldRewards : 0)
        );
    }

    function _activeAt(
        Checkpoints.Trace256 storage weights,
        Checkpoints.Trace256 storage unlockTimes,
        uint256 timepoint
    ) private view returns (uint256) {
        return _activeAt(weights, unlockTimes, timepoint, timepoint);
    }

    function _activeAt(
        Checkpoints.Trace256 storage weights,
        Checkpoints.Trace256 storage unlockTimes,
        uint256 checkpointTimepoint,
        uint256 eligibilityTimepoint
    ) private view returns (uint256) {
        uint256 unlockTime = unlockTimes.upperLookupRecent(checkpointTimepoint);
        if (unlockTime == 0 || eligibilityTimepoint >= unlockTime) return 0;
        return weights.upperLookupRecent(checkpointTimepoint);
    }

    function _activeTotalAt(
        Checkpoints.Trace256 storage total,
        mapping(uint256 node => int256 delta) storage expiries,
        uint256 timepoint
    ) private view returns (uint256) {
        return _activeTotalAt(total, expiries, timepoint, timepoint);
    }

    function _activeTotalAt(
        Checkpoints.Trace256 storage total,
        mapping(uint256 node => int256 delta) storage expiries,
        uint256 checkpointTimepoint,
        uint256 eligibilityTimepoint
    ) private view returns (uint256) {
        uint256 base = total.upperLookupRecent(checkpointTimepoint);
        int256 expired = _expiryPrefix(expiries, eligibilityTimepoint);
        if (expired < 0 || uint256(expired) > base) revert InvalidExpiryAccounting();
        return base - uint256(expired);
    }

    function _scheduleExpiry(uint256 unlockTime, int256 voteDelta, int256 rewardDelta) private {
        // Point updates make expiry prefix sums queryable without iterating stakers. Updating an
        // active position first cancels its still-future point and then schedules the replacement.
        uint256 index = unlockTime;
        while (index < EXPIRY_TREE_SIZE) {
            _voteExpiries[index] += voteDelta;
            _rewardExpiries[index] += rewardDelta;
            index += index & (~index + 1);
        }
    }

    function _expiryPrefix(mapping(uint256 node => int256 delta) storage tree, uint256 timepoint)
        private
        view
        returns (int256 total)
    {
        uint256 index = timepoint;
        while (index != 0) {
            total += tree[index];
            index &= index - 1;
        }
    }

    function _validatePastTimepoint(uint256 timepoint) private view {
        if (timepoint >= block.timestamp) revert FutureLookup();
    }

    function _validateEligibilityTimepoints(
        uint256 checkpointTimepoint,
        uint256 eligibilityTimepoint
    ) private view {
        if (checkpointTimepoint > eligibilityTimepoint || eligibilityTimepoint >= block.timestamp) revert FutureLookup();
    }

    function _signedWeight(uint256 weight) private pure returns (int256) {
        if (weight > uint256(type(int256).max)) revert InvalidExpiryAccounting();
        return int256(weight);
    }

    function _activeTier(uint8 tierId) private view returns (LockTier memory tier) {
        if (tierId >= tierCount) revert InvalidTier();
        tier = lockTiers[tierId];
        if (!tier.enabled) revert InvalidTier();
    }

    function _validateTier(LockTier memory tier) private pure {
        if (
            tier.duration == 0 || tier.rewardWeightBps < BPS
                || tier.rewardWeightBps > MAX_WEIGHT_BPS || tier.governanceWeightBps < BPS
                || tier.governanceWeightBps > MAX_WEIGHT_BPS
        ) revert InvalidTier();
    }
}
