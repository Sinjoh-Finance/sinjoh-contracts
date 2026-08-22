// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { IVotes } from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import { IERC6372 } from "@openzeppelin/contracts/interfaces/IERC6372.sol";
import { SinjohTreasuryVault } from "@sinjoh-treasury/SinjohTreasuryVault.sol";
import { SinjohGovernor } from "./SinjohGovernor.sol";

/// @notice Deploys token-holder governance as an alternative governor module for Treasury Vaults.
/// @dev The timelock occupies the vault's existing governor slot, exactly as SinjohJoint does for
/// Standard treasuries. The subject token must expose historical holder balances through IVotes.
/// This factory does not create or modify tokens and retains no role after deployment.
contract TokenHolderTreasuryFactory {
    uint48 public constant MIN_VOTING_DELAY = 1;
    uint32 public constant MIN_VOTING_PERIOD = 1;
    uint256 public constant MIN_PROPOSAL_THRESHOLD = 1;
    uint256 public constant MIN_QUORUM_NUMERATOR = 1;
    uint256 public constant MAX_QUORUM_NUMERATOR = 100;
    uint256 public constant MIN_TIMELOCK_DELAY = 1 hours;

    TokenHolderTimelockDeployer private immutable _timelockDeployer;
    TokenHolderGovernorDeployer private immutable _governorDeployer;
    TokenHolderVaultDeployer private immutable _vaultDeployer;

    struct GovernanceConfig {
        uint48 votingDelay;
        uint32 votingPeriod;
        uint256 proposalThreshold;
        uint256 quorumNumerator;
        uint256 timelockDelay;
        uint256 governorHandoffDelay;
    }

    mapping(address vault => address subjectToken) public tokenForVault;
    mapping(address vault => address governor) public governorForVault;
    mapping(address vault => address timelock) public timelockForVault;

    error InvalidSubjectToken(address subjectToken);
    error InvalidVotingDelay(uint48 votingDelay);
    error InvalidVotingPeriod(uint32 votingPeriod);
    error InvalidProposalThreshold(uint256 proposalThreshold);
    error InvalidQuorumNumerator(uint256 quorumNumerator);
    error InvalidTimelockDelay(uint256 timelockDelay);

    event TokenHolderGovernorCreated(
        address indexed creator,
        address indexed subjectToken,
        address indexed governor,
        address timelock
    );
    event TokenHolderTreasuryCreated(
        address indexed creator,
        address indexed subjectToken,
        address indexed vault,
        address governor,
        address timelock
    );

    constructor() {
        _timelockDeployer = new TokenHolderTimelockDeployer();
        _governorDeployer = new TokenHolderGovernorDeployer();
        _vaultDeployer = new TokenHolderVaultDeployer();
    }

    /// @notice Deploys a Governor and timelock that can replace another vault governor by handoff.
    function createTokenHolderGovernor(
        address subjectToken,
        string calldata governorName,
        GovernanceConfig calldata config
    ) external returns (SinjohGovernor governor, TimelockController timelock) {
        (governor, timelock) = _deployGovernance(subjectToken, governorName, config);
    }

    /// @notice Deploys a new vault with token-holder governance in its governor slot from genesis.
    function createTokenHolderTreasury(
        address subjectToken,
        string calldata governorName,
        GovernanceConfig calldata config
    )
        external
        returns (SinjohTreasuryVault vault, SinjohGovernor governor, TimelockController timelock)
    {
        (governor, timelock) = _deployGovernance(subjectToken, governorName, config);
        vault = _vaultDeployer.deploy(address(timelock), config.governorHandoffDelay);

        tokenForVault[address(vault)] = subjectToken;
        governorForVault[address(vault)] = address(governor);
        timelockForVault[address(vault)] = address(timelock);
        emit TokenHolderTreasuryCreated(
            msg.sender, subjectToken, address(vault), address(governor), address(timelock)
        );
    }

    function _deployGovernance(
        address subjectToken,
        string calldata governorName,
        GovernanceConfig calldata config
    ) private returns (SinjohGovernor governor, TimelockController timelock) {
        _validateGovernanceConfig(config);
        _validateSubjectToken(subjectToken);

        timelock = _timelockDeployer.deploy(config.timelockDelay, address(this));
        governor = _governorDeployer.deploy(
            governorName,
            IVotes(subjectToken),
            timelock,
            config.votingDelay,
            config.votingPeriod,
            config.proposalThreshold,
            config.quorumNumerator
        );

        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), address(this));

        emit TokenHolderGovernorCreated(
            msg.sender, subjectToken, address(governor), address(timelock)
        );
    }

    function _validateGovernanceConfig(GovernanceConfig calldata config) private pure {
        if (config.votingDelay < MIN_VOTING_DELAY) {
            revert InvalidVotingDelay(config.votingDelay);
        }
        if (config.votingPeriod < MIN_VOTING_PERIOD) {
            revert InvalidVotingPeriod(config.votingPeriod);
        }
        if (config.proposalThreshold < MIN_PROPOSAL_THRESHOLD) {
            revert InvalidProposalThreshold(config.proposalThreshold);
        }
        if (
            config.quorumNumerator < MIN_QUORUM_NUMERATOR
                || config.quorumNumerator > MAX_QUORUM_NUMERATOR
        ) {
            revert InvalidQuorumNumerator(config.quorumNumerator);
        }
        if (config.timelockDelay < MIN_TIMELOCK_DELAY) {
            revert InvalidTimelockDelay(config.timelockDelay);
        }
    }

    function _validateSubjectToken(address subjectToken) private view {
        if (subjectToken.code.length == 0) revert InvalidSubjectToken(subjectToken);

        uint48 currentTimepoint;
        try IERC6372(subjectToken).clock() returns (uint48 timepoint) {
            currentTimepoint = timepoint;
        } catch {
            revert InvalidSubjectToken(subjectToken);
        }
        try IVotes(subjectToken).getVotes(address(this)) returns (uint256) { }
        catch {
            revert InvalidSubjectToken(subjectToken);
        }
        if (currentTimepoint != 0) {
            try IVotes(subjectToken).getPastTotalSupply(uint256(currentTimepoint) - 1) returns (
                uint256
            ) { }
            catch {
                revert InvalidSubjectToken(subjectToken);
            }
        }
    }
}

contract TokenHolderTimelockDeployer {
    function deploy(uint256 delay, address admin) external returns (TimelockController timelock) {
        address[] memory noProposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0);
        timelock = new TimelockController(delay, noProposers, executors, admin);
    }
}

contract TokenHolderGovernorDeployer {
    function deploy(
        string calldata name,
        IVotes subjectToken,
        TimelockController timelock,
        uint48 votingDelay,
        uint32 votingPeriod,
        uint256 proposalThreshold,
        uint256 quorumNumerator
    ) external returns (SinjohGovernor governor) {
        governor = new SinjohGovernor(
            name,
            subjectToken,
            timelock,
            votingDelay,
            votingPeriod,
            proposalThreshold,
            quorumNumerator
        );
    }
}

contract TokenHolderVaultDeployer {
    function deploy(address timelock, uint256 handoffDelay)
        external
        returns (SinjohTreasuryVault vault)
    {
        vault = new SinjohTreasuryVault(timelock, handoffDelay, address(0), 0);
    }
}
