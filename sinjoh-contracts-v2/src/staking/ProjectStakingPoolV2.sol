// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC5805 } from "@openzeppelin/contracts/interfaces/IERC5805.sol";
import { IERC6372 } from "@openzeppelin/contracts/interfaces/IERC6372.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Checkpoints } from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import { Time } from "@openzeppelin/contracts/utils/types/Time.sol";
import { IProjectTokenIdentity } from "../interfaces/IProjectTokenIdentity.sol";
import { IProjectStakingPositionSource } from "../interfaces/IProjectStakingPositionSource.sol";
import { IProjectStakingTransferReceiver } from "../interfaces/IProjectStakingTransferReceiver.sol";
import { ProjectIds } from "../libraries/ProjectIds.sol";
import { SinjohV2Constants } from "../libraries/SinjohV2Constants.sol";
import { ProjectPoSNFT } from "./ProjectPoSNFT.sol";

/// @notice One project-token staking pool with one transferable PoS NFT per fixed position.
/// @dev The pool is also the direct timestamp-checkpointed vote source for optional staked-token
/// governance. Voting is automatic and cannot be delegated.
contract ProjectStakingPoolV2 is
    IERC5805,
    IProjectStakingPositionSource,
    IProjectStakingTransferReceiver,
    ReentrancyGuard
{
    using Checkpoints for Checkpoints.Trace256;
    using SafeERC20 for IERC20;

    uint64 public constant MIN_LOCK_DURATION = 1 days;
    uint64 public constant MAX_LOCK_DURATION = 365 days;
    address public constant BURN_ADDRESS = SinjohV2Constants.BURN_ADDRESS;

    struct Position {
        uint128 amount;
        uint64 createdAt;
        uint64 unlockAt;
    }

    address public immutable registry;
    IERC20 public immutable subject;
    bytes32 public immutable projectId;
    address public immutable treasury;
    address public immutable governanceExecutor;
    address public immutable guardian;
    uint64 public immutable lockDuration;
    ProjectPoSNFT public immutable posNFT;

    bool public newStakesPaused;
    uint256 public nextTokenId = 1;
    uint256 public totalActiveStake;
    uint256 public activePositionCount;

    mapping(uint256 tokenId => Position position) private _positions;
    mapping(address owner => uint256 stake) private _ownerStake;
    mapping(address owner => Checkpoints.Trace256 checkpoints) private _ownerCheckpoints;
    Checkpoints.Trace256 private _totalStakeCheckpoints;

    error InvalidRegistry(address candidate);
    error InvalidSubject(address candidate);
    error ProjectIdentityMismatch(bytes32 expected, bytes32 actual);
    error InvalidTreasury(address candidate);
    error InvalidGovernanceExecutor(address candidate);
    error InvalidGuardian(address candidate);
    error InvalidLockDuration(uint64 supplied);
    error InvalidStakeAmount(uint256 supplied);
    error InvalidPositionRecipient(address recipient);
    error InvalidRedemptionRecipient(address recipient);
    error InexactTokenTransfer(uint256 expected, uint256 actual);
    error StakingPaused();
    error StakingNotPaused();
    error UnauthorizedPause(address caller);
    error OnlyGovernanceExecutor(address caller);
    error OnlyPoSNFT(address caller);
    error InvalidPositionTransfer(uint256 tokenId, address from, address to);
    error PositionNotMature(uint256 tokenId, uint64 unlockAt, uint64 currentTime);
    error NotPositionOperator(uint256 tokenId, address caller);
    error NoSurplus();
    error DelegationUnsupported();
    error FutureLookup(uint256 timepoint, uint48 currentClock);

    event StakingPoolCreated(
        bytes32 indexed projectId,
        address indexed subject,
        address indexed posNFT,
        uint64 lockDuration,
        address treasury,
        address governanceExecutor,
        address guardian
    );
    event PositionCreated(
        uint256 indexed tokenId,
        address indexed funder,
        address indexed owner,
        uint256 amount,
        uint64 unlockAt
    );
    event PositionTransferred(
        uint256 indexed tokenId, address indexed from, address indexed to, uint256 amount
    );
    event PositionRedeemed(
        uint256 indexed tokenId, address indexed owner, address indexed recipient, uint256 amount
    );
    event SurplusRecovered(uint256 amount, address indexed treasury);
    event NewStakesPaused(address indexed caller);
    event NewStakesResumed(address indexed caller);

    constructor(
        address registry_,
        address subject_,
        address treasury_,
        address governanceExecutor_,
        address guardian_,
        uint64 lockDuration_
    ) {
        if (registry_.code.length == 0) {
            revert InvalidRegistry(registry_);
        }
        if (subject_.code.length == 0) revert InvalidSubject(subject_);
        if (treasury_ == address(0) || treasury_ == BURN_ADDRESS) {
            revert InvalidTreasury(treasury_);
        }
        if (governanceExecutor_ == address(0) || governanceExecutor_ == BURN_ADDRESS) {
            revert InvalidGovernanceExecutor(governanceExecutor_);
        }
        if (guardian_ == BURN_ADDRESS) revert InvalidGuardian(guardian_);
        if (lockDuration_ < MIN_LOCK_DURATION || lockDuration_ > MAX_LOCK_DURATION) {
            revert InvalidLockDuration(lockDuration_);
        }

        bytes32 expectedProjectId = ProjectIds.derive(block.chainid, registry_, subject_);
        bytes32 actualProjectId = IProjectTokenIdentity(subject_).projectId();
        if (
            IProjectTokenIdentity(subject_).registry() != registry_
                || actualProjectId != expectedProjectId
        ) {
            revert ProjectIdentityMismatch(expectedProjectId, actualProjectId);
        }

        registry = registry_;
        subject = IERC20(subject_);
        projectId = actualProjectId;
        treasury = treasury_;
        governanceExecutor = governanceExecutor_;
        guardian = guardian_;
        lockDuration = lockDuration_;

        ProjectPoSNFT deployedPoSNFT = new ProjectPoSNFT(address(this), subject_, actualProjectId);
        posNFT = deployedPoSNFT;

        emit StakingPoolCreated(
            actualProjectId,
            subject_,
            address(deployedPoSNFT),
            lockDuration_,
            treasury_,
            governanceExecutor_,
            guardian_
        );
    }

    /// @notice Locks an exact amount and safely mints one position NFT to `recipient`.
    function stake(uint256 amount, address recipient)
        external
        nonReentrant
        returns (uint256 tokenId)
    {
        if (newStakesPaused) revert StakingPaused();
        if (amount == 0 || amount > type(uint128).max) revert InvalidStakeAmount(amount);
        _validatePositionRecipient(recipient);

        uint256 beforeBalance = subject.balanceOf(address(this));
        subject.safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = subject.balanceOf(address(this)) - beforeBalance;
        if (received != amount) revert InexactTokenTransfer(amount, received);

        uint64 createdAt = uint64(clock());
        uint64 unlockAt = createdAt + lockDuration;
        tokenId = nextTokenId++;
        // `amount` was bounded to uint128 above.
        // forge-lint: disable-next-line(unsafe-typecast)
        _positions[tokenId] = Position(uint128(amount), createdAt, unlockAt);
        activePositionCount += 1;
        _increaseOwnerStake(recipient, amount);
        _increaseTotalStake(amount);

        emit PositionCreated(tokenId, msg.sender, recipient, amount, unlockAt);
        posNFT.safeMint(recipient, tokenId);
    }

    /// @notice Burns a matured position and returns its exact locked amount.
    function unstake(uint256 tokenId, address recipient)
        external
        nonReentrant
        returns (uint256 amount)
    {
        if (recipient == address(0) || recipient == address(this)) {
            revert InvalidRedemptionRecipient(recipient);
        }
        if (!posNFT.isApprovedOrOwner(msg.sender, tokenId)) {
            revert NotPositionOperator(tokenId, msg.sender);
        }

        address owner = posNFT.ownerOf(tokenId);
        Position memory current = _positions[tokenId];
        uint64 currentTime = uint64(clock());
        if (currentTime < current.unlockAt) {
            revert PositionNotMature(tokenId, current.unlockAt, currentTime);
        }

        amount = current.amount;
        delete _positions[tokenId];
        activePositionCount -= 1;
        _decreaseOwnerStake(owner, amount);
        _decreaseTotalStake(amount);
        posNFT.burn(tokenId);

        uint256 beforePool = subject.balanceOf(address(this));
        uint256 beforeRecipient = subject.balanceOf(recipient);
        subject.safeTransfer(recipient, amount);
        uint256 spent = beforePool - subject.balanceOf(address(this));
        uint256 received = subject.balanceOf(recipient) - beforeRecipient;
        if (spent != amount || received != amount) {
            revert InexactTokenTransfer(amount, received < spent ? received : spent);
        }

        emit PositionRedeemed(tokenId, owner, recipient, amount);
    }

    /// @notice Moves aggregate weight when the PoS NFT changes owner.
    function onPositionTransfer(uint256 tokenId, address from, address to) external {
        if (msg.sender != address(posNFT)) revert OnlyPoSNFT(msg.sender);
        if (from == address(0) || to == address(0)) {
            revert InvalidPositionTransfer(tokenId, from, to);
        }
        _validatePositionRecipient(to);

        uint256 amount = _positions[tokenId].amount;
        if (amount == 0) revert InvalidPositionTransfer(tokenId, from, to);
        _decreaseOwnerStake(from, amount);
        _increaseOwnerStake(to, amount);
        emit PositionTransferred(tokenId, from, to, amount);
    }

    /// @notice Permissionlessly sends only unaccounted subject-token surplus to the Treasury.
    function recoverSurplus() external nonReentrant returns (uint256 amount) {
        uint256 beforePool = subject.balanceOf(address(this));
        if (beforePool <= totalActiveStake) revert NoSurplus();
        amount = beforePool - totalActiveStake;
        uint256 beforeTreasury = subject.balanceOf(treasury);
        subject.safeTransfer(treasury, amount);
        uint256 spent = beforePool - subject.balanceOf(address(this));
        uint256 received = subject.balanceOf(treasury) - beforeTreasury;
        if (spent != amount || received != amount) {
            revert InexactTokenTransfer(amount, received < spent ? received : spent);
        }
        emit SurplusRecovered(amount, treasury);
    }

    function pauseNewStakes() external {
        if (msg.sender != governanceExecutor && msg.sender != guardian) {
            revert UnauthorizedPause(msg.sender);
        }
        if (newStakesPaused) revert StakingPaused();
        newStakesPaused = true;
        emit NewStakesPaused(msg.sender);
    }

    function resumeNewStakes() external {
        if (msg.sender != governanceExecutor) revert OnlyGovernanceExecutor(msg.sender);
        if (!newStakesPaused) revert StakingNotPaused();
        newStakesPaused = false;
        emit NewStakesResumed(msg.sender);
    }

    function positionData(uint256 tokenId)
        external
        view
        returns (uint128 amount, uint64 createdAt, uint64 unlockAt)
    {
        Position memory current = _positions[tokenId];
        return (current.amount, current.createdAt, current.unlockAt);
    }

    function balanceOfStake(address owner) public view returns (uint256) {
        return owner == BURN_ADDRESS ? 0 : _ownerStake[owner];
    }

    function getPastStake(address owner, uint256 timepoint) public view returns (uint256) {
        _validatePastTimepoint(timepoint);
        if (owner == BURN_ADDRESS) return 0;
        return _ownerCheckpoints[owner].upperLookupRecent(timepoint);
    }

    function getPastTotalStaked(uint256 timepoint) public view returns (uint256) {
        _validatePastTimepoint(timepoint);
        return _totalStakeCheckpoints.upperLookupRecent(timepoint);
    }

    function getVotes(address owner) public view returns (uint256) {
        return balanceOfStake(owner);
    }

    function getPastVotes(address owner, uint256 timepoint) external view returns (uint256) {
        return getPastStake(owner, timepoint);
    }

    function getPastTotalSupply(uint256 timepoint) external view returns (uint256) {
        return getPastTotalStaked(timepoint);
    }

    function delegates(address account) external pure returns (address) {
        return account;
    }

    function delegate(address) external pure {
        revert DelegationUnsupported();
    }

    function delegateBySig(address, uint256, uint256, uint8, bytes32, bytes32) external pure {
        revert DelegationUnsupported();
    }

    function clock()
        public
        view
        override(IERC6372, IProjectStakingPositionSource)
        returns (uint48)
    {
        return Time.timestamp();
    }

    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() external pure returns (string memory) {
        return "mode=timestamp";
    }

    function backingBalance() external view returns (uint256) {
        return subject.balanceOf(address(this));
    }

    function surplusBalance() external view returns (uint256) {
        uint256 balance = subject.balanceOf(address(this));
        return balance > totalActiveStake ? balance - totalActiveStake : 0;
    }

    function isSolvent() external view returns (bool) {
        return subject.balanceOf(address(this)) >= totalActiveStake;
    }

    function _validatePositionRecipient(address recipient) private view {
        if (
            recipient == address(0) || recipient == BURN_ADDRESS || recipient == address(this)
                || recipient == address(posNFT)
        ) {
            revert InvalidPositionRecipient(recipient);
        }
    }

    function _increaseOwnerStake(address owner, uint256 amount) private {
        uint256 previous = _ownerStake[owner];
        uint256 current = previous + amount;
        _ownerStake[owner] = current;
        _ownerCheckpoints[owner].push(clock(), current);
        emit DelegateVotesChanged(owner, previous, current);
    }

    function _decreaseOwnerStake(address owner, uint256 amount) private {
        uint256 previous = _ownerStake[owner];
        uint256 current = previous - amount;
        _ownerStake[owner] = current;
        _ownerCheckpoints[owner].push(clock(), current);
        emit DelegateVotesChanged(owner, previous, current);
    }

    function _increaseTotalStake(uint256 amount) private {
        totalActiveStake += amount;
        _totalStakeCheckpoints.push(clock(), totalActiveStake);
    }

    function _decreaseTotalStake(uint256 amount) private {
        totalActiveStake -= amount;
        _totalStakeCheckpoints.push(clock(), totalActiveStake);
    }

    function _validatePastTimepoint(uint256 timepoint) private view {
        uint48 currentClock = clock();
        if (timepoint >= currentClock) revert FutureLookup(timepoint, currentClock);
    }
}
