// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title SinjohTreasuryVault
/// @notice Immutable treasury custody kernel controlled by exactly one governor address.
/// @dev The vault performs exactly two operations: governor-instructed single-asset transfers and
///      a timelocked two-step governor handoff. It never grants approvals, never delegatecalls,
///      never executes arbitrary calldata, and never calls external contracts except to move
///      assets. Governance capability upgrades happen by handing the governor slot to a new
///      module, never by migrating the vault. An optional dead-man recovery rail, elected
///      irrevocably at deployment, lets a pre-named address claim the slot after prolonged
///      governor inactivity so a bricked governor module cannot lock funds forever.
contract SinjohTreasuryVault is ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public constant NATIVE_ASSET = address(0);

    /// @notice Seconds between a governor nomination and the earliest possible acceptance.
    uint256 public immutable GOVERNOR_HANDOFF_DELAY;

    /// @notice Address that may claim the governor slot after prolonged governor inactivity.
    /// @dev Zero when the recovery rail is disabled for this deployment.
    address public immutable RECOVERY_ADDRESS;

    /// @notice Seconds of governor inactivity required before recovery can begin.
    /// @dev Zero when the recovery rail is disabled for this deployment.
    uint256 public immutable RECOVERY_INACTIVITY_PERIOD;

    address public governor;
    address public pendingGovernor;
    uint256 public pendingGovernorAcceptableAt;
    uint256 public lastGovernorActionAt;

    error NotGovernor(address caller);
    error InvalidGovernor(address candidate);
    error InvalidHandoffDelay();
    error InvalidRecoveryConfiguration(address recoveryAddress, uint256 inactivityPeriod);
    error InvalidRecipient(address recipient);
    error ZeroAmount();
    error InsufficientBalance(address asset, uint256 available, uint256 requested);
    error NativeTransferFailed();
    error InexactTransfer(address asset, uint256 expected, uint256 received);
    error NoPendingGovernor();
    error NotPendingGovernor(address caller);
    error HandoffDelayNotElapsed(uint256 acceptableAt);
    error RecoveryDisabled();
    error NotRecoveryAddress(address caller);
    error GovernorStillActive(uint256 recoverableAt);

    event AssetsReceived(address indexed asset, address indexed sender, uint256 amount);
    event TransferExecuted(address indexed asset, address indexed recipient, uint256 amount);
    event GovernorNominated(address indexed successor, uint256 acceptableAt);
    event GovernorNominationCancelled(address indexed successor);
    event GovernorshipAccepted(address indexed previousGovernor, address indexed newGovernor);
    event RecoveryInitiated(address indexed recoveryAddress, uint256 acceptableAt);

    modifier onlyGovernor() {
        if (msg.sender != governor) revert NotGovernor(msg.sender);
        _;
    }

    constructor(
        address initialGovernor,
        uint256 governorHandoffDelay,
        address recoveryAddress,
        uint256 recoveryInactivityPeriod
    ) {
        if (initialGovernor == address(0)) {
            revert InvalidGovernor(initialGovernor);
        }
        if (governorHandoffDelay == 0) revert InvalidHandoffDelay();
        bool recoveryElected = recoveryAddress != address(0);
        if (
            recoveryElected != (recoveryInactivityPeriod != 0) || recoveryAddress == address(this)
                || recoveryAddress == initialGovernor
        ) {
            revert InvalidRecoveryConfiguration(recoveryAddress, recoveryInactivityPeriod);
        }

        governor = initialGovernor;
        GOVERNOR_HANDOFF_DELAY = governorHandoffDelay;
        RECOVERY_ADDRESS = recoveryAddress;
        RECOVERY_INACTIVITY_PERIOD = recoveryInactivityPeriod;
        lastGovernorActionAt = block.timestamp;
    }

    receive() external payable {
        emit AssetsReceived(NATIVE_ASSET, msg.sender, msg.value);
    }

    /// @notice Sends an exact amount of one asset to a recipient chosen by the governor.
    /// @param asset `NATIVE_ASSET` for native currency, otherwise the ERC-20 token address.
    function transfer(address asset, uint256 amount, address recipient)
        external
        onlyGovernor
        nonReentrant
    {
        if (recipient == address(0) || recipient == address(this)) {
            revert InvalidRecipient(recipient);
        }
        if (amount == 0) revert ZeroAmount();

        _recordGovernorAction();

        if (asset == NATIVE_ASSET) {
            uint256 available = address(this).balance;
            if (available < amount) {
                revert InsufficientBalance(asset, available, amount);
            }

            (bool success,) = recipient.call{ value: amount }("");
            if (!success) revert NativeTransferFailed();
        } else {
            IERC20 token = IERC20(asset);
            uint256 available = token.balanceOf(address(this));
            if (available < amount) {
                revert InsufficientBalance(asset, available, amount);
            }

            uint256 beforeBalance = token.balanceOf(recipient);
            token.safeTransfer(recipient, amount);
            uint256 afterBalance = token.balanceOf(recipient);
            uint256 received =
                afterBalance >= beforeBalance ? afterBalance - beforeBalance : type(uint256).max;
            if (received != amount) revert InexactTransfer(asset, amount, received);
        }

        emit TransferExecuted(asset, recipient, amount);
    }

    /// @notice Nominates the successor governor; acceptance unlocks after the handoff delay.
    /// @dev Overwrites any pending nomination, including one initiated through recovery.
    function nominateGovernor(address successor) external onlyGovernor {
        if (successor == address(0) || successor == address(this)) {
            revert InvalidGovernor(successor);
        }

        _recordGovernorAction();

        uint256 acceptableAt = block.timestamp + GOVERNOR_HANDOFF_DELAY;
        pendingGovernor = successor;
        pendingGovernorAcceptableAt = acceptableAt;
        emit GovernorNominated(successor, acceptableAt);
    }

    /// @notice Cancels the pending nomination, including one initiated through recovery.
    function cancelGovernorNomination() external onlyGovernor {
        address successor = pendingGovernor;
        if (successor == address(0)) revert NoPendingGovernor();

        _recordGovernorAction();

        pendingGovernor = address(0);
        pendingGovernorAcceptableAt = 0;
        emit GovernorNominationCancelled(successor);
    }

    /// @notice Completes the handoff after the delay; callable only by the nominated successor.
    function acceptGovernorship() external {
        address successor = pendingGovernor;
        if (successor == address(0)) revert NoPendingGovernor();
        if (msg.sender != successor) revert NotPendingGovernor(msg.sender);
        uint256 acceptableAt = pendingGovernorAcceptableAt;
        if (block.timestamp < acceptableAt) revert HandoffDelayNotElapsed(acceptableAt);

        address previousGovernor = governor;
        governor = successor;
        pendingGovernor = address(0);
        pendingGovernorAcceptableAt = 0;
        lastGovernorActionAt = block.timestamp;
        emit GovernorshipAccepted(previousGovernor, successor);
    }

    /// @notice Starts a recovery handoff after prolonged governor inactivity.
    /// @dev Nominates the recovery address through the normal delayed handoff, so a still-live
    ///      governor can cancel it, proving liveness and restarting the inactivity clock.
    function beginRecovery() external {
        if (RECOVERY_ADDRESS == address(0)) revert RecoveryDisabled();
        if (msg.sender != RECOVERY_ADDRESS) revert NotRecoveryAddress(msg.sender);
        uint256 recoverableAt = lastGovernorActionAt + RECOVERY_INACTIVITY_PERIOD;
        if (block.timestamp < recoverableAt) revert GovernorStillActive(recoverableAt);

        uint256 acceptableAt = block.timestamp + GOVERNOR_HANDOFF_DELAY;
        pendingGovernor = RECOVERY_ADDRESS;
        pendingGovernorAcceptableAt = acceptableAt;
        emit RecoveryInitiated(RECOVERY_ADDRESS, acceptableAt);
    }

    function _recordGovernorAction() internal {
        lastGovernorActionAt = block.timestamp;
    }
}
