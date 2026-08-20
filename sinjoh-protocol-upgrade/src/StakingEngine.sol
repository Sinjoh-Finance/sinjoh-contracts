// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Checkpoints } from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import { Governed } from "./governance/Governed.sol";
import { IGovernanceController } from "./interfaces/IGovernanceController.sol";
import { IStakingSnapshot } from "./interfaces/IStakingSnapshot.sol";

/// @notice Single-position fixed-tier staking with separate voting and reward checkpoints.
contract StakingEngine is Governed, ReentrancyGuard, IStakingSnapshot {
    using SafeERC20 for IERC20;
    using Checkpoints for Checkpoints.Trace256;

    uint16 public constant BPS = 10_000;
    uint8 public constant MAX_TIERS = 8;
    uint16 public constant MAX_WEIGHT_BPS = 20_000;

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
        uint256 beforeBalance = stakingToken.balanceOf(msg.sender);
        stakingToken.safeTransfer(msg.sender, position.amount);
        uint256 afterBalance = stakingToken.balanceOf(msg.sender);
        uint256 received = afterBalance >= beforeBalance ? afterBalance - beforeBalance : 0;
        if (received != position.amount) revert InexactTransfer(position.amount, received);
        emit Withdrawn(msg.sender, position.amount);
    }

    function getPastVotes(address account, uint256 blockNumber) external view returns (uint256) {
        return _past(_votes[account], blockNumber);
    }

    function getPastTotalSupply(uint256 blockNumber) external view returns (uint256) {
        return _past(_totalVotes, blockNumber);
    }

    function getPastRewardWeight(address account, uint256 blockNumber)
        external
        view
        returns (uint256)
    {
        return _past(_rewardWeights[account], blockNumber);
    }

    function getPastTotalRewardWeight(uint256 blockNumber) external view returns (uint256) {
        return _past(_totalRewardWeights, blockNumber);
    }

    function getPastUnlockTime(address account, uint256 blockNumber)
        external
        view
        returns (uint256)
    {
        return _past(_unlockTimes[account], blockNumber);
    }

    function currentVotes(address account) external view returns (uint256) {
        return _votes[account].latest();
    }

    function currentTotalVotes() external view returns (uint256) {
        return _totalVotes.latest();
    }

    function currentRewardWeight(address account) external view returns (uint256) {
        return _rewardWeights[account].latest();
    }

    function _writePosition(
        address account,
        uint256 amount,
        uint256 unlockTime,
        uint16 rewardWeightBps,
        uint16 governanceWeightBps
    ) private {
        uint256 oldVotes = _votes[account].latest();
        uint256 oldRewards = _rewardWeights[account].latest();
        uint256 newVotes = amount * governanceWeightBps / BPS;
        uint256 newRewards = amount * rewardWeightBps / BPS;
        _votes[account].push(block.number, newVotes);
        _rewardWeights[account].push(block.number, newRewards);
        _unlockTimes[account].push(block.number, unlockTime);
        _totalVotes.push(block.number, _totalVotes.latest() + newVotes - oldVotes);
        _totalRewardWeights.push(
            block.number, _totalRewardWeights.latest() + newRewards - oldRewards
        );
    }

    function _past(Checkpoints.Trace256 storage trace, uint256 blockNumber)
        private
        view
        returns (uint256)
    {
        if (blockNumber >= block.number) revert FutureLookup();
        return trace.upperLookupRecent(blockNumber);
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
