// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { IERC5805 } from "@openzeppelin/contracts/interfaces/IERC5805.sol";
import { Checkpoints } from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import { Time } from "@openzeppelin/contracts/utils/types/Time.sol";
import { ProjectIds } from "../libraries/ProjectIds.sol";
import { SinjohV2Constants } from "../libraries/SinjohV2Constants.sol";

/// @notice Fixed-launch-supply ERC-20 with automatic raw-wallet voting checkpoints.
/// @dev Voting is never delegated. Immutable protocol-custody exclusions contribute neither
/// account votes nor eligible voting supply. The zero address, this token, and the canonical burn
/// address are always excluded without launcher configuration.
contract ProjectVotesToken is ERC20, ERC20Burnable, ERC20Permit, IERC5805 {
    using Checkpoints for Checkpoints.Trace256;

    uint256 public constant MAX_ADDITIONAL_VOTING_EXCLUSIONS = 61;
    address public constant BURN_ADDRESS = SinjohV2Constants.BURN_ADDRESS;

    struct TokenAllocation {
        address recipient;
        uint256 amount;
    }

    address public immutable registry;
    address public immutable creator;
    bytes32 public immutable projectId;
    uint256 public immutable initialSupply;

    uint256 private _eligibleVotingSupply;
    mapping(address account => bool excluded) private _additionalVotingExclusion;
    address[] private _additionalVotingExclusions;
    mapping(address account => Checkpoints.Trace256 checkpoints) private _voteCheckpoints;
    Checkpoints.Trace256 private _eligibleSupplyCheckpoints;

    error InvalidRegistry(address candidate);
    error InvalidCreator();
    error InvalidMetadata();
    error InvalidAllocations();
    error InvalidAllocation(uint256 index);
    error DuplicateAllocation(address recipient);
    error TooManyVotingExclusions(uint256 supplied);
    error InvalidVotingExclusion(uint256 index, address account);
    error UnsortedVotingExclusions(uint256 index, address previous, address current);
    error ReservedVotingExclusion(address account);
    error NoEligibleVotingSupply();
    error DelegationUnsupported();
    error FutureLookup(uint256 timepoint, uint48 currentClock);

    event ProjectVotesTokenCreated(
        bytes32 indexed projectId,
        address indexed registry,
        address indexed creator,
        uint256 initialSupply
    );
    event VotingExclusionConfigured(address indexed account, bool automatic);

    constructor(
        string memory name_,
        string memory symbol_,
        address registry_,
        address creator_,
        TokenAllocation[] memory allocations_,
        address[] memory additionalVotingExclusions_
    ) ERC20(name_, symbol_) ERC20Permit(name_) {
        if (registry_.code.length == 0) {
            revert InvalidRegistry(registry_);
        }
        if (creator_ == address(0)) revert InvalidCreator();
        if (bytes(name_).length == 0 || bytes(symbol_).length == 0) revert InvalidMetadata();

        registry = registry_;
        creator = creator_;
        projectId = ProjectIds.derive(block.chainid, registry_, address(this));

        emit VotingExclusionConfigured(address(0), true);
        emit VotingExclusionConfigured(address(this), true);
        emit VotingExclusionConfigured(BURN_ADDRESS, true);
        _configureAdditionalVotingExclusions(additionalVotingExclusions_);

        uint256 supply = _mintAllocations(allocations_);
        if (_eligibleVotingSupply == 0) revert NoEligibleVotingSupply();
        initialSupply = supply;

        emit ProjectVotesTokenCreated(projectId, registry_, creator_, supply);
    }

    /// @notice Timestamp clock shared with token-holder governance and staking votes.
    function clock() public view returns (uint48) {
        return Time.timestamp();
    }

    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() external pure returns (string memory) {
        return "mode=timestamp";
    }

    /// @notice Current automatically active votes for an eligible wallet.
    function getVotes(address account) public view returns (uint256) {
        return isVotingExcluded(account) ? 0 : balanceOf(account);
    }

    function getPastVotes(address account, uint256 timepoint) external view returns (uint256) {
        _validatePastTimepoint(timepoint);
        if (isVotingExcluded(account)) return 0;
        return _voteCheckpoints[account].upperLookupRecent(timepoint);
    }

    /// @notice Historical eligible voting supply, not raw ERC-20 total supply.
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

    /// @notice Count includes zero, token, burn, then launcher-supplied exclusions.
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

    function _mintAllocations(TokenAllocation[] memory allocations)
        private
        returns (uint256 supply)
    {
        uint256 length = allocations.length;
        if (length == 0 || length > 16) revert InvalidAllocations();

        for (uint256 i; i < length; ++i) {
            TokenAllocation memory allocation = allocations[i];
            if (allocation.recipient == address(0) || allocation.amount == 0) {
                revert InvalidAllocation(i);
            }
            for (uint256 j; j < i; ++j) {
                if (allocations[j].recipient == allocation.recipient) {
                    revert DuplicateAllocation(allocation.recipient);
                }
            }
            supply += allocation.amount;
            _mint(allocation.recipient, allocation.amount);
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
