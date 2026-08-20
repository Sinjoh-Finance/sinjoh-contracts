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

/// @notice Simple token staking with timestamped raw-balance snapshots.
/// @dev One staked token is one reward unit and one governance vote. Stake can be withdrawn at
/// any time; completed historical snapshots do not change when a user later unstakes.
contract StakingEngine is Governed, ReentrancyGuard, IStakingSnapshot {
    using SafeERC20 for IERC20;
    using Checkpoints for Checkpoints.Trace256;

    error InvalidAddress();
    error InvalidAmount();
    error InsufficientStake(uint256 available, uint256 requested);
    error FutureLookup();
    error InexactTransfer(uint256 expected, uint256 received);

    event Staked(address indexed account, uint256 amount, uint256 newBalance);
    event Unstaked(address indexed account, uint256 amount, uint256 newBalance);

    IERC20 public immutable stakingToken;
    uint256 public totalStaked;
    mapping(address account => uint256 amount) public balanceOf;

    mapping(address account => Checkpoints.Trace256) private _balanceCheckpoints;
    Checkpoints.Trace256 private _totalStakedCheckpoints;

    constructor(IGovernanceController controller, address guardian, IERC20 stakingToken_)
        Governed(controller, guardian)
    {
        if (address(stakingToken_).code.length == 0) revert InvalidAddress();
        stakingToken = stakingToken_;
    }

    /// @notice Adds tokens to the caller's stake at one-token-to-one-unit weight.
    function stake(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert InvalidAmount();
        uint256 beforeBalance = stakingToken.balanceOf(address(this));
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = stakingToken.balanceOf(address(this)) - beforeBalance;
        if (received != amount) revert InexactTransfer(amount, received);

        uint256 newBalance = balanceOf[msg.sender] + amount;
        uint256 newTotal = totalStaked + amount;
        balanceOf[msg.sender] = newBalance;
        totalStaked = newTotal;
        _writeCheckpoints(msg.sender, newBalance, newTotal);
        emit Staked(msg.sender, amount, newBalance);
    }

    /// @notice Immediately withdraws any available portion of the caller's stake.
    /// @dev Unstaking remains available while the protocol is paused.
    function unstake(uint256 amount) external nonReentrant {
        if (amount == 0) revert InvalidAmount();
        uint256 oldBalance = balanceOf[msg.sender];
        if (amount > oldBalance) revert InsufficientStake(oldBalance, amount);

        uint256 newBalance = oldBalance - amount;
        uint256 newTotal = totalStaked - amount;
        balanceOf[msg.sender] = newBalance;
        totalStaked = newTotal;
        _writeCheckpoints(msg.sender, newBalance, newTotal);
        ProtocolAccounting.sendExact(stakingToken, msg.sender, amount);
        emit Unstaked(msg.sender, amount, newBalance);
    }

    function getPastBalance(address account, uint256 timepoint) external view returns (uint256) {
        _validatePastTimepoint(timepoint);
        return _balanceCheckpoints[account].upperLookupRecent(timepoint);
    }

    function getPastTotalStaked(uint256 timepoint) external view returns (uint256) {
        _validatePastTimepoint(timepoint);
        return _totalStakedCheckpoints.upperLookupRecent(timepoint);
    }

    function _writeCheckpoints(address account, uint256 accountBalance, uint256 total) private {
        uint256 timepoint = block.timestamp;
        _balanceCheckpoints[account].push(timepoint, accountBalance);
        _totalStakedCheckpoints.push(timepoint, total);
    }

    function _validatePastTimepoint(uint256 timepoint) private view {
        if (timepoint >= block.timestamp) revert FutureLookup();
    }
}
