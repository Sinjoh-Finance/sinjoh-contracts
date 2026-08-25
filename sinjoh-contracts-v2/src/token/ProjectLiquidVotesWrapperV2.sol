// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC5805 } from "@openzeppelin/contracts/interfaces/IERC5805.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Wrapper } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Wrapper.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Checkpoints } from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import { Time } from "@openzeppelin/contracts/utils/types/Time.sol";
import { IProjectReferenceSupply } from "../interfaces/IProjectReferenceSupply.sol";
import { IProjectTokenIdentity } from "../interfaces/IProjectTokenIdentity.sol";
import { ProjectIds } from "../libraries/ProjectIds.sol";
import { SinjohV2Constants } from "../libraries/SinjohV2Constants.sol";

/// @notice Freely transferable, exactly collateralized voting wrapper for an existing Project
/// subject launched as an ordinary public Pons ERC-20.
/// @dev Every wrapper holder votes their own balance automatically. Wrapping escrows the same
/// amount of the underlying subject, so the underlying and wrapper cannot represent liquid votes
/// for the same units at the same time. Timestamp checkpoints make later transfer, unwrap, or
/// re-wrap operations unable to change an earlier governance snapshot.
contract ProjectLiquidVotesWrapperV2 is
    ERC20Wrapper,
    ReentrancyGuard,
    IERC5805,
    IProjectTokenIdentity,
    IProjectReferenceSupply
{
    using Checkpoints for Checkpoints.Trace256;
    using SafeERC20 for IERC20;

    uint256 public constant MAX_ADDITIONAL_VOTING_EXCLUSIONS = 61;
    address public constant BURN_ADDRESS = SinjohV2Constants.BURN_ADDRESS;

    IERC20 public immutable subject;
    address public immutable override registry;
    address public immutable creator;
    bytes32 public immutable override projectId;
    uint256 public immutable override initialSupply;

    uint256 private _eligibleVotingSupply;
    mapping(address account => bool excluded) private _additionalVotingExclusion;
    address[] private _additionalVotingExclusions;
    mapping(address account => Checkpoints.Trace256 checkpoints) private _voteCheckpoints;
    Checkpoints.Trace256 private _eligibleSupplyCheckpoints;

    error InvalidRegistry(address candidate);
    error InvalidUnderlying(address candidate);
    error InvalidCreator();
    error InvalidMetadata();
    error InvalidReferenceSupply(uint256 actual, uint256 expected);
    error ReferenceSupplyExceeded(uint256 current, uint256 requested, uint256 referenceSupply);
    error UnexpectedBalanceDelta(address account, uint256 expected, uint256 actual);
    error TooManyVotingExclusions(uint256 supplied);
    error InvalidVotingExclusion(uint256 index, address account);
    error UnsortedVotingExclusions(uint256 index, address previous, address current);
    error ReservedVotingExclusion(address account);
    error DelegationUnsupported();
    error FutureLookup(uint256 timepoint, uint48 currentClock);

    event ProjectLiquidVotesWrapperCreated(
        bytes32 indexed projectId,
        address indexed registry,
        address indexed subject,
        address creator,
        uint256 referenceSupply
    );
    event VotingExclusionConfigured(address indexed account, bool automatic);
    event Wrapped(address indexed caller, address indexed recipient, uint256 amount);
    event Unwrapped(address indexed caller, address indexed recipient, uint256 amount);

    constructor(
        address registry_,
        address underlying_,
        address creator_,
        uint256 referenceSupply_,
        string memory name_,
        string memory symbol_,
        address[] memory additionalVotingExclusions_
    ) ERC20(name_, symbol_) ERC20Wrapper(IERC20(underlying_)) {
        if (registry_.code.length == 0) revert InvalidRegistry(registry_);
        if (underlying_.code.length == 0) revert InvalidUnderlying(underlying_);
        if (creator_ == address(0)) revert InvalidCreator();
        if (bytes(name_).length == 0 || bytes(symbol_).length == 0) revert InvalidMetadata();

        uint256 actualSupply = IERC20(underlying_).totalSupply();
        if (referenceSupply_ == 0 || actualSupply != referenceSupply_) {
            revert InvalidReferenceSupply(actualSupply, referenceSupply_);
        }

        subject = IERC20(underlying_);
        registry = registry_;
        creator = creator_;
        projectId = ProjectIds.derive(block.chainid, registry_, underlying_);
        initialSupply = referenceSupply_;

        emit VotingExclusionConfigured(address(0), true);
        emit VotingExclusionConfigured(address(this), true);
        emit VotingExclusionConfigured(BURN_ADDRESS, true);
        _configureAdditionalVotingExclusions(additionalVotingExclusions_);

        emit ProjectLiquidVotesWrapperCreated(
            projectId, registry_, underlying_, creator_, referenceSupply_
        );
    }

    /// @notice Escrows exactly `value` underlying units and mints the same wrapper amount.
    function depositFor(address account, uint256 value)
        public
        override
        nonReentrant
        returns (bool)
    {
        address sender = _msgSender();
        if (sender == address(this)) revert ERC20InvalidSender(address(this));
        if (account == address(this)) revert ERC20InvalidReceiver(account);

        uint256 currentSupply = totalSupply();
        if (value > initialSupply - currentSupply) {
            revert ReferenceSupplyExceeded(currentSupply, value, initialSupply);
        }

        IERC20 token = subject;
        uint256 beforeBalance = token.balanceOf(address(this));
        token.safeTransferFrom(sender, address(this), value);
        uint256 received = token.balanceOf(address(this)) - beforeBalance;
        if (received != value) {
            revert UnexpectedBalanceDelta(address(this), value, received);
        }

        _mint(account, value);
        emit Wrapped(sender, account, value);
        return true;
    }

    /// @notice Burns exactly `value` wrapper units and redeems the same underlying amount.
    function withdrawTo(address account, uint256 value)
        public
        override
        nonReentrant
        returns (bool)
    {
        if (account == address(this)) revert ERC20InvalidReceiver(account);

        address sender = _msgSender();
        IERC20 token = subject;
        uint256 wrapperBefore = token.balanceOf(address(this));
        uint256 recipientBefore = token.balanceOf(account);

        _burn(sender, value);
        token.safeTransfer(account, value);

        uint256 spent = wrapperBefore - token.balanceOf(address(this));
        if (spent != value) {
            revert UnexpectedBalanceDelta(address(this), value, spent);
        }
        uint256 received = token.balanceOf(account) - recipientBefore;
        if (received != value) revert UnexpectedBalanceDelta(account, value, received);

        emit Unwrapped(sender, account, value);
        return true;
    }

    /// @notice Timestamp clock shared with Project governance and staking votes.
    function clock() public view returns (uint48) {
        return Time.timestamp();
    }

    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() external pure returns (string memory) {
        return "mode=timestamp";
    }

    function getVotes(address account) public view returns (uint256) {
        return isVotingExcluded(account) ? 0 : balanceOf(account);
    }

    function getPastVotes(address account, uint256 timepoint) external view returns (uint256) {
        _validatePastTimepoint(timepoint);
        if (isVotingExcluded(account)) return 0;
        return _voteCheckpoints[account].upperLookupRecent(timepoint);
    }

    /// @notice Historical eligible wrapper supply, not the underlying reference supply.
    function getPastTotalSupply(uint256 timepoint) external view returns (uint256) {
        _validatePastTimepoint(timepoint);
        return _eligibleSupplyCheckpoints.upperLookupRecent(timepoint);
    }

    function eligibleVotingSupply() external view returns (uint256) {
        return _eligibleVotingSupply;
    }

    /// @dev Accounts always vote themselves; assigning votes elsewhere is unsupported.
    function delegates(address account) external pure returns (address) {
        return account;
    }

    function delegate(address) external pure {
        revert DelegationUnsupported();
    }

    function delegateBySig(address, uint256, uint256, uint8, bytes32, bytes32) external pure {
        revert DelegationUnsupported();
    }

    function isVotingExcluded(address account) public view returns (bool) {
        return account == address(0) || account == address(this) || account == BURN_ADDRESS
            || _additionalVotingExclusion[account];
    }

    /// @notice Count includes zero, wrapper, burn, then launcher-supplied exclusions.
    function votingExclusionCount() external view returns (uint256) {
        return 3 + _additionalVotingExclusions.length;
    }

    function votingExclusionAt(uint256 index) external view returns (address) {
        if (index == 0) return address(0);
        if (index == 1) return address(this);
        if (index == 2) return BURN_ADDRESS;
        return _additionalVotingExclusions[index - 3];
    }

    function additionalVotingExclusions() external view returns (address[] memory) {
        return _additionalVotingExclusions;
    }

    function _update(address from, address to, uint256 value) internal override {
        bool fromEligible = from != address(0) && !isVotingExcluded(from);
        bool toEligible = to != address(0) && !isVotingExcluded(to);

        super._update(from, to, value);

        uint256 timepoint = clock();
        if (fromEligible) _writeVotes(from, timepoint);
        if (toEligible && to != from) _writeVotes(to, timepoint);

        if (fromEligible != toEligible) {
            if (fromEligible) {
                _eligibleVotingSupply -= value;
            } else {
                _eligibleVotingSupply += value;
            }
            _eligibleSupplyCheckpoints.push(timepoint, _eligibleVotingSupply);
        }
    }

    function _configureAdditionalVotingExclusions(address[] memory exclusions) private {
        uint256 length = exclusions.length;
        if (length > MAX_ADDITIONAL_VOTING_EXCLUSIONS) {
            revert TooManyVotingExclusions(length);
        }

        address previous;
        for (uint256 i; i < length; ++i) {
            address account = exclusions[i];
            if (account == address(0)) revert InvalidVotingExclusion(i, account);
            if (account == address(this) || account == BURN_ADDRESS) {
                revert ReservedVotingExclusion(account);
            }
            if (i != 0 && account <= previous) {
                revert UnsortedVotingExclusions(i, previous, account);
            }
            previous = account;
            _additionalVotingExclusion[account] = true;
            _additionalVotingExclusions.push(account);
            emit VotingExclusionConfigured(account, false);
        }
    }

    function _writeVotes(address account, uint256 timepoint) private {
        uint256 currentVotes = balanceOf(account);
        (uint256 previousVotes,) = _voteCheckpoints[account].push(timepoint, currentVotes);
        if (previousVotes != currentVotes) {
            emit DelegateVotesChanged(account, previousVotes, currentVotes);
        }
    }

    function _validatePastTimepoint(uint256 timepoint) private view {
        uint48 currentClock = clock();
        if (timepoint >= currentClock) revert FutureLookup(timepoint, currentClock);
    }
}
